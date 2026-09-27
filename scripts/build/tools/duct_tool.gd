class_name DuctTool
extends BuildTool

# Duct runs: click a socket (they glow as you pass), then a matching socket
# and the run routes itself over the walls. Click open space in between to
# lay manual bends at the current height; PageUp / PageDown change it.

const Ducts := preload("res://scripts/build/duct_geometry.gd")
const DuctPorts := preload("res://scripts/build/duct_connections.gd")
const Bindings := preload("res://scripts/data/animation_binding.gd")

var elevation := DuctPorts.ROUTE_HEIGHT
var anchor := Vector3.INF
var cursor := Vector3.INF
var waypoints: Array = []
var start_port: Dictionary = {}
var hover_port: Dictionary = {}
var socket_marks: Node3D

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "duct"
	label = "Duct run"
	shows_grid = false

func enter() -> void:
	_mark_sockets()
	super.enter()

func exit() -> void:
	if is_instance_valid(socket_marks):
		socket_marks.free()
	super.exit()

func cancel() -> bool:
	if anchor != Vector3.INF:
		anchor = Vector3.INF
		waypoints.clear()
		start_port.clear()
		clear_ghost()
		game.set_status("Duct run cancelled · click a socket to start again")
		return true
	return super.cancel()

# Every free socket gets a small yellow collar so they are easy to find.
func _mark_sockets() -> void:
	if is_instance_valid(socket_marks):
		socket_marks.free()
	socket_marks = Node3D.new()
	socket_marks.name = "Free sockets"
	game.ghost_root.add_child(socket_marks)
	for item in game.model.objects:
		for name in DuctPorts.port_names(item):
			var port := DuctPorts.port(item, name)
			if DuctPorts.occupied(port, game.model.objects):
				continue
			var mark := Bricks.place_centered(socket_marks, "4032a", port.position, Color("ffd23f"), Basis(Vector3.UP, 0.0))
			mark.material_override = Bricks.material(Color("ffd23f"), 0.6)
			mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _nearest_port(mouse: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var nearest := 34.0
	var camera: Camera3D = game.rig.camera
	for item in game.model.objects:
		for name in DuctPorts.port_names(item):
			var port := DuctPorts.port(item, name)
			if DuctPorts.occupied(port, game.model.objects) or camera.is_position_behind(port.position):
				continue
			if not start_port.is_empty() and port.owner == start_port.owner:
				continue
			var distance := mouse.distance_to(camera.unproject_position(port.position))
			if distance < nearest:
				nearest = distance
				best = port
	return best

func hover(mouse: Vector2) -> void:
	hover_port = _nearest_port(mouse)
	if not hover_port.is_empty():
		cursor = hover_port.position
	else:
		var point: Vector3 = game.rig.ground_point(mouse, elevation)
		if point == Vector3.INF:
			return
		cursor = Vector3(snappedf(point.x, 0.25), elevation, snappedf(point.z, 0.25))
		if anchor != Vector3.INF:
			var delta := cursor - anchor
			if absf(delta.x) >= absf(delta.z): cursor.z = anchor.z
			else: cursor.x = anchor.x
			cursor.y = elevation
	_preview()

func _candidate() -> Dictionary:
	var points: Array = waypoints.duplicate()
	points.append([cursor.x, cursor.y, cursor.z])
	var props := {"waypoints": points, "service": "supply_air", "profile": "brick_1.0_outer_0.6_inner", "enabled": true}
	if not start_port.is_empty():
		props.start_port = {"owner": start_port.owner, "port": start_port.port}
	if not hover_port.is_empty():
		props.end_port = {"owner": hover_port.owner, "port": hover_port.port}
		if not start_port.is_empty() and waypoints.size() == 1:
			var routed := DuctPorts.auto_route(start_port, hover_port, game.model.objects)
			if bool(routed.ok):
				return routed.properties
			props.error = String(routed.message)
	return props

func _preview() -> void:
	new_ghost()
	if anchor == Vector3.INF:
		var dot := Bricks.place_centered(ghost, "4032a", cursor, "ffd23f")
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		game.set_status("Duct run · %s · PageUp/PageDown height %s" % ["click this %s socket to start" % String(hover_port.port).replace("_", " ") if not hover_port.is_empty() else "click a socket (or open space) to start", Units.length(elevation)])
		return
	var props := _candidate()
	var error := String(props.get("error", ""))
	if error.is_empty():
		error = DuctPorts.route_error(props, game.model.objects)
	if error.is_empty() and not start_port.is_empty() and not hover_port.is_empty():
		error = String(DuctPorts.compatible(start_port, hover_port).message)
	var path := DuctPorts.path(props, game.model.objects)
	if path.size() >= 2:
		Ducts.path_shell(ghost, path, Color("66c79a") if error.is_empty() else Color("d9695a"), props.has("start_port"), props.has("end_port"))
		BuildTool.ghostify(ghost, error.is_empty())
	var length := 0.0
	for index in range(path.size() - 1):
		length += path[index].distance_to(path[index + 1])
	if not error.is_empty():
		game.set_status(error)
	elif not hover_port.is_empty():
		game.set_status("Click to connect · %s run · routes over the walls" % Units.length(length))
	else:
		game.set_status("Duct run · %s · click to bend here · click a socket to finish · Esc cancels" % Units.length(length))

func press(_mouse: Vector2) -> void:
	if cursor == Vector3.INF:
		return
	if anchor == Vector3.INF:
		anchor = cursor
		start_port = hover_port.duplicate()
		waypoints = [[cursor.x, cursor.y, cursor.z]]
		if not start_port.is_empty():
			elevation = maxf(elevation, DuctPorts.ROUTE_HEIGHT)
		game.play_sound("tick")
		_preview()
		return
	var props := _candidate()
	var error := String(props.get("error", ""))
	if error.is_empty():
		error = DuctPorts.route_error(props, game.model.objects)
	if error.is_empty() and not start_port.is_empty() and not hover_port.is_empty():
		error = String(DuctPorts.compatible(start_port, hover_port).message)
	if not error.is_empty():
		game.play_sound("error")
		game.set_status(error)
		return
	if hover_port.is_empty():
		# A manual bend: keep going from here.
		waypoints.append([cursor.x, cursor.y, cursor.z])
		anchor = cursor
		game.play_sound("tick")
		return
	props.erase("error")
	props.bindings = Bindings.defaults("duct")
	var result: Dictionary = game.apply("Duct run", [{"kind": "duct", "transform": {"position": [0, 0, 0], "rotation_y": 0.0}, "properties": props}])
	game.flash(result.added)
	game.play_sound("place")
	game.set_status("Connected %s → %s" % [game.describe(String(props.start_port.owner)) if props.has("start_port") else "open end", game.describe(String(hover_port.owner))])
	anchor = Vector3.INF
	waypoints.clear()
	start_port.clear()
	hover_port.clear()
	clear_ghost()
	_mark_sockets()

func key(event: InputEventKey) -> bool:
	match event.physical_keycode:
		KEY_PAGEUP, KEY_BRACKETRIGHT:
			elevation = clampf(elevation + 0.25, 0.5, 8.0)
			hover(last_mouse)
			return true
		KEY_PAGEDOWN, KEY_BRACKETLEFT:
			elevation = clampf(elevation - 0.25, 0.5, 8.0)
			hover(last_mouse)
			return true
	return false
