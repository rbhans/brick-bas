class_name OpeningTool
extends BuildTool

# Doors and windows slide along walls and drop into the wall section under
# the cursor. R flips a door's swing. Picking up an existing opening (Move)
# reuses this tool with moving_id set.

var kind := "door"
var edge := ""
var valid := false
var swing := 1.0
var moving_id := ""
var preview: ArchitectureRenderer
var hidden_wall := ""

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	kind = String(tool_params.get("kind", "door"))
	id = kind
	label = kind.capitalize()
	moving_id = String(tool_params.get("moving_id", ""))
	swing = float(tool_params.get("swing", 1.0))

func style() -> String:
	return String(params.get("style", kind))

func exit() -> void:
	_restore_wall()
	_clear_preview()
	super.exit()

func hover(mouse: Vector2) -> void:
	var found: String = game.wall_edge_at(mouse)
	if found == edge and preview != null:
		return
	edge = found
	_restore_wall()
	_clear_preview()
	if edge.is_empty():
		valid = false
		game.set_status("%s · point at a wall section to fit it" % label)
		return
	var occupant: Dictionary = game.index.openings.get(edge, {})
	valid = occupant.is_empty() or String(occupant.id) == moving_id
	var entry: Dictionary = game.opening_entry(kind, edge, style(), swing)
	entry.id = "ghost-opening"
	new_ghost()
	preview = ArchitectureRenderer.preview(ghost, [entry], valid)
	# Pull the preview a hair toward the viewer so it reads over the wall.
	ghost.scale = Vector3(1.0, 1.0, 1.0)
	if valid:
		hidden_wall = String(game.index.walls[edge].id)
		game.arch.batch.set_owner_hidden(hidden_wall, true)
	game.set_status("%s · %s · R flips the swing · click to fit" % [label, "fits this wall section" if valid else "this section already has an opening"])

func press(_mouse: Vector2) -> void:
	if edge.is_empty() or not valid:
		game.play_sound("error")
		return
	var entry: Dictionary = game.opening_entry(kind, edge, style(), swing)
	var result: Dictionary
	if not moving_id.is_empty():
		var moved: Dictionary = game.model.find_object(moving_id).duplicate(true)
		moved.transform = entry.transform
		moved.properties.edge = edge
		moved.properties.swing = swing
		result = game.apply("Move " + kind, [], [], [moved])
		game.select(moving_id)
		game.finish_tool()
	else:
		result = game.apply("Place " + kind, [entry])
		game.flash(result.added)
	hidden_wall = ""
	_clear_preview()
	game.play_sound("place")

func key(event: InputEventKey) -> bool:
	if event.physical_keycode == KEY_R:
		swing = -swing
		_clear_preview()
		hover(last_mouse)
		game.play_sound("tick")
		return true
	return false

func _restore_wall() -> void:
	if not hidden_wall.is_empty():
		game.arch.batch.set_owner_hidden(hidden_wall, false)
	hidden_wall = ""

func _clear_preview() -> void:
	if preview != null:
		preview.clear()
	preview = null
	clear_ghost()
