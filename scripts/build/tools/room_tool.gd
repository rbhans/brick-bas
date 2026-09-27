class_name RoomTool
extends BuildTool

# Drag a rectangle between grid corners: perimeter walls plus a finished floor
# in one undoable step. Shared walls with neighbouring rooms are reused.

var start_vertex := Vector2i.ZERO
var end_vertex := Vector2i.ZERO
var preview: ArchitectureRenderer

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "room"
	label = "Room"

func wall_style() -> String:
	return String(params.get("style", "tan"))

func finish() -> String:
	return String(params.get("finish", "oak"))

func exit() -> void:
	_clear_preview()
	super.exit()

func hover(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse)
	if point == Vector3.INF:
		return
	game.show_vertex_cursor(PlanGrid.nearest_vertex(point), false)
	game.stage.set_grid(true, point)
	game.set_status("Room · drag from corner to corner · walls and floor go down together")

func press(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse)
	if point == Vector3.INF:
		pressed = false
		return
	start_vertex = PlanGrid.nearest_vertex(point)
	end_vertex = start_vertex
	_update_preview()

func drag(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse)
	if point == Vector3.INF:
		return
	var vertex := PlanGrid.nearest_vertex(point)
	game.show_vertex_cursor(vertex, false)
	game.stage.set_grid(true, point)
	if vertex != end_vertex:
		end_vertex = vertex
		_update_preview()
		game.play_sound("tick")

func release(_mouse: Vector2) -> void:
	_clear_preview()
	var size := (end_vertex - start_vertex).abs()
	if size.x == 0 or size.y == 0:
		game.set_status("Drag out a rectangle at least one tile each way.")
		return
	var adds: Array = []
	var updates: Array = []
	for edge in PlanGrid.rect_perimeter(start_vertex, end_vertex):
		if not game.index.has_wall(edge):
			adds.append(game.wall_entry(edge, wall_style()))
	for cell in PlanGrid.rect_cells(start_vertex, end_vertex):
		var existing: Dictionary = game.index.floors.get(PlanGrid.cell_key(cell), {})
		if existing.is_empty():
			adds.append(game.floor_entry(cell, finish()))
		elif String(existing.properties.get("finish", "")) != finish():
			var changed := existing.duplicate(true)
			changed.properties.finish = finish()
			updates.append(changed)
	var result: Dictionary = game.apply("Build room", adds, [], updates)
	game.flash(result.added)
	game.play_sound("place")
	game.set_status("Room %d × %d tiles · %s · name it from its floor" % [size.x, size.y, Units.area(size.x * size.y * PlanGrid.TILE * PlanGrid.TILE)])

func cancel() -> bool:
	if pressed:
		_clear_preview()
	return super.cancel()

func _update_preview() -> void:
	_clear_preview()
	var objects: Array = []
	var serial := 0
	for edge in PlanGrid.rect_perimeter(start_vertex, end_vertex):
		var entry: Dictionary = game.wall_entry(edge, wall_style())
		entry.id = "ghost-%d" % serial
		serial += 1
		objects.append(entry)
	for cell in PlanGrid.rect_cells(start_vertex, end_vertex):
		var entry: Dictionary = game.floor_entry(cell, finish())
		entry.id = "ghost-%d" % serial
		serial += 1
		objects.append(entry)
	new_ghost()
	if not objects.is_empty():
		preview = ArchitectureRenderer.preview(ghost, objects, true)
	var size := (end_vertex - start_vertex).abs()
	game.set_status("Room · %d × %d tiles · %s · release to build" % [size.x, size.y, Units.size(size.x * PlanGrid.TILE, size.y * PlanGrid.TILE)])
	game.show_measure(PlanGrid.vertex_position(start_vertex), PlanGrid.vertex_position(Vector2i(end_vertex.x, start_vertex.y)), PlanGrid.vertex_position(end_vertex))

func _clear_preview() -> void:
	if preview != null:
		preview.clear()
	preview = null
	clear_ghost()
	game.hide_measure()
