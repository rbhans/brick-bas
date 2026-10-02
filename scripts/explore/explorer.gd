extends Node3D

# Explore mode: a minifigure walks the building. Interactions are proximity
# based: the HUD shows a key prompt beside whatever you face.
# Doors swing away from you as you walk into them and close behind you;
# E uses things (doors, chairs, thermostats, equipment access doors).

const Minifigure := preload("res://scripts/build/minifigure.gd")
const WALK_SPEED := 3.4
const RUN_SPEED := 6.0
const REACH := 2.7
const ZOOM_MIN := 3.5
const ZOOM_MAX := 26.0

var game: Node
var player: CharacterBody3D
var figure: Node3D
var camera: Camera3D
var active := false
var view_yaw := 0.4
var view_pitch := -0.62
var view_distance := 11.0
var goal_yaw := 0.4
var goal_pitch := -0.62
var goal_distance := 11.0
var drag_button := MOUSE_BUTTON_NONE
var drag_travel := 0.0
var interactables: Array[Dictionary] = []
var target: Dictionary = {}
var open_doors: Dictionary = {}     # door id -> bool (player's explicit/automatic state)
var door_auto: Dictionary = {}      # door id -> seconds since the player left (auto-opened doors)
var door_angles: Dictionary = {}    # door id -> current swing angle
var door_sides: Dictionary = {}     # door id -> +1/-1 swing direction chosen at opening
var seated: Dictionary = {}
var seat_return := Vector3.ZERO
var _focus := Vector3.ZERO

func setup(owner: Node) -> void:
	game = owner
	name = "Explorer"
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 1
	player.floor_snap_length = 0.35
	player.floor_max_angle = deg_to_rad(50.0)
	player.safe_margin = 0.05
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 2.3
	shape.shape = capsule
	shape.position.y = 1.15
	player.add_child(shape)
	figure = Minifigure.new()
	player.add_child(figure)
	add_child(player)
	player.visible = false
	camera = Camera3D.new()
	camera.name = "Explore camera"
	camera.fov = 44.0
	camera.near = 0.2
	camera.far = 800.0
	add_child(camera)
	set_physics_process(true)

func reset_state() -> void:
	open_doors.clear()
	door_auto.clear()
	door_angles.clear()
	door_sides.clear()
	seated = {}

func reset_player() -> void:
	var spawn: Array = game.model.site.get("spawn", [0, 1, 2.5])
	player.global_position = Vector3(float(spawn[0]), maxf(float(spawn[1]), 0.3), float(spawn[2]))
	player.velocity = Vector3.ZERO
	_focus = player.global_position

# Puts the minifigure on a clear spot near `target` (a service call's
# "walk over"), preferring the room the target is in, facing it.
func teleport_near(target: Vector3) -> bool:
	var room: Dictionary = game.index.room_at(Vector3(target.x, 0.0, target.z))
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 2.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var best := Vector3.INF
	var best_score := INF
	for radius in [1.3, 1.9, 2.5, 3.1]:
		for step in range(12):
			var angle := TAU * float(step) / 12.0
			var point := Vector3(target.x + cos(angle) * radius, PlanGrid.FLOOR_TOP + 0.08, target.z + sin(angle) * radius)
			var here: Dictionary = game.index.room_at(point)
			var score: float = float(radius) + (0.0 if String(here.get("id", "")) == String(room.get("id", "")) else 4.0)
			if score >= best_score: continue
			query.transform = Transform3D(Basis(), point + Vector3(0, 1.15, 0))
			if not space.intersect_shape(query, 1).is_empty(): continue
			best = point
			best_score = score
	if best == Vector3.INF: return false
	seated = {}
	figure.sit(false)
	player.global_position = best
	player.velocity = Vector3.ZERO
	figure.rotation.y = atan2(-(target.x - best.x), -(target.z - best.z))
	goal_yaw = figure.rotation.y + PI
	_focus = best + Vector3(0, 1.3, 0)
	return true

func activate(on: bool) -> void:
	active = on
	player.visible = on
	game.hud.hide_prompt()
	# A thermostat opened in Build would otherwise take the wheel in Explore.
	game.hud.hide_thermostat()
	if on:
		seated = {}
		figure.sit(false)
		if not _on_ground_or_floor(player.global_position):
			reset_player()
		_focus = player.global_position
		view_yaw = game.rig.yaw
		goal_yaw = view_yaw
		_apply_camera(1.0)
		camera.make_current()
		game.set_hover("")
	else:
		game.set_hover("")

