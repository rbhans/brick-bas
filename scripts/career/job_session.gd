class_name JobSession
extends RefCounted

# One career job in progress: sets the building up, runs its phases, tracks
# objectives and grades the result. The game owns the building and the
# simulation; this reads them and asks the game to act.
#
#   install  design (paused, build HVAC) -> commission (time-lapse 06:30-18:00) -> review
#   service  travel (time-lapse to arrival) -> on site (live; tests and repairs
#            take clock time) -> close out (by hand, or at the deadline); the
#            rest of the day then plays out to the deadline, so comfort is
#            graded on whether the fixes hold, not on how early you left
#   tune     adjust (paused, BAS programming) -> verify (time-lapse 00:00-24:00) -> review

const ServiceCatalog := preload("res://scripts/career/service_catalog.gd")
const Templates := preload("res://scripts/model/templates.gd")

const COMMISSION_START_S := 23400.0 # 06:30, the simulation's normal start
const COMMISSION_END_S := 64800.0   # 18:00, when people leave
const WALK_MINUTES := 2.0
const TICKET_AFTER_S := 900.0       # a room out of range this long gets a comfort call
const TICKET_CLEAR_S := 600.0       # and the call closes after this long back in range
const ON_SITE_DISTANCE := 3.6       # metres (horizontal) to work on a piece of equipment
const STANDARD_COOL_C := 22.78      # 73 °F
const STANDARD_HEAT_C := 21.11      # 70 °F

signal changed

var game: Node
var def: Dictionary
var type := "service"
var phase := ""
var graded: Array = []          # room ids that count for comfort
var faults: Array = []          # {kind, target, host, label, room, value, fixed, fixed_at}
var tickets: Array = []         # {room_id, room, text, opened_at, closed_at}
var findings: Dictionary = {}   # "equipment id|check id" -> text
var log_lines: Array[String] = []
var wrong_parts := 0
var wasted_usd := 0.0
var parts_usd := 0.0
var arrived_at := 0.0
var deadline := 0.0
var work: Dictionary = {}       # {label, until, done}
var budget := 0.0
var reference_cost := 0.0
var energy_max := 0.0
var baseline_usd := 0.0
var last_run: Dictionary = {}
var result: Dictionary = {}
var hint_index := 0
var _out: Dictionary = {}       # room id -> seconds out of range (for comfort calls)
var _back: Dictionary = {}      # room id -> seconds back in range
var _resume_phase := ""
var closed_at := 0.0

func _init(owner: Node, job: Dictionary) -> void:
	game = owner
	def = job.duplicate(true)
	type = String(def.get("type", "service"))

func sim() -> DemoSimulation:
	return game.sim

func title() -> String:
	return String(def.get("title", "Job"))

# --- Lifecycle --------------------------------------------------------------------------

func begin() -> void:
	graded = CareerJobs.graded_rooms(game.index)
	match type:
		"install":
			var reference := Templates.create(String(def.template))
			reference_cost = HvacCosts.total(reference.objects)
			budget = ceilf(reference_cost * float(def.get("budget_factor", 1.3)) / 500.0) * 500.0
			energy_max = float(def.get("energy_usd", 0.0))
			_enter_design()
			game.set_mode(1)
			_say("Design the system. Nothing runs until you commission it.")
		"service":
			_resolve_faults()
			_start_day()
			_apply_due_faults()
			phase = "travel"
			game.set_turbo(float(def.get("arrive_h", 9.0)) * 3600.0)
			game.set_mode(1)
			_say("On the way to %s…" % String(def.get("client", "the site")))
		"tune":
			baseline_usd = float(def.get("baseline_usd", 0.0))
			_start_day()
			sim().set_controls(CareerJobs.AS_FOUND)
			_set_all_setpoints(Units.kelvin_from_f(float(def.setpoints_f[0]) - 32.0), Units.kelvin_from_f(float(def.setpoints_f[1]) - 32.0))
			sim().running = false
			phase = "adjust"
			game.set_mode(1)
			_say("This is the building as found. Open BAS programming and fix what's wasting energy.")
	changed.emit()

func _start_day() -> void:
	game.reset_day(String(def.get("scenario", "Normal weekday")))

func _enter_design() -> void:
	phase = "design"
	game.set_turbo(-1.0)
	_start_day()
	sim().running = false

