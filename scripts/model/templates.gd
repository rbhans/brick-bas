extends RefCounted

# Hand-authored starter plans. Each plan lists rooms as cell rectangles on the
# PlanGrid (2.5 m tiles); walls come from the room outlines (shared walls are
# built once), doors connect named rooms, windows follow each room's rhythm,
# and the site gets sidewalks, parking and planting. Furniture and HVAC are
# seeded by Furnisher / HvacSeeder so every starter is lived-in and running.

const Furnisher := preload("res://scripts/model/furnisher.gd")
const HvacSeeder := preload("res://scripts/model/hvac_seeder.gd")

const PRESETS := [
	{"id": "studio", "name": "Corner workshop", "detail": "One big workroom, an office and a washroom. A packaged unit on the back pad feeds two zones.", "size": "49 × 33 ft"},
	{"id": "office", "name": "Neighborhood office", "detail": "Lobby, open office, private offices, conference and break rooms around a central corridor.", "size": "98 × 66 ft"},
	{"id": "school", "name": "Elementary school", "detail": "Six classrooms, library, gym and front office off one hallway. A plant-room AHU plus a gym unit.", "size": "197 × 90 ft"},
	{"id": "blank", "name": "Empty lot", "detail": "Open ground. Drag out rooms with the Room tool.", "size": "open"},
]

static func definition(id: String) -> Dictionary:
	for entry in PRESETS:
		if entry.id == id: return entry
	return PRESETS[-1]

static func plan(id: String) -> Dictionary:
	match id:
		"studio": return _studio()
		"office": return _office()
		"school": return _school()
	return {}

static func create(id: String) -> ProjectModel:
	var model := ProjectModel.new()
	model.project_id = id
	var spec := definition(id)
	model.site = ProjectModel.default_site()
	model.site.starter = id
	model.site.name = String(spec.name)
	var layout := plan(id)
	if layout.is_empty():
		model.site.spawn = [0.0, 1.0, 2.5]
		return model
	var builder := PlanBuilder.new(model, layout)
	builder.build()
	HvacSeeder.seed(model, builder)
	Furnisher.furnish(model, builder)
	model.site.spawn = builder.spawn()
	return model

# --- Plans -----------------------------------------------------------------------
# Rects are [x0, z0, x1, z1] in cells (end exclusive), relative to "origin".
# North is -Z; the street and main entrance face +Z (toward the default camera).

static func _studio() -> Dictionary:
	return {
		"origin": Vector2i(-3, -2), "exterior": "red_brick", "interior": "white",
		"rooms": [
			{"name": "Workshop", "type": "workshop", "rect": [0, 0, 4, 4], "floor": "maple", "windows": "alternate"},
			{"name": "Office", "type": "office", "rect": [4, 2, 6, 4], "floor": "carpet_blue", "windows": "all"},
			{"name": "Washroom", "type": "restroom", "rect": [4, 0, 6, 2], "floor": "checker", "windows": "none"},
		],
		"doors": [
			{"a": "Workshop", "b": "outside", "edge": "x:1:4", "style": "glass_door"},
			{"a": "Workshop", "b": "Office", "style": "door"},
			{"a": "Workshop", "b": "Washroom", "style": "door_blue"},
		],
		"storefront": ["x:2:4"],
		"paving": [[0, 4, 6, 5], [1, 5, 2, 7]],
		"asphalt": [[7, 1, 11, 6]],
		"parking": [{"cell": [7, 1], "count": 4, "facing": "west"}],
		"trees": [["oak", -2, 1], ["pine", -2, 4], ["oak", 12, 6], ["spruce", 3, 8], ["poplar", -1, 7]],
		"shrubs": [[-1, 5], [6, 0]],
		"outdoor": [["lamp_post", 3, 4.9, 0.0], ["park_bench", 3, 5, PI], ["flower_bed", 0, 4.4, 0.0], ["flower_bed", 4, 4.4, 0.0], ["bike_rack", 5, 6, 0.0, {"variant": "two_bikes"}], ["trash_bin", 2, 5.6, 0.0]],
		"pad": {"rect": [0, -6, 2, 0], "unit": "AHU-1"},
		# A packaged unit on the back pad blows south into the ceiling; the
		# main runs east above the back of the building.
		"hvac": {
			"units": {"AHU-1": {"id": "ahu", "at": [1.1, -3.0], "rotation": -90.0, "outdoor": true, "layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"]}},
			"trunks": [{"id": "main", "unit": "AHU-1", "axis": "x", "line": 0.5, "flow": 1.0}],
			"zones": [{"trunk": "main", "room": "Workshop", "at": 2.0, "label": "VAV-1 · Workshop"}, {"trunk": "main", "room": "Office", "at": 5.0, "label": "VAV-2 · Office"}],
		},
	}

