extends RefCounted

# Furnishes template rooms by type so every starter feels lived in. Pieces go
# against walls (backs to the wall, fronts into the room) or in simple grids,
# always stud-aligned, clear of door swings and of each other.

const HANG := ["whiteboard", "tv", "chalkboard", "electrical_panel"]

static func furnish(model: ProjectModel, builder: RefCounted) -> void:
	var catalog := Placement.furniture_catalog()
	if catalog == null:
		return
	for name in builder.rooms:
		var room: Dictionary = builder.rooms[name]
		var layout := RoomLayout.new(model, builder, String(name), room)
		match String(room.type):
			"classroom": _classroom(layout)
			"office": _office(layout)
			"open_office": _open_office(layout)
			"conference": _conference(layout)
			"lobby": _lobby(layout)
			"break_room": _break_room(layout)
			"restroom": _restroom(layout)
			"storage": _storage(layout)
			"mechanical": _mechanical(layout)
			"corridor": _corridor(layout)
			"library": _library(layout)
			"gym": _gym(layout)
			"workshop": _workshop(layout)
	var paved: Dictionary = {}
	for item in model.objects:
		if item.kind == "floor": paved[Vector2i(int(item.properties.cell[0]), int(item.properties.cell[1]))] = true
	# Outdoor pieces keep clear of each other, parking stalls and tree
	# canopies (a tree's crown is about 2 m across, far wider than its trunk).
	var outside: Dictionary = {}
	for item in model.objects:
		var values: Array = item.transform.position
		var at := Vector3(float(values[0]), 0, float(values[2]))
		match String(item.kind):
			"tree", "shrub":
				for stud in Placement.footprint_studs(at, Vector2i(4, 4), 0.0): outside[stud] = true
			"parking":
				for stud in Placement.footprint_studs(at, Vector2i(5, 10), float(item.transform.get("rotation_y", 0.0))): outside[stud] = true
	for spot in builder.layout.get("outdoor", []):
		var size: Vector2i = Placement.furniture_items().get(String(spot[0]), {}).get("footprint", Vector2i(2, 2))
		var yaw := float(spot[3]) if spot.size() > 3 else 0.0
		var turned := PlanGrid.rotated_footprint(size, yaw)
		var wanted := Vector3((float(spot[1]) + builder.origin.x + 0.5) * PlanGrid.TILE, 0, (float(spot[2]) + builder.origin.y + 0.5) * PlanGrid.TILE)
		# Slide along the street a stud at a time until the spot is clear.
		for shift in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.5, -2.5]:
			var center := Vector3(PlanGrid.snap_part_center(wanted.x + shift, turned.x), 0, PlanGrid.snap_part_center(wanted.z, turned.y))
			var studs := Placement.footprint_studs(center, size, yaw)
			if studs.any(func(stud: Vector2i) -> bool: return outside.has(stud)):
				continue
			for stud in studs: outside[stud] = true
			# Anything touching the sidewalk stands on it, not in it.
			var on_paving := studs.any(func(stud: Vector2i) -> bool: return paved.has(Vector2i(floori(stud.x / 5.0), floori(stud.y / 5.0))))
			RoomLayout.add_item(model, String(spot[0]), center, yaw, PlanGrid.FLOOR_TOP if on_paving else 0.0, dict_or_empty(spot))
			break

static func dict_or_empty(spot: Array) -> Dictionary:
	return spot[4] if spot.size() > 4 and spot[4] is Dictionary else {}

static func _classroom(room: RoomLayout) -> void:
	var board_wall := room.plain_wall()
	room.hang("chalkboard", board_wall, 0.0)
	room.hang("whiteboard", room.opposite(board_wall), 0.0)
	room.against(board_wall, "teacher_desk", -0.28, true, {"color": "reddish_brown"}, 0.9)
	# Rows of student desks facing the board.
	var colors := ["medium_nougat", "red", "medium_blue", "yellow", "lime"]
	room.grid("student_desk", board_wall, 3, 3, 2.25, 0.35, func(index: int) -> Dictionary: return {"color": colors[index % colors.size()]})
	room.against(room.side_wall(board_wall, 1), "cubby_shelf", -0.25)
	room.against(room.side_wall(board_wall, -1), "lockers", 0.25, false, {"color": "sand_blue"})
	room.corner("tall_plant", board_wall, 1)
	room.corner("globe", room.opposite(board_wall), -1)

