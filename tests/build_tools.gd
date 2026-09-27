extends SceneTree

# Drives the build tools through real mouse events on the running game and
# checks the model after each step. Pass -- --capture-dir=/abs/dir to also
# save screenshots mid-drag (windowed run).

var game: Node
var failures: Array[String] = []
var checks := 0
var capture_dir := ""

func _init() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func screen(point: Vector3) -> Vector2:
	return game.rig.camera.unproject_position(point)

func mouse(kind: String, point: Vector3, button: int = MOUSE_BUTTON_LEFT, pressed: bool = true) -> void:
	var at := screen(point)
	var event: InputEvent
	if kind == "move":
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		event = motion
	else:
		var click := InputEventMouseButton.new()
		click.button_index = button
		click.pressed = pressed
		click.position = at
		click.global_position = at
		event = click
	root.push_input(event, true)
	await process_frame

func drag(a: Vector3, b: Vector3, steps: int = 6, shot: String = "") -> void:
	await mouse("move", a)
	await mouse("button", a)
	for i in range(1, steps + 1):
		await mouse("move", a.lerp(b, float(i) / steps))
	if not shot.is_empty(): await capture(shot)
	await mouse("button", b, MOUSE_BUTTON_LEFT, false)

func click(point: Vector3) -> void:
	await mouse("move", point)
	await mouse("button", point)
	await mouse("button", point, MOUSE_BUTTON_LEFT, false)

func key(code: Key, ctrl: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	root.push_input(event, true)
	await process_frame

func capture(name: String) -> void:
	if capture_dir.is_empty(): return
	for i in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [capture_dir, name])

func count(kind: String) -> int:
	return game.model.objects_of([kind]).size()

func live_vavs() -> int:
	var network := RouteNetwork.evaluate(game.model.objects)
	return network.terminals.values().filter(func(terminal: Dictionary) -> bool: return bool(terminal.connected)).size()

func broken_ducts() -> int:
	return game.model.objects_of(["duct"]).filter(func(duct: Dictionary) -> bool: return not DuctConnections.route_error(duct.properties, game.model.objects, String(duct.id)).is_empty()).size()

