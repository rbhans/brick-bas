class_name BuildingIndex
extends RefCounted

# Derived, read-only view of the architecture on the PlanGrid. Rebuilt after
# every edit (cheap: dictionaries keyed by edge / cell).
#
# Rooms are found Sims-style: flood fill across cells, blocked by wall edges
# (doors and windows sit in walls, so they separate rooms). A region that
# reaches the search border is outdoors; every other region is a room.

var walls: Dictionary = {}      # edge key -> wall item
var openings: Dictionary = {}   # edge key -> door/window item
var floors: Dictionary = {}     # cell key -> floor item
var rooms: Array[Dictionary] = []
var cell_room: Dictionary = {}  # cell key -> room index
var region_min := Vector2i.ZERO
var region_max := Vector2i.ZERO

func rebuild(objects: Array, site: Dictionary = {}) -> void:
	walls.clear()
	openings.clear()
	floors.clear()
	rooms.clear()
	cell_room.clear()
	var cells_of_interest: Array[Vector2i] = []
	for item in objects:
		match String(item.kind):
			"wall":
				var edge := String(item.properties.get("edge", ""))
				if PlanGrid.is_edge_key(edge):
					walls[edge] = item
					cells_of_interest.append_array(PlanGrid.edge_cells(edge))
			"door", "window":
				var edge := String(item.properties.get("edge", ""))
				if PlanGrid.is_edge_key(edge):
					openings[edge] = item
			"floor":
				var cell := cell_of(item)
				floors[PlanGrid.cell_key(cell)] = item
				cells_of_interest.append(cell)
	if cells_of_interest.is_empty():
		return
	region_min = cells_of_interest[0]
	region_max = cells_of_interest[0]
	for cell in cells_of_interest:
		region_min = Vector2i(mini(region_min.x, cell.x), mini(region_min.y, cell.y))
		region_max = Vector2i(maxi(region_max.x, cell.x), maxi(region_max.y, cell.y))
	region_min -= Vector2i.ONE
	region_max += Vector2i.ONE
	_find_rooms(site.get("room_names", {}), site.get("room_types", {}))

static func cell_of(item: Dictionary) -> Vector2i:
	var value: Variant = item.properties.get("cell", null)
	if value is Array and value.size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	var position: Array = item.transform.position
	return PlanGrid.cell_at(Vector3(float(position[0]), 0, float(position[2])))

func has_wall(edge: String) -> bool:
	return walls.has(edge)

func opening(edge: String) -> Dictionary:
	return openings.get(edge, {})

func has_floor(cell: Vector2i) -> bool:
	return floors.has(PlanGrid.cell_key(cell))

# Which axes have walls touching a vertex. Drives interlocked corner bricks.
func vertex_axes(vertex: Vector2i) -> Dictionary:
	var along_x := walls.has(PlanGrid.edge_key("x", vertex.x, vertex.y)) or walls.has(PlanGrid.edge_key("x", vertex.x - 1, vertex.y))
	var along_z := walls.has(PlanGrid.edge_key("z", vertex.x, vertex.y)) or walls.has(PlanGrid.edge_key("z", vertex.x, vertex.y - 1))
	return {"x": along_x, "z": along_z}

func room_at_cell(cell: Vector2i) -> Dictionary:
	var index := int(cell_room.get(PlanGrid.cell_key(cell), -1))
	return rooms[index] if index >= 0 else {}

func room_at(point: Vector3) -> Dictionary:
	return room_at_cell(PlanGrid.cell_at(point))

func room_by_id(id: String) -> Dictionary:
	for room in rooms:
		if String(room.id) == id:
			return room
	return {}

func is_indoors(point: Vector3) -> bool:
	return not room_at(point).is_empty()

# Rooms on either side of an edge: [negative side, positive side] ids ("" = outside).
func edge_rooms(edge: String) -> Array[String]:
	var result: Array[String] = []
	for cell in PlanGrid.edge_cells(edge):
		result.append(String(room_at_cell(cell).get("id", "")))
	return result