# Called by the game every frame after the simulation advanced `steps` seconds.
func process(steps: int) -> void:
	if type == "service": _apply_due_faults()
	match phase:
		"travel":
			if sim().sim_seconds >= float(def.get("arrive_h", 9.0)) * 3600.0 - 0.5: _arrive()
		"onsite":
			_track_comfort(steps)
			_check_setpoint_faults()
			if sim().sim_seconds >= deadline:
				_say("It's %s: time's up." % CareerJobs.clock(deadline / 3600.0))
				close_out()
		"working":
			if type == "service":
				_track_comfort(steps)
				if sim().sim_seconds >= deadline - 0.5:
					_say("It's %s: time's up before %s was finished." % [CareerJobs.clock(deadline / 3600.0), String(work.get("label", "the work")).to_lower()])
					close_out()
					return
			if sim().sim_seconds >= float(work.until) - 0.5: _finish_work()
		"wrapup":
			_track_comfort(steps)
			if sim().sim_seconds >= deadline - 0.5:
				game.set_turbo(-1.0)
				phase = "done"
				_finish()
		"commission":
			if sim().sim_seconds >= COMMISSION_END_S - 0.5: _end_run()
		"verify":
			if sim().sim_seconds >= 86400.0 - 0.5: _end_run()

func _arrive() -> void:
	game.set_turbo(-1.0)
	phase = "onsite"
	arrived_at = sim().sim_seconds
	deadline = float(def.get("deadline_h", 17.0)) * 3600.0
	sim().reset_meters()
	sim().running = true
	sim().speed = 1.0
	for ticket in def.get("tickets", []):
		var room: Dictionary = game.room_by_label(String(ticket.room))
		tickets.append({"room_id": String(room.get("id", "")), "room": String(ticket.room), "text": String(ticket.text), "opened_at": arrived_at, "closed_at": -1.0, "manual": true})
	_say("On site at %s. Work order: %d call%s. Deadline %s." % [game.sim.weather().clock, tickets.size(), "" if tickets.size() == 1 else "s", CareerJobs.clock(deadline / 3600.0)])
	game.on_job_phase()
	changed.emit()

# --- Service: faults ------------------------------------------------------------------

# Turns the job's fault specs ("the VAV for the Office") into real ids.
func _resolve_faults() -> void:
	faults.clear()
	var rng := RandomNumberGenerator.new()
	for spec in def.get("faults", []):
		var kind := String(spec.kind)
		var fault := {"kind": kind, "value": float(spec.get("value", 0.0)), "fixed": false, "fixed_at": -1.0, "applied": false,
			"onset_s": float(spec.get("onset_h", 0.0)) * 3600.0}
		if spec.has("pick"): rng.seed = int(spec.pick)
		if spec.has("ahu"):
			var unit := _ahu_named(String(spec.ahu), rng)
			if unit.is_empty(): continue
			fault.target = String(unit.id)
			fault.host = String(unit.id)
			fault.label = String(unit.properties.get("label", unit.id))
		elif spec.has("vav"):
			var vav := _vav_serving(String(spec.vav), rng)
			if vav.is_empty(): continue
			fault.target = String(vav.id)
			fault.host = String(vav.id)
			fault.label = String(vav.properties.get("label", vav.id))
		elif spec.has("room"):
			var room: Dictionary = game.room_by_label(String(spec.room)) if String(spec.room) != "*" else _random_zoned_room(rng)
			if room.is_empty(): continue
			var tstat: String = game.thermostat_in(String(room.id))
			fault.target = String(room.id)
			fault.host = tstat
			fault.room = String(room.label)
			fault.label = "Thermostat · " + String(room.label)
			if kind == "setpoint":
				fault.cool_c = (float(spec.get("cool_f", 64.0)) - 32.0) / 1.8
				fault.heat_c = (float(spec.get("heat_f", 62.0)) - 32.0) / 1.8
		else:
			continue
		faults.append(fault)

func _ahu_named(label: String, rng: RandomNumberGenerator) -> Dictionary:
	var units: Array = game.model.objects_of(["ahu"])
	if label == "*":
		return units[rng.randi() % units.size()] if not units.is_empty() else {}
	for unit in units:
		if String(unit.properties.get("label", "")) == label: return unit
	return {}

