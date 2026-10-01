extends SceneTree

# Career mode, headless, through the real game: every catalog job is started
# and played the way a player would (service calls diagnosed and repaired,
# installs built and commissioned, tune-ups re-programmed and verified), so
# each job is proven winnable and its targets match the simulation.
#   Godot --headless --path . --script res://tests/career_mode.gd [-- --calibrate] [-- --only=<job id>]
# --calibrate prints the measured install energy and tune-up baselines.

const Templates := preload("res://scripts/model/templates.gd")
const Catalog := preload("res://scripts/career/service_catalog.gd")
const TEST_CAREER := "user://career_test.json"

var game: Node
var failures: Array[String] = []
var checks := 0
var calibrate := false
var only := ""

func _init() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	var started := Time.get_ticks_msec()
	calibrate = OS.get_cmdline_user_args().has("--calibrate")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	game.career = CareerState.load_or_new(TEST_CAREER)
	game.career.reset()
	if only.is_empty():
		test_state()
		test_catalog()
		await test_locks()
		await test_wrong_part()
		await test_phase_locks()
		await test_deadline_during_work()
	for job in CareerJobs.all():
		if not only.is_empty() and String(job.id) != only: continue
		var t0 := Time.get_ticks_msec()
		match String(job.type):
			"service": await play_service(job)
			"install": await play_install(job)
			"tune": await play_tune(job)
		print("  %-24s %6d ms" % [String(job.id), Time.get_ticks_msec() - t0])
	if only.is_empty():
		await play_service(CareerJobs.on_call(0, 0))
		await play_service(CareerJobs.on_call(7, 30))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CAREER))
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if failures.is_empty(): print("CAREER_MODE PASS checks=%d" % checks)
	else: print("CAREER_MODE FAIL checks=%d failures=%d\n  - %s" % [checks, failures.size(), "\n  - ".join(failures)])
	quit(0 if failures.is_empty() else 1)

# Frames until `condition` holds or the limit runs out.
func until(condition: Callable, limit: int = 20000) -> bool:
	for frame in range(limit):
		if condition.call(): return true
		await process_frame
	return condition.call()

func sim() -> DemoSimulation:
	return game.sim

# --- Career state ------------------------------------------------------------------------

func test_state() -> void:
	var state := CareerState.load_or_new(TEST_CAREER)
	state.reset()
	var first := state.record("t1_hot_office", 2, 900.0)
	expect(float(first.earned) == 900.0 and int(first.new_stars) == 2 and state.total_stars() == 2, "first completion pays the fee")
	var again := state.record("t1_hot_office", 1, 900.0)
	expect(float(again.earned) == 0.0 and state.stars_for("t1_hot_office") == 2, "a worse replay pays nothing and keeps the best stars")
	var better := state.record("t1_hot_office", 3, 900.0)
	expect(absf(float(better.earned) - 300.0) < 0.01 and state.stars_for("t1_hot_office") == 3, "a better replay pays the added stars' share")
	var failed := state.record("t1_cold_start", 0, 1100.0)
	expect(float(failed.earned) == 0.0 and not state.completed("t1_cold_start"), "a failed job pays nothing")
	state.record("oncall_0", 2, 800.0)
	expect(state.on_call_done == 1 and state.total_stars() == 3, "on-call calls pay but don't count toward rank stars")
	var loaded := CareerState.load_or_new(TEST_CAREER)
	expect(loaded.total_stars() == 3 and absf(loaded.money - state.money) < 0.01 and loaded.on_call_done == 1, "career survives a save and load")
	loaded.from_dictionary({"money": "lots", "results": {"x": {"stars": 99}, 7: {}, "y": "no"}, "company": ""})
	expect(loaded.stars_for("x") == 3 and not loaded.results.has("y") and loaded.company != "", "junk in the save is clamped or ignored")
	expect(CareerJobs.rank(0) == "Apprentice" and CareerJobs.rank(10) == "Lead technician" and CareerJobs.next_rank(30).is_empty(), "ranks follow stars")
	state.reset()
	expect(state.total_stars() == 0 and state.money == 0.0, "career reset")

