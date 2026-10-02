class_name EquipmentTool
extends BuildTool

# Places air handlers on the floor and VAVs, fittings and diffusers in the
# ceiling space. The ghost glides to its snapped spot; R turns it; placing a
# VAV, fitting or diffuser tries to duct it to the nearest free socket so a
# new zone is usually live in one click.

const DuctPorts := preload("res://scripts/build/duct_connections.gd")
const Bindings := preload("res://scripts/data/animation_binding.gd")

var kind := "vav"
var properties: Dictionary = {}
var rotation := 0.0
var moving_id := ""
var target := Transform3D.IDENTITY
var shown := Transform3D.IDENTITY
var valid := false
var reason := ""
var visible_target := false

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	kind = String(tool_params.get("kind", "vav"))
	id = "equipment"
	label = {"ahu": "Air handler", "vav": "VAV", "diffuser": "Diffuser", "tee": "Supply tee", "cross": "Trunk cross"}.get(kind, kind.capitalize())
	moving_id = String(tool_params.get("moving_id", ""))
	rotation = float(tool_params.get("rotation", 0.0))
	properties = tool_params.get("properties", {}).duplicate(true)
	if properties.is_empty() and kind in ["ahu", "vav"]:
		properties = owner.equipment.current_config(kind)
	shows_grid = kind == "ahu"

func enter() -> void:
	if not moving_id.is_empty():
		game.hide_object(moving_id, true)
	new_ghost()
	var body := Node3D.new()
	ghost.add_child(body)
	game.equipment.build_preview(body, kind, properties)
	BuildTool.ghostify(ghost, true)
	_label_ports(body)
	valid = true
	ghost.visible = false
	super.enter()

# Floating tags on the ghost's sockets show which way the air goes before
# it's placed (they turn with it when R rotates the piece).
func _label_ports(body: Node3D) -> void:
	var library := Placement.equipment_models()
	if library == null:
		return
	var names := {"ahu": {"inlet": "Outside air in", "outlet": "Supply air out »"}, "vav": {"inlet": "Supply in", "outlet": "To diffusers »"}, "diffuser": {"inlet": "Duct in"}}
	for port_name in library.port_names(kind):
		var local: Dictionary = library.port_local(kind, properties, port_name)
		var tag := Label3D.new()
		tag.text = String(names.get(kind, {}).get(port_name, "in" if port_name == "inlet" else "out"))
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.render_priority = 20   # drawn after the see-through ghost
		tag.outline_render_priority = 19
		tag.pixel_size = 0.012
		tag.font_size = 40
		tag.outline_size = 10
		tag.modulate = Color("ffe28a") if port_name == "inlet" else Color("9fe8ff")
		tag.position = (local.face as Vector3) + (local.normal as Vector3) * 0.6 + Vector3(0, 0.9, 0)
		body.add_child(tag)

func exit() -> void:
	if not moving_id.is_empty():
		game.hide_object(moving_id, false)
	super.exit()

func footprint() -> Vector2i:
	var library := Placement.equipment_models()
	return library.footprint(kind, properties) if library != null else Vector2i(4, 4)

func mount_height(floor_height: float) -> float:
	var library := Placement.equipment_models()
	match kind:
		"ahu":
			return floor_height
		"diffuser":
			return game.equipment.CEILING_FACE
	if library == null:
		return DuctPorts.ROUTE_HEIGHT
	var names: Array = library.port_names(kind)
	var local: Dictionary = library.port_local(kind, properties, String(names[0]))
	return DuctPorts.ROUTE_HEIGHT - float((local.get("face", Vector3.ZERO) as Vector3).y)

func hover(mouse: Vector2) -> void:
	var height: float = PlanGrid.FLOOR_TOP if kind == "ahu" else float(game.equipment.CEILING_FACE)
	var point: Vector3 = game.rig.ground_point(mouse, height)
	if point == Vector3.INF:
		return
	var size := footprint()
	var turned := PlanGrid.rotated_footprint(size, rotation)
	var center := Vector3(PlanGrid.snap_part_center(point.x, turned.x), 0.0, PlanGrid.snap_part_center(point.z, turned.y))
	center.y = mount_height(game.placement.floor_height(center))
	target = Transform3D(Bricks.basis_y(rotation), center)
	var was_valid := valid
	reason = _problem(center, size)
	valid = reason.is_empty()
	if not visible_target:
		shown = target
		visible_target = true
	ghost.visible = true
	if was_valid != valid:
		BuildTool.ghostify(ghost, valid)
	game.show_footprint(Transform3D(target.basis, Vector3(center.x, game.placement.floor_height(center), center.z)), size, valid, false)
	var where := "on the floor" if kind == "ahu" else "in the ceiling space"
	game.set_status("%s · %s · R turns · click to place%s" % [label, where if valid else reason, "" if moving_id.is_empty() else " · Esc puts it back"])

func _problem(center: Vector3, size: Vector2i) -> String:
	if kind == "ahu":
		for stud in Placement.footprint_studs(center, size, rotation):
			var owner := String(game.placement.studs.get(stud, ""))
			if not owner.is_empty() and owner != moving_id:
				return "Blocked by %s" % game.describe(owner)
		return ""
	if kind == "diffuser" and not game.index.is_indoors(center):
		return "Diffusers go in a room's ceiling"
	for stud in Placement.footprint_studs(center, size, rotation):
		var owner := String(game.equipment_ceiling().get(stud, ""))
		if not owner.is_empty() and owner != moving_id:
			return "Overlaps %s" % game.describe(owner)
	return ""