func any_free_inlet(kind: String) -> bool:
	for item in game.model.objects_of([kind]):
		if not DuctConnections.occupied(DuctConnections.port(item, "inlet"), game.model.objects): return true
	return false

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	game.start_new_game("blank", false)
	game.rig.set_view(Vector3(6, 0, 4), -0.62, -0.95, 34, true)
	await process_frame
	# Room tool: a 4 x 3 room at the origin.
	game.start_tool("room", {"style": "tan", "finish": "oak"})
	await drag(PlanGrid.vertex_position(Vector2i(0, 0)), PlanGrid.vertex_position(Vector2i(4, 3)), 8, "01-room-drag")
	expect(count("wall") == 14 and count("floor") == 12, "room tool builds 14 perimeter walls and 12 floor tiles (got %d/%d)" % [count("wall"), count("floor")])
	expect(game.index.rooms.size() == 1, "one closed room detected")
	# Wall tool splits it into two rooms.
	game.start_tool("wall", {"style": "white"})
	await drag(PlanGrid.vertex_position(Vector2i(2, 0)), PlanGrid.vertex_position(Vector2i(2, 3)), 6, "02-wall-drag")
	expect(count("wall") == 17 and game.index.rooms.size() == 2, "interior wall splits the room in two (walls %d rooms %d)" % [count("wall"), game.index.rooms.size()])
	# Undo / redo as single transactions.
	await key(KEY_Z, true)
	expect(count("wall") == 14 and game.index.rooms.size() == 1, "undo removes the whole wall drag")
	await key(KEY_Z, true, true)
	expect(count("wall") == 17, "redo restores it")
	# Door between the rooms, window on the outside.
	game.start_tool("door", {"style": "door"})
	await mouse("move", PlanGrid.edge_center("z:2:1") + Vector3(0, 1.5, 0))
	await capture("03-door-hover")
	await click(PlanGrid.edge_center("z:2:1") + Vector3(0, 1.5, 0))
	expect(count("door") == 1 and String(game.model.objects_of(["door"])[0].properties.edge) == "z:2:1", "door fits the hovered wall section")
	game.start_tool("window", {"style": "window"})
	await click(PlanGrid.edge_center("x:1:0") + Vector3(0, 1.5, 0))
	expect(count("window") == 1, "window fits a wall section")
	await click(PlanGrid.edge_center("x:1:0") + Vector3(0, 1.5, 0))
	expect(count("window") == 1, "a section holds only one opening")
	# Floor paint: repaint one room by shift-click.
	game.start_tool("floor", {"finish": "carpet_blue"})

	await mouse("move", PlanGrid.cell_center(Vector2i(3, 1)))
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.keycode = KEY_SHIFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await process_frame
	await click(PlanGrid.cell_center(Vector2i(3, 1)))
	shift.pressed = false
	Input.parse_input_event(shift)
	var blue: int = game.model.objects_of(["floor"]).filter(func(item: Dictionary) -> bool: return item.properties.finish == "carpet_blue").size()
	expect(blue == 6, "shift-click fills the east room with carpet (got %d)" % blue)
	# Trees outside, blocked inside.
	game.start_tool("place", {"kind": "tree", "item": "oak"})
	await mouse("move", Vector3(15, 0, 4))
	for i in range(10): await process_frame
	await capture("04-tree-ghost")
	await click(Vector3(15, 0, 4))
	print("TREE status=", game.status_text, " ghost=", game.tool.ghost.global_position if is_instance_valid(game.tool.ghost) else "none", " visible=", game.tool.ghost.visible if is_instance_valid(game.tool.ghost) else false, " target=", game.tool.target.origin, " valid=", game.tool.valid)
	expect(count("tree") == 1, "tree placed on open ground")
	await click(PlanGrid.cell_center(Vector2i(1, 1)))
	expect(count("tree") == 1, "trees refuse indoor floor")
	# Sledgehammer area sweep removes the tree.
	game.start_tool("delete")
	await drag(Vector3(13, 0, 2), Vector3(17, 0, 6))
	expect(count("tree") == 0, "sledgehammer area clears the tree")
	# Wall removal with the erase wall tool drops the door too.
	game.start_tool("wall", {"style": "white", "erase": true})
	await drag(PlanGrid.vertex_position(Vector2i(2, 0)), PlanGrid.vertex_position(Vector2i(2, 3)))
	expect(count("wall") == 14 and count("door") == 0 and game.index.rooms.size() == 1, "removing walls takes their door with them")
	# Select + move a window via drag.
	game.finish_tool()
	await capture("05-final")
	# HVAC: an air handler on the ground behind the room, then Zone a room.
	game.set_mode(1)
	game.rig.set_view(Vector3(5, 0, -3), 0.0, -1.2, 48, true)
	await process_frame
	game.start_tool("equipment", {"kind": "ahu", "properties": {"layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"], "sensor_enabled": true}, "rotation": -PI * 0.5})
	await click(Vector3(5.0, PlanGrid.FLOOR_TOP, -13.0))
	expect(count("ahu") == 1, "air handler placed on open ground")
	game.start_tool("zone")
	await click(Vector3(5.0, PlanGrid.FLOOR_TOP, 3.75))
	expect(count("vav") == 1 and count("diffuser") >= 1 and count("tstat") == 1 and count("duct") >= 2, "Zone a room adds a VAV, diffuser, thermostat and ducts (vav %d diffuser %d tstat %d duct %d)" % [count("vav"), count("diffuser"), count("tstat"), count("duct")])
	var network := RouteNetwork.evaluate(game.model.objects)
	var live := 0
	for vav_id in network.terminals:
		if bool(network.terminals[vav_id].connected): live += 1
	expect(live == 1, "the new zone is fed by the air handler")
	var zoned := false
	for zone_id in game.topology.zones:
		if bool(game.sim.zone_state(String(zone_id)).get("served", false)): zoned = true
	expect(zoned, "the simulation serves the zoned room")
	game.undo()
	expect(count("vav") == 0 and count("duct") == 0 and count("tstat") == 0, "one undo removes the whole zone")
	game.redo()
	expect(count("vav") == 1 and count("tstat") == 1, "redo puts it back")
	# A second room: the air handler's outlet is taken, so zoning taps the main.
	game.set_mode(0)
	game.start_tool("room", {"style": "tan", "finish": "oak"})
	await drag(PlanGrid.vertex_position(Vector2i(4, 0)), PlanGrid.vertex_position(Vector2i(8, 3)))
	game.finish_tool()
	game.set_mode(1)
	game.rig.set_view(Vector3(10, 0, -3), 0.0, -1.2, 56, true)
	await process_frame
	game.start_tool("zone")
	await click(Vector3(15.0, PlanGrid.FLOOR_TOP, 3.75))
	expect(count("vav") == 2 and count("cross") == 1, "the second room taps the main with a trunk cross (vav %d cross %d)" % [count("vav"), count("cross")])
	expect(live_vavs() == 2, "both rooms get air (%d live)" % live_vavs())
	# A hand-placed diffuser hooks itself to its room's VAV.
	var diffusers := count("diffuser")
	game.start_tool("equipment", {"kind": "diffuser"})
	# Like a player: slide over the room until the ghost says the spot is free.
	var spot := Vector3.INF
	for x in [18.0, 16.5, 12.0, 13.5, 15.0]:
		for z in [1.25, 6.25, 3.75]:
			game.tool.hover(screen(Vector3(x, 3.6, z)))
			if game.tool.valid:
				spot = Vector3(x, 3.6, z)
				break
		if spot != Vector3.INF: break
	expect(spot != Vector3.INF, "there's a free ceiling spot for another diffuser")
	await click(spot)
	expect(count("diffuser") == diffusers + 1 and not any_free_inlet("diffuser"), "a placed diffuser is ducted to its VAV")
	# Moving a VAV: its ducts follow instead of breaking.
	var vav_id := String(game.model.objects_of(["vav"])[1].id)
	var moved: Dictionary = game.model.find_object(vav_id).duplicate(true)
	# (A realistic nudge: back along its axis and a little sideways.)
	moved.transform.position[0] = float(moved.transform.position[0]) - 2.0
	moved.transform.position[2] = float(moved.transform.position[2]) + 1.0
	var replan := ZonePlanner.new(game.model.objects, game.index, game.model.new_id)
	replan.reroute_attached(moved)
	game.apply("Move VAV", replan.entries, replan.removed_ids(), [moved])
	expect(broken_ducts() == 0 and live_vavs() == 2, "ducts follow a moved VAV (%d broken, %d live)" % [broken_ducts(), live_vavs()])
	# Pulling the trunk cross out bridges the main for the first room.
	game.select(String(game.model.objects_of(["cross"])[0].id))
	game.delete_selected()
	expect(count("cross") == 0 and broken_ducts() == 0 and live_vavs() == 1, "deleting the cross bridges the main and leaves no loose ducts (%d broken, %d live)" % [broken_ducts(), live_vavs()])
	game.undo()
	expect(count("cross") == 1 and live_vavs() == 2, "undo restores the tap")
	game.finish_tool()
	game.set_mode(0)
	# Graphics quality (not remembered: tests share the player's settings file).
	game.set_graphics("low", false)
	expect(not game.stage.sun.shadow_enabled and is_equal_approx(game.get_viewport().scaling_3d_scale, 0.75), "Low graphics drops shadows and render scale")
	game.set_graphics("high", false)
	expect(game.stage.sun.shadow_enabled and is_equal_approx(game.get_viewport().scaling_3d_scale, 1.0), "High graphics restores them")
	game.set_graphics("auto", false)
	# The quick tour walks through the modes (hidden again without marking it seen).
	game.tour.show()
	game.tour.show_step(1)
	expect(game.mode == 1, "the tour's Equipment step switches to Equipment")
	game.tour.show_step(3)
	expect(game.mode == 2, "its last step goes exploring")
	game.tour.hide()
	game.set_mode(0)
	# Save round trip keeps names and objects.
	var path := "user://build_tools_test.json"
	game.model.site.room_names[PlanGrid.cell_key(Vector2i(0, 0))] = "Studio"
	expect(game.model.save_to(path) == OK, "save succeeds")
	var loaded := ProjectModel.new()
	expect(loaded.load_from(path) and loaded.objects.size() == game.model.objects.size(), "save round trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("BUILD_TOOLS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
