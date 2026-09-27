class_name ArchitectureRenderer
extends RefCounted

# Turns plan objects (walls, openings, floors, landscaping) into batched LDraw
# bricks plus simple collision. Walls are laid course by course in running
# bond; corners interlock (X runs own the corner stud on even courses, Z runs
# on odd ones) exactly like a real brick-built corner.

const BRICK_PARTS := {1: "3005", 2: "3004", 3: "3622", 4: "3010", 6: "3009", 8: "3008"}
const TILE_PARTS := {1: "3070b", 2: "3069b", 3: "63864", 4: "2431", 6: "6636", 8: "4162"}
const PLATE_PARTS := {1: "3024", 2: "3023b", 3: "3623", 4: "3710", 6: "3666", 8: "3460"}

const WALL_STYLES := {
	"tan": {"label": "Tan brick", "body": "tan", "base": "dark_tan"},
	"white": {"label": "White plaster", "body": "white", "base": "light_bluish_gray"},
	"cream": {"label": "Cream", "body": "light_nougat", "base": "tan"},
	"red_brick": {"label": "Red brick", "body": "dark_red", "base": "dark_bluish_gray"},
	"gray": {"label": "Gray block", "body": "light_bluish_gray", "base": "dark_bluish_gray"},
	"sand_blue": {"label": "Sand blue", "body": "sand_blue", "base": "dark_bluish_gray"},
	"sand_green": {"label": "Sage", "body": "sand_green", "base": "dark_tan"},
	"nougat": {"label": "Terracotta", "body": "nougat", "base": "reddish_brown"},
	"dark_tan": {"label": "Stone", "body": "dark_tan", "base": "dark_bluish_gray"},
}

const FLOOR_FINISHES := {
	"oak": {"label": "Oak planks", "pattern": "planks", "colors": ["medium_nougat", "nougat"]},
	"maple": {"label": "Maple planks", "pattern": "planks", "colors": ["tan", "light_nougat"]},
	"walnut": {"label": "Walnut planks", "pattern": "planks", "colors": ["reddish_brown", "dark_brown"]},
	"carpet_blue": {"label": "Blue carpet", "pattern": "tiles", "colors": ["sand_blue"]},
	"carpet_gray": {"label": "Gray carpet", "pattern": "tiles", "colors": ["dark_bluish_gray"]},
	"carpet_green": {"label": "Green carpet", "pattern": "tiles", "colors": ["sand_green"]},
	"carpet_red": {"label": "Red carpet", "pattern": "tiles", "colors": ["dark_red"]},
	"tile_white": {"label": "White tile", "pattern": "tiles", "colors": ["white"]},
	"tile_gray": {"label": "Gray tile", "pattern": "tiles", "colors": ["light_bluish_gray"]},
	"checker": {"label": "Checker tile", "pattern": "checker", "colors": ["white", "black"]},
	"checker_blue": {"label": "Blue checker", "pattern": "checker", "colors": ["white", "medium_blue"]},
	"concrete": {"label": "Studded concrete", "pattern": "plates", "colors": ["dark_bluish_gray"]},
	"paving": {"label": "Paving", "pattern": "pavers", "colors": ["light_bluish_gray", "flat_silver"]},
	"paving_tan": {"label": "Tan paving", "pattern": "pavers", "colors": ["tan", "dark_tan"]},
	"asphalt": {"label": "Asphalt", "pattern": "tiles", "colors": ["dark_bluish_gray"]},
}

const DOOR_STYLES := {
	"door": {"label": "Panel door", "frame": "white", "leaf": "medium_nougat", "part": "60616b"},
	"door_blue": {"label": "Blue door", "frame": "white", "leaf": "sand_blue", "part": "60616b"},
	"door_red": {"label": "Red door", "frame": "white", "leaf": "dark_red", "part": "60616b"},
	"glass_door": {"label": "Glass door", "frame": "dark_bluish_gray", "leaf": "dark_bluish_gray", "part": "60623", "glass": true},
}

const WINDOW_STYLES := {
	"window": {"label": "Window", "frame": "white", "tall": false},
	"window_dark": {"label": "Dark window", "frame": "dark_bluish_gray", "tall": false},
	"tall_window": {"label": "Tall window", "frame": "white", "tall": true},
	"storefront": {"label": "Storefront", "frame": "dark_bluish_gray", "tall": true},
}

