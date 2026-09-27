class_name CameraRig
extends Node3D

# Sims-style build camera: everything eases toward a target state so orbiting,
# panning, zooming and snapping never pop.
#
#   right-drag  orbit          middle-drag / WASD / arrows  pan
#   wheel       zoom to cursor  Q / E  rotate 45°           Home  frame the lot

signal moved

const PITCH_MIN := -1.45
const PITCH_MAX := -0.22
const DISTANCE_MIN := 5.0
const DISTANCE_MAX := 240.0

var camera: Camera3D
var target := Vector3.ZERO
var yaw := -0.62
var pitch := -0.82
var distance := 60.0
var goal_target := Vector3.ZERO
var goal_yaw := -0.62
var goal_pitch := -0.82
var goal_distance := 60.0
var orbiting := false
var panning := false
var input_enabled := true
var pan_keys_enabled := true
var bounds := AABB(Vector3(-400, 0, -400), Vector3(800, 20, 800))

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Build camera"
	camera.fov = 36.0
	# The rig never gets closer than DISTANCE_MIN, so a deep near plane buys
	# depth precision (the web renderer has no reverse-Z) and stops shimmer.
	camera.near = 0.5
	camera.far = 1500.0
	add_child(camera)
	_apply()

func current() -> bool:
	return camera.current

func make_current() -> void:
	camera.make_current()

func set_view(new_target: Vector3, new_yaw: float, new_pitch: float, new_distance: float, instant: bool = false) -> void:
	goal_target = new_target
	goal_yaw = new_yaw
	goal_pitch = clampf(new_pitch, PITCH_MIN, PITCH_MAX)
	goal_distance = clampf(new_distance, DISTANCE_MIN, DISTANCE_MAX)
	if instant:
		target = goal_target
		yaw = goal_yaw
		pitch = goal_pitch
		distance = goal_distance
		_apply()

func frame_box(box: AABB, instant: bool = false) -> void:
	var span := maxf(box.size.x, box.size.z)
	set_view(box.get_center() * Vector3(1, 0, 1) + Vector3(0, 0.5, 0), goal_yaw, -0.86, clampf(span * 1.35 + 12.0, 14.0, 200.0), instant)

func forward_flat() -> Vector3:
	var forward := -camera.global_basis.z
	forward.y = 0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD

func handle_input(event: InputEvent) -> bool:
	if not input_enabled:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				orbiting = button.pressed
				return true
			MOUSE_BUTTON_MIDDLE:
				panning = button.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom_at(button.position, 0.86 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.86)
				return true
	elif event is InputEventMagnifyGesture:
		zoom_at((event as InputEventMagnifyGesture).position, 1.0 / (event as InputEventMagnifyGesture).factor)
		return true
	elif event is InputEventPanGesture:
		var gesture := event as InputEventPanGesture
		_pan_pixels(-gesture.delta * 18.0)
		return true
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if orbiting:
			goal_yaw -= motion.relative.x * 0.0065
			goal_pitch = clampf(goal_pitch - motion.relative.y * 0.0055, PITCH_MIN, PITCH_MAX)
			return true
		if panning:
			_pan_pixels(motion.relative)
			return true
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
			return false
		match key.physical_keycode:
			KEY_Q:
				rotate_step(1)
				return true
			KEY_E:
				rotate_step(-1)
				return true
	return false

func rotate_step(direction: int) -> void:
	goal_yaw += float(direction) * PI * 0.25

func zoom_at(screen: Vector2, factor: float) -> void:
	var before := ground_point(screen)
	goal_distance = clampf(goal_distance * factor, DISTANCE_MIN, DISTANCE_MAX)
	if before != Vector3.INF:
		# Pull the focus toward the cursor so zooming follows the pointer.
		var pull := (1.0 - factor) * 0.9
		goal_target += (before - goal_target) * Vector3(1, 0, 1) * clampf(pull, -0.6, 0.6)

func _pan_pixels(relative: Vector2) -> void:
	var right := camera.global_basis.x
	right.y = 0
	right = right.normalized()
	var forward := forward_flat()
	var scale := goal_distance * 0.0016
	goal_target += (-right * relative.x + forward * relative.y) * scale

func _process(delta: float) -> void:
	if input_enabled and pan_keys_enabled and not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_META):
		var move := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): move.y += 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): move.y -= 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): move.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): move.x += 1
		if move != Vector2.ZERO:
			var right := camera.global_basis.x
			right.y = 0
			var speed := goal_distance * (1.9 if Input.is_physical_key_pressed(KEY_SHIFT) else 0.95)
			goal_target += (right.normalized() * move.x + forward_flat() * move.y) * speed * delta
	goal_target = goal_target.clamp(bounds.position, bounds.end)
	var weight := 1.0 - exp(-delta * 12.0)
	var previous := [target, yaw, pitch, distance]
	target = target.lerp(goal_target, weight)
	yaw = lerp_angle(yaw, goal_yaw, weight)
	pitch = lerpf(pitch, goal_pitch, weight)
	distance = lerpf(distance, goal_distance, weight)
	if previous != [target, yaw, pitch, distance]:
		_apply()
		moved.emit()

func _apply() -> void:
	if camera == null:
		return
	var orbit := Basis.from_euler(Vector3(pitch, yaw, 0))
	camera.global_position = target + orbit * Vector3(0, 0, distance)
	camera.look_at(target, Vector3.UP)

func ground_point(screen: Vector2, height: float = 0.0) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP, height).intersects_ray(origin, direction)
	return hit if hit is Vector3 else Vector3.INF

func state() -> Dictionary:
	return {"target": [goal_target.x, goal_target.y, goal_target.z], "yaw": goal_yaw, "pitch": goal_pitch, "distance": goal_distance}

func restore(data: Dictionary) -> void:
	if data.is_empty():
		return
	var values: Array = data.get("target", [0, 0, 0])
	set_view(Vector3(float(values[0]), float(values[1]), float(values[2])), float(data.get("yaw", goal_yaw)), float(data.get("pitch", goal_pitch)), float(data.get("distance", goal_distance)), true)
