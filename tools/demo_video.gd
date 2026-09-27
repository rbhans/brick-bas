extends SceneTree

# A ~45 s stretch of real play for the demo video, rendered frame by frame
# with Godot's Movie Maker (tools/render_demo_video.sh). Everything goes
# through real input: mouse moves and clicks on the actual HUD, right-drag to
# orbit, the wheel to zoom, WASD and keys in Explore. The OS cursor isn't in
# rendered frames, so a pointer is drawn where the scripted mouse is.
#
# The session picks up mid-morning in the Neighborhood office: the player
# spins round to the back, adds a room with a door and windows, zones it,
# opens the new VAV, speeds up the day, then walks in the front door and
# turns the lobby thermostat down.

const FPS := 60.0
const ORBIT_PER_PIXEL := 0.0065   # CameraRig: yaw change per pixel of right-drag
const LOOK_PER_PIXEL := 0.0062    # Explorer: yaw change per pixel of drag

var game: Node
var pointer: Control
var mouse := Vector2(900, 380)
var held := 0                     # button mask
var ripple := 1.0                 # click ring (0 → 1 after a click)

func _init() -> void:
	run.call_deferred()

# --- Time ------------------------------------------------------------------------------------

func wait(seconds: float) -> void:
	for frame in range(maxi(1, roundi(seconds * FPS))):
		if is_instance_valid(pointer): _process_pointer()
		await process_frame

func smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

# --- The pointer and mouse -----------------------------------------------------------------------

func _make_pointer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	pointer = Control.new()
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pointer)
	var arrow := PackedVector2Array([Vector2(0, 0), Vector2(0, 19), Vector2(4.6, 14.6), Vector2(7.8, 21.6), Vector2(10.6, 20.4), Vector2(7.5, 13.6), Vector2(13.4, 13.6)])
	pointer.draw.connect(func() -> void:
		if ripple < 1.0:
			pointer.draw_arc(Vector2.ZERO, 5.0 + ripple * 14.0, 0.0, TAU, 32, Color(1, 1, 1, 0.8 * (1.0 - ripple)), 2.0, true)
		var shadow := PackedVector2Array()
		for point in arrow: shadow.append(point + Vector2(1.2, 1.6))
		pointer.draw_colored_polygon(shadow, Color(0, 0, 0, 0.28))
		pointer.draw_colored_polygon(arrow, Color.WHITE)
		var outline := arrow.duplicate()
		outline.append(arrow[0])
		pointer.draw_polyline(outline, Color(0.08, 0.08, 0.1), 1.4, true))
	pointer.position = mouse

func _process_pointer() -> void:
	ripple = minf(1.0, ripple + 1.0 / (0.3 * FPS))
	pointer.position = mouse
	pointer.queue_redraw()