func _find_rooms(names: Dictionary, types: Dictionary) -> void:
	var visited: Dictionary = {}
	var room_serial := 1
	for j in range(region_min.y, region_max.y + 1):
		for i in range(region_min.x, region_max.x + 1):
			var start := Vector2i(i, j)
			var start_key := PlanGrid.cell_key(start)
			if visited.has(start_key):
				continue
			var region: Array[Vector2i] = []
			var outdoor := false
			var frontier: Array[Vector2i] = [start]
			visited[start_key] = true
			while not frontier.is_empty():
				var cell: Vector2i = frontier.pop_back()
				region.append(cell)
				if cell.x <= region_min.x or cell.y <= region_min.y or cell.x >= region_max.x or cell.y >= region_max.y:
					outdoor = true
				for step in [[Vector2i(1, 0), PlanGrid.edge_key("z", cell.x + 1, cell.y)], [Vector2i(-1, 0), PlanGrid.edge_key("z", cell.x, cell.y)], [Vector2i(0, 1), PlanGrid.edge_key("x", cell.x, cell.y + 1)], [Vector2i(0, -1), PlanGrid.edge_key("x", cell.x, cell.y)]]:
					var next: Vector2i = cell + step[0]
					if next.x < region_min.x or next.y < region_min.y or next.x > region_max.x or next.y > region_max.y:
						continue
					if walls.has(String(step[1])):
						continue
					var next_key := PlanGrid.cell_key(next)
					if visited.has(next_key):
						continue
					visited[next_key] = true
					frontier.append(next)
			if outdoor:
				continue
			region.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
			var room := {"id": "room-%d_%d" % [region[0].x, region[0].y], "cells": region, "index": rooms.size()}
			var label := ""
			var type := ""
			for cell in region:
				var key := PlanGrid.cell_key(cell)
				if label.is_empty() and names.has(key): label = String(names[key])
				if type.is_empty() and types.has(key): type = String(types[key])
				cell_room[key] = rooms.size()
			room.label = label if not label.is_empty() else "Room %d" % room_serial
			room.type = type if not type.is_empty() else "room"
			room_serial += 1
			rooms.append(room)
	for room in rooms:
		_describe(room)

func _describe(room: Dictionary) -> void:
	var cells: Array = room.cells
	var center := Vector3.ZERO
	var floored := 0
	for cell in cells:
		center += PlanGrid.cell_center(cell)
		if has_floor(cell): floored += 1
	room.center = center / float(cells.size())
	room.area_m2 = float(cells.size()) * PlanGrid.TILE * PlanGrid.TILE
	room.floored = floored
	var exterior: Array[String] = []
	var neighbours: Dictionary = {}
	var windows: Array[Dictionary] = []
	var doors: Array[Dictionary] = []
	var seen: Dictionary = {}
	for cell in cells:
		for edge in PlanGrid.cell_edges(cell):
			if seen.has(edge) or not walls.has(edge):
				continue
			seen[edge] = true
			var sides := PlanGrid.edge_cells(edge)
			var inside_positive: bool = sides[1] == cell
			var other: Vector2i = sides[0] if inside_positive else sides[1]
			var other_room := room_at_cell(other)
			var outward := PlanGrid.edge_normal(edge) * (-1.0 if inside_positive else 1.0)
			var other_id := String(other_room.get("id", ""))
			if other_id.is_empty():
				exterior.append(edge)
			else:
				neighbours[other_id] = int(neighbours.get(other_id, 0)) + 1
			var hosted: Dictionary = openings.get(edge, {})
			if hosted.is_empty():
				continue
			if hosted.kind == "window":
				windows.append({"edge": edge, "outward": outward, "exterior": other_id.is_empty(), "style": String(hosted.properties.get("style", "window"))})
			else:
				doors.append({"edge": edge, "to": other_id if not other_id.is_empty() else "outside", "id": String(hosted.id)})
	room.exterior_edges = exterior
	room.neighbours = neighbours
	room.windows = windows
	room.doors = doors
