extends SceneTree

# Headless UI and game-flow checks: keys typed into fields stay in them,
# typed numbers count when Apply is clicked, mode switches leave nothing
# behind, Explore uses the access door you face, alarms judge their delays
# during a time-lapse, and leaving for the title screen ends a job.

const TEST_CAREER := "user://ui_checks_career.json"

var game: Node
var failures: Array[String] = []
var checks := 0
var errors_before := 0

func _init() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int) -> void:
	for index in range(count): await physics_frame

func key(code: Key, pressed: bool, text: String = "") -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	if pressed and not text.is_empty(): event.unicode = text.unicode_at(0)
	Input.parse_input_event(event)

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	game.start_new_game("office", false)
	await process_frame
	await typing_stays_in_fields()
	await typed_numbers_apply()
	await mode_switches()
	await access_doors()
	await workbench_after_delete()
	await alarms_in_time_lapse()
	await details_follow_selection()
	await saves_and_secrets()
	await title_screen_ends_job()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CAREER))
	print("UI_CHECKS %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	quit(0 if failures.is_empty() else 1)

func room_floor() -> String:
	for item in game.model.objects_of(["floor"]):
		if not game.index.room_at_cell(BuildingIndex.cell_of(item)).is_empty(): return String(item.id)
	return ""

func room_name_field() -> LineEdit:
	for child in game.hud.card_extra.get_children():
		if child is LineEdit: return child
	return null

func typing_stays_in_fields() -> void:
	var floor_id := room_floor()
	game.select(floor_id)
	await process_frame
	var line := room_name_field()
	expect(line != null, "a room's card has a name field")
	if line == null: return
	line.grab_focus()
	await process_frame
	var before: Vector3 = game.rig.goal_target
	key(KEY_W, true, "w")
	for index in range(10): await process_frame
	key(KEY_W, false)
	await process_frame
	expect((game.rig.goal_target - before).length() < 0.01, "typing W in the room name doesn't pan the camera (moved %.2f m)" % (game.rig.goal_target - before).length())
	# A name typed without Enter is kept when you select something else, and
	# the card rebuilt for that selection has one set of actions.
	var chips: int = game.hud.card_actions.get_child_count()
	line.text = "Probe Room"
	var other := ""
	for item in game.model.objects_of(["floor"]):
		var cell_room: Dictionary = game.index.room_at_cell(BuildingIndex.cell_of(item))
		if not cell_room.is_empty() and String(cell_room.id) != String(game.index.room_at_cell(BuildingIndex.cell_of(game.model.find_object(floor_id))).id):
			other = String(item.id)
			break
	game.select(other)
	await process_frame
	await process_frame
	var room: Dictionary = game.index.room_at_cell(BuildingIndex.cell_of(game.model.find_object(floor_id)))
	expect(String(room.get("label", "")) == "Probe Room", "selecting something else keeps a typed room name")
	expect(game.hud.card_actions.get_child_count() == chips, "renaming rebuilds the card once (%d chips, was %d)" % [game.hud.card_actions.get_child_count(), chips])
	game.select("")
	await process_frame

func typed_numbers_apply() -> void:
	var panel: Control = game.hud.controls_panel
	var zone := String(game.sim.zone_ids()[0])
	var exact := float(game.sim.zone_state(zone).cool_setpoint_c)
	# Apply with nothing changed leaves each room's exact setpoint alone.
	game.hud.open_programming()
	await process_frame
	panel.apply_button.pressed.emit()
	await process_frame
	expect(is_equal_approx(float(game.sim.zone_state(zone).cool_setpoint_c), exact), "Apply with the setpoints unchanged doesn't round them (%.3f °C, was %.3f)" % [float(game.sim.zone_state(zone).cool_setpoint_c), exact])
	# A number typed but not yet committed (no Enter, no focus change) counts.
	game.hud.open_programming()
	await process_frame
	var field: LineEdit = panel.cool_sp.get_line_edit()
	field.grab_focus()
	field.text = "76"
	panel.apply_button.pressed.emit()
	await process_frame
	var applied := Units.fahrenheit(float(game.sim.zone_state(zone).cool_setpoint_c))
	expect(absf(applied - 76.0) < 0.01, "a typed cooling setpoint is applied on Apply (%.2f °F)" % applied)
	panel.hide()
	await process_frame

func mode_switches() -> void:
	# A refused switch leaves the current tab lit, not the clicked one.
	game.start_new_game("blank", false)
	await process_frame
	var tabs: Array = game.hud.mode_buttons
	tabs[2].button_pressed = true
	tabs[2].pressed.emit()
	await process_frame
	expect(game.mode == 0 and tabs[0].button_pressed and not tabs[2].button_pressed, "a refused Explore leaves only Build lit")
	# A thermostat opened in Build closes on the way into Explore.
	game.start_new_game("office", false)
	await process_frame
	var tstat := String(game.model.objects_of(["tstat"])[0].id)
	var room: Dictionary = game.thermostat_room(tstat)
	var setpoint := float(game.sim.zone_state(String(room.id)).cool_setpoint_c)
	game.hud.show_thermostat(tstat)
	game.set_mode(2)
	await frames(2)
	expect(not game.hud.thermostat_open(), "entering Explore closes the thermostat")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	var distance: float = game.explorer.goal_distance
	game.explorer.handle_input(wheel)
	expect(game.explorer.goal_distance > distance and is_equal_approx(float(game.sim.zone_state(String(room.id)).cool_setpoint_c), setpoint), "in Explore the wheel zooms instead of changing a setpoint")
	# An orbit drag under way when the mode changes doesn't stick.
	game.set_mode(0)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	game.rig.handle_input(right)
	game.set_mode(2)
	var release := right.duplicate()
	release.pressed = false
	game.explorer.handle_input(release)
	game.set_mode(0)
	expect(not game.rig.orbiting, "an orbit drag doesn't carry across a mode switch")

func access_doors() -> void:
	game.set_mode(2)
	await frames(2)
	var explorer: Node3D = game.explorer
	var doors: Array = explorer.interactables.filter(func(entry: Dictionary) -> bool: return entry.has("access_key"))
	expect(doors.size() >= 2, "the air handler has several access doors")
	if doors.size() < 2:
		return
	var last: Dictionary = doors[doors.size() - 1]
	for pick: Dictionary in [doors[0], last]:
		var spot: Vector3 = pick.position
		explorer.teleport_near(Vector3(spot.x, 0, spot.z))
		await frames(3)
		var flat: Vector3 = spot - explorer.player.global_position
		explorer.figure.rotation.y = atan2(-flat.x, -flat.z)
		await frames(2)
	expect(String(explorer.target.get("access_key", "")) == String(last.access_key), "facing another access door targets it (%s, wanted %s)" % [explorer.target.get("access_key", "?"), last.access_key])
	explorer.interact()
	expect(game.equipment.access_open(String(last.access_key)) and not game.equipment.access_open(String(doors[0].access_key)), "E opens the door you face")
	game.set_mode(0)
	await process_frame

func workbench_after_delete() -> void:
	var ahu: Dictionary = game.model.objects_of(["ahu"])[0]
	game.equipment.open_workbench("ahu", String(ahu.id))
	await process_frame
	var bench: Control = game.equipment.workbench
	game.apply("Delete", [], [String(ahu.id)])
	await process_frame
	bench._commit()
	await process_frame
	expect(not bench.visible and game.model.find_object(String(ahu.id)).is_empty(), "rebuilding a unit deleted while the workbench was open just closes it")
	game.undo()
	await process_frame

# Alarm delays hold during a time-lapse: judged once a frame, a frame's whole
# span went to whatever held at its end, and dampers still closing at the
# schedule change raised "not following command".
func alarms_in_time_lapse() -> void:
	game.start_new_game("studio", false)
	await process_frame
	game.sim.set_scenario("Hot afternoon")
	var raised: Dictionary = {}
	game.set_turbo(game.sim.sim_seconds + 13.0 * 3600.0)
	while game.turbo_until > game.sim.sim_seconds:
		game._process(1.0 / 60.0)
		for id in game.alarms.active: raised[id] = true
	game.set_turbo(-1.0)
	var dampers: Array = raised.keys().filter(func(id: String) -> bool: return id.begins_with("damper:"))
	expect(dampers.is_empty(), "no false damper alarms through a time-lapsed day (%s)" % [dampers])

func title_screen_ends_job() -> void:
	game.career = CareerState.new()
	game.career.path = TEST_CAREER
	game.start_job(CareerJobs.find("t1_hot_office"))
	await process_frame
	expect(game.job != null, "a career job starts")
	game.hud.toggle_menu()
	var row: Button = null
	for button in game.hud.menu.find_children("*", "Button", true, false):
		if (button as Button).text == "Title screen": row = button
	expect(row != null, "the menu has a Title screen row")
	if row != null: row.pressed.emit()
	await process_frame
	expect(game.job == null and game.session_ui.welcome, "going to the title screen leaves the job")

func details_follow_selection() -> void:
	game.start_new_game("office", false)
	await process_frame
	var ahu := String(game.model.objects_of(["ahu"])[0].id)
	var vav := String(game.model.objects_of(["vav"])[0].id)
	game.select(ahu)
	game.hud.details.open(ahu)
	await process_frame
	game.select(vav)
	await process_frame
	expect(String(game.hud.details.target_id) == vav, "the open Details drawer follows the selection")
	game.hud.details.hide()
	game.select("")
	await process_frame

func saves_and_secrets() -> void:
	# Backup and save messages (the browser build's only way to back up).
	game.browser_files.download()
	expect(game.status_text.begins_with("Backup downloaded"), "Download backup finishes and says so (%s)" % game.status_text)
	game.browser_files.saved()
	expect(game.status_text.begins_with("Saved in this browser"), "a browser save reports where it went (%s)" % game.status_text)
	# A login typed into the station address would be saved with the build.
	var before: Array = game.model.connections.duplicate(true)
	var accepted: bool = await game.data.connect_station({"station_url": "https://admin:secret@station.invalid", "username": "admin"}, "secret")
	expect(not accepted and game.model.connections == before, "a station address carrying a login is refused and not saved")