func _vav_serving(room_label: String, rng: RandomNumberGenerator) -> Dictionary:
	var vavs: Array = game.model.objects_of(["vav"])
	if room_label == "*":
		var served: Array = vavs.filter(func(vav: Dictionary) -> bool: return graded.has(String(game.topology.get("terminals", {}).get(String(vav.id), {}).get("zone_id", ""))))
		return served[rng.randi() % served.size()] if not served.is_empty() else {}
	var room: Dictionary = game.room_by_label(room_label)
	for vav in vavs:
		if String(game.topology.get("terminals", {}).get(String(vav.id), {}).get("zone_id", "")) == String(room.get("id", "-")): return vav
	return {}

func _random_zoned_room(rng: RandomNumberGenerator) -> Dictionary:
	var rooms: Array = []
	for id in graded:
		if not game.thermostat_in(String(id)).is_empty() and bool(sim().zone_state(String(id)).get("served", false)): rooms.append(game.index.room_by_id(String(id)))
	return rooms[rng.randi() % rooms.size()] if not rooms.is_empty() else {}

# Faults start at their onset (equipment fails during the morning, close to
# when the call comes in), so a room isn't baked for hours before you arrive.
# One can also fail while you're on site.
func _apply_due_faults() -> void:
	for fault in faults:
		if bool(fault.applied) or sim().sim_seconds < float(fault.onset_s) - 0.5: continue
		fault.applied = true
		_apply_fault(fault)

func _apply_fault(fault: Dictionary) -> void:
	if String(fault.kind) == "setpoint":
		sim().set_zone_setpoints(String(fault.target), float(fault.cool_c), float(fault.heat_c))
		return
	var list := sim().faults()
	list.append({"kind": String(fault.kind), "target": String(fault.target), "value": float(fault.value)})
	sim().set_faults(list)

func faults_on(equipment_id: String) -> Array:
	return faults.filter(func(f: Dictionary) -> bool: return String(f.host) == equipment_id and bool(f.applied) and not bool(f.fixed))

func fixed_count() -> int:
	return faults.filter(func(f: Dictionary) -> bool: return bool(f.fixed)).size()

# A tampered thermostat counts as fixed once its setpoints are back to normal
# by any means (the thermostat's own buttons, a reset, a replacement).
func _check_setpoint_faults() -> void:
	for fault in faults:
		if String(fault.kind) != "setpoint" or bool(fault.fixed) or not bool(fault.applied): continue
		var zone := sim().zone_state(String(fault.target))
		var cool := float(zone.get("cool_setpoint_c", 0.0))
		var heat := float(zone.get("heat_setpoint_c", 0.0))
		if cool >= 22.0 and cool <= 24.5 and heat >= 19.9 and heat <= 22.3:
			_mark_fixed(fault, "Setpoints in %s back to normal." % String(fault.room))

func _mark_fixed(fault: Dictionary, message: String) -> void:
	fault.fixed = true
	fault.fixed_at = sim().sim_seconds
	_say(message + " (%d of %d fixed)" % [fixed_count(), faults.size()])
	game.play_sound("save")
	changed.emit()

# --- Service: tickets ---------------------------------------------------------------

func _track_comfort(steps: int) -> void:
	if steps <= 0 or not bool(sim().weather().get("people_present", false)): return
	for room_id in graded:
		var zone := sim().zone_state(String(room_id))
		if zone.is_empty(): continue
		var temp := float(zone.true_temp_c)
		var bad := temp > DemoSimulation.COMFORT_MAX_C + 0.3 or temp < DemoSimulation.COMFORT_MIN_C - 0.3
		var open := _open_ticket(String(room_id))
		if bad:
			_out[room_id] = float(_out.get(room_id, 0.0)) + steps
			_back[room_id] = 0.0
			if open.is_empty() and float(_out[room_id]) >= TICKET_AFTER_S:
				var label := String(zone.get("label", room_id))
				tickets.append({"room_id": String(room_id), "room": label, "text": "Comfort call: too %s (%s)" % ["warm" if temp > DemoSimulation.COMFORT_MAX_C else "cold", Units.temp(temp)], "opened_at": sim().sim_seconds, "closed_at": -1.0, "manual": false})
				_say("New call from %s: too %s." % [label, "warm" if temp > DemoSimulation.COMFORT_MAX_C else "cold"])
				game.play_sound("error")
				changed.emit()
		else:
			_out[room_id] = 0.0
			_back[room_id] = float(_back.get(room_id, 0.0)) + steps
			if not open.is_empty() and float(_back[room_id]) >= TICKET_CLEAR_S and _room_faults_fixed(String(room_id)):
				open.closed_at = sim().sim_seconds
				_say("%s is comfortable again: call closed." % String(open.room))
				changed.emit()

