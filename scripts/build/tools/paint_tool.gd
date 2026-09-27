class_name PaintTool
extends BuildTool

# Wall paint: click or drag across wall sections to change their brick style.
# Shift-click repaints every wall around the room under the cursor.

var painted: Dictionary = {}
var hovered := ""

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "paint"
	label = "Wall paint"
	shows_grid = false

func style() -> String:
	return String(params.get("style", "white"))

func exit() -> void:
	game.clear_marks()
	super.exit()

func hover(mouse: Vector2) -> void:
	var edge: String = game.wall_edge_at(mouse)
	var wall_id := String(game.index.walls.get(edge, {}).get("id", ""))
	if wall_id != hovered:
		hovered = wall_id
		game.clear_marks()
		if not wall_id.is_empty():
			game.mark([wall_id], "hover")
	var style_label: String = ArchitectureRenderer.WALL_STYLES.get(style(), {}).get("label", style())
	game.set_status("%s · click or drag across walls · Shift-click paints a whole room" % style_label)

func press(mouse: Vector2) -> void:
	painted.clear()
	if Input.is_key_pressed(KEY_SHIFT):
		pressed = false
		_paint_room(mouse)
		return
	_paint_at(mouse)

func drag(mouse: Vector2) -> void:
	_paint_at(mouse)

func release(_mouse: Vector2) -> void:
	var updates: Array = []
	for wall_id in painted:
		var item: Dictionary = game.model.find_object(wall_id).duplicate(true)
		if item.is_empty() or String(item.properties.get("style", "")) == style():
			continue
		item.properties.style = style()
		updates.append(item)
	painted.clear()
	game.clear_marks()
	if updates.is_empty():
		return
	game.apply("Paint walls", [], [], updates)
	game.play_sound("paint")

func _paint_at(mouse: Vector2) -> void:
	var edge: String = game.wall_edge_at(mouse)
	if edge.is_empty() or not game.index.has_wall(edge):
		return
	var wall_id := String(game.index.walls[edge].id)
	if not painted.has(wall_id):
		painted[wall_id] = true
		game.mark(painted.keys(), "paint")
		game.play_sound("tick")

func _paint_room(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse, PlanGrid.FLOOR_TOP)
	var room: Dictionary = game.index.room_at(point) if point != Vector3.INF else {}
	if room.is_empty():
		game.set_status("Shift-click inside a closed room to paint all its walls.")
		return
	for cell in room.cells:
		for edge in PlanGrid.cell_edges(cell):
			if game.index.has_wall(edge):
				painted[String(game.index.walls[edge].id)] = true
	release(mouse)