func _on_ground_or_floor(point: Vector3) -> bool:
	return point.y > -1.0 and point.length() < 1500.0

func focus_point() -> Vector3:
	return _focus

func cut_radius() -> float:
	return clampf(view_distance * 0.75, 6.0, 14.0)

func escape() -> bool:
	if game.hud.thermostat_open():
		game.hud.hide_thermostat()
		return true
	if not seated.is_empty():
		_stand()
		return true
	return false

# --- Interactables --------------------------------------------------------------------

func refresh() -> void:
	interactables.clear()
	for door_id in game.arch.doors:
		var door: Dictionary = game.arch.doors[door_id]
		var center := PlanGrid.edge_center(String(door.edge)) + Vector3(0, 1.0, 0)
		interactables.append({"id": String(door_id), "kind": "door", "position": center, "edge": String(door.edge)})
	for item in game.model.objects:
		if item.kind == "tstat" and (game.job == null or game.job.type != "service"):
			interactables.append({"id": String(item.id), "kind": "tstat", "position": game.vector(item.transform.position)})
	for seat in game.furniture_seats():
		interactables.append(seat)
	if game.job != null and game.job.type == "service":
		# Service calls: every air handler, VAV and thermostat can be worked on.
		for item in game.model.objects:
			if String(item.kind) not in ["ahu", "vav", "tstat"]: continue
			var owner := String(item.id)
			var at: Vector3 = game.vector(item.transform.position) + (Vector3(0, 1.0, 0) if item.kind == "ahu" else Vector3.ZERO)
			interactables.append({"id": owner, "kind": "service", "position": at, "action": func() -> void: game.hud.open_service(owner)})
	for entry in game.equipment.interactables():
		interactables.append(entry)
	# Doors that no longer exist forget their state.
	for door_id in open_doors.keys():
		if not game.arch.doors.has(door_id): open_doors.erase(door_id)

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			drag_button = button.button_index
			drag_travel = 0.0
		elif not button.pressed and button.button_index == drag_button:
			if drag_button == MOUSE_BUTTON_LEFT and drag_travel < 6.0:
				_click(button.position)
			drag_button = MOUSE_BUTTON_NONE
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			if game.hud.thermostat_open(): game.hud.nudge_thermostat(1.0)
			else: goal_distance = clampf(goal_distance / 1.12, ZOOM_MIN, ZOOM_MAX)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if game.hud.thermostat_open(): game.hud.nudge_thermostat(-1.0)
			else: goal_distance = clampf(goal_distance * 1.12, ZOOM_MIN, ZOOM_MAX)
	elif event is InputEventMouseMotion and drag_button != MOUSE_BUTTON_NONE:
		var motion := event as InputEventMouseMotion
		drag_travel += motion.relative.length()
		goal_yaw -= motion.relative.x * 0.0062
		goal_pitch = clampf(goal_pitch - motion.relative.y * 0.005, -1.4, -0.12)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.physical_keycode:
			KEY_E, KEY_ENTER:
				interact()
			KEY_HOME:
				goal_yaw = figure.global_rotation.y + PI
				goal_pitch = -0.62
				goal_distance = 11.0
			KEY_EQUAL, KEY_KP_ADD:
				if game.hud.thermostat_open(): game.hud.nudge_thermostat(1.0)
			KEY_MINUS, KEY_KP_SUBTRACT:
				if game.hud.thermostat_open(): game.hud.nudge_thermostat(-1.0)

func _click(mouse: Vector2) -> void:
	var hit: Dictionary = game.pick(mouse, 80.0)
	var id := String(hit.get("id", ""))
	if id.is_empty():
		return
	# An air handler offers one entry per access door: use the one clicked.
	var clicked: Dictionary = {}
	for entry in interactables:
		if String(entry.id) == id and _distance(entry) < REACH + 1.0:
			if clicked.is_empty() or hit.position.distance_to(entry.position) < hit.position.distance_to(clicked.position):
				clicked = entry
	if not clicked.is_empty():
		_use(clicked)
		return
	game.select(id)

func interact() -> void:
	if not seated.is_empty():
		_stand()
		return
	if game.hud.thermostat_open():
		game.hud.hide_thermostat()
		return
	if target.is_empty():
		return
	_use(target)

