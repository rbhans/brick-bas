class_name Placement
extends RefCounted

# Where things may go. A stud-occupancy map (walls occupy their grid-line
# studs, furniture its footprint) answers "is this spot free?", and snapping
# rules put floor pieces on the stud lattice and wall pieces flush on a wall.

const FURNITURE_SCRIPT := "res://scripts/build/furniture_catalog.gd"
const EQUIPMENT_SCRIPT := "res://scripts/build/equipment_models.gd"

const THERMOSTAT_HEIGHT := 1.55

const PLANTS := {
	"tree": {"label": "Tree", "footprint": Vector2i(2, 2), "mount": "floor", "outdoor": true},
	"shrub": {"label": "Shrub", "footprint": Vector2i(4, 4), "mount": "floor", "outdoor": true},
	"parking": {"label": "Parking stall", "footprint": Vector2i(5, 10), "mount": "floor", "outdoor": true, "surface": true},
}

var game: Node
var studs: Dictionary = {}      # Vector2i stud -> owner id
var surfaces: Dictionary = {}   # stud -> owner id for flat markings (parking)
var wall_slots: Dictionary = {} # "edge|side|slot" -> owner id

static var _furniture: Script
static var _equipment: Script

func _init(owner: Node) -> void:
	game = owner

static func furniture_catalog() -> Script:
	if _furniture == null and ResourceLoader.exists(FURNITURE_SCRIPT):
		_furniture = load(FURNITURE_SCRIPT)
	return _furniture

const EQUIPMENT_API := ["build_ahu", "build_vav", "build_diffuser", "build_tee", "build_cross", "build_thermostat", "size", "footprint", "port_local", "port_names"]

# The equipment model library is used only when its whole API is present.
static func equipment_models() -> Script:
	if _equipment == null and ResourceLoader.exists(EQUIPMENT_SCRIPT):
		var script := load(EQUIPMENT_SCRIPT) as Script
		var names: Array = script.get_script_method_list().map(func(method: Dictionary) -> String: return String(method.name))
		if EQUIPMENT_API.all(func(name: String) -> bool: return name in names):
			_equipment = script
	return _equipment

static func furniture_items() -> Dictionary:
	var catalog := furniture_catalog()
	return catalog.ITEMS if catalog != null else {}

func spec(kind: String, item_id: String = "") -> Dictionary:
	if kind == "furniture":
		var entry: Dictionary = furniture_items().get(item_id, {})
		return {"label": String(entry.get("label", item_id.capitalize())), "footprint": entry.get("footprint", Vector2i(2, 2)), "mount": String(entry.get("mount", "floor")), "height": float(entry.get("height", 1.0)), "category": String(entry.get("category", "decor"))}
	if PLANTS.has(kind):
		var plant: Dictionary = PLANTS[kind].duplicate()
		if kind == "tree" and not item_id.is_empty():
			plant.label = "%s tree" % item_id.capitalize()
		return plant
	if kind == "tstat":
		return {"label": "Thermostat", "footprint": Vector2i(1, 1), "mount": "wall"}
	var models := equipment_models()
	if models != null and kind in ["ahu", "vav", "diffuser", "tee"]:
		return {"label": kind.to_upper() if kind in ["ahu", "vav"] else kind.capitalize(), "footprint": models.footprint(kind, game.equipment_config(kind)), "mount": "floor" if kind == "ahu" else "ceiling"}
	return {"label": kind.capitalize(), "footprint": Vector2i(2, 2), "mount": "floor"}

