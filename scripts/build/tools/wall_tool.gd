class_name WallTool
extends BuildTool

# Drag along the plan grid to raise walls; hold Ctrl (or pick "Remove walls")
# to knock them down. Existing walls are left alone and new ones interlock.

var start_vertex := Vector2i.ZERO
var end_vertex := Vector2i.ZERO
var erase := false
var preview: ArchitectureRenderer

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "wall"
	label = "Wall"

func style() -> String:
	return String(params.get("style", "tan"))

func exit() -> void:
	_clear_preview()
	game.clear_marks()
	super.exit()

func hover(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse)
	if point == Vector3.INF:
		return
	var vertex := PlanGrid.nearest_vertex(point)
	game.show_vertex_cursor(vertex, _erasing())
	game.stage.set_grid(true, point)
	game.set_status("%s · drag along the grid · Ctrl-drag removes walls · Esc done" % ("Remove walls" if _erasing() else "Wall"))

func _erasing() -> bool:
	return bool(params.get("erase", false)) or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)

func press(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse)
	if point == Vector3.INF:
		pressed = false
		return
	start_vertex = PlanGrid.nearest_vertex(point)
	end_vertex = start_vertex
	erase = _erasing()
	_update_preview()

func drag(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse)
	if point == Vector3.INF:
		return
	var vertex := PlanGrid.nearest_vertex(point)
	if absi(vertex.x - start_vertex.x) >= absi(vertex.y - start_vertex.y):
		vertex.y = start_vertex.y
	else:
		vertex.x = start_vertex.x
	game.show_vertex_cursor(vertex, erase)
	game.stage.set_grid(true, point)
	if vertex != end_vertex:
		end_vertex = vertex
		_update_preview()
		game.play_sound("tick")

func release(_mouse: Vector2) -> void:
	var edges := PlanGrid.edges_between(start_vertex, end_vertex)
	_clear_preview()
	game.clear_marks()
	if edges.is_empty():
		return
	if erase:
		var count := edges.filter(func(edge: String) -> bool: return game.index.has_wall(edge)).size()
		var removes: Array = game.walls_and_dependents(edges)
		if removes.is_empty():
			game.set_status("No walls there to remove.")
			return
		game.apply("Remove walls", [], removes)
		game.play_sound("demolish")
		game.set_status("Removed %d wall section%s" % [count, "" if count == 1 else "s"])
		return
	var adds: Array = []
	for edge in edges:
		if not game.index.has_wall(edge):
			adds.append(game.wall_entry(edge, style()))
	if adds.is_empty():
		game.set_status("Those walls are already built.")
		return
	var result: Dictionary = game.apply("Build walls", adds)
	game.flash(result.added)
	game.play_sound("place")
	game.set_status("Built %d wall section%s · %s" % [adds.size(), "" if adds.size() == 1 else "s", Units.length(adds.size() * PlanGrid.TILE)])

func cancel() -> bool:
	if pressed:
		_clear_preview()
		game.clear_marks()
	return super.cancel()

func _update_preview() -> void:
	_clear_preview()
	game.clear_marks()
	var edges := PlanGrid.edges_between(start_vertex, end_vertex)
	if erase:
		var doomed: Array = []
		for edge in edges:
			if game.index.has_wall(edge):
				doomed.append(String(game.index.walls[edge].id))
		game.mark(doomed, "delete")
		game.set_status("Remove %d wall section%s · release to demolish" % [doomed.size(), "" if doomed.size() == 1 else "s"])
		return
	var objects: Array = []
	var serial := 0
	for edge in edges:
		if game.index.has_wall(edge):
			continue
		var entry: Dictionary = game.wall_entry(edge, style())
		entry.id = "ghost-%d" % serial
		serial += 1
		objects.append(entry)
	new_ghost()
	if not objects.is_empty():
		preview = ArchitectureRenderer.preview(ghost, objects, true)
	var length := edges.size() * PlanGrid.TILE
	game.set_status("Wall · %d new section%s · %s · release to build" % [objects.size(), "" if objects.size() == 1 else "s", Units.length(length)])
	game.show_measure(PlanGrid.vertex_position(start_vertex), PlanGrid.vertex_position(end_vertex))

func _clear_preview() -> void:
	if preview != null:
		preview.clear()
	preview = null
	clear_ghost()
	game.hide_measure()