func _open_ticket(room_id: String) -> Dictionary:
	for ticket in tickets:
		if String(ticket.room_id) == room_id and float(ticket.closed_at) < 0.0: return ticket
	return {}

# A complaint about a room isn't closed while that room's own problem is unfixed.
func _room_faults_fixed(room_id: String) -> bool:
	for fault in faults:
		if bool(fault.fixed): continue
		if String(fault.target) == room_id: return false
		if String(fault.host) != "" and String(game.topology.get("terminals", {}).get(String(fault.host), {}).get("zone_id", "")) == room_id: return false
	return true

func open_tickets() -> Array:
	return tickets.filter(func(t: Dictionary) -> bool: return float(t.closed_at) < 0.0)

# --- Service: working on equipment ------------------------------------------------------

func is_service_target(id: String) -> bool:
	if type != "service": return false
	var item: Dictionary = game.model.find_object(id)
	return String(item.get("kind", "")) in ["ahu", "vav", "tstat"]

func equipment_kind(id: String) -> String:
	return String(game.model.find_object(id).get("kind", ""))

func equipment_position(id: String) -> Vector3:
	var item: Dictionary = game.model.find_object(id)
	if item.is_empty(): return Vector3.INF
	return game.vector(item.transform.position)

func on_site(id: String) -> bool:
	if game.mode != 2: return false
	var at := equipment_position(id)
	if at == Vector3.INF: return false
	var player: Vector3 = game.explorer.player.global_position
	return Vector2(at.x - player.x, at.z - player.z).length() <= ON_SITE_DISTANCE

func busy() -> bool:
	return phase == "working" or phase == "travel"

# Everything the service panel shows for one piece of equipment.
func options_for(id: String) -> Dictionary:
	var item: Dictionary = game.model.find_object(id)
	var kind := String(item.get("kind", ""))
	var layout: Array = RouteNetwork.layout(item.get("properties", {})) if kind != "tstat" else []
	var checks: Array = []
	for entry in ServiceCatalog.checks_for(kind, layout):
		var check: Dictionary = entry.duplicate()
		check.result = String(findings.get(id + "|" + String(entry.id), ""))
		checks.append(check)
	return {"id": id, "kind": kind, "title": game.describe(id), "checks": checks, "repairs": ServiceCatalog.repairs_for(kind, layout),
		"on_site": on_site(id), "busy": busy(), "live": game.equipment.short_readout(id) if kind != "tstat" else String(game.thermostat_info(id).get("detail", ""))}

func go_to(id: String) -> void:
	if busy() or phase != "onsite": return
	var at := equipment_position(id)
	if at == Vector3.INF: return
	if game.mode != 2: game.set_mode(2)
	game.explorer.teleport_near(at)
	_start_work("Walking over to %s" % game.describe(id), WALK_MINUTES, func() -> void: pass)

func run_check(id: String, check_id: String) -> void:
	if busy() or phase != "onsite" or not on_site(id): return
	var check := ServiceCatalog.find(ServiceCatalog.CHECKS, equipment_kind(id), check_id)
	if check.is_empty(): return
	_start_work(String(check.label), float(check.minutes), func() -> void:
		var item: Dictionary = game.model.find_object(id)
		var text := ServiceCatalog.check_result(check_id, item, sim(), faults_on(id), game.thermostat_room(id) if equipment_kind(id) == "tstat" else {})
		findings[id + "|" + check_id] = text
		_say("%s: %s" % [game.describe(id), text]))

func run_repair(id: String, repair_id: String) -> void:
	if busy() or phase != "onsite" or not on_site(id): return
	var repair := ServiceCatalog.find(ServiceCatalog.REPAIRS, equipment_kind(id), repair_id)
	if repair.is_empty(): return
	_start_work(String(repair.label), float(repair.minutes), func() -> void: _complete_repair(id, repair))