static func _office() -> Dictionary:
	return {
		"origin": Vector2i(-6, -4), "exterior": "tan", "interior": "white",
		"rooms": [
			{"name": "Mechanical", "type": "mechanical", "rect": [0, 0, 5, 3], "floor": "concrete", "windows": "none", "walls": "gray"},
			{"name": "Office 1", "type": "office", "rect": [5, 0, 7, 3], "floor": "carpet_gray", "windows": "all"},
			{"name": "Office 2", "type": "office", "rect": [7, 0, 9, 3], "floor": "carpet_gray", "windows": "all"},
			{"name": "Conference", "type": "conference", "rect": [9, 0, 12, 3], "floor": "carpet_blue", "windows": "alternate", "walls": "sand_blue"},
			{"name": "Corridor", "type": "corridor", "rect": [0, 3, 12, 4], "floor": "tile_gray", "windows": "ends"},
			{"name": "Restroom", "type": "restroom", "rect": [0, 4, 2, 6], "floor": "checker", "windows": "none"},
			{"name": "Storage", "type": "storage", "rect": [0, 6, 2, 8], "floor": "concrete", "windows": "none"},
			{"name": "Break room", "type": "break_room", "rect": [2, 4, 4, 8], "floor": "checker_blue", "windows": "alternate", "walls": "cream"},
			{"name": "Lobby", "type": "lobby", "rect": [4, 4, 7, 8], "floor": "walnut", "windows": "none"},
			{"name": "Open office", "type": "open_office", "rect": [7, 4, 12, 8], "floor": "carpet_gray", "windows": "alternate"},
		],
		"doors": [
			{"a": "Lobby", "b": "outside", "edge": "x:5:8", "style": "glass_door"},
			{"a": "Mechanical", "b": "outside", "edge": "x:1:0", "style": "door"},
			{"a": "Mechanical", "b": "Corridor", "style": "door"},
			{"a": "Office 1", "b": "Corridor", "style": "door"},
			{"a": "Office 2", "b": "Corridor", "style": "door"},
			{"a": "Conference", "b": "Corridor", "style": "glass_door"},
			{"a": "Restroom", "b": "Corridor", "style": "door_blue"},
			{"a": "Storage", "b": "Break room", "style": "door"},
			{"a": "Break room", "b": "Corridor", "style": "door"},
			{"a": "Lobby", "b": "Corridor", "style": "glass_door"},
			{"a": "Open office", "b": "Corridor", "style": "door"},
			{"a": "Open office", "b": "Lobby", "style": "glass_door"},
		],
		"storefront": ["x:4:8", "x:6:8"],
		"paving": [[-1, 8, 13, 9], [5, 9, 6, 11]],
		"asphalt": [[-1, 11, 13, 15]],
		"parking": [{"cell": [0, 11], "count": 12, "facing": "north"}],
		"trees": [["oak", -2, 2], ["oak", -2, 6], ["pine", 14, 1], ["oak", 14, 6], ["poplar", 3, 10], ["poplar", 8, 10], ["spruce", 13, 12]],
		"shrubs": [[-1, 9], [13, 9]],
		# The air handler discharges west, then the main swings into the
		# corridor and runs east, so every branch is downstream of it.
		"hvac": {
			"units": {"AHU-1": {"id": "ahu", "at": [2.5, 1.5], "rotation": 180.0, "layout": ["damper", "filter", "cooling_coil", "fan"]}},
			"trunks": [{"id": "main", "unit": "AHU-1", "axis": "x", "line": 3.5, "flow": 1.0}],
			"zones": [
				{"trunk": "main", "room": "Break room", "at": 3.0, "label": "VAV-1 · Break room"},
				{"trunk": "main", "room": "Office 1", "at": 6.0, "label": "VAV-2 · Office 1"},
				{"trunk": "main", "room": "Lobby", "at": 6.0, "label": "VAV-3 · Lobby"},
				{"trunk": "main", "room": "Office 2", "at": 8.0, "label": "VAV-4 · Office 2"},
				{"trunk": "main", "room": "Open office", "at": 9.5, "label": "VAV-5 · Open office"},
				{"trunk": "main", "room": "Conference", "at": 11.0, "label": "VAV-6 · Conference"},
			],
		},
		"outdoor": [["lamp_post", 0, 10, 0.0], ["lamp_post", 6, 10, 0.0], ["lamp_post", 12, 10, 0.0], ["park_bench", 3, 8.6, PI], ["park_bench", 8, 8.6, PI], ["flower_bed", 4, 8.3, 0.0], ["flower_bed", 6.6, 8.3, 0.0], ["bike_rack", 10, 9.6, 0.0, {"variant": "one_bike"}], ["trash_bin", 7, 9.6, 0.0], ["outdoor_table", 14.2, 6, 0.0, {"variant": "umbrella"}]],
	}

