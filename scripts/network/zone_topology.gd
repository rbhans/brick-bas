class_name ZoneTopology
extends RefCounted

# Turns what the player built into the simulation's topology: every closed
# room becomes a thermal zone (area, exterior wall, windows by orientation,
# neighbours), and each VAV serves the room its diffusers blow into.

const WINDOW_AREA := 2.0 * 1.8   # 1 x 4 x 3 window
const TALL_WINDOW_AREA := 2.0 * 3.6

static func build(index: BuildingIndex, objects: Array, network: Dictionary) -> Dictionary:
	var zones: Dictionary = {}
	for room in index.rooms:
		var windows := {"N": 0.0, "E": 0.0, "S": 0.0, "W": 0.0}
		var glazing := 0.0
		for window in room.windows:
			if not bool(window.exterior):
				continue
			var tall := String(window.style) in ["tall_window", "storefront"]
			var area := TALL_WINDOW_AREA if tall else WINDOW_AREA
			windows[facing(window.outward)] += area
			glazing += area
		var exterior_doors := 0
		for door in room.doors:
			if String(door.to) == "outside": exterior_doors += 1
		var neighbours: Dictionary = {}
		for other in room.neighbours:
			neighbours[other] = float(room.neighbours[other]) * PlanGrid.TILE * PlanGrid.WALL_HEIGHT
		zones[String(room.id)] = {
			"label": String(room.label), "type": String(room.type), "area_m2": float(room.area_m2),
			"exterior_wall_m2": maxf(0.0, room.exterior_edges.size() * PlanGrid.TILE * PlanGrid.WALL_HEIGHT - glazing),
			"roof_m2": float(room.area_m2), "window_m2": windows, "neighbours": neighbours, "exterior_doors": exterior_doors,
		}
	var terminals: Dictionary = {}
	var positions: Dictionary = {}
	for item in objects:
		positions[String(item.id)] = item
	for vav_id in network.get("terminals", {}):
		var terminal: Dictionary = network.terminals[vav_id].duplicate(true)
		terminal.zone_id = _served_zone(index, positions, vav_id, terminal.get("diffusers", []))
		terminals[vav_id] = terminal
	return {"zones": zones, "units": network.get("units", {}), "terminals": terminals, "limits": network.get("limits", {}), "routes": network.get("routes", {})}

static func facing(outward: Vector3) -> String:
	if absf(outward.x) > absf(outward.z):
		return "E" if outward.x > 0.0 else "W"
	return "S" if outward.z > 0.0 else "N"

static func _served_zone(index: BuildingIndex, objects: Dictionary, vav_id: String, diffusers: Array) -> String:
	var votes: Dictionary = {}
	for diffuser_id in diffusers:
		var item: Dictionary = objects.get(diffuser_id, {})
		if item.is_empty(): continue
		var room := index.room_at(_position(item))
		if not room.is_empty():
			votes[room.id] = int(votes.get(room.id, 0)) + 1
	var best := ""
	for id in votes:
		if best.is_empty() or int(votes[id]) > int(votes[best]) or (int(votes[id]) == int(votes[best]) and String(id) < best):
			best = String(id)
	if best.is_empty() and objects.has(vav_id):
		best = String(index.room_at(_position(objects[vav_id])).get("id", ""))
	return best

static func _position(item: Dictionary) -> Vector3:
	var values: Array = item.transform.position
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