func _use(entry: Dictionary) -> void:
	match String(entry.kind):
		"door":
			_toggle_door(String(entry.id), false)
		"tstat":
			game.select(String(entry.id))
			game.hud.show_thermostat(String(entry.id))
			game.play_sound("open")
		"seat":
			_sit(entry)
		_:
			if entry.has("action"):
				(entry.action as Callable).call()

func _distance(entry: Dictionary) -> float:
	var position: Vector3 = entry.position
	return Vector2(position.x - player.global_position.x, position.z - player.global_position.z).length()

# --- Doors ------------------------------------------------------------------------------

func _toggle_door(id: String, automatic: bool) -> void:
	var opening := not bool(open_doors.get(id, false))
	if opening:
		var door: Dictionary = game.arch.doors.get(id, {})
		if door.is_empty(): return
		# Swing away from whoever pushes it: a positive hinge angle moves the
		# leaf toward the edge's negative-normal side.
		var normal := PlanGrid.edge_normal(String(door.edge))
		var side := signf((player.global_position - PlanGrid.edge_center(String(door.edge))).dot(normal))
		door_sides[id] = side if side != 0.0 else 1.0
	open_doors[id] = opening
	if automatic and opening: door_auto[id] = 0.0
	else: door_auto.erase(id)
	game.play_sound("open" if opening else "close")
	game.sync_openings()

func _update_doors(delta: float) -> void:
	for id in game.arch.doors:
		var door: Dictionary = game.arch.doors[id]
		var hinge: Node3D = door.hinge
		if not is_instance_valid(hinge): continue
		var open := bool(open_doors.get(id, false))
		var direction := float(door_sides.get(id, door.swing))
		var goal := direction * PI * 0.48 if open else 0.0
		var current := float(door_angles.get(id, 0.0))
		current = goal if game.reduced_motion else move_toward(current, goal, delta * 3.6)
		door_angles[id] = current
		hinge.rotation.y = PlanGrid.edge_rotation(String(door.edge)) + current
		if door_auto.has(id):
			var away := _distance({"position": PlanGrid.edge_center(String(door.edge))}) > 2.4
			door_auto[id] = float(door_auto[id]) + delta if away else 0.0
			if float(door_auto[id]) > 1.6:
				_toggle_door(String(id), true)
				door_auto.erase(id)

# Walking into a closed door opens it (like a real push door).
func _auto_open(direction: Vector3) -> void:
	if direction.length_squared() < 0.01:
		return
	for entry in interactables:
		if entry.kind != "door" or bool(open_doors.get(entry.id, false)):
			continue
		var center := PlanGrid.edge_center(String(entry.edge))
		var offset := center - player.global_position
		offset.y = 0
		if offset.length() < 1.5 and offset.normalized().dot(direction.normalized()) > 0.55:
			_toggle_door(String(entry.id), true)

# --- Sitting ----------------------------------------------------------------------------

func _sit(entry: Dictionary) -> void:
	seated = entry.duplicate()
	seat_return = player.global_position
	player.velocity = Vector3.ZERO
	player.global_position = entry.position
	figure.rotation.y = float(entry.get("facing", 0.0))
	figure.sit(true)
	game.play_sound("select")
	game.set_status("Sitting · E or move to stand up")

func _stand() -> void:
	seated = {}
	figure.sit(false)
	player.global_position = seat_return
	game.play_sound("select")

# --- Frame loop -------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_update_doors(delta)
	if not active:
		return
	var blocked: bool = game.session_ui.visible or game.hud.typing()
	var input := Vector2.ZERO if blocked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if not seated.is_empty():
		if input.length() > 0.2:
			_stand()
		else:
			_apply_camera(delta)
			_update_target()
			return
	var direction := Basis(Vector3.UP, view_yaw) * Vector3(input.x, 0, input.y)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var running := Input.is_physical_key_pressed(KEY_SHIFT)
	var target_velocity := direction * (RUN_SPEED if running else WALK_SPEED)
	var acceleration := 18.0 if direction.length_squared() > 0.001 else 24.0
	player.velocity.x = move_toward(player.velocity.x, target_velocity.x, acceleration * delta)
	player.velocity.z = move_toward(player.velocity.z, target_velocity.z, acceleration * delta)
	# Step up plate-height curbs (floor tiles, paving) without climbing walls.
	if player.is_on_floor() and direction.length_squared() > 0.01:
		var step := direction.normalized() * 0.2
		if player.test_move(player.global_transform, step):
			var raised := player.global_transform.translated(Vector3.UP * 0.26)
			if not player.test_move(raised, step):
				player.global_position.y += 0.26
	if player.is_on_floor():
		player.velocity.y = -0.5
		if not blocked and Input.is_physical_key_pressed(KEY_SPACE):
			player.velocity.y = 6.2
	else:
		player.velocity.y -= 19.0 * delta
	player.move_and_slide()
	_auto_open(direction)
	var flat := Vector2(player.velocity.x, player.velocity.z)
	if flat.length() > 0.2:
		figure.rotation.y = lerp_angle(figure.rotation.y, atan2(-flat.x, -flat.y), minf(delta * 12.0, 1.0))
	figure.animate_walk(delta, flat.length(), game.reduced_motion)
	if player.global_position.y < -6.0:
		reset_player()
	_apply_camera(delta)
	_update_target()