func test_catalog() -> void:
	var ids: Dictionary = {}
	for job in CareerJobs.all():
		expect(not ids.has(job.id), "job ids are unique (%s)" % job.id)
		ids[job.id] = true
		expect(String(job.type) in ["install", "service", "tune"] and Templates.definition(String(job.template)).id == job.template, "%s: known type and building" % job.id)
		expect(String(job.scenario) in DemoSimulation.SCENARIOS, "%s: known weather" % job.id)
		if job.type == "service":
			for fault in job.faults:
				var host := String(Catalog.FAULT_HOST.get(String(fault.kind), ""))
				var fixable := false
				for repair in Catalog.REPAIRS.get(host, []):
					if String(fault.kind) in (repair.fixes as Array): fixable = true
				expect(fixable, "%s: %s has a repair" % [job.id, fault.kind])
		if job.type == "tune":
			expect(float(job.get("baseline_usd", 0.0)) > 0.0 or calibrate, "%s: has an as-found baseline" % job.id)
		if job.type == "install":
			expect(float(job.get("energy_usd", 0.0)) > 0.0 or calibrate, "%s: has an energy target" % job.id)
	var a := CareerJobs.on_call(3, 12)
	var b := CareerJobs.on_call(3, 12)
	expect(a == b and not (a.faults as Array).is_empty() and (a.faults as Array).size() <= 3, "on-call jobs are deterministic per serial")
	var kinds: Dictionary = {}
	for serial in range(40):
		for fault in CareerJobs.on_call(serial, 30).faults: kinds[String(fault.kind)] = true
	expect(kinds.size() >= 6, "on-call covers most fault kinds (%s)" % str(kinds.keys()))

# Edits a job forbids are refused, and Creative is untouched.
func test_locks() -> void:
	game.start_job(CareerJobs.find("t1_hot_office"))
	await process_frame
	var walls: int = game.model.objects_of(["wall"]).size()
	var vav: Dictionary = game.model.objects_of(["vav"])[0]
	game.select(String(vav.id))
	game.delete_selected()
	expect(game.model.has_object(String(vav.id)), "service call: equipment can't be deleted")
	game.start_tool("room")
	expect(game.tool.id == "select", "service call: architecture tools refused")
	game.save_project()
	expect(game.status_text.contains("aren't saved"), "jobs aren't saved part-way")
	game.set_scenario("Heat wave")
	expect(sim().scenario == "Hot afternoon", "the weather is the job's")
	var inspect: Dictionary = game.inspect(String(vav.id))
	var labels: Array = (inspect.actions as Array).map(func(a: Dictionary) -> String: return String(a.label))
	expect(String(labels[0]).begins_with("Service") and not labels.any(func(l: String) -> bool: return l.begins_with("Delete") or l.begins_with("Move")), "the card offers Service, not edits (%s)" % str(labels))
	expect(game.model.objects_of(["wall"]).size() == walls, "the building is untouched")
	game.end_job()
	game.start_new_game("studio", false)
	game.select(String(game.model.objects_of(["vav"])[0].id))
	var count: int = game.model.objects_of(["vav"]).size()
	game.delete_selected()
	expect(game.model.objects_of(["vav"]).size() == count - 1, "Creative still edits freely")

# --- Service calls --------------------------------------------------------------------------