var batch := BrickBatch.new()
var root: Node3D
var preview_mode := false # ghosts: no collision, door leaves batched
var doors: Dictionary = {}   # door object id -> {hinge, edge, custom, swing, open}
var bodies: Dictionary = {}  # object id -> Array[CollisionObject3D]
var furniture_builder: Callable
var _parking_lines: Dictionary = {}   # stripes laid this build (neighbouring stalls share them)

func clear() -> void:
	batch.clear()
	_parking_lines.clear()
	if is_instance_valid(root):
		root.free()
	root = null
	doors.clear()
	bodies.clear()

# Renders plan objects as a translucent placement preview.
static func preview(parent: Node3D, objects: Array, valid: bool, furniture: Callable = Callable()) -> ArchitectureRenderer:
	var renderer := ArchitectureRenderer.new()
	renderer.preview_mode = true
	renderer.furniture_builder = furniture
	renderer.batch.override_material = BrickBatch.ghost_material(valid)
	var index := BuildingIndex.new()
	index.rebuild(objects)
	renderer.rebuild(parent, objects, index)
	return renderer

func rebuild(parent: Node3D, objects: Array, index: BuildingIndex) -> void:
	clear()
	root = Node3D.new()
	root.name = "Architecture preview" if preview_mode else "Architecture"
	parent.add_child(root)
	_build_walls(index)
	for edge in index.openings:
		if index.walls.has(edge):
			_build_opening(index.openings[edge], edge)
	for key in index.floors:
		_build_floor(index.floors[key], index)
	for item in objects:
		match String(item.kind):
			"parking": _build_parking(item)
			"tree", "shrub": _build_plant(item)
			"furniture":
				if furniture_builder.is_valid():
					_build_furniture(item)
	for edge in index.walls:
		_wall_collision(index.walls[edge], edge, index.openings.get(edge, {}))
	batch.build(root)

# --- Walls -------------------------------------------------------------------

func _build_walls(index: BuildingIndex) -> void:
	var lines: Dictionary = {}
	for edge in index.walls:
		var parsed := PlanGrid.parse_edge(edge)
		var line_key := "%s:%d" % [parsed.axis, parsed.j if parsed.axis == "x" else parsed.i]
		if not lines.has(line_key):
			lines[line_key] = {"axis": parsed.axis, "line": parsed.j if parsed.axis == "x" else parsed.i, "steps": []}
		lines[line_key].steps.append(parsed.i if parsed.axis == "x" else parsed.j)
	for line in lines.values():
		var steps: Array = line.steps
		steps.sort()
		var run_start := int(steps[0])
		var previous := run_start
		for index_value in range(1, steps.size() + 1):
			var step := int(steps[index_value]) if index_value < steps.size() else 1 << 30
			if step != previous + 1:
				_build_run(index, String(line.axis), int(line.line), run_start, previous + 1)
				run_start = step
			previous = step

# A straight run from vertex `from_step` to `to_step` along one grid line.
func _build_run(index: BuildingIndex, axis: String, line: int, from_step: int, to_step: int) -> void:
	var first_slot := from_step * PlanGrid.TILE_STUDS
	var last_slot := to_step * PlanGrid.TILE_STUDS
	for course in range(PlanGrid.WALL_COURSES):
		var filled: Array[bool] = []
		for slot in range(first_slot, last_slot + 1):
			filled.append(_slot_filled(index, axis, line, slot, course))
		var slot := first_slot
		while slot <= last_slot:
			if not filled[slot - first_slot]:
				slot += 1
				continue
			var end := slot
			while end + 1 <= last_slot and filled[end + 1 - first_slot]:
				end += 1
			_lay_course(index, axis, line, slot, end, course)
			slot = end + 1