func _motion(to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - mouse
	event.velocity = event.relative * FPS
	event.button_mask = held
	mouse = to
	root.push_input(event, true)

func _button(index: MouseButton, pressed: bool) -> void:
	var mask: int = {MOUSE_BUTTON_LEFT: MOUSE_BUTTON_MASK_LEFT, MOUSE_BUTTON_RIGHT: MOUSE_BUTTON_MASK_RIGHT, MOUSE_BUTTON_MIDDLE: MOUSE_BUTTON_MASK_MIDDLE}.get(index, 0)
	held = (held | mask) if pressed else (held & ~mask)
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = mouse
	event.global_position = mouse
	event.button_mask = held
	root.push_input(event, true)

# Glides the mouse to `target` (a point, or a Callable giving one each frame,
# for things that move on screen) along a gentle arc, like a hand would.
func move(target: Variant, seconds: float = 0.5) -> void:
	var start := mouse
	var frames := maxi(1, roundi(seconds * FPS))
	for frame in range(1, frames + 1):
		var goal: Vector2 = target.call() if target is Callable else target
		var t := smooth(float(frame) / frames)
		var bend := (goal - start).orthogonal().normalized() * sin(t * PI) * minf(40.0, start.distance_to(goal) * 0.08)
		_motion(start.lerp(goal, t) + bend)
		_process_pointer()
		await process_frame

func click(button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_button(button, true)
	ripple = 0.0
	await wait(0.07)
	_button(button, false)

func scroll(up: bool) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = mouse
		event.global_position = mouse
		root.push_input(event, true)

func drag(button: MouseButton, by: Vector2, seconds: float) -> void:
	_button(button, true)
	await move(mouse + by, seconds)
	_button(button, false)

func key(code: Key, down: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key(code, true)
	await wait(0.08)
	key(code, false)

# --- Where things are ------------------------------------------------------------------------

func at(point: Vector3) -> Vector2:
	var camera: Camera3D = game.active_camera()
	return camera.unproject_position(point)

func center_of(control: Control) -> Vector2:
	return control.get_global_rect().get_center()

func card_action(tooltip: String) -> Control:
	for child in game.hud.card_actions.get_children():
		if child is Control and String(child.tooltip_text).begins_with(tooltip):
			return child
	return null

func find(kind: String, label_part: String = "") -> Dictionary:
	for item in game.model.objects:
		if String(item.kind) == kind and String(item.properties.get("label", "")).contains(label_part):
			return item
	return {}

# A morning's worth of simulation (and trend history) before the clip starts.
func preroll(hour: float) -> void:
	var sim: RefCounted = game.sim
	while fposmod(float(sim.sim_seconds), 86400.0) < hour * 3600.0:
		sim.step_for_test(60.0)
		var snapshot: Array = game.data.provider.snapshot()
		game.points.apply_updates(snapshot)
		game.history.sample(snapshot, float(sim.sim_seconds))

# Middle-drag the build camera so `point` ends up where the view is centred.
func pan_to(point: Vector3, seconds: float) -> void:
	var rig: Node = game.rig
	var right: Vector3 = rig.camera.global_basis.x * Vector3(1, 0, 1)
	right = right.normalized()
	var forward: Vector3 = rig.forward_flat()
	var scale: float = float(rig.goal_distance) * 0.0016
	var delta: Vector3 = (point - rig.goal_target) * Vector3(1, 0, 1)
	await drag(MOUSE_BUTTON_MIDDLE, Vector2(-delta.dot(right) / scale, delta.dot(forward) / scale), seconds)

# Walks with W held, steering by dragging the view toward `goal` (a point or a
# Callable), until within `near` metres or out of time.
func walk_to(goal: Variant, near: float, seconds: float) -> void:
	var explorer: Node = game.explorer
	key(KEY_W, true)
	_button(MOUSE_BUTTON_LEFT, true)
	var frames := roundi(seconds * FPS)
	for frame in range(frames):
		var point: Vector3 = goal.call() if goal is Callable else goal
		var offset: Vector3 = (point - explorer.player.global_position) * Vector3(1, 0, 1)
		if offset.length() < near:
			break
		var wanted := atan2(-offset.x, -offset.z)
		var turn := wrapf(wanted - float(explorer.goal_yaw), -PI, PI)
		var pixels := clampf(-turn / LOOK_PER_PIXEL, -14.0, 14.0)
		_motion(mouse + Vector2(pixels, 0))
		_process_pointer()
		await process_frame
	_button(MOUSE_BUTTON_LEFT, false)
	key(KEY_W, false)

# --- The session -----------------------------------------------------------------------------

# If a step ever fails, stop anyway rather than record forever.
func _watchdog() -> void:
	for frame in range(roundi(70.0 * FPS)):
		await process_frame
	push_error("demo_video: timed out")
	quit(1)

func run() -> void:
	_watchdog()
	root.mouse_passthrough = true          # the real mouse can't steer anything
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND   # fill 16:9
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.session_ui.hide()
	game.set_graphics("high", false)
	game.start_new_game("office", false)
	preroll(8.85)
	_make_pointer()
	await wait(0.6)

	# Spin round to the back of the building, bring the empty lot to the
	# middle and zoom in on it.
	var lot_center := PlanGrid.cell_center(Vector2i(3, -6))
	await move(Vector2(980, 420), 0.5)
	await drag(MOUSE_BUTTON_RIGHT, Vector2(-470, 24), 1.5)
	await wait(0.5)
	await move(Vector2(760, 470), 0.35)
	await pan_to(lot_center, 0.9)
	await wait(0.45)
	await move(func() -> Vector2: return at(lot_center), 0.4)
	for notch in 2:
		scroll(true)
		await wait(0.22)
	await wait(0.5)

	# A new room off the back: Room tool, drag it out.
	await move(center_of(game.hud.shelf_tiles["tool_room"]), 0.55)
	await click()
	await wait(0.25)
	var corner_a := PlanGrid.vertex_position(Vector2i(1, -7))
	var corner_b := PlanGrid.vertex_position(Vector2i(5, -4))
	await move(func() -> Vector2: return at(corner_a), 0.5)
	_button(MOUSE_BUTTON_LEFT, true)
	await move(func() -> Vector2: return at(corner_b), 1.3)
	await wait(0.15)
	_button(MOUSE_BUTTON_LEFT, false)
	await wait(0.8)
	# Walls down to work inside, then a door through to the conference room.
	await tap(KEY_V)
	await wait(0.3)
	await move(center_of(game.hud.shelf_tiles["tool_door"]), 0.5)
	await click()
	await move(func() -> Vector2: return at(PlanGrid.edge_center("x:3:-4") + Vector3(0, 0.9, 0)), 0.55)
	await wait(0.15)
	await click()
	await wait(0.35)
	# Two windows in the back wall.
	await move(center_of(game.hud.shelf_tiles["tool_window"]), 0.5)
	await click()
	for edge in ["x:2:-7", "x:3:-7"]:
		await move(func() -> Vector2: return at(PlanGrid.edge_center(edge) + Vector3(0, 0.9, 0)), 0.4)
		await click()
		await wait(0.12)
	await wait(0.4)

	# Equipment: the tray says the new room has no air. Zone it.
	await move(center_of(game.hud.mode_buttons[1]), 0.6)
	await click()
	await wait(0.6)
	await move(center_of(game.hud.shelf_tiles["zone"]), 0.5)
	await click()
	var room_center := PlanGrid.cell_center(Vector2i(3, -6)) + Vector3(0, PlanGrid.FLOOR_TOP, 0)
	await move(func() -> Vector2: return at(room_center), 0.6)
	await wait(0.35)
	var before: Array = game.model.objects_of(["vav"]).map(func(item: Dictionary) -> String: return String(item.id))
	await click()
	await wait(0.9)
	await drag(MOUSE_BUTTON_RIGHT, Vector2(-90, 10), 1.3)
	await wait(0.4)

	# Open up the new VAV and let the day run faster.
	var vav: Dictionary = {}
	for item in game.model.objects_of(["vav"]):
		if not before.has(String(item.id)):
			vav = item
	var vav_at: Vector3 = DuctConnections.vector(vav.transform.position) + Vector3(0, 0.7, 0)
	await move(func() -> Vector2: return at(vav_at), 0.55)
	await click()
	await wait(0.8)
	var casing := card_action("Open casing")
	if casing != null:
		await move(center_of(casing), 0.55)
		await click()
	await wait(0.5)
	await move(center_of(game.hud.speed_buttons[3]), 0.7)
	await click()
	await wait(1.2)
	await move(func() -> Vector2: return at(vav_at) + Vector2(60, 40), 0.6)
	await drag(MOUSE_BUTTON_RIGHT, Vector2(150, 0), 1.2)
	await wait(1.2)

	# Walk in the front door and turn the lobby down a couple of degrees.
	await move(center_of(game.hud.mode_buttons[2]), 0.6)
	await click()
	await wait(0.5)
	await move(Vector2(800, 470), 0.4)
	scroll(false)
	await wait(0.3)
	var tstat: Dictionary = find("tstat", "Lobby")
	var tstat_at := DuctConnections.vector(tstat.transform.position)
	var entrance := Vector3.INF
	for door_id in game.arch.doors:
		var door: Dictionary = game.arch.doors[door_id]
		var sides: Array = game.index.edge_rooms(String(door.edge))
		if sides.has("") and String(game.index.room_by_id(String(sides[0] if sides[0] != "" else sides[1])).get("label", "")) == "Lobby":
			entrance = PlanGrid.edge_center(String(door.edge))
	var inside := entrance + (tstat_at - entrance) * Vector3(1, 0, 1) * 0.4
	await walk_to(entrance, 0.6, 3.0)
	await walk_to(inside, 1.0, 2.0)
	await walk_to(tstat_at, 2.1, 2.5)
	await wait(0.5)
	await tap(KEY_E)
	await wait(0.9)
	await tap(KEY_MINUS)
	await wait(0.55)
	await tap(KEY_MINUS)
	await wait(1.3)
	await tap(KEY_ESCAPE)
	await wait(0.4)
	# Across the lobby into the open office.
	var into_office := Vector3.INF
	for door_id in game.arch.doors:
		var door: Dictionary = game.arch.doors[door_id]
		var names: Array = game.index.edge_rooms(String(door.edge)).map(func(id: String) -> String: return String(game.index.room_by_id(id).get("label", "")))
		if names.has("Lobby") and names.has("Open office"):
			into_office = PlanGrid.edge_center(String(door.edge))
	if into_office != Vector3.INF:
		await walk_to(into_office, 0.7, 3.2)
		await walk_to(into_office + Vector3(3.0, 0, 0), 0.8, 1.6)
	await wait(0.5)
	# Back to building for the whole picture, the day still running fast.
	await tap(KEY_TAB)
	await wait(0.6)
	await move(Vector2(820, 430), 0.4)
	scroll(false)
	await wait(0.25)
	scroll(false)
	await wait(2.2)
	quit()