func _complete_repair(id: String, repair: Dictionary) -> void:
	var cost := float(repair.cost)
	var fixed_any := false
	for fault in faults_on(id):
		if String(fault.kind) not in (repair.fixes as Array): continue
		fixed_any = true
		if String(fault.kind) == "setpoint":
			sim().set_zone_setpoints(String(fault.target), STANDARD_COOL_C, STANDARD_HEAT_C)
		else:
			sim().clear_fault(String(fault.target), String(fault.kind))
		_mark_fixed(fault, "%s: %s fixed it." % [String(fault.label), String(repair.label).to_lower()])
	if String(repair.id) == "reset_setpoints" and not fixed_any:
		var room: Dictionary = game.thermostat_room(id)
		if not room.is_empty(): sim().set_zone_setpoints(String(room.id), STANDARD_COOL_C, STANDARD_HEAT_C)
	if fixed_any:
		parts_usd += cost
	elif cost > 0.0:
		wrong_parts += 1
		wasted_usd += cost
		_say("%s: %s, but nothing changed. That part wasn't the problem (%s you can't bill)." % [game.describe(id), String(repair.label).to_lower(), Units.money(cost)])
		game.play_sound("error")
	else:
		_say("%s: %s. No change." % [game.describe(id), String(repair.label).to_lower()])
	game.points.apply_updates(game.data.provider.snapshot())

func _start_work(label: String, minutes: float, done: Callable) -> void:
	_resume_phase = phase
	phase = "working"
	work = {"label": label, "until": sim().sim_seconds + minutes * 60.0, "minutes": minutes, "done": done, "started": sim().sim_seconds}
	# Work can't run past the deadline: the clock stops there and the job closes.
	game.set_turbo(minf(float(work.until), deadline) if type == "service" and deadline > 0.0 else float(work.until))
	changed.emit()

func _finish_work() -> void:
	game.set_turbo(-1.0)
	var done: Callable = work.get("done", Callable())
	phase = _resume_phase if not _resume_phase.is_empty() else "onsite"
	work = {}
	if done.is_valid(): done.call()
	changed.emit()

func work_progress() -> float:
	if work.is_empty(): return 0.0
	return clampf((sim().sim_seconds - float(work.started)) / maxf(1.0, float(work.until) - float(work.started)), 0.0, 1.0)

func close_out() -> void:
	if type != "service" or phase in ["travel", "done", "wrapup"]: return
	if phase == "working":
		game.set_turbo(-1.0)
		work = {}
	closed_at = sim().sim_seconds
	if closed_at >= deadline - 1.0:
		phase = "done"
		_finish()
		return
	phase = "wrapup"
	game.set_turbo(deadline)
	_say("Closed out. The rest of the day plays out until %s…" % CareerJobs.clock(deadline / 3600.0))
	game.on_job_phase()
	changed.emit()

# --- Install / tune runs ---------------------------------------------------------------

func can_run() -> String:
	if type == "install" and phase == "design":
		var served := served_rooms()
		if served.size() == 0: return "Give at least one room air first."
		return ""
	if type == "tune" and phase == "adjust": return ""
	return "Not now."

func start_run() -> void:
	if not can_run().is_empty(): return
	game.history.mark_boundary("run", sim().sim_seconds)
	if type == "install":
		_start_day()
		sim().reset_meters()
		phase = "commission"
		game.set_turbo(COMMISSION_END_S)
		_say("Commissioning: running a working day, 06:30 to 18:00.")
	else:
		var controls := sim().controls_state()
		var setpoints := _zone_setpoints()
		_start_day()
		sim().set_controls(controls)
		for id in setpoints: sim().set_zone_setpoints(String(id), float(setpoints[id][0]), float(setpoints[id][1]))
		sim().set_time_of_day(0.0)
		sim().reset_meters()
		phase = "verify"
		game.set_turbo(86400.0)
		_say("Verification: measuring a full day, midnight to midnight.")
	game.on_job_phase()
	changed.emit()

