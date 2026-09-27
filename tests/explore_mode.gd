extends SceneTree

# Headless Explore checks: seeded HVAC is connected, doors open as you walk
# into them and close behind you, chairs seat the minifigure, and thermostats
# adjust their room's setpoint.

var game: Node
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in range(count): await physics_frame

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	for template in ["studio", "office", "school"]:
		game.start_new_game(template, false)
		await process_frame
		var terminals: Dictionary = game.network.get("terminals", {})
		var connected := terminals.values().filter(func(t: Dictionary) -> bool: return bool(t.connected)).size()
		var ducts: Array = game.model.objects_of(["duct"])
		var broken := ducts.filter(func(item: Dictionary) -> bool: return not DuctConnections.route_error(item.properties, game.model.objects, String(item.id)).is_empty())
		print("TEMPLATE ", template, " vavs=", terminals.size(), " connected=", connected, " ducts=", ducts.size(), " broken=", broken.size(), " rooms=", game.index.rooms.size(), " furniture=", game.model.objects_of(["furniture"]).size(), " tstats=", game.model.objects_of(["tstat"]).size())
		expect(terminals.size() > 0 and connected == terminals.size(), "%s: every seeded VAV is connected (%d/%d)" % [template, connected, terminals.size()])
		expect(broken.is_empty(), "%s: no seeded duct needs rerouting" % template)
		var zoned := 0
		for vav_id in game.topology.terminals:
			if not String(game.topology.terminals[vav_id].zone_id).is_empty(): zoned += 1
		expect(zoned == terminals.size(), "%s: every VAV serves a room (%d/%d)" % [template, zoned, terminals.size()])
	# Doors: walk into the office's front door from outside.
	game.start_new_game("office", false)
	await process_frame
	game.set_mode(2)
	await frames(2)
	var front := ""
	for door_id in game.arch.doors:
		var door: Dictionary = game.arch.doors[door_id]
		var rooms: Array = game.index.edge_rooms(String(door.edge))
		if rooms.filter(func(r: String) -> bool: return r.is_empty()).size() != 1:
			continue
		var room_id := String(rooms.filter(func(r: String) -> bool: return not r.is_empty())[0])
		if String(game.index.room_by_id(room_id).get("label", "")) == "Lobby":
			front = String(door_id)
			break
	expect(not front.is_empty(), "office has an exterior door")
	var edge := String(game.arch.doors[front].edge)
	var center := PlanGrid.edge_center(edge)
	var outside := center + PlanGrid.edge_normal(edge) * (3.0 if game.index.room_at(center + PlanGrid.edge_normal(edge) * 1.5).is_empty() else -3.0)
	game.explorer.player.global_position = outside + Vector3(0, 0.3, 0)
	game.explorer.player.velocity = Vector3.ZERO
	await frames(4)
	var toward := (center - outside).normalized()
	game.explorer.view_yaw = atan2(-toward.x, -toward.z)
	game.explorer.goal_yaw = game.explorer.view_yaw
	Input.action_press("move_forward")
	await frames(70)
	Input.action_release("move_forward")
	expect(bool(game.explorer.open_doors.get(front, false)), "walking into the front door opens it")
	await frames(20)
	var inside: Dictionary = game.index.room_at(game.explorer.player.global_position)
	expect(not inside.is_empty(), "the minifigure walked through the open door into %s" % String(inside.get("label", "nowhere")))
	Input.action_press("move_forward")
	await frames(60)
	Input.action_release("move_forward")
	await frames(150)
	expect(not bool(game.explorer.open_doors.get(front, false)), "the door closes behind you")
	# Sit and stand.
	var seats: Array = game.explorer.interactables.filter(func(entry: Dictionary) -> bool: return entry.kind == "seat")
	expect(not seats.is_empty(), "furniture offers seats")
	if not seats.is_empty():
		game.explorer._use(seats[0])
		expect(not game.explorer.seated.is_empty() and game.explorer.figure.sitting, "the minifigure sits")
		game.explorer.interact()
		expect(game.explorer.seated.is_empty() and not game.explorer.figure.sitting, "E stands back up")
	# Thermostat adjusts its room.
	# Only real interactions: doors, seats, thermostats and HVAC equipment.
	var kinds := {}
	for entry in game.explorer.interactables: kinds[String(entry.get("kind", ""))] = true
	expect(kinds.keys().all(func(kind: String) -> bool: return kind in ["door", "seat", "tstat", "equipment"]), "only real interactions are offered (%s)" % str(kinds.keys()))
	var casings: Array = game.explorer.interactables.filter(func(entry: Dictionary) -> bool: return entry.has("casing"))
	expect(not casings.is_empty(), "VAVs offer their casing")
	if not casings.is_empty():
		game.explorer._use(casings[0])
		expect(bool(game.equipment.open_casings.get(String(casings[0].id), false)), "E opens the VAV casing")
		game.explorer._use(casings[0])
	var vents: Array = game.explorer.interactables.filter(func(entry: Dictionary) -> bool: return entry.has("airflow"))
	expect(not vents.is_empty() and game.equipment.short_readout(String(vents[0].id)).contains("CFM"), "diffusers report their airflow in CFM")
	if not vents.is_empty():
		game.explorer._use(vents[0])
		expect(game.equipment.airflow_view, "E at a diffuser shows the airflow")
		game.equipment.toggle_airflow_view()
	var unkinded: Array = game.explorer.interactables.filter(func(entry: Dictionary) -> bool: return not entry.has("kind"))
	expect(unkinded.is_empty(), "every interactable has a kind (%s)" % str(unkinded.map(func(entry: Dictionary) -> Array: return entry.keys()).slice(0, 2)))
	var tstats: Array = game.explorer.interactables.filter(func(entry: Dictionary) -> bool: return entry.get("kind", "") == "tstat")
	expect(not tstats.is_empty(), "thermostats are interactive")
	if not tstats.is_empty():
		game.explorer._use(tstats[0])
		expect(game.hud.thermostat_open(), "the thermostat panel opens")
		var before: Dictionary = game.thermostat_info(String(tstats[0].id))
		game.hud.nudge_thermostat(-1.0)
		var after: Dictionary = game.thermostat_info(String(tstats[0].id))
		var drop_f := Units.fahrenheit(float(before.get("setpoint_c", 0))) - Units.fahrenheit(float(after.get("setpoint_c", 0)))
		expect(absf(drop_f - 1.0) < 0.05, "a nudge lowers the setpoint by 1 °F (dropped %.2f °F)" % drop_f)
		expect(game.hud.thermostat_reading.text.ends_with("°F"), "the thermostat reads in °F (%s)" % game.hud.thermostat_reading.text)
		game.hud.hide_thermostat()
	game.set_mode(0)
	print("EXPLORE_MODE ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