func rebuild(objects: Array, index: BuildingIndex) -> void:
	studs.clear()
	surfaces.clear()
	wall_slots.clear()
	for edge in index.walls:
		var ends := PlanGrid.edge_vertices(edge)
		var a := PlanGrid.vertex_position(ends[0])
		var b := PlanGrid.vertex_position(ends[1])
		for slot in range(PlanGrid.TILE_STUDS + 1):
			var point := a.lerp(b, float(slot) / PlanGrid.TILE_STUDS)
			var stud := Vector2i(PlanGrid.stud_cell(point.x), PlanGrid.stud_cell(point.z))
			if not studs.has(stud): studs[stud] = String(index.walls[edge].id)
	for item in objects:
		var kind := String(item.kind)
		if kind not in ["furniture", "tree", "shrub", "parking", "ahu"]:
			if kind == "tstat": _claim_wall(item)
			continue
		var item_spec := spec(kind, String(item.properties.get("item", item.properties.get("variant", ""))))
		if String(item_spec.mount) == "wall":
			_claim_wall(item)
			continue
		var layer := surfaces if bool(item_spec.get("surface", false)) else studs
		var size: Vector2i = item_spec.footprint
		var models := equipment_models()
		if kind == "ahu" and models != null:
			size = models.footprint(kind, item.properties)   # its own bays, not the workbench design
		for stud in footprint_studs(_position(item), size, float(item.transform.get("rotation_y", 0.0))):
			layer[stud] = String(item.id)

func _claim_wall(item: Dictionary) -> void:
	var edge := String(item.properties.get("edge", ""))
	if edge.is_empty():
		return
	var side := int(item.properties.get("side", 1))
	var width: int = spec(String(item.kind), String(item.properties.get("item", ""))).footprint.x
	for key in _wall_slots(edge, side, _position(item), width):
		wall_slots[key] = String(item.id)

# Wall slots are keyed per grid line and face, so pieces wider than one
# section (chalkboards) claim studs across neighbouring sections.
func _wall_slots(edge: String, side: int, position: Vector3, width: int) -> Array[String]:
	var parsed := PlanGrid.parse_edge(edge)
	var line := int(parsed.j) if parsed.axis == "x" else int(parsed.i)
	var along := position.x if parsed.axis == "x" else position.z
	var first := roundi(along / PlanGrid.STUD - float(width - 1) * 0.5)
	var result: Array[String] = []
	for offset in range(width):
		result.append("%s:%d|%d|%d" % [parsed.axis, line, side, first + offset])
	return result

# The straight, opening-free stretch of wall containing `edge`, as the range
# of along-axis coordinates (metres) a hung piece may cover.
func _wall_run(edge: String) -> Vector2:
	var parsed := PlanGrid.parse_edge(edge)
	var axis := String(parsed.axis)
	var step := int(parsed.i) if axis == "x" else int(parsed.j)
	var line := int(parsed.j) if axis == "x" else int(parsed.i)
	var low := step
	var high := step
	while true:
		var next := PlanGrid.edge_key(axis, low - 1, line) if axis == "x" else PlanGrid.edge_key(axis, line, low - 1)
		if not game.index.has_wall(next) or not game.index.openings.get(next, {}).is_empty(): break
		low -= 1
	while true:
		var next := PlanGrid.edge_key(axis, high + 1, line) if axis == "x" else PlanGrid.edge_key(axis, line, high + 1)
		if not game.index.has_wall(next) or not game.index.openings.get(next, {}).is_empty(): break
		high += 1
	return Vector2(low * PlanGrid.TILE + PlanGrid.STUD * 0.5, (high + 1) * PlanGrid.TILE - PlanGrid.STUD * 0.5)

static func footprint_studs(center: Vector3, size: Vector2i, rotation_y: float) -> Array[Vector2i]:
	var turned := PlanGrid.rotated_footprint(size, rotation_y)
	return PlanGrid.footprint_studs(center, turned.x, turned.y)

func floor_height(point: Vector3) -> float:
	return PlanGrid.FLOOR_TOP if game.index.has_floor(PlanGrid.cell_at(point)) else 0.0