func stop_run() -> void:
	if phase not in ["commission", "verify", "review"]: return
	game.set_turbo(-1.0)
	if type == "install":
		_enter_design()
	else:
		var controls := sim().controls_state()
		var setpoints := _zone_setpoints()
		_start_day()
		sim().set_controls(controls)
		for id in setpoints: sim().set_zone_setpoints(String(id), float(setpoints[id][0]), float(setpoints[id][1]))
		sim().running = false
		phase = "adjust"
	game.on_job_phase()
	changed.emit()

func _end_run() -> void:
	game.set_turbo(-1.0)
	sim().running = false
	last_run = measure()
	phase = "review"
	var passed := stars_now() > 0
	_say("Run complete: %s." % ("all requirements met" if passed else "requirements not met yet"))
	game.play_sound("save" if passed else "error")
	game.on_job_phase()
	changed.emit()

func hand_over() -> void:
	if phase != "review" or stars_now() == 0: return
	phase = "done"
	_finish()

func measure() -> Dictionary:
	var energy := sim().energy()
	var comfort := sim().comfort(graded)
	var out := {"cost_usd": float(energy.cost_usd), "electric_kwh": float(energy.electric_kwh), "heating_therms": float(energy.heating_therms),
		"setpoint_pct": float(comfort.setpoint_pct), "range_pct": float(comfort.range_pct), "air_pct": float(comfort.air_pct), "zones": comfort.zones}
	if type == "tune" and baseline_usd > 0.0: out.cut_pct = (1.0 - float(energy.cost_usd) / baseline_usd) * 100.0
	return out

func _zone_setpoints() -> Dictionary:
	var out: Dictionary = {}
	for id in sim().zone_ids():
		var zone := sim().zone_state(String(id))
		out[String(id)] = [float(zone.cool_setpoint_c), float(zone.heat_setpoint_c)]
	return out

func _set_all_setpoints(cool_c: float, heat_c: float) -> void:
	for id in sim().zone_ids(): sim().set_zone_setpoints(String(id), cool_c, heat_c)

# Applies BAS programming from the panel (tune jobs: only while adjusting).
func program(controls: Dictionary, cool_c: float = NAN, heat_c: float = NAN) -> bool:
	if type == "tune" and phase != "adjust": return false
	sim().set_controls(controls)
	if is_finite(cool_c): _set_all_setpoints(cool_c, heat_c)
	changed.emit()
	return true

# --- Objectives and grading ---------------------------------------------------------------

func served_rooms() -> Array:
	return graded.filter(func(id: String) -> bool: return bool(sim().zone_state(id).get("served", false)))

func spent() -> float:
	return HvacCosts.total(game.model.objects)