func process(delta: float) -> void:
	if not is_instance_valid(ghost) or not visible_target:
		return
	var weight := 1.0 - exp(-delta * 26.0)
	shown = Transform3D(shown.basis.slerp(target.basis, weight).orthonormalized(), shown.origin.lerp(target.origin, weight))
	ghost.transform = shown

func press(_mouse: Vector2) -> void:
	if not visible_target:
		return
	if not valid:
		game.play_sound("error")
		game.set_status(reason)
		return
	var position := target.origin
	var transform := {"position": [position.x, position.y, position.z], "rotation_y": rotation}
	if not moving_id.is_empty():
		var moved: Dictionary = game.model.find_object(moving_id).duplicate(true)
		moved.transform = transform
		# Its ducts follow it: auto-routed runs are laid again in the same step.
		var replanner := ZonePlanner.new(game.model.objects, game.index, game.model.new_id)
		replanner.reroute_attached(moved)
		if not replanner.blocked.is_empty():
			game.play_sound("error")
			game.set_status("Can't put it there: it would sit on the duct to %s" % replanner.blocked[0])
			return
		game.hide_object(moving_id, false)
		var moved_id := moving_id
		moving_id = ""
		game.apply("Move " + label, replanner.entries, replanner.removed_ids(), [moved])
		if not replanner.unhooked.is_empty():
			game.set_status("Moved · %s couldn't follow: use Connect supply on its card" % ", ".join(replanner.unhooked))
		game.select(moved_id)
		game.play_sound("place")
		game.finish_tool()
		return
	var new_id: String = game.model.new_id(kind)
	var props := properties.duplicate(true)
	props.label = _next_label()
	match kind:
		"ahu":
			props.capacity_m3_s = float(props.get("capacity_m3_s", 1.6))
			props.bindings = Bindings.defaults("ahu", "", new_id)
			props.mount_level = 0
		"vav":
			props.served_room = new_id
			props.capacity_m3_s = float(props.get("capacity_m3_s", 0.45))
			props.bindings = Bindings.defaults("vav", new_id)
			props.mount_level = 1
		"tee", "cross":
			props.capacity_m3_s = float(props.get("capacity_m3_s", 1.6))
		"diffuser":
			props.capacity_m3_s = 0.45
	var entry := {"kind": kind, "transform": transform, "properties": props, "id": new_id}
	# Placing and ducting are one step (and one undo): the piece hooks onto
	# the nearest free outlet, or taps the main with a trunk cross.
	var planner := ZonePlanner.new(game.model.objects, game.index, game.model.new_id)
	# Never on top of a working run (that would cut the air to what it feeds),
	# unless tapping in replaces that very run; the fittings a tap adds keep
	# clear of the rest.
	var sound := planner.ducts_ok()
	planner.include(entry)
	planner.keep_clear = planner.ducts_ok()
	var connected := kind in ["vav", "tee", "cross", "diffuser"] and planner.connect_inlet(entry)
	if kind == "vav":
		_feed_diffusers(planner, entry)
	var cut := planner.cuts(sound)
	if not cut.is_empty():
		game.play_sound("error")
		game.set_status("Can't put it there: it would sit on the duct to %s" % cut[0])
		return
	game.apply("Place " + label, planner.entries, planner.removed_ids())
	game.flash([new_id])
	game.play_sound("place")
	match kind:
		"ahu":
			game.set_status("%s placed · now click Zone a room to give each room air" % label)
		"vav", "tee", "cross", "diffuser":
			if connected:
				var tapped := "" if planner.removed.is_empty() else (" · added a branch to its VAV's ductwork" if kind == "diffuser" else " · tapped into the main")
				game.set_status("%s placed and ducted%s" % [label, tapped])
			else:
				game.set_status("%s placed · no air within reach yet: add an air handler, then use Connect on its card" % label)
	if bool(params.get("once", false)):
		game.select(new_id)
		game.finish_tool()

# A replacement VAV picks up orphaned diffusers in the room below it.
func _feed_diffusers(planner: ZonePlanner, vav: Dictionary) -> void:
	var outlet := DuctPorts.port(vav, "outlet")
	var room: Dictionary = game.index.room_at(outlet.position)
	for item in planner.objects.duplicate():
		if String(item.kind) != "diffuser" or room.is_empty():
			continue
		var inlet := DuctPorts.port(item, "inlet")
		if DuctPorts.occupied(inlet, planner.objects) or String(game.index.room_at(inlet.position).get("id", "")) != String(room.id):
			continue
		if not planner.route(vav, "outlet", item, "inlet").is_empty():
			return

func _next_label() -> String:
	var prefix: String = {"ahu": "AHU", "vav": "VAV", "diffuser": "Diffuser", "tee": "Tee", "cross": "Cross"}.get(kind, kind.to_upper())
	var count := 1
	for item in game.model.objects:
		if item.kind == kind: count += 1
	return "%s-%d" % [prefix, count]

func key(event: InputEventKey) -> bool:
	if event.physical_keycode == KEY_R:
		rotation = fposmod(rotation + (PI * 0.5 if not event.shift_pressed else -PI * 0.5), TAU)
		hover(last_mouse)
		game.play_sound("tick")
		return true
	return false