# Returns {transform, valid, reason, footprint, edge?, side?} or {} off-lot.
func snap(mouse: Vector2, kind: String, item_id: String, rotation: float, exclude_id: String = "") -> Dictionary:
	var item_spec := spec(kind, item_id)
	var point: Vector3 = game.rig.ground_point(mouse, PlanGrid.FLOOR_TOP * 0.5)
	if point == Vector3.INF:
		return {}
	if String(item_spec.mount) == "wall":
		return _snap_wall(point, kind, item_spec, exclude_id)
	var size: Vector2i = item_spec.footprint
	var turned := PlanGrid.rotated_footprint(size, rotation)
	var center := Vector3(PlanGrid.snap_part_center(point.x, turned.x), 0.0, PlanGrid.snap_part_center(point.z, turned.y))
	center.y = floor_height(center)
	var result := {"transform": Transform3D(Bricks.basis_y(rotation), center), "valid": true, "reason": "", "footprint": size}
	var layer := surfaces if bool(item_spec.get("surface", false)) else studs
	for stud in footprint_studs(center, size, rotation):
		var owner := String(layer.get(stud, ""))
		if not owner.is_empty() and owner != exclude_id:
			result.valid = false
			result.reason = "Blocked by %s" % game.describe(owner)
			return result
	if bool(item_spec.get("outdoor", false)):
		if game.index.is_indoors(center):
			result.valid = false
			result.reason = "That belongs outdoors"
		elif kind in ["tree", "shrub"] and game.index.has_floor(PlanGrid.cell_at(center)):
			result.valid = false
			result.reason = "Plants need open ground"
	return result

func _snap_wall(point: Vector3, kind: String, item_spec: Dictionary, exclude_id: String) -> Dictionary:
	var best := ""
	var best_distance := 1.8
	var cell := PlanGrid.cell_at(point)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for edge in PlanGrid.cell_edges(cell + Vector2i(dx, dz)):
				if not game.index.has_wall(edge):
					continue
				var found := PlanGrid.edge_distance(edge, point)
				if float(found.distance) < best_distance:
					best_distance = found.distance
					best = edge
	if best.is_empty():
		return {"transform": Transform3D(Basis.IDENTITY, Vector3(point.x, 0, point.z)), "valid": false, "reason": "Point at a wall to hang it", "footprint": item_spec.footprint}
	var normal := PlanGrid.edge_normal(best)
	var center := PlanGrid.edge_center(best)
	var side := 1 if (point - center).dot(normal) >= 0.0 else -1
	var along_axis := Vector3(1, 0, 0) if best.begins_with("x") else Vector3(0, 0, 1)
	var width: int = item_spec.footprint.x
	var run := _wall_run(best)
	var half := float(width) * PlanGrid.STUD * 0.5
	var along := PlanGrid.snap_part_center(point.dot(along_axis), width)
	var result := {"valid": true, "reason": "", "footprint": item_spec.footprint, "edge": best, "side": side}
	if run.y - run.x < half * 2.0 - 0.01:
		result.valid = false
		result.reason = "Needs a longer stretch of plain wall"
	along = clampf(along, run.x + half, maxf(run.x + half, run.y - half))
	along = PlanGrid.snap_part_center(along, width)
	var outward := normal * float(side)
	var position := center + along_axis * (along - center.dot(along_axis)) + outward * (PlanGrid.STUD * 0.5)
	position.y = floor_height(center + outward * 0.8) + (THERMOSTAT_HEIGHT if kind == "tstat" else 0.0)
	var yaw := atan2(outward.x, outward.z)
	result.transform = Transform3D(Bricks.basis_y(yaw), position)
	if not game.index.openings.get(best, {}).is_empty():
		result.valid = false
		result.reason = "That wall section has a door or window"
		return result
	for key in _wall_slots(best, side, position, width):
		var owner := String(wall_slots.get(key, ""))
		if not owner.is_empty() and owner != exclude_id:
			result.valid = false
			result.reason = "Something already hangs there"
			return result
	return result

static func _position(item: Dictionary) -> Vector3:
	var values: Array = item.transform.position
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