# [{label, detail, state: "done" | "failed" | "open", required}]
func objectives() -> Array:
	var list: Array = []
	var ran := not last_run.is_empty()
	match type:
		"install":
			var served := served_rooms().size()
			list.append(_objective("Air in every occupied room", "%d of %d rooms" % [served, graded.size()], "done" if served == graded.size() else "open", true))
			var comfort_min := float(def.get("comfort_min", 90.0))
			list.append(_objective("Rooms hold setpoint %d%% of the day" % roundi(comfort_min), ("%.0f%% last run" % float(last_run.setpoint_pct)) if ran else "commission to measure", _graded_state(ran, float(last_run.get("setpoint_pct", 0.0)) >= comfort_min), true))
			var cost := spent()
			list.append(_objective("Stay within the %s budget" % Units.money(budget), "%s spent" % Units.money(cost), "done" if cost <= budget else "failed", false))
			if energy_max > 0.0:
				list.append(_objective("Run the day for under %s of energy" % Units.money(energy_max), (Units.money(float(last_run.cost_usd)) + " last run") if ran else "commission to measure", _graded_state(ran, float(last_run.get("cost_usd", INF)) <= energy_max), false))
		"service":
			var fixed := fixed_count()
			list.append(_objective("Find and fix every problem", "%d of %d fixed · until %s" % [fixed, faults.size(), CareerJobs.clock(float(def.get("deadline_h", 17.0)))], "done" if fixed == faults.size() else "open", true))
			var comfort_star := float(def.get("comfort_star", 80.0))
			var pct := float(sim().comfort(graded).range_pct) if phase not in ["travel", ""] else 100.0
			var graded_now := phase == "done"
			list.append(_objective("Rooms comfortable %d%% of the day until %s" % [roundi(comfort_star), CareerJobs.clock(float(def.get("deadline_h", 17.0)))], ("%.0f%%" if graded_now else "%.0f%% so far") % pct, ("done" if pct >= comfort_star else "failed") if graded_now else "open", false))
			list.append(_objective("No unnecessary parts", ("none" if phase == "done" else "none so far") if wrong_parts == 0 else "%d wasted (%s)" % [wrong_parts, Units.money(wasted_usd)], "done" if wrong_parts == 0 else "failed", false))
		"tune":
			var cut_min := float(def.get("cut_min", 30.0))
			var cut := float(last_run.get("cut_pct", 0.0))
			list.append(_objective("Cut the day's energy bill %d%%" % roundi(cut_min), ("%.0f%% cut (%s to %s)" % [cut, Units.money(baseline_usd), Units.money(float(last_run.cost_usd))]) if ran else "as found: %s a day" % Units.money(baseline_usd), _graded_state(ran, cut >= cut_min), true))
			var comfort_min := float(def.get("comfort_min", 90.0))
			list.append(_objective("Rooms 68–76.5 °F %d%% of the day" % roundi(comfort_min), ("%.0f%%" % float(last_run.range_pct)) if ran else "verify to measure", _graded_state(ran, float(last_run.get("range_pct", 0.0)) >= comfort_min), true))
			var air_min := float(def.get("air_min", 90.0))
			list.append(_objective("Fresh air (CO₂ under %s ppm) %d%%" % [_grouped(DemoSimulation.FRESH_AIR_CO2_PPM), roundi(air_min)], ("%.0f%%" % float(last_run.air_pct)) if ran else "verify to measure", _graded_state(ran, float(last_run.get("air_pct", 0.0)) >= air_min), true))
			for star in def.get("cut_star", []):
				list.append(_objective("Bonus: cut %d%%" % roundi(float(star)), ("%.0f%%" % cut) if ran else "", _graded_state(ran, cut >= float(star)), false))
	return list

static func _grouped(value: float) -> String:
	var text := str(roundi(value))
	return text.left(text.length() - 3) + "," + text.right(3) if text.length() > 3 else text

func _objective(label: String, detail: String, state: String, required: bool) -> Dictionary:
	return {"label": label, "detail": detail, "state": state, "required": required}

func _graded_state(ran: bool, ok: bool) -> String:
	if not ran: return "open"
	return "done" if ok else "failed"

func stars_now() -> int:
	var stars := 1
	for objective in objectives():
		if bool(objective.required) and String(objective.state) != "done": return 0
		if not bool(objective.required) and String(objective.state) == "done": stars += 1
	return mini(stars, 3)

func _finish() -> void:
	var stars := stars_now()
	var fee := float(def.get("fee", 0.0))
	var pay := fee
	var notes: Array[String] = []
	match type:
		"install":
			var over := maxf(0.0, spent() - budget)
			if over > 0.0:
				pay -= over
				notes.append("Over budget by %s, out of your fee" % Units.money(over))
		"service":
			if wasted_usd > 0.0:
				pay -= wasted_usd
				notes.append("Unneeded parts: %s" % Units.money(wasted_usd))
	if stars == 0: pay = 0.0
	result = {"job_id": String(def.id), "title": title(), "type": type, "stars": stars, "objectives": objectives(), "fee": fee, "pay": maxf(0.0, pay), "notes": notes,
		"stats": _stats(), "log": log_lines.duplicate()}
	game.finish_job(result)

func _stats() -> Array:
	var lines: Array = []
	match type:
		"install":
			lines.append(["Equipment and ducts", Units.money(spent())])
			lines.append(["Budget", Units.money(budget)])
			if not last_run.is_empty():
				lines.append(["Comfort (on setpoint)", "%.0f%%" % float(last_run.setpoint_pct)])
				lines.append(["Energy for the day", Units.money(float(last_run.cost_usd))])
		"service":
			lines.append(["Problems fixed", "%d of %d" % [fixed_count(), faults.size()]])
			lines.append(["Comfort, arrival to %s" % CareerJobs.clock(deadline / 3600.0), "%.0f%%" % float(sim().comfort(graded).range_pct)])
			lines.append(["Time on site", "%.1f h" % ((maxf(closed_at, arrived_at) - arrived_at) / 3600.0)])
			lines.append(["Parts used", Units.money(parts_usd + wasted_usd)])
			var missed: Array[String] = []
			for fault in faults:
				if not bool(fault.fixed): missed.append(_fault_summary(fault))
			if not missed.is_empty(): lines.append(["Still broken", ", ".join(missed)])
		"tune":
			if not last_run.is_empty():
				lines.append(["As found", Units.money(baseline_usd) + " a day"])
				lines.append(["After your programming", Units.money(float(last_run.cost_usd)) + " a day"])
				lines.append(["Saved per year (250 days)", Units.money((baseline_usd - float(last_run.cost_usd)) * 250.0)])
				lines.append(["Comfort / fresh air", "%.0f%% / %.0f%%" % [float(last_run.range_pct), float(last_run.air_pct)]])
	return lines