func play_service(job: Dictionary) -> void:
	var id := String(job.id)
	game.start_job(job)
	var session: JobSession = game.job
	expect(session.phase == "travel" and session.faults.size() == (job.faults as Array).size(), "%s: starts on the road with every fault resolved (%d of %d)" % [id, session.faults.size(), (job.faults as Array).size()])
	expect(await until(func() -> bool: return session.phase == "onsite"), "%s: arrives on site" % id)
	expect(absf(sim().sim_seconds - float(job.arrive_h) * 3600.0) <= 1.0, "%s: arrives at %s" % [id, CareerJobs.clock(float(job.arrive_h))])
	# Every fault shows a symptom a BAS tech could find.
	sim().run_steps(600)
	for fault in session.faults:
		expect(symptom(fault) != "", "%s: %s on %s shows a symptom" % [id, fault.kind, fault.label])
	for ticket in session.tickets:
		expect(not String(ticket.room_id).is_empty(), "%s: ticket room %s exists" % [id, ticket.room])
	# A competent visit: test each suspect, then fit the right part.
	for fault in session.faults:
		var host := String(fault.host)
		await walk(session, host)
		var check := _check_for(String(fault.kind))
		if not check.is_empty():
			session.run_check(host, check)
			await until(func() -> bool: return session.phase == "onsite")
			var found := String(session.findings.get(host + "|" + check, ""))
			expect(not found.is_empty() and (found.contains("failed") or found.contains("snapped") or found.contains("off") or found.contains("caked") or found.contains("dead") or found.contains("isn't driving") or found.contains("Cooling 6")), "%s: the test finds %s (%s)" % [id, fault.kind, found])
		var repair := _repair_for(String(fault.kind), session.equipment_kind(host), _layout(host))
		session.run_repair(host, repair)
		await until(func() -> bool: return session.phase == "onsite")
		expect(bool(fault.fixed), "%s: %s fixed by %s" % [id, fault.kind, repair])
	expect(sim().faults().is_empty(), "%s: no faults left in the simulation" % id)
	expect(String(session.objectives()[0].state) == "done", "%s: fix-everything objective met" % id)
	# Close out: the rest of the day plays out before grading.
	var money_before: float = game.career.money
	var fixed_at := sim().sim_seconds
	session.close_out()
	expect(session.phase == "wrapup", "%s: closing out early plays out the day" % id)
	expect(await until(func() -> bool: return session.phase == "done", 60000), "%s: the day plays out to the deadline" % id)
	expect(absf(sim().sim_seconds - session.deadline) <= 1.0, "%s: graded at the deadline" % id)
	var result: Dictionary = session.result
	var stars := int(result.get("stars", 0))
	expect(stars >= 2, "%s: everything fixed with no wasted parts earns at least two stars (%d)" % [id, stars])
	expect(calibrate or bool(job.get("on_call", false)) or stars == 3, "%s: a competent visit earns all three stars (comfort %.0f%% vs %.0f%%)" % [id, sim().comfort(session.graded).range_pct, float(job.comfort_star)])
	expect(absf(float(result.pay) - float(job.fee)) < 0.01 and game.career.money >= money_before, "%s: paid the fee" % id)
	expect(game.session_ui.visible, "%s: results shown" % id)
	print("    %s: stars %d · comfort %.1f%% (star at %.0f%%) · fixed by %s" % [id, stars, sim().comfort(session.graded).range_pct, float(job.comfort_star), CareerJobs.clock(fixed_at / 3600.0)])
	game.end_job()
	game.session_ui.hide()

# A tool or workbench left open can't edit once the job stops allowing it.
func test_phase_locks() -> void:
	game.start_job(CareerJobs.find("t1_workshop_fitout"))
	var session: JobSession = game.job
	var reference := Templates.create("studio")
	var design: Array = reference.objects.filter(func(item: Dictionary) -> bool: return String(item.kind) in HvacCosts.HVAC_KINDS)
	game.apply("The design", design.map(func(item: Dictionary) -> Dictionary: return item.duplicate(true)))
	game.start_tool("zone")
	game.equipment.open_workbench("ahu")
	expect(game.tool.id == "zone" and game.equipment.workbench.visible, "design: tools and the workbench open")
	session.start_run()
	expect(session.phase == "commission" and game.tool.id == "select" and not game.equipment.workbench.visible, "commissioning closes the open tool and workbench")
	var before: int = game.model.objects.size()
	var extra: Dictionary = reference.objects_of(["tstat"])[0].duplicate(true)
	extra.id = "tstat-sneaky"
	var result: Dictionary = game.apply("Sneak in a thermostat", [extra])
	expect(game.model.objects.size() == before and (result.added as Array).is_empty(), "nothing commits while the run is on")
	game.undo()
	expect(game.model.objects.size() == before, "and undo is locked too")
	session.stop_run()
	expect(session.phase == "design", "back to design")
	game.end_job()
	# Leaving a tune-up keeps its programming; loading a save without programming resets it.
	game.start_job(CareerJobs.find("t2_office_tuneup"))
	game.end_job()
	expect(sim().controls_state() != DemoSimulation.DEFAULT_CONTROLS, "a left tune-up keeps its programming in the sandbox")
	game._adopt(Templates.create("studio"))
	expect(sim().controls_state() == DemoSimulation.DEFAULT_CONTROLS and sim().faults().is_empty(), "a loaded build without programming gets the defaults")