func _slot_filled(index: BuildingIndex, axis: String, line: int, slot: int, course: int) -> bool:
	var step := floori(float(slot) / PlanGrid.TILE_STUDS)
	var within := posmod(slot, PlanGrid.TILE_STUDS)
	if within == 0:
		var vertex := Vector2i(step, line) if axis == "x" else Vector2i(line, step)
		var axes := index.vertex_axes(vertex)
		if bool(axes.x) and bool(axes.z):
			return (course % 2 == 0) == (axis == "x")
		return true
	var edge := PlanGrid.edge_key(axis, step, line) if axis == "x" else PlanGrid.edge_key(axis, line, step)
	var hosted: Dictionary = index.openings.get(edge, {})
	if hosted.is_empty():
		return true
	if hosted.kind == "door" or bool(WINDOW_STYLES.get(String(hosted.properties.get("style", "window")), {}).get("tall", false)):
		return false
	return course < 2 or course > 4

# Fill stud slots [a, b] of one course with a running bond: joints fall on
# multiples of four studs, shifted by two on alternate courses.
func _lay_course(index: BuildingIndex, axis: String, line: int, a: int, b: int, course: int) -> void:
	var lengths: Array[int] = []
	var cursor := a
	var phase := 2 * (course % 2)
	while cursor <= b:
		var next_joint := cursor + 4 - posmod(cursor - phase, 4)
		lengths.append(mini(next_joint, b + 1) - cursor)
		cursor = mini(next_joint, b + 1)
	# Avoid 1-stud slivers beside a full brick: (1, 4) -> (2, 3).
	for i in range(lengths.size() - 1):
		if lengths[i] == 1 and lengths[i + 1] == 4:
			lengths[i] = 2; lengths[i + 1] = 3
		elif lengths[i] == 4 and lengths[i + 1] == 1:
			lengths[i] = 3; lengths[i + 1] = 2
	cursor = a
	for length in lengths:
		var center_slot := float(cursor) + float(length - 1) * 0.5
		var along := center_slot * PlanGrid.STUD
		var fixed := line * PlanGrid.TILE
		var position := Vector3(along, course * PlanGrid.BRICK, fixed) if axis == "x" else Vector3(fixed, course * PlanGrid.BRICK, along)
		var step := floori((center_slot + 0.001) / PlanGrid.TILE_STUDS)
		var edge := PlanGrid.edge_key(axis, step, line) if axis == "x" else PlanGrid.edge_key(axis, line, step)
		if not index.walls.has(edge):
			# A corner-stud brick belongs to whichever neighbouring edge exists.
			edge = PlanGrid.edge_key(axis, step - 1, line) if axis == "x" else PlanGrid.edge_key(axis, line, step - 1)
		var wall: Dictionary = index.walls.get(edge, {})
		var style: Dictionary = WALL_STYLES.get(String(wall.get("properties", {}).get("style", "tan")), WALL_STYLES.tan)
		var tint := vary(Bricks.color(style.base if course == 0 else style.body), position)
		var custom := BrickBatch.wall_custom(0 if course == 0 else 1, edge)
		batch.place(String(wall.get("id", "")), String(BRICK_PARTS[length]), position, tint, PlanGrid.edge_rotation(edge), custom)
		cursor += length

# --- Openings ----------------------------------------------------------------

func _build_opening(item: Dictionary, edge: String) -> void:
	var center := PlanGrid.edge_center(edge)
	var rotation := PlanGrid.edge_rotation(edge)
	var id := String(item.id)
	if item.kind == "door":
		var style: Dictionary = DOOR_STYLES.get(String(item.properties.get("style", "door")), DOOR_STYLES.door)
		batch.place(id, "60596", center, style.frame, rotation, BrickBatch.wall_custom(2, edge))
		_build_door_leaf(item, edge, style)
		return
	var window: Dictionary = WINDOW_STYLES.get(String(item.properties.get("style", "window")), WINDOW_STYLES.window)
	var basis := Bricks.basis_y(rotation)
	if bool(window.tall):
		batch.place(id, "57894", center, window.frame, rotation, BrickBatch.wall_custom(2, edge))
		batch.add(id, "57895", Transform3D(basis, center + Vector3(0, 3.6, 0) + basis * Vector3(0, -0.14, 0)), "trans_light_blue", BrickBatch.wall_custom(2, edge))
	else:
		var sill := center + Vector3(0, 2 * PlanGrid.BRICK, 0)
		batch.place(id, "60594", sill, window.frame, rotation, BrickBatch.wall_custom(1, edge))
		batch.add(id, "60603", Transform3D(basis, sill + Vector3(0, 1.8, 0) + basis * Vector3(0, -0.2, 0)), "trans_light_blue", BrickBatch.wall_custom(1, edge))

