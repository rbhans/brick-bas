class_name DuctRouter
extends RefCounted

# Orthogonal duct routing through the ceiling space. Each run leaves its
# socket along the socket's normal, rises (or drops) to a routing plane above
# the walls, travels across that plane around equipment and other ducts, and
# drops back into the far socket. Simple L and Z shapes are tried first on
# each plane; a grid A* search (with a turn penalty, for tidy runs) handles
# everything else. Every candidate is re-checked by the full clearance test.

const CELL := 0.5
const PLANES := [4.6, 5.5, 6.4]
const TURN_COST := 3.0
const SEARCH_MARGIN := 14.0
const MAX_EXPANSIONS := 24000

static func route(start: Dictionary, finish: Dictionary, objects: Array, exclude_id: String, check: Callable) -> Dictionary:
	var ends := [start.position as Vector3, finish.position as Vector3]
	var start_lead: Vector3 = start.position + start.normal * DuctConnections.LEAD
	var end_lead: Vector3 = finish.position + finish.normal * DuctConnections.LEAD
	var failures: Array[String] = []
	# Straight shot between facing sockets.
	if is_equal_approx(ends[0].y, ends[1].y) and (is_equal_approx(ends[0].x, ends[1].x) or is_equal_approx(ends[0].z, ends[1].z)):
		var result := _try([ends[0], ends[1]], check, failures)
		if not result.is_empty(): return result
	var planes: Array = []
	for height in [start_lead.y, end_lead.y]:
		if height >= DuctConnections.WALL_TOP + 0.55 and not planes.any(func(p: float) -> bool: return absf(p - height) < 0.01):
			planes.append(height)
	for height in PLANES:
		if not planes.any(func(p: float) -> bool: return absf(p - height) < 0.3):
			planes.append(height)
	planes.sort()
	for height in planes:
		var a := Vector3(start_lead.x, height, start_lead.z)
		var b := Vector3(end_lead.x, height, end_lead.z)
		var shapes: Array = [
			[a, Vector3(b.x, height, a.z), b],
			[a, Vector3(a.x, height, b.z), b],
		]
		var mid_x := snappedf((a.x + b.x) * 0.5, CELL)
		var mid_z := snappedf((a.z + b.z) * 0.5, CELL)
		shapes.append([a, Vector3(mid_x, height, a.z), Vector3(mid_x, height, b.z), b])
		shapes.append([a, Vector3(a.x, height, mid_z), Vector3(b.x, height, mid_z), b])
		for shape in shapes:
			var result := _try(_assemble(ends, start_lead, end_lead, shape), check, failures)
			if not result.is_empty(): return result
		var searched := _search(a, b, height, objects, exclude_id, [String(start.owner), String(finish.owner)])
		if not searched.is_empty():
			var result := _try(_assemble(ends, start_lead, end_lead, searched), check, failures)
			if not result.is_empty(): return result
	return {"ok": false, "message": "No clear route: " + (failures[0] if not failures.is_empty() else "blocked")}

static func _assemble(ends: Array, start_lead: Vector3, end_lead: Vector3, middle: Array) -> Array:
	var points: Array = [ends[0], start_lead]
	points.append_array(middle)
	points.append_array([end_lead, ends[1]])
	var clean: Array = []
	for point in points:
		var p: Vector3 = point
		if not clean.is_empty() and p.distance_to(clean[-1]) < 0.01:
			continue
		if clean.size() >= 2:
			var before: Vector3 = (clean[-1] - clean[-2]).normalized()
			var after: Vector3 = (p - clean[-1]).normalized()
			if before.dot(after) > 0.9999:
				clean.remove_at(clean.size() - 1)
		clean.append(p)
	return clean