# Work can't run past the deadline: the clock stops there and the job closes.
func test_deadline_during_work() -> void:
	game.start_job(CareerJobs.find("t1_cold_start"))
	var session: JobSession = game.job
	await until(func() -> bool: return session.phase == "onsite")
	var fault: Dictionary = session.faults.filter(func(f: Dictionary) -> bool: return String(f.kind) == "reheat_stuck")[0]
	await walk(session, String(fault.host))
	sim().step_for_test(session.deadline - sim().sim_seconds - 120.0)
	session.run_repair(String(fault.host), "reheat_actuator")
	expect(session.phase == "working", "a 30-minute repair starts two minutes before the deadline")
	expect(await until(func() -> bool: return session.phase == "done", 20000), "the job closes at the deadline")
	expect(absf(sim().sim_seconds - session.deadline) <= 11.0 and not bool(fault.fixed), "the clock stops at the deadline and the unfinished repair fixes nothing (%s)" % sim().weather().clock)
	expect(int(session.result.get("stars", 0)) == 0, "so the job isn't done")
	game.end_job()
	game.session_ui.hide()

# Fitting a part that wasn't broken fixes nothing and comes out of the fee.
func test_wrong_part() -> void:
	var job := CareerJobs.find("t1_hot_office")
	game.start_job(job)
	var session: JobSession = game.job
	await until(func() -> bool: return session.phase == "onsite")
	var fault: Dictionary = session.faults[0]
	var host := String(fault.host)
	session.run_check(host, "damper")
	expect(session.phase == "onsite" and session.findings.is_empty(), "tests need you at the unit")
	await walk(session, host)
	session.run_repair(host, "vav_controller")
	expect(session.phase == "working" and session.busy(), "a repair takes clock time")
	session.run_repair(host, "damper_actuator")
	expect(session.wrong_parts == 0, "one job at a time")
	await until(func() -> bool: return session.phase == "onsite")
	expect(session.wrong_parts == 1 and absf(session.wasted_usd - 650.0) < 0.01 and not bool(fault.fixed), "a wrong part fixes nothing and is counted")
	var parts: Dictionary = session.objectives()[2]
	expect(String(parts.state) == "failed", "the no-unnecessary-parts star is lost")
	session.run_repair(host, "damper_actuator")
	await until(func() -> bool: return session.phase == "onsite")
	expect(bool(fault.fixed) and sim().faults().is_empty(), "the right part fixes it")
	session.close_out()
	await until(func() -> bool: return session.phase == "done", 60000)
	expect(absf(float(session.result.pay) - (float(job.fee) - 650.0)) < 0.01, "the wasted part comes out of the fee (%s)" % Units.money(float(session.result.pay)))
	game.end_job()
	game.session_ui.hide()

func walk(session: JobSession, host: String) -> void:
	session.go_to(host)
	await until(func() -> bool: return session.phase == "onsite")
	await process_frame
	await physics_frame
	expect(session.on_site(host), "%s: standing at %s after walking over" % [session.def.id, game.describe(host)])

