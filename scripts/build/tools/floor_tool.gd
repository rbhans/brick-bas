class_name FloorTool
extends BuildTool

# Paint floor finishes tile by tile or by dragging a rectangle. Shift-click
# fills the whole room under the cursor; Ctrl-drag lifts floor tiles.

var start_cell := Vector2i.ZERO
var end_cell := Vector2i.ZERO
var erase := false
var preview: ArchitectureRenderer

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "floor"
	label = "Floor"

func finish() -> String:
	return String(params.get("finish", "oak"))

func exit() -> void:
	_clear_preview()
	game.clear_marks()
	super.exit()

func _cell(mouse: Vector2) -> Variant:
	var point: Vector3 = game.rig.ground_point(mouse, PlanGrid.FLOOR_TOP)
	return null if point == Vector3.INF else PlanGrid.cell_at(point)

func hover(mouse: Vector2) -> void:
	var cell: Variant = _cell(mouse)
	if cell == null:
		return
	game.show_cell_cursor(cell, _erasing())
	game.stage.set_grid(true, PlanGrid.cell_center(cell))
	var label_text: String = ArchitectureRenderer.FLOOR_FINISHES.get(finish(), {}).get("label", finish())
	game.set_status("%s · click or drag tiles · Shift-click fills a room · Ctrl-drag lifts tiles" % ("Remove floor" if _erasing() else label_text))

func _erasing() -> bool:
	return bool(params.get("erase", false)) or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)

func press(mouse: Vector2) -> void:
	var cell: Variant = _cell(mouse)
	if cell == null:
		pressed = false
		return
	erase = _erasing()
	if Input.is_key_pressed(KEY_SHIFT) and not erase:
		pressed = false
		_fill_room(cell)
		return
	start_cell = cell
	end_cell = cell
	_update_preview()

func drag(mouse: Vector2) -> void:
	var cell: Variant = _cell(mouse)
	if cell == null:
		return
	game.show_cell_cursor(cell, erase)
	if cell != end_cell:
		end_cell = cell
		_update_preview()
		game.play_sound("tick")

func _rect_cells() -> Array[Vector2i]:
	var low := Vector2i(mini(start_cell.x, end_cell.x), mini(start_cell.y, end_cell.y))
	var high := Vector2i(maxi(start_cell.x, end_cell.x), maxi(start_cell.y, end_cell.y))
	return PlanGrid.rect_cells(low, high + Vector2i.ONE)

func release(_mouse: Vector2) -> void:
	_clear_preview()
	game.clear_marks()
	_commit(_rect_cells())

func _commit(cells: Array[Vector2i]) -> void:
	var adds: Array = []
	var removes: Array = []
	var updates: Array = []
	for cell in cells:
		var existing: Dictionary = game.index.floors.get(PlanGrid.cell_key(cell), {})
		if erase:
			if not existing.is_empty():
				removes.append(String(existing.id))
		elif existing.is_empty():
			adds.append(game.floor_entry(cell, finish()))
		elif String(existing.properties.get("finish", "")) != finish():
			var changed := existing.duplicate(true)
			changed.properties.finish = finish()
			updates.append(changed)
	if adds.is_empty() and removes.is_empty() and updates.is_empty():
		return
	var result: Dictionary = game.apply("Remove floor" if erase else "Floor", adds, removes, updates)
	game.flash(result.added)
	game.play_sound("demolish" if erase else "place")
	game.set_status("%d floor tile%s %s" % [cells.size(), "" if cells.size() == 1 else "s", "lifted" if erase else "finished"])

func _fill_room(cell: Vector2i) -> void:
	var room: Dictionary = game.index.room_at_cell(cell)
	if room.is_empty():
		game.set_status("Shift-click inside a closed room to fill it.")
		return
	var cells: Array[Vector2i] = []
	cells.assign(room.cells)
	_commit(cells)

func cancel() -> bool:
	if pressed:
		_clear_preview()
		game.clear_marks()
	return super.cancel()

func _update_preview() -> void:
	_clear_preview()
	game.clear_marks()
	var cells := _rect_cells()
	if erase:
		var doomed: Array = []
		for cell in cells:
			var existing: Dictionary = game.index.floors.get(PlanGrid.cell_key(cell), {})
			if not existing.is_empty(): doomed.append(String(existing.id))
		game.mark(doomed, "delete")
		return
	var objects: Array = []
	for index in range(cells.size()):
		var entry: Dictionary = game.floor_entry(cells[index], finish())
		entry.id = "ghost-%d" % index
		objects.append(entry)
	new_ghost()
	ghost.position.y = 0.02
	preview = ArchitectureRenderer.preview(ghost, objects, true)
	var span := (end_cell - start_cell).abs() + Vector2i.ONE
	game.set_status("Floor · %d × %d tiles · release to lay %s" % [span.x, span.y, ArchitectureRenderer.FLOOR_FINISHES.get(finish(), {}).get("label", finish())])

func _clear_preview() -> void:
	if preview != null:
		preview.clear()
	preview = null
	clear_ghost()