static func _try(points: Array, check: Callable, failures: Array[String]) -> Dictionary:
	for index in range(points.size() - 1):
		if (points[index] as Vector3).distance_to(points[index + 1]) < 0.25:
			failures.append("Duct sections need at least 0.25 m.")
			return {}
	var error: String = check.call(points)
	if error.is_empty():
		return {"ok": true, "points": points}
	failures.append(error)
	return {}

# Grid A* across one routing plane. Returns plane points (corners only).
static func _search(a: Vector3, b: Vector3, height: float, objects: Array, exclude_id: String, owners: Array) -> Array:
	var origin := Vector2(a.x, a.z)
	var goal := _cell(Vector2(b.x, b.z), origin)
	var start := Vector2i.ZERO
	var low := Vector2i(mini(start.x, goal.x), mini(start.y, goal.y)) - Vector2i.ONE * int(SEARCH_MARGIN / CELL)
	var high := Vector2i(maxi(start.x, goal.x), maxi(start.y, goal.y)) + Vector2i.ONE * int(SEARCH_MARGIN / CELL)
	var blocked := _obstacles(height, objects, exclude_id, origin, low, high, owners)
	blocked.erase(start)
	blocked.erase(goal)
	var width := high.y - low.y + 1
	var key := func(cell: Vector2i, heading: int) -> int: return (((cell.x - low.x) * width) + (cell.y - low.y)) * 5 + heading + 1
	var heap := Heap.new()
	var cost: Dictionary = {}
	var parent: Dictionary = {}
	var cell_of: Dictionary = {}
	var start_key: int = key.call(start, -1)
	cost[start_key] = 0.0
	cell_of[start_key] = [start, -1]
	heap.push(0.0, start_key)
	var directions := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var expansions := 0
	var found := -1
	while not heap.is_empty() and expansions < MAX_EXPANSIONS:
		var current: int = heap.pop()
		var state: Array = cell_of[current]
		var cell: Vector2i = state[0]
		var heading: int = state[1]
		expansions += 1
		if cell == goal:
			found = current
			break
		var base := float(cost[current])
		for direction_index in range(4):
			var next: Vector2i = cell + directions[direction_index]
			if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y or blocked.has(next):
				continue
			var total := base + 1.0 + (TURN_COST if heading >= 0 and heading != direction_index else 0.0)
			var next_key: int = key.call(next, direction_index)
			if total < float(cost.get(next_key, INF)):
				cost[next_key] = total
				parent[next_key] = current
				cell_of[next_key] = [next, direction_index]
				heap.push(total + absf(next.x - goal.x) + absf(next.y - goal.y), next_key)
	if found < 0:
		return []
	var cells: Array = []
	var cursor := found
	while true:
		cells.push_front(cell_of[cursor][0])
		if not parent.has(cursor): break
		cursor = parent[cursor]
	var corners: Array = []
	for index in range(cells.size()):
		var is_corner := index == 0 or index == cells.size() - 1
		if not is_corner:
			var before: Vector2i = cells[index] - cells[index - 1]
			var after: Vector2i = cells[index + 1] - cells[index]
			is_corner = before != after
		if is_corner:
			var point := origin + Vector2(cells[index]) * CELL
			corners.append(Vector3(point.x, height, point.y))
	# Finish exactly on the far lead (grids are anchored at the near one).
	var last: Vector3 = corners[-1]
	if Vector2(last.x - b.x, last.z - b.z).length() > 0.01:
		if absf(last.x - b.x) > 0.01: corners.append(Vector3(b.x, height, last.z))
		corners.append(b)
	return corners

static func _cell(point: Vector2, origin: Vector2) -> Vector2i:
	return Vector2i(roundi((point.x - origin.x) / CELL), roundi((point.y - origin.y) / CELL))

static func _mark_rect(blocked: Dictionary, rect: Rect2, origin: Vector2, low: Vector2i, high: Vector2i) -> void:
	var a := _cell(rect.position, origin)
	var b := _cell(rect.end, origin)
	for x in range(maxi(mini(a.x, b.x), low.x), mini(maxi(a.x, b.x), high.x) + 1):
		for z in range(maxi(mini(a.y, b.y), low.y), mini(maxi(a.y, b.y), high.y) + 1):
			blocked[Vector2i(x, z)] = true