func _fault_summary(fault: Dictionary) -> String:
	var names := {"fan_failure": "broken fan belt", "dirty_filter": "loaded filters", "chw_valve_stuck": "stuck cooling valve", "oa_damper_stuck": "stuck outdoor-air damper",
		"stuck_damper": "stuck damper", "reheat_stuck": "stuck reheat valve", "sensor_bias": "miscalibrated sensor", "setpoint": "tampered setpoints"}
	return "%s (%s)" % [String(names.get(String(fault.kind), fault.kind)), String(fault.label)]

# The objectives as a briefing lists them, before the job starts: [[text, star]].
static func preview_objectives(job: Dictionary, budget: float = 0.0) -> Array:
	match String(job.get("type", "")):
		"install":
			var list: Array = [["Air in every occupied room", false], ["Rooms hold setpoint %d%% of the day (07:00–18:00)" % roundi(float(job.get("comfort_min", 90.0))), false]]
			if budget > 0.0: list.append(["Stay within the %s budget" % Units.money(budget), true])
			if float(job.get("energy_usd", 0.0)) > 0.0: list.append(["Run the day for under %s of energy" % Units.money(float(job.energy_usd)), true])
			return list
		"service":
			return [["Find and fix every problem by %s" % CareerJobs.clock(float(job.get("deadline_h", 17.0))), false],
				["Rooms comfortable %d%% of the day until %s" % [roundi(float(job.get("comfort_star", 80.0))), CareerJobs.clock(float(job.get("deadline_h", 17.0)))], true],
				["No unnecessary parts", true]]
		"tune":
			var list: Array = [["Cut the day's energy bill %d%%" % roundi(float(job.get("cut_min", 30.0))), false],
				["Rooms 68–76.5 °F %d%% of the day" % roundi(float(job.get("comfort_min", 90.0))), false],
				["Fresh air (CO₂ under %s ppm) %d%% of the day" % [_grouped(DemoSimulation.FRESH_AIR_CO2_PPM), roundi(float(job.get("air_min", 90.0)))], false]]
			for star in job.get("cut_star", []): list.append(["Cut it %d%%" % roundi(float(star)), true])
			return list
	return []

# --- HUD helpers ---------------------------------------------------------------------------

func phase_text() -> String:
	match phase:
		"design": return "Design · build the HVAC, then commission"
		"commission": return "Commissioning · %s" % sim().weather().clock
		"review": return "Run finished · review the results"
		"travel": return "Driving to site · %s" % sim().weather().clock
		"onsite": return "On site · until %s" % CareerJobs.clock(deadline / 3600.0)
		"wrapup": return "Closed out · the day plays out · %s" % sim().weather().clock
		"working": return "%s…" % String(work.get("label", "Working"))
		"adjust": return "Adjust the BAS programming, then verify"
		"verify": return "Verifying · %s" % sim().weather().clock
		"done": return "Job finished"
	return ""

func hint() -> String:
	var hints: Array = def.get("hints", [])
	if hints.is_empty(): return ""
	return String(hints[clampi(hint_index, 0, hints.size() - 1)])

func next_hint() -> void:
	var hints: Array = def.get("hints", [])
	if hints.is_empty(): return
	hint_index = (hint_index + 1) % hints.size()
	changed.emit()

func can_edit_equipment() -> bool:
	return type == "install" and phase == "design"

func _say(text: String) -> void:
	log_lines.append("%s  %s" % [sim().weather().clock, text])
	if log_lines.size() > 60: log_lines = log_lines.slice(-60)
	game.set_status(text)
