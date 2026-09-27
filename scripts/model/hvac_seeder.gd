extends RefCounted

# Seeds a real, connected VAV system into a template: air handlers where the
# plan says, a supply trunk above the corridor with 4-way crosses, one VAV per
# served room (sized from its floor area), one or two ceiling diffusers per
# room, and a thermostat on the wall by each room's door. Every duct is routed
# with the same auto-router players use, so the result is always valid.

const DuctPorts := preload("res://scripts/build/duct_connections.gd")
const Bindings := preload("res://scripts/data/animation_binding.gd")
const THERMOSTAT_HEIGHT := 1.55
const CEILING_FACE := 3.6

static func seed(model: ProjectModel, builder: RefCounted) -> void:
	var spec: Dictionary = builder.layout.get("hvac", {})
	if spec.is_empty():
		return
	var library := Placement.equipment_models()
	var seeder := Seeder.new(model, builder, library)
	seeder.run(spec)

class Seeder:
	var model: ProjectModel
	var builder: RefCounted
	var library: Script
	var units: Dictionary = {}     # name -> item
	var serial := 0

	func _init(target: ProjectModel, plan: RefCounted, models: Script) -> void:
		model = target
		builder = plan
		library = models

	func run(spec: Dictionary) -> void:
		for name in spec.get("units", {}):
			_unit(String(name), spec.units[name])
		for trunk in spec.get("trunks", []):
			_trunk(trunk, spec.get("zones", []).filter(func(zone: Dictionary) -> bool: return String(zone.get("trunk", "")) == String(trunk.get("id", ""))))
		for zone in spec.get("direct", []):
			_direct(zone)
		_size_units()

	# --- Placement helpers ----------------------------------------------------------------

	func world(x: float, z: float) -> Vector3:
		return Vector3((x + builder.origin.x) * PlanGrid.TILE, 0.0, (z + builder.origin.y) * PlanGrid.TILE)

	func add(kind: String, position: Vector3, rotation: float, properties: Dictionary) -> Dictionary:
		var id := String(properties.get("id", model.new_id(kind)))
		properties.erase("id")
		return model.add_object(kind, {"position": [position.x, position.y, position.z], "rotation_y": fposmod(rotation, TAU)}, properties, id)

	func port_height(kind: String, properties: Dictionary, port: String) -> float:
		if library == null:
			return 0.0
		var local: Dictionary = library.port_local(kind, properties, port)
		return float((local.get("face", Vector3.ZERO) as Vector3).y)

	func ceiling_y(kind: String, properties: Dictionary, port: String) -> float:
		return DuctPorts.ROUTE_HEIGHT - port_height(kind, properties, port)

	func footprint(kind: String, properties: Dictionary) -> Vector2i:
		return library.footprint(kind, properties) if library != null else Vector2i(4, 4)

	func snap(point: Vector3, kind: String, properties: Dictionary, rotation: float) -> Vector3:
		var turned := PlanGrid.rotated_footprint(footprint(kind, properties), rotation)
		return Vector3(PlanGrid.snap_part_center(point.x, turned.x), point.y, PlanGrid.snap_part_center(point.z, turned.y))

	func route(from_item: Dictionary, from_port: String, to_item: Dictionary, to_port: String) -> bool:
		var start := DuctPorts.port(from_item, from_port)
		var finish := DuctPorts.port(to_item, to_port)
		if start.is_empty() or finish.is_empty():
			return false
		var routed := DuctPorts.auto_route(start, finish, model.objects)
		if not bool(routed.ok):
			push_warning("Template duct %s.%s -> %s.%s: %s" % [from_item.id, from_port, to_item.id, to_port, routed.message])
			return false
		var properties: Dictionary = routed.properties
		properties.bindings = Bindings.defaults("duct")
		add("duct", Vector3.ZERO, 0.0, properties)
		return true

	# --- Units ---------------------------------------------------------------------------

	func _unit(name: String, spec: Dictionary) -> void:
		var layout: Array = spec.get("layout", ["damper", "filter", "cooling_coil", "heating_coil", "fan"])
		var properties := {"id": String(spec.get("id", name.to_lower())), "label": name, "layout": layout, "sensor_enabled": true, "capacity_m3_s": 1.6, "mount_level": 0}
		var rotation := deg_to_rad(float(spec.get("rotation", 0.0)))
		var at: Array = spec.at
		var point := snap(world(float(at[0]), float(at[1])), "ahu", properties, rotation)
		point.y = PlanGrid.FLOOR_TOP if not bool(spec.get("outdoor", false)) else PlanGrid.FLOOR_TOP
		var item := add("ahu", point, rotation, properties)
		item.properties.bindings = Bindings.defaults("ahu", "", String(item.id))
		units[name] = item

	func _size_units() -> void:
		# Air handlers are sized to the terminals they serve, with diversity.
		var totals: Dictionary = {}
		var network := RouteNetwork.evaluate(model.objects)
		for vav_id in network.get("terminals", {}):
			var terminal: Dictionary = network.terminals[vav_id]
			var source := String(terminal.get("source_id", ""))
			if source.is_empty(): continue
			totals[source] = float(totals.get(source, 0.0)) + float(terminal.get("capacity_m3_s", 0.4))
		for name in units:
			var item: Dictionary = units[name]
			item.properties.capacity_m3_s = snappedf(maxf(0.6, float(totals.get(String(item.id), 1.0)) * 0.85), 0.05)

	# --- Trunks ----------------------------------------------------------------------------

	# A trunk is an axis-aligned main at duct height. Zones along it get a cross
	# at their position; two rooms facing each other share one cross.
	func _trunk(trunk: Dictionary, zones: Array) -> void:
		var unit: Dictionary = units.get(String(trunk.unit), {})
		if unit.is_empty() or zones.is_empty():
			return
		var axis := String(trunk.get("axis", "x"))
		var line := float(trunk.line)
		var taps: Dictionary = {}
		for zone in zones:
			var at := float(zone.at)
			var key := snappedf(at, 0.01)
			if not taps.has(key): taps[key] = []
			taps[key].append(zone)
		var positions: Array = taps.keys()
		var flow := float(trunk.get("flow", 1.0))
		positions.sort_custom(func(a: float, b: float) -> bool: return a * flow < b * flow)
		var upstream := unit
		var upstream_port := "outlet"
		for at in positions:
			var point := world(float(at), line) if axis == "x" else world(line, float(at))
			var rotation := (0.0 if flow > 0 else PI) if axis == "x" else (-PI * 0.5 if flow > 0 else PI * 0.5)
			var fitting := {"label": "Trunk cross", "capacity_m3_s": 1.6}
			point = snap(point, "cross", fitting, rotation)
			point.y = ceiling_y("cross", fitting, "inlet")
			var cross := add("cross", point, rotation, fitting)
			route(upstream, upstream_port, cross, "inlet")
			for zone in taps[at]:
				var branch := _branch_toward(cross, String(zone.room))
				_zone(zone, cross, branch, axis)
			upstream = cross
			upstream_port = "outlet"

	func _branch_toward(cross: Dictionary, room_name: String) -> String:
		var rect: Rect2i = builder.room_rect(room_name)
		var center := (Vector3(rect.position.x, 0, rect.position.y) + Vector3(rect.end.x, 0, rect.end.y)) * 0.5 * PlanGrid.TILE
		var best := "branch_a"
		var best_dot := -INF
		for name in ["branch_a", "branch_b"]:
			var port := DuctPorts.port(cross, name)
			var toward := (center - (port.face as Vector3)) * Vector3(1, 0, 1)
			var score := (port.normal as Vector3).dot(toward.normalized())
			if score > best_dot:
				best_dot = score
				best = name
		return best

	# The shared zone planner places the VAV, diffusers, ducts and thermostat.
	func _zone(zone: Dictionary, supply: Dictionary, supply_port: String, _axis: String) -> void:
		var index := BuildingIndex.new()
		index.rebuild(model.objects, model.site)
		var room: Dictionary = {}
		for candidate in index.rooms:
			if String(candidate.label) == String(zone.room): room = candidate
		if room.is_empty():
			push_warning("Template zone room not found: %s" % zone.room)
			return
		var planner := ZonePlanner.new(model.objects, index, model.new_id)
		var vav := planner.zone_from(room, supply, supply_port, String(zone.get("label", "VAV · " + String(zone.room))), zone.get("layout", ["damper", "heating_coil"]), float(zone.get("reach", 1.2)))
		if vav.is_empty():
			push_warning("Template zone %s: %s" % [zone.room, planner.error])
			return
		for entry in planner.entries:
			model.restore_object(entry)

	# Small buildings: unit -> (tee ->) VAVs without a trunk.
	func _direct(zone: Dictionary) -> void:
		var unit: Dictionary = units.get(String(zone.unit), {})
		if unit.is_empty():
			return
		_zone(zone, unit, "outlet", "x")