static func _obstacles(height: float, objects: Array, exclude_id: String, origin: Vector2, low: Vector2i, high: Vector2i, owners: Array = []) -> Dictionary:
	var blocked: Dictionary = {}
	var reach := DuctGeometry.OUTER + 0.15
	var lookup: Dictionary = {}
	for item in objects:
		lookup[String(item.id)] = item
	for item in objects:
		var kind := String(item.kind)
		if kind in ["ahu", "vav", "tee", "cross", "diffuser"]:
			var values: Array = item.transform.position
			var base := Vector3(float(values[0]), float(values[1]), float(values[2]))
			var size := DuctConnections.equipment_size(item)
			# The run's own units dock at their collars; block only the casing.
			if String(item.id) in owners and kind in ["ahu", "vav"]:
				size.x = maxf(0.5, size.x - 1.0)
			var bottom := base.y
			if height < bottom - reach or height > bottom + size.y + reach:
				continue
			var turned := size if absf(sin(float(item.transform.get("rotation_y", 0.0)))) < 0.7 else Vector3(size.z, size.y, size.x)
			var rect := Rect2(Vector2(base.x, base.z) - Vector2(turned.x, turned.z) * 0.5, Vector2(turned.x, turned.z)).grow(reach)
			_mark_rect(blocked, rect, origin, low, high)
		elif kind == "duct" and String(item.id) != exclude_id and bool(item.properties.get("enabled", true)):
			var path := DuctConnections.path(item.properties, objects, lookup)
			for index in range(path.size() - 1):
				var p: Vector3 = path[index]
				var q: Vector3 = path[index + 1]
				if (height < minf(p.y, q.y) - 1.15) or (height > maxf(p.y, q.y) + 1.15):
					continue
				var rect := Rect2(Vector2(p.x, p.z), Vector2.ZERO).expand(Vector2(q.x, q.z)).grow(DuctGeometry.OUTER * 2.0 + 0.15)
				_mark_rect(blocked, rect, origin, low, high)
		elif kind == "wall" and height < DuctConnections.WALL_TOP + DuctGeometry.OUTER + 0.1:
			var edge := String(item.properties.get("edge", ""))
			if edge.is_empty(): continue
			var ends := PlanGrid.edge_vertices(edge)
			var a := PlanGrid.vertex_position(ends[0])
			var b := PlanGrid.vertex_position(ends[1])
			_mark_rect(blocked, Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(0.3 + DuctGeometry.OUTER), origin, low, high)
	return blocked


# Minimal binary min-heap of (priority, value) pairs.
class Heap:
	var priorities: PackedFloat64Array = PackedFloat64Array()
	var values: PackedInt64Array = PackedInt64Array()

	func is_empty() -> bool:
		return values.is_empty()

	func push(priority: float, value: int) -> void:
		priorities.append(priority)
		values.append(value)
		var index := values.size() - 1
		while index > 0:
			var up := (index - 1) >> 1
			if priorities[up] <= priorities[index]: break
			_swap(index, up)
			index = up

	func pop() -> int:
		var top := values[0]
		var last := values.size() - 1
		_swap(0, last)
		priorities.resize(last)
		values.resize(last)
		var index := 0
		while true:
			var left := index * 2 + 1
			var right := left + 1
			var smallest := index
			if left < last and priorities[left] < priorities[smallest]: smallest = left
			if right < last and priorities[right] < priorities[smallest]: smallest = right
			if smallest == index: break
			_swap(index, smallest)
			index = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var p := priorities[a]
		priorities[a] = priorities[b]
		priorities[b] = p
		var v := values[a]
		values[a] = values[b]
		values[b] = v