func symptom(fault: Dictionary) -> String:
	var target := String(fault.target)
	match String(fault.kind):
		"stuck_damper":
			var t := sim().terminal_state(target)
			return "damper" if absf(float(t.damper_command) - float(t.damper_feedback)) > 0.15 or float(t.airflow_m3_s) < float(t.airflow_target_m3_s) - 0.03 else ""
		"reheat_stuck":
			var t := sim().terminal_state(target)
			return "reheat" if absf(float(t.reheat_command) - float(t.reheat_output)) > 0.2 else ""
		"sensor_bias":
			var z := sim().zone_state(target)
			return "bias" if absf(float(z.temp_c) - float(z.true_temp_c)) > 1.5 else ""
		"dirty_filter":
			var u := sim().unit_state(target)
			var flow := float(u.flow_fraction)
			return "filter" if flow >= 0.25 and float(u.filter_dp_pa) / (flow * flow) > 180.0 else ""
		"fan_failure":
			var u := sim().unit_state(target)
			return "fan" if bool(u.enabled) and not bool(u.fan_running) else ""
		"chw_valve_stuck":
			var u := sim().unit_state(target)
			return "chw" if float(u.supply_temp_c) > float(u.supply_setpoint_c) + 2.0 else ""
		"oa_damper_stuck":
			var u := sim().unit_state(target)
			return "oa" if absf(float(u.damper_command) - float(u.damper_feedback)) > 0.3 else ""
		"setpoint":
			var z := sim().zone_state(target)
			return "setpoint" if float(z.cool_setpoint_c) < 20.0 else ""
	return ""

func _layout(id: String) -> Array:
	var item: Dictionary = game.model.find_object(id)
	return RouteNetwork.layout(item.properties) if String(item.kind) != "tstat" else []

func _check_for(kind: String) -> String:
	return {"stuck_damper": "damper", "reheat_stuck": "reheat", "sensor_bias": "sensor", "dirty_filter": "filter", "fan_failure": "fan",
		"chw_valve_stuck": "chw_valve", "oa_damper_stuck": "oa_damper", "setpoint": "setpoints"}.get(kind, "")

func _repair_for(kind: String, host_kind: String, layout: Array) -> String:
	for repair in Catalog.repairs_for(host_kind, layout):
		if kind in (repair.fixes as Array) and String(repair.id) != "replace_tstat": return String(repair.id)
	return ""

# --- Installs ----------------------------------------------------------------------------------

func play_install(job: Dictionary) -> void:
	var id := String(job.id)
	game.start_job(job)
	var session: JobSession = game.job
	expect(game.model.objects_of(HvacCosts.HVAC_KINDS).is_empty() and session.phase == "design", "%s: an empty-of-HVAC building to design" % id)
	expect(not session.can_run().is_empty(), "%s: can't commission with no air" % id)
	expect(game.mode == 1 and not sim().running, "%s: design in Equipment view, clock stopped" % id)
	game.start_tool("room")
	expect(game.tool.id == "select", "%s: walls are the client's" % id)
	# Build the reference design (the starter's own system); upsize the air
	# handlers if it can't hold the rooms on this job's day.
	var reference := Templates.create(String(job.template))
	var design: Array = reference.objects.filter(func(item: Dictionary) -> bool: return String(item.kind) in HvacCosts.HVAC_KINDS)
	var best: Dictionary = {}
	for attempt in range(3):
		if attempt > 0:
			game.undo()
			for item in design:
				if String(item.kind) == "ahu": item.properties.capacity_m3_s = _next_size(float(item.properties.capacity_m3_s))
		game.apply("Reference design", design.map(func(item: Dictionary) -> Dictionary: return item.duplicate(true)))
		expect(session.served_rooms().size() == session.graded.size(), "%s: the reference design serves every graded room" % id)
		session.start_run()
		expect(session.phase == "commission" and not session.can_edit_equipment(), "%s: commissioning locks the design" % id)
		expect(await until(func() -> bool: return session.phase == "review", 40000), "%s: commissioning day finishes" % id)
		var run: Dictionary = session.last_run
		print("    %s attempt %d: cost %s of %s budget · comfort %.1f%% · energy %s (target %s)" % [id, attempt, Units.money(session.spent()), Units.money(session.budget), float(run.setpoint_pct), Units.money(float(run.cost_usd)), Units.money(session.energy_max)])
		if float(run.setpoint_pct) >= float(job.comfort_min):
			best = run
			break
		session.stop_run()
	expect(not best.is_empty(), "%s: a reasonable design meets the comfort requirement" % id)
	if calibrate and not best.is_empty():
		print("    CALIBRATE %s energy_usd ≈ %.2f (×%.2f = %.2f)" % [id, float(best.cost_usd), float(job.get("energy_factor", 1.1)), ceilf(float(best.cost_usd) * float(job.get("energy_factor", 1.1)) * 2.0) / 2.0])
	if best.is_empty():
		game.end_job()
		return
	expect(session.spent() <= session.budget, "%s: the design fits the budget (%s of %s)" % [id, Units.money(session.spent()), Units.money(session.budget)])
	expect(session.energy_max <= 0.0 or (float(best.cost_usd) <= session.energy_max and float(best.cost_usd) >= session.energy_max * 0.75), "%s: energy target is reachable but not loose (%s vs %s)" % [id, Units.money(float(best.cost_usd)), Units.money(session.energy_max)])
	var stars := session.stars_now()
	expect(stars >= 2 and (calibrate or stars == 3), "%s: the reference design can earn all three stars (%d)" % [id, stars])
	session.hand_over()
	await process_frame
	expect(int(session.result.get("stars", 0)) == stars and game.session_ui.visible, "%s: handed over" % id)
	game.end_job()
	game.session_ui.hide()

