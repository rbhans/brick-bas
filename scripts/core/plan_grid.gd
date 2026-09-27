class_name PlanGrid
extends RefCounted

# Sims-style plan lattice built from native LDraw studs.
#
#   * One stud is 0.5 m. Stud centres sit on integer multiples of 0.5 m.
#   * One plan tile is 5 studs (2.5 m). Grid lines pass through stud centres,
#     so a 1-stud wall laid on a line is stud-aligned in both axes and two
#     perpendicular walls share exactly one corner stud.
#   * Every edge therefore has four interior studs: a 1 x 4 door or window
#     frame fits exactly between the corner posts.
#
# Vertices are integer pairs (i, j) at world (i * TILE, j * TILE). Cells are
# the squares between vertices. Edges are keyed "x:i:j" (from vertex (i, j) to
# (i + 1, j)) or "z:i:j" (from (i, j) to (i, j + 1)).

const STUD := 0.5
const PLATE := 0.2
const BRICK := 0.6
const TILE_STUDS := 5
const TILE := STUD * TILE_STUDS
const WALL_COURSES := 6
const WALL_HEIGHT := BRICK * WALL_COURSES
const FLOOR_TOP := PLATE
const EPSILON := 0.0001

static func vertex_position(vertex: Vector2i) -> Vector3:
	return Vector3(vertex.x * TILE, 0.0, vertex.y * TILE)

static func nearest_vertex(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / TILE), roundi(point.z / TILE))

static func cell_at(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / TILE), floori(point.z / TILE))

static func cell_center(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * TILE, 0.0, (cell.y + 0.5) * TILE)

static func cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]

static func parse_cell(key: String) -> Vector2i:
	var parts := key.split(":")
	return Vector2i(int(parts[0]), int(parts[1]))

# --- Edges -----------------------------------------------------------------

static func edge_key(axis: String, i: int, j: int) -> String:
	return "%s:%d:%d" % [axis, i, j]

static func parse_edge(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 3 or parts[0] not in ["x", "z"]:
		return {}
	return {"axis": parts[0], "i": int(parts[1]), "j": int(parts[2])}

static func is_edge_key(key: String) -> bool:
	return not parse_edge(key).is_empty()

static func edge_vertices(key: String) -> Array[Vector2i]:
	var edge := parse_edge(key)
	var start := Vector2i(edge.i, edge.j)
	var finish := start + (Vector2i(1, 0) if edge.axis == "x" else Vector2i(0, 1))
	return [start, finish]

static func edge_center(key: String) -> Vector3:
	var ends := edge_vertices(key)
	return (vertex_position(ends[0]) + vertex_position(ends[1])) * 0.5

static func edge_rotation(key: String) -> float:
	# Local +X of a wall piece runs along the edge.
	return 0.0 if key.begins_with("x") else PI * 0.5

static func edge_normal(key: String) -> Vector3:
	return Vector3(0, 0, 1) if key.begins_with("x") else Vector3(1, 0, 0)

# The two cells an edge separates: [negative side, positive side].
static func edge_cells(key: String) -> Array[Vector2i]:
	var edge := parse_edge(key)
	if edge.axis == "x":
		return [Vector2i(edge.i, edge.j - 1), Vector2i(edge.i, edge.j)]
	return [Vector2i(edge.i - 1, edge.j), Vector2i(edge.i, edge.j)]

static func cell_edges(cell: Vector2i) -> Array[String]:
	return [
		edge_key("x", cell.x, cell.y), edge_key("x", cell.x, cell.y + 1),
		edge_key("z", cell.x, cell.y), edge_key("z", cell.x + 1, cell.y),
	]

# Every edge on the straight line between two vertices. The caller has already
# constrained the vertices to one axis.
static func edges_between(a: Vector2i, b: Vector2i) -> Array[String]:
	var result: Array[String] = []
	if a.y == b.y and a.x != b.x:
		for i in range(mini(a.x, b.x), maxi(a.x, b.x)):
			result.append(edge_key("x", i, a.y))
	elif a.x == b.x and a.y != b.y:
		for j in range(mini(a.y, b.y), maxi(a.y, b.y)):
			result.append(edge_key("z", a.x, j))
	return result

static func rect_perimeter(a: Vector2i, b: Vector2i) -> Array[String]:
	var low := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var high := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	var result: Array[String] = []
	if low.x == high.x or low.y == high.y:
		return edges_between(low, high)
	result.append_array(edges_between(low, Vector2i(high.x, low.y)))
	result.append_array(edges_between(Vector2i(low.x, high.y), high))
	result.append_array(edges_between(low, Vector2i(low.x, high.y)))
	result.append_array(edges_between(Vector2i(high.x, low.y), high))
	return result

static func rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(mini(a.x, b.x), maxi(a.x, b.x)):
		for j in range(mini(a.y, b.y), maxi(a.y, b.y)):
			result.append(Vector2i(i, j))
	return result

# Distance from a ground point to an edge's centre line, and the parameter
# along it (0..1). Used to aim openings and thermostats at walls.
static func edge_distance(key: String, point: Vector3) -> Dictionary:
	var ends := edge_vertices(key)
	var a := vertex_position(ends[0])
	var b := vertex_position(ends[1])
	var ab := b - a
	var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := a + ab * t
	return {"distance": Vector2(point.x - closest.x, point.z - closest.z).length(), "t": t, "point": closest}

static func nearest_edge(point: Vector3) -> String:
	var cell := cell_at(point)
	var best := ""
	var best_distance := INF
	for key in cell_edges(cell):
		var result := edge_distance(key, point)
		if float(result.distance) < best_distance:
			best_distance = result.distance
			best = key
	return best

# --- Studs -----------------------------------------------------------------

static func snap_stud(value: float) -> float:
	return snappedf(value, STUD)

# Centre of a part with an odd/even stud footprint so its studs align with the
# lattice. Odd widths centre on a stud, even widths between studs.
static func snap_part_center(value: float, footprint_studs: int) -> float:
	if footprint_studs % 2 == 1:
		return snappedf(value, STUD)
	return snappedf(value - STUD * 0.5, STUD) + STUD * 0.5

static func stud_cell(value: float) -> int:
	return roundi(value / STUD)

static func footprint_studs(center: Vector3, studs_x: int, studs_z: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x_index in range(studs_x):
		var x := center.x + (float(x_index) - float(studs_x - 1) * 0.5) * STUD
		for z_index in range(studs_z):
			var z := center.z + (float(z_index) - float(studs_z - 1) * 0.5) * STUD
			result.append(Vector2i(stud_cell(x), stud_cell(z)))
	return result

static func rotated_footprint(size: Vector2i, rotation_y: float) -> Vector2i:
	return Vector2i(size.y, size.x) if absf(sin(rotation_y)) > 0.7 else size

static func quarter_turns(rotation_y: float) -> int:
	return posmod(roundi(rotation_y / (PI * 0.5)), 4)