static func _office(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	var desk_center := room.against(back, "desk", 0.0, false, {"variant": "monitors"}, 0.4)
	if desk_center != Vector3.INF:
		room.facing_item("office_chair", desk_center, back, 2.1)
	room.against(room.side_wall(back, 1), "bookshelf", 0.1)
	room.against(room.side_wall(back, -1), "filing_cabinet", 0.2)
	room.corner("small_plant", room.opposite(back), 1)
	room.hang("tv", room.side_wall(back, -1), -0.2)

static func _open_office(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	# Two rows of desks back to back, each with a chair.
	for row in [0.0, 1.0]:
		for column in range(3):
			var t := (float(column) - 1.0) * 0.62
			# Rows 4 m apart leave an aisle behind each chair.
			var center := room.against(back, "desk", t, false, {"variant": "laptop" if column % 2 else "monitors"}, 0.6 + row * 4.0)
			if center != Vector3.INF:
				room.facing_item("office_chair", center, back, 2.1)
	room.against(room.side_wall(back, 1), "printer", 0.0)
	room.against(room.side_wall(back, -1), "water_cooler", 0.3)
	room.corner("tall_plant", room.opposite(back), 1)
	room.corner("tall_plant", room.opposite(back), -1)
	room.hang("whiteboard", room.side_wall(back, -1), -0.3)

static func _conference(room: RoomLayout) -> void:
	room.center("meeting_table", {"color": "medium_nougat"})
	var back := room.far_wall_from_door()
	room.hang("tv", back, 0.0)
	room.corner("tall_plant", back, 1)
	room.corner("small_plant", room.opposite(back), -1)

static func _lobby(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	room.against(back, "reception_desk", 0.0, true, {"color": "white"}, 1.6)
	room.against(room.side_wall(back, 1), "sofa", 0.0, false, {"color": "sand_blue"})
	room.against(room.side_wall(back, -1), "armchair", -0.2, false, {"color": "dark_red"})
	room.corner("tall_plant", back, 1)
	room.corner("tall_plant", back, -1)
	room.hang("tv", room.side_wall(back, -1), 0.3)

static func _break_room(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	room.against(back, "kitchen_counter", -0.3)
	room.against(back, "fridge", 0.55)
	room.against(room.side_wall(back, 1), "coffee_station", 0.0)
	room.against(room.side_wall(back, -1), "vending_machine", 0.0)
	room.center("dining_table", {"color": "white"}, 0.8)

static func _restroom(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	room.against(back, "toilet_stall", -0.25)
	room.against(room.side_wall(back, 1), "sink_vanity", 0.1)
	room.against(room.side_wall(back, -1), "sink_vanity", 0.1)

static func _storage(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	room.against(back, "storage_shelving", -0.25)
	room.against(back, "storage_shelving", 0.35)
	room.against(room.side_wall(back, 1), "storage_shelving", 0.0)
	room.corner("trash_bin", room.opposite(back), -1)

static func _mechanical(room: RoomLayout) -> void:
	var back := room.near_wall_to_door()
	room.against(back, "workbench", 0.35)
	room.against(back, "water_heater", -0.35)
	room.hang("electrical_panel", back, 0.0)
	room.against(room.side_wall(back, 1), "storage_shelving", 0.3)

static func _corridor(room: RoomLayout) -> void:
	var long := room.long_walls()
	if room.builder.layout.get("rooms", [{}])[0].get("type", "") == "classroom":
		for index in range(4):
			room.against(long[0], "lockers", -0.42 + index * 0.28, false, {"color": ["medium_blue", "red", "sand_green", "dark_azure"][index % 4]})
	else:
		room.against(long[0], "water_cooler", 0.35)
		room.against(long[0], "tall_plant", -0.45)

static func _library(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	for t in [-0.55, -0.15, 0.25, 0.62]:
		room.against(back, "bookshelf", t, false, {"color": "reddish_brown"})
	room.against(room.side_wall(back, 1), "bookshelf", 0.0, false, {"color": "reddish_brown"})
	room.against(room.side_wall(back, -1), "bookshelf", 0.2, false, {"color": "reddish_brown"})
	room.center("dining_table", {"color": "medium_nougat"}, 0.2, -0.22)
	room.center("reading_rug", {"color": "medium_blue"}, 0.2, 0.25)
	room.corner("armchair", room.opposite(back), 1)
	room.corner("globe", room.opposite(back), -1)

static func _gym(room: RoomLayout) -> void:
	var long := room.long_walls()
	room.against(long[0], "park_bench", -0.3, false, {"color": "medium_nougat"})
	room.against(long[0], "park_bench", 0.3, false, {"color": "medium_nougat"})
	room.against(long[1], "lockers", 0.0, false, {"color": "red"})

static func _workshop(room: RoomLayout) -> void:
	var back := room.far_wall_from_door()
	room.against(back, "workbench", -0.3)
	room.against(back, "workbench", 0.3)
	room.against(room.side_wall(back, 1), "storage_shelving", -0.1)
	room.against(room.side_wall(back, -1), "desk", 0.1, false, {"variant": "laptop"})
	room.corner("tall_plant", room.opposite(back), 1)
	room.hang("whiteboard", back, 0.0)
	room.center("rug", {"color": "tan"}, 0.0, 0.1)

# --- Layout helper --------------------------------------------------------------------------

class RoomLayout:
	var model: ProjectModel
	var builder: RefCounted
	var name: String
	var rect: Rect2i
	var inner: Rect2      # interior in metres, inside the wall faces
	var taken: Dictionary = {}
	var hung: Dictionary = {}
	var door_edges: Array[String] = []

	func _init(target: ProjectModel, plan: RefCounted, room_name: String, room: Dictionary) -> void:
		model = target
		builder = plan
		name = room_name
		rect = room.rect
		var low := Vector2(rect.position) * PlanGrid.TILE + Vector2(0.25, 0.25)
		var high := Vector2(rect.end) * PlanGrid.TILE - Vector2(0.25, 0.25)
		inner = Rect2(low, high - low)
		for edge in PlanGrid.rect_perimeter(rect.position, rect.end):
			if builder.doors.has(edge) and not bool(builder.doors[edge].get("window", false)):
				door_edges.append(edge)
				_block_door(edge)
		# Existing objects (the air handler) are respected.
		for item in model.objects:
			if item.kind == "ahu":
				var library := Placement.equipment_models()
				if library == null: continue
				var values: Array = item.transform.position
				for stud in Placement.footprint_studs(Vector3(float(values[0]), 0, float(values[2])), library.footprint("ahu", item.properties), float(item.transform.rotation_y)):
					taken[stud] = true

	func _block_door(edge: String) -> void:
		var center := PlanGrid.edge_center(edge)
		var normal := PlanGrid.edge_normal(edge)
		var inward := normal if rect.has_point(PlanGrid.cell_at(center + normal * 0.5)) else -normal
		var along := Vector3(1, 0, 0) if edge.begins_with("x") else Vector3(0, 0, 1)
		for a in range(-3, 4):
			for d in range(1, 5):
				var point := center + along * (a * 0.5) + inward * (d * 0.5)
				taken[Vector2i(PlanGrid.stud_cell(point.x), PlanGrid.stud_cell(point.z))] = true

	# Walls are named by the side of the room: "north" (-Z), "south", "west" (-X), "east".
	func wall_edges(side: String) -> Array[String]:
		match side:
			"north": return PlanGrid.edges_between(rect.position, Vector2i(rect.end.x, rect.position.y))
			"south": return PlanGrid.edges_between(Vector2i(rect.position.x, rect.end.y), rect.end)
			"west": return PlanGrid.edges_between(rect.position, Vector2i(rect.position.x, rect.end.y))
			"east": return PlanGrid.edges_between(Vector2i(rect.end.x, rect.position.y), rect.end)
		return []

	func opposite(side: String) -> String:
		return {"north": "south", "south": "north", "west": "east", "east": "west"}[side]

	func side_wall(side: String, which: int) -> String:
		if side in ["north", "south"]:
			return "east" if which > 0 else "west"
		return "south" if which > 0 else "north"

	func long_walls() -> Array[String]:
		var result: Array[String] = []
		if rect.size.x >= rect.size.y: result.assign(["north", "south"])
		else: result.assign(["west", "east"])
		return result

	# The side with the room's main door: an entrance to the outside wins.
	func _door_side() -> String:
		var fallback := ""
		for side in ["south", "north", "west", "east"]:
			for edge in wall_edges(side):
				if edge not in door_edges:
					continue
				if String(builder.doors[edge].get("b", "")) == "outside" or String(builder.doors[edge].get("a", "")) == "outside":
					return side
				if fallback.is_empty():
					fallback = side
		return fallback if not fallback.is_empty() else "south"

	# The side with the most uninterrupted wall (no doors or windows).
	func plain_wall() -> String:
		var best := "north"
		var best_score := -1
		for side in ["west", "east", "north", "south"]:
			var score := 0
			for edge in wall_edges(side):
				if not builder.doors.has(edge): score += 1
			if score > best_score:
				best_score = score
				best = side
		return best

	func far_wall_from_door() -> String:
		return opposite(_door_side())

	func near_wall_to_door() -> String:
		return _door_side()

	func _inward(side: String) -> Vector3:
		return {"north": Vector3(0, 0, 1), "south": Vector3(0, 0, -1), "west": Vector3(1, 0, 0), "east": Vector3(-1, 0, 0)}[side]

	func _yaw(side: String) -> float:
		var inward := _inward(side)
		return atan2(inward.x, inward.z)

	func _floor_y() -> float:
		return PlanGrid.FLOOR_TOP

	# Place a floor piece with its back to `side`; t runs -0.5..0.5 along the
	# wall, `gap` pushes it further into the room (metres).
	# flip turns the piece so its user side faces the wall (reception, teacher).
	func against(side: String, item: String, t: float, flip: bool = false, options: Dictionary = {}, gap: float = 0.0) -> Vector3:
		var spec: Dictionary = Placement.furniture_items().get(item, {})
		if spec.is_empty(): return Vector3.INF
		var size: Vector2i = spec.footprint
		var yaw := _yaw(side) + (PI if flip else 0.0)
		var inward := _inward(side)
		var along_axis := Vector3(1, 0, 0) if side in ["north", "south"] else Vector3(0, 0, 1)
		var span := inner.size.x if side in ["north", "south"] else inner.size.y
		var mid := Vector3(inner.get_center().x, 0, inner.get_center().y)
		var wall_line: float = {"north": inner.position.y, "south": inner.end.y, "west": inner.position.x, "east": inner.end.x}[side]
		var depth := float(size.y) * PlanGrid.STUD
		var point := mid + along_axis * (t * span)
		if side in ["north", "south"]:
			point.z = wall_line + inward.z * (depth * 0.5 + gap)
		else:
			point.x = wall_line + inward.x * (depth * 0.5 + gap)
		return _try(item, point, yaw, options)

	func facing_item(item: String, anchor: Vector3, side: String, distance: float) -> void:
		var inward := _inward(side)
		var point := anchor + inward * distance
		_try(item, point, _yaw(side) + PI, {}, 0.8)

	func corner(item: String, side: String, which: int) -> void:
		for t in [0.45 * which, 0.35 * which, 0.25 * which]:
			if against(side, item, t) != Vector3.INF:
				return

	# Centre-ish: tries small nudges until the piece clears doors and walls.
	func center(item: String, options: Dictionary = {}, dx: float = 0.0, dz: float = 0.0) -> Vector3:
		for nudge in [Vector2.ZERO, Vector2(0, 0.08), Vector2(0, -0.08), Vector2(0.08, 0), Vector2(-0.08, 0), Vector2(0, 0.16), Vector2(0, -0.16), Vector2(0.16, 0), Vector2(-0.16, 0)]:
			var point := Vector3(inner.get_center().x + (dx + nudge.x) * inner.size.x, 0, inner.get_center().y + (dz + nudge.y) * inner.size.y)
			var placed := _try(item, point, 0.0, options)
			if placed != Vector3.INF:
				return placed
		return Vector3.INF

	# rows x columns of pieces facing `board` (their fronts face away from it).
	func grid(item: String, board: String, rows: int, columns: int, spacing: float, start: float, options: Callable) -> void:
		var inward := _inward(board)
		var along_axis := Vector3(1, 0, 0) if board in ["north", "south"] else Vector3(0, 0, 1)
		var wall_line: float = {"north": inner.position.y, "south": inner.end.y, "west": inner.position.x, "east": inner.end.x}[board]
		var span := inner.size.x if board in ["north", "south"] else inner.size.y
		var mid := Vector3(inner.get_center().x, 0, inner.get_center().y)
		var index := 0
		for row in range(rows):
			for column in range(columns):
				var point := mid + along_axis * ((float(column) - float(columns - 1) * 0.5) * spacing)
				var depth := start * span + 2.6 + row * spacing
				if board in ["north", "south"]: point.z = wall_line + inward.z * depth
				else: point.x = wall_line + inward.x * depth
				# Students sit on the desk's +Z side looking toward -Z: at the board.
				_try(item, point, _yaw(board), options.call(index))
				index += 1

	func hang(item: String, side: String, t: float) -> void:
		var spec: Dictionary = Placement.furniture_items().get(item, {})
		if spec.is_empty(): return
		var width: int = spec.footprint.x
		var edges := wall_edges(side)
		if edges.is_empty(): return
		var inward := _inward(side)
		var order: Array = range(edges.size())
		var preferred := clampi(roundi((t + 0.5) * float(edges.size() - 1)), 0, edges.size() - 1)
		order.sort_custom(func(a: int, b: int) -> bool: return absi(a - preferred) < absi(b - preferred))
		for index in order:
			var edge := edges[index]
			if builder.doors.has(edge) or hung.has(edge):
				continue
			var center := PlanGrid.edge_center(edge)
			var position := center + inward * (PlanGrid.STUD * 0.5)
			var along := Vector3(1, 0, 0) if edge.begins_with("x") else Vector3(0, 0, 1)
			position += along * (0.0 if width % 2 == 0 else PlanGrid.STUD * 0.5)
			position.y = _floor_y()
			# Wide boards span several wall sections: all of them must be plain
			# wall (no door or window), and the board must stop short of the
			# room's corners.
			var half_width := float(width) * PlanGrid.STUD * 0.5
			var mid := position.dot(along)
			var span_low := inner.position.x if along.x > 0.5 else inner.position.y
			var span_high := inner.end.x if along.x > 0.5 else inner.end.y
			if mid - half_width < span_low - 0.01 or mid + half_width > span_high + 0.01:
				continue
			var covered: Array[String] = []
			for other in edges:
				var at := PlanGrid.edge_center(other).dot(along)
				if at + PlanGrid.TILE * 0.5 > mid - half_width + 0.01 and at - PlanGrid.TILE * 0.5 < mid + half_width - 0.01:
					covered.append(other)
			if covered.any(func(other: String) -> bool: return builder.doors.has(other) or hung.has(other)):
				continue
			# The floor strip under a wall piece is reserved both ways, so no
			# shelf, plant or bench ends up inside the board above it.
			var strip := Placement.footprint_studs(position + inward * (float(spec.footprint.y) * PlanGrid.STUD * 0.5), spec.footprint, atan2(inward.x, inward.z))
			if strip.any(func(stud: Vector2i) -> bool: return taken.has(stud)):
				continue
			for stud in strip: taken[stud] = true
			var normal := PlanGrid.edge_normal(edge)
			var side_sign := 1 if inward.dot(normal) > 0.0 else -1
			for other in covered: hung[other] = true
			RoomLayout.add_item(model, item, position, atan2(inward.x, inward.z), position.y, {"edge": edge, "side": side_sign})
			return

	func _try(item: String, point: Vector3, yaw: float, options: Dictionary, margin: float = 0.0) -> Vector3:
		var spec: Dictionary = Placement.furniture_items().get(item, {})
		if spec.is_empty(): return Vector3.INF
		var size: Vector2i = spec.footprint
		var turned := PlanGrid.rotated_footprint(size, yaw)
		var center := Vector3(PlanGrid.snap_part_center(point.x, turned.x), 0, PlanGrid.snap_part_center(point.z, turned.y))
		var half := Vector2(turned) * PlanGrid.STUD * 0.5
		var box := Rect2(Vector2(center.x, center.z) - half, half * 2.0)
		if not inner.grow(0.01).encloses(box):
			return Vector3.INF
		var studs := Placement.footprint_studs(center, size, yaw)
		for stud in studs:
			if taken.has(stud): return Vector3.INF
		for stud in studs:
			taken[stud] = true
		RoomLayout.add_item(model, item, center, yaw, _floor_y(), options)
		return center

	static func add_item(target: ProjectModel, item: String, center: Vector3, yaw: float, height: float, extra: Dictionary) -> void:
		var properties := {"item": item}
		properties.merge(extra, true)
		target.add_object("furniture", {"position": [center.x, height, center.z], "rotation_y": fposmod(yaw, TAU)}, properties)
