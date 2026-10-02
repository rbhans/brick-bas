class_name BuildTool
extends RefCounted

# Base class for build-mode tools. The game forwards pointer and key input;
# tools own their ghost preview and commit through game.apply() so every
# action is a single undoable transaction.

var game: Node
var id := "tool"
var label := "Tool"
var params: Dictionary = {}
var ghost: Node3D
var pressed := false
var press_screen := Vector2.ZERO
var last_mouse := Vector2.ZERO
var shows_grid := true

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	game = owner
	params = tool_params

func enter() -> void:
	# Remembered so a key pressed before the mouse moves (R) re-hovers here.
	last_mouse = game.get_viewport().get_mouse_position()
	hover(last_mouse)

func exit() -> void:
	clear_ghost()

func cancel() -> bool:
	# Returns true when the tool consumed Escape (e.g. aborting a drag).
	if pressed:
		pressed = false
		clear_ghost()
		hover(last_mouse)
		return true
	return false

func hover(_mouse: Vector2) -> void:
	pass

func press(_mouse: Vector2) -> void:
	pass

func drag(_mouse: Vector2) -> void:
	pass

func release(_mouse: Vector2) -> void:
	pass

func key(_event: InputEventKey) -> bool:
	return false

func process(_delta: float) -> void:
	pass

func status() -> String:
	return label

func handle(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		last_mouse = event.position
		if pressed:
			drag(event.position)
		else:
			hover(event.position)
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		last_mouse = event.position
		if event.pressed:
			pressed = true
			press_screen = event.position
			press(event.position)
		elif pressed:
			pressed = false
			release(event.position)
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		return key(event)
	return false

func new_ghost() -> Node3D:
	clear_ghost()
	ghost = Node3D.new()
	ghost.name = "%s ghost" % label
	game.ghost_root.add_child(ghost)
	return ghost

func clear_ghost() -> void:
	if is_instance_valid(ghost):
		ghost.free()
	ghost = null

static var _ghost_cache: Dictionary = {}

# Recolour every MeshInstance3D in a node tree with the ghost look. The source
# material is remembered so the same nodes can be re-tinted valid/invalid.
static func ghostify(node: Node, valid: bool) -> void:
	var tint := Color("5fe28c") if valid else Color("ef5a48")
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if not mesh_node.has_meta("ghost_source"):
			mesh_node.set_meta("ghost_source", mesh_node.material_override)
		var source := mesh_node.get_meta("ghost_source") as StandardMaterial3D
		mesh_node.material_override = _ghost_standard(source, tint)
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		ghostify(child, valid)

static func _ghost_standard(source: StandardMaterial3D, tint: Color) -> StandardMaterial3D:
	var base := source.albedo_color if source != null else Color.WHITE
	var key := base.to_html() + tint.to_html()
	if _ghost_cache.has(key):
		return _ghost_cache[key]
	var result := StandardMaterial3D.new()
	_ghost_cache[key] = result
	result.albedo_color = Color(base.lerp(tint, 0.4), 0.68)
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.emission_enabled = true
	result.emission = tint
	result.emission_energy_multiplier = 0.18
	result.roughness = 0.5
	return result