static func _school() -> Dictionary:
	return {
		"origin": Vector2i(-11, -6), "exterior": "red_brick", "interior": "cream",
		"rooms": [
			{"name": "Classroom 101", "type": "classroom", "rect": [0, 0, 4, 4], "floor": "carpet_green", "windows": "all", "walls": "white"},
			{"name": "Classroom 102", "type": "classroom", "rect": [4, 0, 8, 4], "floor": "carpet_blue", "windows": "all", "walls": "white"},
			{"name": "Classroom 103", "type": "classroom", "rect": [8, 0, 12, 4], "floor": "carpet_green", "windows": "all", "walls": "white"},
			{"name": "Classroom 104", "type": "classroom", "rect": [12, 0, 16, 4], "floor": "carpet_blue", "windows": "all", "walls": "white"},
			{"name": "Classroom 106", "type": "classroom", "rect": [16, 0, 20, 4], "floor": "carpet_green", "windows": "all", "walls": "white"},
			{"name": "Library", "type": "library", "rect": [20, 0, 24, 4], "floor": "oak", "windows": "all"},
			{"name": "Hallway", "type": "corridor", "rect": [0, 4, 24, 5], "floor": "checker", "windows": "ends"},
			{"name": "Mechanical", "type": "mechanical", "rect": [0, 5, 6, 9], "floor": "concrete", "windows": "none", "walls": "gray"},
			{"name": "Girls restroom", "type": "restroom", "rect": [6, 5, 8, 7], "floor": "tile_white", "windows": "none"},
			{"name": "Boys restroom", "type": "restroom", "rect": [8, 5, 10, 7], "floor": "tile_white", "windows": "none"},
			{"name": "Custodial", "type": "storage", "rect": [6, 7, 10, 9], "floor": "concrete", "windows": "alternate"},
			{"name": "Entry lobby", "type": "lobby", "rect": [10, 5, 13, 11], "floor": "walnut", "windows": "alternate"},
			{"name": "Main office", "type": "office", "rect": [13, 5, 16, 9], "floor": "carpet_gray", "windows": "all", "walls": "white"},
			{"name": "Classroom 105", "type": "classroom", "rect": [16, 5, 19, 9], "floor": "carpet_green", "windows": "all", "walls": "white"},
			{"name": "Gym", "type": "gym", "rect": [19, 5, 24, 11], "floor": "maple", "windows": "alternate", "walls": "tan"},
		],
		"doors": [
			{"a": "Entry lobby", "b": "outside", "edge": "x:11:11", "style": "glass_door"},
			{"a": "Gym", "b": "outside", "edge": "z:24:9", "style": "door_red"},
			{"a": "Mechanical", "b": "outside", "edge": "x:1:9", "style": "door"},
			{"a": "Hallway", "b": "outside", "edge": "z:0:4", "style": "glass_door"},
			{"a": "Classroom 101", "b": "Hallway", "style": "door"},
			{"a": "Classroom 102", "b": "Hallway", "style": "door"},
			{"a": "Classroom 103", "b": "Hallway", "style": "door"},
			{"a": "Classroom 104", "b": "Hallway", "style": "door"},
			{"a": "Classroom 106", "b": "Hallway", "style": "door"},
			{"a": "Library", "b": "Hallway", "style": "glass_door", "at": 1},
			{"a": "Mechanical", "b": "Hallway", "style": "door"},
			{"a": "Girls restroom", "b": "Hallway", "style": "door_red"},
			{"a": "Boys restroom", "b": "Hallway", "style": "door_blue"},
			{"a": "Custodial", "b": "Mechanical", "edge": "z:6:8", "style": "door"},
			{"a": "Entry lobby", "b": "Hallway", "style": "glass_door"},
			{"a": "Main office", "b": "Entry lobby", "style": "glass_door"},
			{"a": "Main office", "b": "Hallway", "style": "door"},
			{"a": "Classroom 105", "b": "Hallway", "style": "door"},
			{"a": "Gym", "b": "Hallway", "style": "door_red"},
		],
		"storefront": ["x:10:11", "x:12:11"],
		"paving": [[-1, 11, 25, 12], [11, 12, 12, 14], [24, 9, 26, 10], [-2, 4, -1, 5]],
		"asphalt": [[-2, 14, 18, 18]],
		"parking": [{"cell": [-1, 14], "count": 18, "facing": "north"}],
		"trees": [["oak", -3, 1], ["oak", -3, 8], ["pine", 26, 1], ["oak", 30, 5], ["poplar", 2, 13], ["poplar", 6, 13], ["poplar", 15, 13], ["poplar", 18, 13], ["spruce", 21, 14], ["oak", 25, 14], ["pine", 10, -2], ["oak", 4, -2], ["oak", 17, -2], ["spruce", 22, -2]],
		"shrubs": [[-2, 11], [25, 11], [25, 3]],
		"outdoor": [["lamp_post", 2, 12.8, 0.0], ["lamp_post", 8, 12.8, 0.0], ["lamp_post", 15, 12.8, 0.0], ["lamp_post", 21, 12.8, 0.0], ["park_bench", 7, 11.4, PI], ["park_bench", 15, 11.4, PI], ["flower_bed", 10.2, 11.4, 0.0], ["flower_bed", 13, 11.4, 0.0], ["bike_rack", 4, 11.6, 0.0, {"variant": "two_bikes"}], ["bike_rack", 17, 11.6, 0.0, {"variant": "one_bike"}], ["trash_bin", 12.4, 12.4, 0.0], ["outdoor_table", 25.4, 0, 0.0, {"variant": "umbrella"}], ["outdoor_table", 25.4, -1.6, 0.0, {"variant": "plain"}], ["picket_fence", -2, -1, 0.0], ["picket_fence", -1, -1, 0.0]],
		"pad": {"rect": [24, 6, 29, 9], "unit": "AHU-2"},
		# AHU-1 discharges west, swings into the hallway and runs a main east
		# with a 4-way cross for each pair of facing rooms. The gym has its own
		# packaged unit on the east pad.
		"hvac": {
			"units": {
				"AHU-1": {"id": "ahu", "at": [2.9, 7.0], "rotation": 180.0, "layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"]},
				"AHU-2": {"id": "ahu-gym", "at": [26.9, 8.0], "rotation": 180.0, "outdoor": true, "layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"]},
			},
			"trunks": [
				{"id": "main", "unit": "AHU-1", "axis": "x", "line": 4.5, "flow": 1.0},
			],
			"zones": [
				{"trunk": "main", "room": "Classroom 101", "at": 2.0, "label": "VAV-101"},
				{"trunk": "main", "room": "Classroom 102", "at": 6.0, "label": "VAV-102"},
				{"trunk": "main", "room": "Classroom 103", "at": 11.0, "label": "VAV-103"},
				{"trunk": "main", "room": "Entry lobby", "at": 11.0, "label": "VAV-LOBBY"},
				{"trunk": "main", "room": "Classroom 104", "at": 14.5, "label": "VAV-104"},
				{"trunk": "main", "room": "Main office", "at": 14.5, "label": "VAV-OFFICE"},
				{"trunk": "main", "room": "Classroom 106", "at": 17.5, "label": "VAV-106"},
				{"trunk": "main", "room": "Classroom 105", "at": 17.5, "label": "VAV-105"},
				{"trunk": "main", "room": "Library", "at": 22.0, "label": "VAV-LIBRARY"},
			],
			"direct": [{"unit": "AHU-2", "room": "Gym", "label": "VAV-GYM"}],
		},
	}