func _build_door_leaf(item: Dictionary, edge: String, style: Dictionary) -> void:
	var center := PlanGrid.edge_center(edge)
	var rotation := PlanGrid.edge_rotation(edge)
	var swing := 1.0 if float(item.properties.get("swing", 1.0)) >= 0.0 else -1.0
	if preview_mode:
		var hinge := Transform3D(Bricks.basis_y(rotation), center + Bricks.basis_y(rotation) * Vector3(-0.8, 0, 0))
		batch.add(String(item.id), String(style.part), hinge * Bricks.bottom_transform(String(style.part), Vector3(0, 0.12, 0)), style.leaf)
		return
	var body := AnimatableBody3D.new()
	body.name = "Door " + String(item.id)
	body.sync_to_physics = false
	body.set_meta("entity_id", String(item.id))
	body.set_meta("door_id", String(item.id))
	body.set_meta("interaction_kind", "door")
	body.transform = Transform3D(Bricks.basis_y(rotation), center + Bricks.basis_y(rotation) * Vector3(-0.8, 0, 0))
	root.add_child(body)
	var leaf := Bricks.place(body, String(style.part), Vector3(0, 0.12, 0.0), style.leaf)
	leaf.set_meta("paint_role", "door")
	if bool(style.get("glass", false)):
		Bricks.box(body, Vector3(1.2, 2.6, 0.04), Vector3(0.84, 1.75, 0.0), "trans_light_blue")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 3.3, 0.16)
	shape.shape = box
	shape.position = Vector3(0.8, 1.75, 0.0)
	body.add_child(shape)
	doors[String(item.id)] = {"hinge": body, "edge": edge, "custom": BrickBatch.wall_custom(1, edge), "swing": swing, "angle": 0.0, "target": 0.0}
	_remember(String(item.id), body)

# --- Floors ------------------------------------------------------------------

func _build_floor(item: Dictionary, index: BuildingIndex) -> void:
	var cell := BuildingIndex.cell_of(item)
	var finish: Dictionary = FLOOR_FINISHES.get(String(item.properties.get("finish", "oak")), FLOOR_FINISHES.oak)
	var id := String(item.id)
	var colors: Array = finish.colors
	var sx0 := cell.x * PlanGrid.TILE_STUDS
	var sz0 := cell.y * PlanGrid.TILE_STUDS
	var min_z_wall := index.has_wall(PlanGrid.edge_key("x", cell.x, cell.y))
	var min_x_wall := index.has_wall(PlanGrid.edge_key("z", cell.x, cell.y))
	var corner_axes := index.vertex_axes(cell)
	var corner_wall := bool(corner_axes.x) or bool(corner_axes.z)
	match String(finish.pattern):
		"planks":
			for row in range(PlanGrid.TILE_STUDS):
				var sz := sz0 + row
				if row == 0 and min_z_wall:
					continue
				var run: Array[int] = []
				for column in range(PlanGrid.TILE_STUDS):
					var blocked := column == 0 and (min_x_wall or (row == 0 and corner_wall))
					run.append(0 if blocked else 1)
				var lengths_even: Array[int] = [4, 1]
				var lengths_odd: Array[int] = [1, 4]
				_fill_row(id, "x", sx0, sz, run, lengths_even if posmod(sz, 2) == 0 else lengths_odd, colors, TILE_PARTS)
		"plates", "tiles", "checker", "pavers":
			var parts := PLATE_PARTS if finish.pattern == "plates" else TILE_PARTS
			# 4 x 4 interior as 2 x 2 tiles (or one 4 x 4 plate for concrete).
			if finish.pattern == "plates":
				batch.place(id, "3031", _slot_position(sx0 + 2.5, sz0 + 2.5), colors[0])
			else:
				for qx in range(2):
					for qz in range(2):
						var tile_x := sx0 + 1 + qx * 2
						var tile_z := sz0 + 1 + qz * 2
						var tint: Variant = colors[0]
						if finish.pattern == "checker":
							tint = colors[posmod(floori(tile_x / 2.0) + floori(tile_z / 2.0), 2)]
						elif finish.pattern == "pavers":
							tint = colors[posmod(hash(Vector2i(tile_x, tile_z)), colors.size())]
						batch.place(id, "3068b", _slot_position(tile_x + 0.5, tile_z + 0.5), vary(Bricks.color(tint), Vector3(tile_x, 0, tile_z), 0.02))
			# The shared grid-line row and column, unless a wall sits there.
			if not min_z_wall:
				var row_run: Array[int] = [0 if corner_wall else 1, 1, 1, 1, 1]
				_fill_row(id, "x", sx0, sz0, row_run, [5], colors, parts)
			if not min_x_wall:
				var column_run: Array[int] = [0, 1, 1, 1, 1]
				_fill_row(id, "z", sz0, sx0, column_run, [4], colors, parts)
	_floor_collision(item, cell)