static func _next_size(capacity: float) -> float:
	for size in HvacCosts.AHU_SIZES:
		if float(size) > capacity + 0.01: return float(size)
	return capacity * 1.25

# --- Tune-ups ----------------------------------------------------------------------------------

func play_tune(job: Dictionary) -> void:
	var id := String(job.id)
	game.start_job(job)
	var session: JobSession = game.job
	expect(session.phase == "adjust" and sim().controls_state() == _as_found(), "%s: starts with the as-found programming" % id)
	# Verify as found: the baseline.
	session.start_run()
	expect(await until(func() -> bool: return session.phase == "review", 60000), "%s: as-found verification finishes" % id)
	var found: Dictionary = session.last_run
	print("    %s as found: %s · comfort %.1f%% · air %.1f%%" % [id, Units.money(float(found.cost_usd)), float(found.range_pct), float(found.air_pct)])
	if calibrate: print("    CALIBRATE %s baseline_usd = %.2f" % [id, float(found.cost_usd)])
	else: expect(absf(float(found.cost_usd) - session.baseline_usd) <= session.baseline_usd * 0.02, "%s: baseline matches the as-found day (%s vs %s)" % [id, Units.money(float(found.cost_usd)), Units.money(session.baseline_usd)])
	expect(session.stars_now() == 0, "%s: the as-found building doesn't pass" % id)
	session.stop_run()
	expect(session.phase == "adjust" and sim().controls_state() == _as_found(), "%s: back to adjusting, programming kept" % id)
	# Switching everything off saves energy but fails comfort or air.
	session.program({"occupied_start_h": 12.0, "occupied_end_h": 12.5, "optimal_start": false}, 26.0, 18.0)
	session.start_run()
	await until(func() -> bool: return session.phase == "review", 60000)
	print("    %s switched off: %s · comfort %.1f%% · air %.1f%%" % [id, Units.money(float(session.last_run.cost_usd)), float(session.last_run.range_pct), float(session.last_run.air_pct)])
	expect(session.stars_now() == 0, "%s: switching the building off doesn't pass" % id)
	session.stop_run()
	# Good programming: the default sequences and standard setpoints.
	session.program(DemoSimulation.DEFAULT_CONTROLS, (CareerJobs.STANDARD_COOL_F - 32.0) / 1.8, (CareerJobs.STANDARD_HEAT_F - 32.0) / 1.8)
	session.start_run()
	await until(func() -> bool: return session.phase == "review", 60000)
	var good: Dictionary = session.last_run
	print("    %s tuned: %s (%.0f%% cut) · comfort %.1f%% · air %.1f%%" % [id, Units.money(float(good.cost_usd)), float(good.get("cut_pct", 0.0)), float(good.range_pct), float(good.air_pct)])
	expect(calibrate or session.stars_now() == 3, "%s: good programming earns three stars (%d)" % [id, session.stars_now()])
	session.hand_over()
	await process_frame
	game.end_job()
	game.session_ui.hide()

static func _as_found() -> Dictionary:
	var expected: Dictionary = DemoSimulation.DEFAULT_CONTROLS.duplicate()
	expected.merge(CareerJobs.AS_FOUND, true)
	return expected