# --- Builder ---------------------------------------------------------------------

class PlanBuilder:
	var model: ProjectModel
	var layout: Dictionary
	var origin := Vector2i.ZERO
	var rooms: Dictionary = {}      # name -> {rect: Rect2i (absolute cells), type, floor}
	var cell_room: Dictionary = {}  # Vector2i -> room name
	var walls: Dictionary = {}      # edge -> style
	var doors: Dictionary = {}      # edge -> {style, a, b}
	var entrances: Array[String] = []

	func _init(target: ProjectModel, plan_layout: Dictionary) -> void:
		model = target
		layout = plan_layout
		origin = plan_layout.get("origin", Vector2i.ZERO)

	func cell(x: int, z: int) -> Vector2i:
		return Vector2i(x, z) + origin

	func rect_of(values: Array) -> Rect2i:
		var low := cell(int(values[0]), int(values[1]))
		return Rect2i(low, Vector2i(int(values[2]) - int(values[0]), int(values[3]) - int(values[1])))

	func edge_rel(key: String) -> String:
		var parsed := PlanGrid.parse_edge(key)
		return PlanGrid.edge_key(parsed.axis, int(parsed.i) + origin.x, int(parsed.j) + origin.y)

	func build() -> void:
		for spec in layout.rooms:
			var rect := rect_of(spec.rect)
			rooms[String(spec.name)] = {"rect": rect, "type": String(spec.type), "floor": String(spec.floor), "windows": String(spec.get("windows", "alternate")), "walls": String(spec.get("walls", layout.get("interior", "white")))}
			for i in range(rect.position.x, rect.end.x):
				for j in range(rect.position.y, rect.end.y):
					cell_room[Vector2i(i, j)] = String(spec.name)
		_walls()
		_doors()
		_windows()
		_site()
		# Commit: floors, walls, openings. Room names live on the site.
		for name in rooms:
			var room: Dictionary = rooms[name]
			var rect: Rect2i = room.rect
			model.site.room_names[PlanGrid.cell_key(rect.position)] = name
			model.site.room_types[PlanGrid.cell_key(rect.position)] = String(room.type)
			for i in range(rect.position.x, rect.end.x):
				for j in range(rect.position.y, rect.end.y):
					var c := Vector2i(i, j)
					_add("floor", PlanGrid.cell_center(c), 0.0, {"cell": [c.x, c.y], "finish": room.floor})
		for edge in walls:
			_add("wall", PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge), {"edge": edge, "style": walls[edge]})
		for edge in doors:
			if bool(doors[edge].get("window", false)):
				continue
			_add("door", PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge), {"edge": edge, "style": doors[edge].style, "swing": doors[edge].swing})

	func _add(kind: String, position: Vector3, rotation_y: float, properties: Dictionary) -> Dictionary:
		return model.add_object(kind, {"position": [position.x, position.y, position.z], "rotation_y": rotation_y}, properties)

	func _walls() -> void:
		var exterior := String(layout.get("exterior", "tan"))
		for name in rooms:
			var room: Dictionary = rooms[name]
			var rect: Rect2i = room.rect
			for edge in PlanGrid.rect_perimeter(rect.position, rect.end):
				var sides := PlanGrid.edge_cells(edge)
				var outside := not cell_room.has(sides[0]) or not cell_room.has(sides[1])
				var style := exterior if outside else String(room.walls)
				# Interior walls between two styled rooms: the room listed first wins.
				if not walls.has(edge) or outside:
					walls[edge] = style

	func shared_edges(a: String, b: String) -> Array[String]:
		var result: Array[String] = []
		var rect: Rect2i = rooms[a].rect
		for edge in PlanGrid.rect_perimeter(rect.position, rect.end):
			var sides := PlanGrid.edge_cells(edge)
			var other: Vector2i = sides[1] if cell_room.get(sides[0], "") == a else sides[0]
			var other_name := String(cell_room.get(other, "outside"))
			if other_name == b:
				result.append(edge)
		result.sort_custom(func(x: String, y: String) -> bool: return PlanGrid.edge_center(x).x + PlanGrid.edge_center(x).z < PlanGrid.edge_center(y).x + PlanGrid.edge_center(y).z)
		return result

	func _doors() -> void:
		for spec in layout.doors:
			var edge := ""
			if spec.has("edge"):
				edge = edge_rel(String(spec.edge))
			else:
				var candidates := shared_edges(String(spec.a), String(spec.b))
				if candidates.is_empty():
					push_warning("Template door has no shared wall: %s / %s" % [spec.a, spec.b])
					continue
				var pick := int(spec.get("at", candidates.size() / 2))
				edge = candidates[clampi(pick, 0, candidates.size() - 1)]
			# Doors swing into the first-named room.
			var sides := PlanGrid.edge_cells(edge)
			var swing := 1.0 if cell_room.get(sides[1], "") == String(spec.a) else -1.0
			doors[edge] = {"style": String(spec.get("style", "door")), "swing": swing, "a": spec.a, "b": spec.b}
			if String(spec.b) == "outside":
				entrances.append(edge)
		for edge in layout.get("storefront", []):
			doors_or_window(edge_rel(String(edge)), "storefront")

	func doors_or_window(edge: String, style: String) -> void:
		if doors.has(edge) or not walls.has(edge):
			return
		_add("window", PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge), {"edge": edge, "style": style})
		doors[edge] = {"style": "window", "swing": 1.0, "window": true}

	func _windows() -> void:
		for name in rooms:
			var room: Dictionary = rooms[name]
			var rule := String(room.windows)
			if rule == "none":
				continue
			var rect: Rect2i = room.rect
			var exterior: Array[String] = []
			for edge in PlanGrid.rect_perimeter(rect.position, rect.end):
				var sides := PlanGrid.edge_cells(edge)
				if not cell_room.has(sides[0]) or not cell_room.has(sides[1]):
					exterior.append(edge)
			# Group by facade line so the rhythm restarts on each side.
			var lines: Dictionary = {}
			for edge in exterior:
				var parsed := PlanGrid.parse_edge(edge)
				var key := "%s:%d" % [parsed.axis, parsed.j if parsed.axis == "x" else parsed.i]
				if not lines.has(key): lines[key] = []
				lines[key].append(edge)
			for key in lines:
				var edges: Array = lines[key]
				edges.sort_custom(func(x: String, y: String) -> bool: return PlanGrid.parse_edge(x).i + PlanGrid.parse_edge(x).j < PlanGrid.parse_edge(y).i + PlanGrid.parse_edge(y).j)
				for n in range(edges.size()):
					var edge := String(edges[n])
					if doors.has(edge): continue
					var place := false
					match rule:
						"all": place = edges.size() <= 2 or (n > 0 and n < edges.size() - 1) or edges.size() == 3
						"alternate": place = n % 2 == 1 or edges.size() == 1
						"ends": place = edges.size() <= 2
					if place:
						var style := "window"
						if String(room.type) in ["gym", "library"] : style = "tall_window"
						_add("window", PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge), {"edge": edge, "style": style})
						doors[edge] = {"style": style, "swing": 1.0, "window": true}

	func _site() -> void:
		for area in layout.get("paving", []):
			_surface(rect_of(area), "paving")
		for area in layout.get("asphalt", []):
			_surface(rect_of(area), "asphalt")
		if layout.has("pad"):
			_surface(rect_of(layout.pad.rect), "concrete")
		for lot in layout.get("parking", []):
			var start := cell(int(lot.cell[0]), int(lot.cell[1]))
			var facing := String(lot.get("facing", "north"))
			for n in range(int(lot.count)):
				var position: Vector3
				var rotation := 0.0
				if facing == "north":
					# Stalls one tile wide and two deep, nose to the north.
					position = PlanGrid.cell_center(start + Vector2i(n, 0)) + Vector3(0, 0, PlanGrid.TILE * 0.5)
				else:
					position = PlanGrid.cell_center(start + Vector2i(0, n)) + Vector3(PlanGrid.TILE * 0.5, 0, 0)
					rotation = PI * 0.5
				_add("parking", position, rotation, {})
		for tree in layout.get("trees", []):
			var c := cell(int(tree[1]), int(tree[2]))
			_add("tree", PlanGrid.cell_center(c), float(hash(c) % 4) * PI * 0.5, {"variant": String(tree[0])})
		for shrub in layout.get("shrubs", []):
			var c := cell(int(shrub[0]), int(shrub[1]))
			_add("shrub", PlanGrid.cell_center(c), 0.0, {})

	func _surface(rect: Rect2i, finish: String) -> void:
		for i in range(rect.position.x, rect.end.x):
			for j in range(rect.position.y, rect.end.y):
				var c := Vector2i(i, j)
				if cell_room.has(c): continue
				_add("floor", PlanGrid.cell_center(c), 0.0, {"cell": [c.x, c.y], "finish": finish})

	func spawn() -> Array:
		if entrances.is_empty():
			return [0.0, 1.0, 2.5]
		var edge := entrances[0]
		var center := PlanGrid.edge_center(edge)
		var sides := PlanGrid.edge_cells(edge)
		var outside: Vector2i = sides[0] if not cell_room.has(sides[0]) else sides[1]
		var point := PlanGrid.cell_center(outside)
		point = center.lerp(point, 0.9)
		return [point.x, 1.2, point.z]

	func room_rect(name: String) -> Rect2i:
		return rooms.get(name, {}).get("rect", Rect2i())
