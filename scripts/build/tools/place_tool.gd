class_name PlaceTool
extends BuildTool

# Places catalogue pieces: furniture, plants, parking stalls. The ghost glides
# to the snapped stud position (never pops), R turns it, a click drops it and
# the tool stays armed for the next one. Wall pieces hug the nearest wall face.
# With params.moving_id it picks up an existing object instead (Move).

var kind := "furniture"
var item_id := ""
var rotation := 0.0
var target := Transform3D.IDENTITY
var shown := Transform3D.IDENTITY
var valid := false
var reason := ""
var moving_id := ""
var mount := "floor"
var footprint := Vector2i(2, 2)
var visible_target := false
var _ghost_rotation := INF

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	kind = String(tool_params.get("kind", "furniture"))
	item_id = String(tool_params.get("item", ""))
	moving_id = String(tool_params.get("moving_id", ""))
	rotation = float(tool_params.get("rotation", 0.0))
	id = "place"
	var spec: Dictionary = owner.placeable_spec(kind, item_id)
	label = String(spec.get("label", kind.capitalize()))
	mount = String(spec.get("mount", "floor"))
	footprint = spec.get("footprint", Vector2i(2, 2))
	shows_grid = false

func enter() -> void:
	if not moving_id.is_empty():
		game.hide_object(moving_id, true)
	super.enter()

func exit() -> void:
	if not moving_id.is_empty():
		game.hide_object(moving_id, false)
	super.exit()

func _ensure_ghost() -> void:
	if is_instance_valid(ghost) and _ghost_rotation == rotation:
		return
	new_ghost()
	var body := Node3D.new()
	ghost.add_child(body)
	game.build_placeable(body, kind, item_id, params.get("properties", {}))
	BuildTool.ghostify(ghost, valid)
	_ghost_rotation = rotation
	ghost.visible = false

func hover(mouse: Vector2) -> void:
	_ensure_ghost()
	var placement: Dictionary = game.snap_placeable(mouse, kind, item_id, rotation, moving_id)
	if placement.is_empty():
		ghost.visible = false
		visible_target = false
		game.set_status("%s · move over the lot" % label)
		return
	target = placement.transform
	var was_valid := valid
	valid = bool(placement.valid)
	reason = String(placement.get("reason", ""))
	if not visible_target:
		shown = target
		visible_target = true
	ghost.visible = true
	if was_valid != valid:
		BuildTool.ghostify(ghost, valid)
	game.show_footprint(target, placement.get("footprint", footprint), valid, mount == "wall")
	game.set_status("%s · %s · R turns · click to place%s" % [label, "ready" if valid else reason, "" if moving_id.is_empty() else " · Esc puts it back"])

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
		game.set_status(reason if not reason.is_empty() else "Can't place that here.")
		return
	var rotation_y := target.basis.get_euler().y
	var position := target.origin
	if not moving_id.is_empty():
		var moved: Dictionary = game.model.find_object(moving_id).duplicate(true)
		moved.transform = {"position": [position.x, position.y, position.z], "rotation_y": rotation_y}
		var extra: Dictionary = game.placement_properties(kind, item_id, target)
		moved.properties.merge(extra, true)
		game.hide_object(moving_id, false)
		game.apply("Move " + label, [], [], [moved])
		var moved_id := moving_id
		moving_id = ""
		game.select(moved_id)
		game.play_sound("place")
		game.finish_tool()
		return
	var properties: Dictionary = params.get("properties", {}).duplicate(true)
	properties.merge(game.placement_properties(kind, item_id, target), true)
	var result: Dictionary = game.apply("Place " + label, [game.entry(kind, position, rotation_y, properties)])
	game.flash(result.added)
	game.play_sound("place")
	if bool(params.get("once", false)):
		game.select(String(result.added[0].id))
		game.finish_tool()

func key(event: InputEventKey) -> bool:
	if event.physical_keycode == KEY_R:
		rotation = fposmod(rotation + (PI * 0.5 if not event.shift_pressed else -PI * 0.5), TAU)
		hover(last_mouse)
		game.play_sound("tick")
		return true
	return false

func cancel() -> bool:
	return super.cancel()