func _slot_position(sx: float, sz: float) -> Vector3:
	return Vector3(sx * PlanGrid.STUD, 0.0, sz * PlanGrid.STUD)

# Lay tiles along one row of stud slots. `run` marks usable slots; lengths is
# the preferred rhythm, trimmed to each open interval.
func _fill_row(id: String, axis: String, start: int, fixed: int, run: Array[int], rhythm: Array[int], colors: Array, parts: Dictionary) -> void:
	var slot := 0
	var rhythm_index := 0
	while slot < run.size():
		if run[slot] == 0:
			slot += 1
			continue
		var available := 0
		while slot + available < run.size() and run[slot + available] == 1:
			available += 1
		var length := mini(int(rhythm[rhythm_index % rhythm.size()]), available)
		while not parts.has(length):
			length -= 1
		rhythm_index += 1
		var center := float(start + slot) + float(length - 1) * 0.5
		var tint := vary(Bricks.color(colors[posmod(hash(Vector2i(start + slot, fixed)), colors.size())]), Vector3(start + slot, 0, fixed), 0.025)
		if axis == "x":
			batch.place(id, String(parts[length]), _slot_position(center, fixed), tint)
		else:
			batch.place(id, String(parts[length]), _slot_position(fixed, center), tint, PI * 0.5)
		slot += length

# --- Landscaping ---------------------------------------------------------------

func _build_parking(item: Dictionary) -> void:
	var position := _position(item)
	var rotation := float(item.transform.get("rotation_y", 0.0))
	var basis := Bricks.basis_y(rotation)
	var id := String(item.id)
	# Stripes sit on the pavement (not in it), and neighbouring stalls share
	# the stripe between them instead of drawing it twice.
	for side in [-1.0, 1.0]:
		var at: Vector3 = position + Vector3(0, PlanGrid.FLOOR_TOP, 0) + basis * Vector3(side * 1.25, 0, 0)
		var key := Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0))
		if _parking_lines.has(key):
			continue
		_parking_lines[key] = true
		batch.add(id, "4162", Bricks.bottom_transform("4162", at, basis * Basis(Vector3.UP, PI * 0.5)), "white")
	batch.place(id, "3710", position + Vector3(0, PlanGrid.FLOOR_TOP, 0) + basis * Vector3(0, 0, -2.25), "yellow")

const TREES := {
	"oak": {"part": "3470", "color": "green", "trunk": 0.6},
	"pine": {"part": "3471", "color": "dark_green", "trunk": 0.6},
	"poplar": {"part": "3778", "color": "bright_green", "trunk": 0.6},
	"spruce": {"part": "2435", "color": "dark_green", "trunk": 0.0},
}