func _apply_camera(delta: float) -> void:
	var weight := 1.0 - exp(-delta * 10.0)
	view_yaw = lerp_angle(view_yaw, goal_yaw, weight)
	view_pitch = lerpf(view_pitch, goal_pitch, weight)
	view_distance = lerpf(view_distance, goal_distance, weight)
	_focus = _focus.lerp(player.global_position + Vector3(0, 1.3, 0), 1.0 - exp(-delta * 14.0))
	var boom := Basis.from_euler(Vector3(view_pitch, view_yaw, 0)) * Vector3(0, 0, view_distance)
	camera.global_position = _focus + boom
	if camera.global_position.y < 0.6:
		camera.global_position.y = 0.6
	camera.look_at(_focus, Vector3.UP)

func _update_target() -> void:
	var best: Dictionary = {}
	var best_score := INF
	var facing := -figure.global_basis.z
	facing.y = 0
	facing = facing.normalized()
	for entry in interactables:
		var offset: Vector3 = entry.position - player.global_position
		var flat := Vector3(offset.x, 0, offset.z)
		var distance := flat.length()
		if distance > REACH or absf(offset.y) > 4.5:
			continue
		var alignment := facing.dot(flat.normalized()) if distance > 0.05 else 1.0
		if alignment < -0.25:
			continue
		var score := distance - alignment * 0.9
		if score < best_score:
			best_score = score
			best = entry
	if String(best.get("id", "")) != String(target.get("id", "")) or String(best.get("kind", "")) != String(target.get("kind", "")) or String(best.get("access_key", "")) != String(target.get("access_key", "")):
		target = best
		game.set_hover(String(target.get("id", "")))
	if target.is_empty() or not seated.is_empty():
		game.hud.hide_prompt()
		return
	var detail := ""
	if String(target.kind) in ["equipment", "service"]:
		detail = game.equipment.short_readout(String(target.id))
	elif String(target.kind) == "tstat":
		var info: Dictionary = game.thermostat_info(String(target.id))
		if info.has("temp_c") and is_finite(float(info.temp_c)) and is_finite(float(info.get("setpoint_c", NAN))): detail = "%s · set %s" % [Units.temp(float(info.temp_c), 1), Units.temp(float(info.setpoint_c))]
	var anchor: Vector3 = target.position
	# Ceiling equipment gets its prompt just below it, everything else beside it.
	var lift := 0.4 if target.kind == "tstat" or (target.kind == "service" and anchor.y < 2.5 and anchor.y > 1.0) else (-0.4 if anchor.y > 3.0 else 0.9)
	game.hud.show_prompt(_prompt_text(target), detail, anchor + Vector3(0, lift, 0))

func _prompt_text(entry: Dictionary) -> String:
	match String(entry.kind):
		"door": return "Close door" if bool(open_doors.get(entry.id, false)) else "Open door"
		"tstat": return "Adjust thermostat"
		"seat": return "Sit"
		"service": return "Service %s" % game.describe(String(entry.id))
		"equipment":
			if entry.has("access_key"):
				var text := String(entry.prompt).trim_prefix("Open ")
				return ("Close " if game.equipment.access_open(String(entry.access_key)) else "Open ") + text
			if entry.has("casing"):
				return ("Close" if bool(game.equipment.open_casings.get(String(entry.id), false)) else "Open") + " VAV casing"
			if entry.has("airflow"):
				return "Hide airflow" if game.equipment.airflow_view else "Show airflow in the ducts"
	return String(entry.get("prompt", "Use"))
