extends RefCounted

# Best-effort conversion of version-1 saves (2 m stud-row wall modules and
# 4 x 4 floor plates) onto the version-2 PlanGrid (2.5 m edges and cells).
# Equipment, ducts, landscaping and bindings keep their ids and positions.

static func migrate(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	result.version = 2
	var objects: Array = []
	var walls: Dictionary = {}
	var openings: Dictionary = {}
	var cells: Dictionary = {}
	for item in data.get("objects", []):
		var kind := String(item.get("kind", ""))
		var position: Array = item.transform.position
		var rotation := float(item.transform.get("rotation_y", 0.0))
		match kind:
			"floor":
				var cell := PlanGrid.cell_at(Vector3(float(position[0]), 0, float(position[2])))
				cells[PlanGrid.cell_key(cell)] = cell
			"wall_run", "wall", "door", "window":
				var segments: Array = item.properties.get("segments", [position])
				var hosted: Dictionary = item.properties.get("openings", {})
				for index in range(segments.size()):
					var center := Vector3(float(segments[index][0]), 0, float(segments[index][2]))
					var edge := _edge_for_module(center, rotation)
					walls[edge] = true
					var opening := String(hosted.get(str(index), kind if kind in ["door", "window"] else ""))
					if not opening.is_empty():
						openings[edge] = opening
			"terrain":
				pass
			"tstat":
				var host := PlanGrid.nearest_edge(Vector3(float(position[0]), 0, float(position[2])))
				var copy: Dictionary = item.duplicate(true)
				copy.properties.edge = host
				copy.properties.erase("wall_id")
				copy.properties.erase("module")
				objects.append(copy)
			_:
				objects.append(item.duplicate(true))
	var serial := int(data.get("next_id", 1))
	for key in cells:
		var cell: Vector2i = cells[key]
		var center := PlanGrid.cell_center(cell)
		objects.append(_item("floor-m%05d" % serial, "floor", center, 0.0, {"cell": [cell.x, cell.y], "finish": "tile_gray"}))
		serial += 1
	for edge in walls:
		var center := PlanGrid.edge_center(edge)
		objects.append(_item("wall-m%05d" % serial, "wall", center, PlanGrid.edge_rotation(edge), {"edge": edge, "style": "tan"}))
		serial += 1
		if openings.has(edge):
			var kind := String(openings[edge])
			objects.append(_item("%s-m%05d" % [kind, serial], kind, center, PlanGrid.edge_rotation(edge), {"edge": edge, "style": kind}))
			serial += 1
	result.objects = objects
	result.next_id = serial + 1
	# The simulation state format changed; the model starts fresh on load.
	result.demo_checkpoint = {}
	var site: Dictionary = result.get("site", {})
	site.erase("camera_distance")
	site.open_doors = {}
	site.room_names = {}
	site.room_types = {}
	result.site = site
	return result

static func _edge_for_module(center: Vector3, rotation_y: float) -> String:
	if absf(cos(rotation_y)) >= absf(sin(rotation_y)):
		return PlanGrid.edge_key("x", floori(center.x / PlanGrid.TILE), roundi(center.z / PlanGrid.TILE))
	return PlanGrid.edge_key("z", roundi(center.x / PlanGrid.TILE), floori(center.z / PlanGrid.TILE))

static func _item(id: String, kind: String, position: Vector3, rotation_y: float, properties: Dictionary) -> Dictionary:
	return {"id": id, "kind": kind, "floor_id": "floor-1", "transform": {"position": [position.x, position.y, position.z], "rotation_y": rotation_y}, "properties": properties}