func _build_plant(item: Dictionary) -> void:
	var position := _position(item)
	var id := String(item.id)
	if item.kind == "tree":
		var tree: Dictionary = TREES.get(String(item.properties.get("variant", "oak")), TREES.oak)
		batch.place(id, "4032a", position, "reddish_brown")
		batch.place(id, String(tree.part), position + Vector3(0, 0.2, 0), tree.color, float(hash(id) % 4) * PI * 0.5)
		_box_body(id, Vector3(0.6, 3.0, 0.6), position + Vector3(0, 1.5, 0), 0.0)
	else:
		# A rounded bush: four leafy 2 x 2 plant bricks with a fifth on top.
		var turn := Bricks.basis_y(float(posmod(hash(id), 4)) * PI * 0.5)
		for offset in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
			var tint := "green" if posmod(hash(offset + position), 3) != 0 else "bright_green"
			batch.add(id, "30657", Bricks.bottom_transform("30657", position + turn * offset, turn), tint)
		batch.add(id, "30657", Bricks.bottom_transform("30657", position + Vector3(0, 0.6, 0), turn * Basis(Vector3.UP, PI * 0.25)), "bright_green")
		_box_body(id, Vector3(2.0, 1.3, 2.0), position + Vector3(0, 0.65, 0), 0.0)

func _build_furniture(item: Dictionary) -> void:
	var holder := Node3D.new()
	holder.transform = Transform3D(Bricks.basis_y(float(item.transform.get("rotation_y", 0.0))), _position(item))
	root.add_child(holder)
	var result: Dictionary = furniture_builder.call(holder, item)
	batch.absorb(String(item.id), holder)
	for box in result.get("collision", []):
		_box_body(String(item.id), box.size, holder.transform * Vector3(box.center), float(item.transform.get("rotation_y", 0.0)))
	if holder.get_child_count() == 0:
		holder.queue_free()
	else:
		holder.set_meta("entity_id", String(item.id))

# --- Collision -----------------------------------------------------------------

func _wall_collision(item: Dictionary, edge: String, hosted: Dictionary) -> void:
	var center := PlanGrid.edge_center(edge)
	var rotation := PlanGrid.edge_rotation(edge)
	var id := String(item.id)
	var basis := Bricks.basis_y(rotation)
	if hosted.get("kind", "") == "door":
		for side in [-1.0, 1.0]:
			_box_body(id, Vector3(0.5, PlanGrid.WALL_HEIGHT, 0.5), center + basis * Vector3(side * 1.25, 0, 0) + Vector3(0, PlanGrid.WALL_HEIGHT * 0.5, 0), rotation)
		_box_body(id, Vector3(2.5, 0.3, 0.5), center + Vector3(0, PlanGrid.WALL_HEIGHT - 0.15, 0), rotation)
		return
	_box_body(id, Vector3(2.5, PlanGrid.WALL_HEIGHT, 0.5), center + Vector3(0, PlanGrid.WALL_HEIGHT * 0.5, 0), rotation)

func _floor_collision(item: Dictionary, cell: Vector2i) -> void:
	_box_body(String(item.id), Vector3(PlanGrid.TILE, PlanGrid.FLOOR_TOP, PlanGrid.TILE), PlanGrid.cell_center(cell) + Vector3(0, PlanGrid.FLOOR_TOP * 0.5, 0), 0.0)

func _box_body(id: String, size: Vector3, center: Vector3, rotation_y: float) -> StaticBody3D:
	if preview_mode:
		return null
	var body := StaticBody3D.new()
	body.set_meta("entity_id", id)
	body.transform = Transform3D(Bricks.basis_y(rotation_y), center)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	_remember(id, body)
	return body

func _remember(id: String, body: CollisionObject3D) -> void:
	if not bodies.has(id):
		bodies[id] = []
	bodies[id].append(body)

# Real bricks are never perfectly uniform; a tiny per-brick shift in value
# makes the running bond readable without drawing mortar lines.
static func vary(base: Color, where: Vector3, amount: float = 0.035) -> Color:
	var noise := float(posmod(hash(Vector3i(roundi(where.x * 4.0), roundi(where.y * 5.0), roundi(where.z * 4.0))), 1000)) / 1000.0 - 0.5
	return base.lightened(noise * amount * 2.0) if noise > 0.0 else base.darkened(-noise * amount * 2.0)

static func _position(item: Dictionary) -> Vector3:
	var values: Array = item.transform.position
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func set_wall_collision_enabled(enabled: bool, ids: Dictionary) -> void:
	for id in ids:
		for body in bodies.get(id, []):
			if is_instance_valid(body):
				body.collision_layer = 1 if enabled else 0
