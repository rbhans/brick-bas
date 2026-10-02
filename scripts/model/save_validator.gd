extends RefCounted

const KINDS_V1 := ["floor", "wall", "wall_run", "door", "window", "ahu", "vav", "duct", "tee", "diffuser", "terrain", "path", "parking", "tree", "shrub", "tstat"]
const KINDS := ["floor", "wall", "door", "window", "furniture", "ahu", "vav", "duct", "tee", "cross", "diffuser", "path", "parking", "tree", "shrub", "tstat"]
const TEXT_KEYS := ["label", "served_room", "vav_id", "wall_id", "id", "role", "edge", "style", "finish", "item", "zone", "template", "room"]
const ROLES := ["damper", "filter", "cooling_coil", "heating_coil", "fan"]
# Everything sits on the lot (the build camera stops at ±400 m). Room
# detection walks every cell between the outermost floors and walls, so a
# piece far off the lot would make every edit crawl.
const LOT_M := 450.0
const LOT_TILES := 180

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) < 1.0e12

static func point(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(func(v: Variant) -> bool: return number(v) and absf(float(v)) <= LOT_M)

static func records(value: Variant) -> bool:
	return value is Array and value.size() <= 20000 and value.all(func(v: Variant) -> bool: return v is Dictionary)

static func simulation_value(key: String, value: Variant) -> bool:
	if not number(value): return false
	if key in ["fan_command", "fan_feedback", "damper_command", "damper_feedback", "cooling_command", "cooling_output", "heating_command", "heating_output", "reheat_output", "cooling_demand", "heating_demand"]:
		return float(value) >= 0.0 and float(value) <= 1.0
	if key.ends_with("_m3_s") or key.ends_with("_pa") or key in ["ua_w_k", "internal_w", "solar_w", "heating_w", "cooling_w"]:
		return float(value) >= 0.0
	if key.ends_with("_temp_c"): return float(value) >= -50.0 and float(value) <= 65.0
	return true

static func plain(value: Variant, depth: int = 0) -> bool:
	if depth > 20: return false
	if value == null or value is bool: return true
	if value is String or value is StringName: return String(value).length() <= 4096
	if value is int or value is float: return number(value)
	if value is Array:
		if value.size() > 20000: return false
		for entry in value:
			if not plain(entry, depth + 1): return false
		return true
	if value is Dictionary:
		if value.size() > 20000: return false
		for key in value:
			if (not key is String and not key is StringName) or not plain(value[key], depth + 1): return false
		return true
	return false

static func property_shapes(props: Dictionary) -> bool:
	for key in TEXT_KEYS:
		if props.has(key) and not props[key] is String: return false
	if props.has("edge"):
		var edge := PlanGrid.parse_edge(String(props.edge))
		if edge.is_empty() or absi(int(edge.i)) > LOT_TILES or absi(int(edge.j)) > LOT_TILES: return false
	if props.has("cell"):
		if not props.cell is Array or props.cell.size() != 2 or not number(props.cell[0]) or not number(props.cell[1]): return false
		if absf(float(props.cell[0])) > LOT_TILES or absf(float(props.cell[1])) > LOT_TILES: return false
	for key in ["paint", "bindings", "components", "brick_connection", "openings", "opening_hosts", "start_port", "end_port"]:
		if props.has(key) and not props[key] is Dictionary: return false
	for key in ["segments", "waypoints"]:
		if props.has(key):
			if not props[key] is Array or props[key].size() > 512: return false
			for value in props[key]:
				if not point(value): return false
	for key in props.get("paint", {}):
		if not props.paint[key] is String or not Color.html_is_valid(props.paint[key]): return false
	for binding in props.get("bindings", {}).values():
		if not binding is Dictionary or not binding.get("enum_levels", {}) is Dictionary: return false
		for key in ["source", "point_id", "connection_id", "mapping", "unit"]:
			if binding.has(key) and not binding[key] is String: return false
		for key in ["input_min", "input_max"]:
			if binding.has(key) and not number(binding[key]): return false
	for opening in props.get("opening_hosts", {}).values():
		if not opening is Dictionary: return false
	for opening in props.get("openings", {}).values():
		if opening not in ["door", "window"]: return false
	for key in ["start_port", "end_port"]:
		if props.has(key):
			if not props[key].get("owner", "") is String or not props[key].get("port", "") is String: return false
	if props.has("layout"):
		if not props.layout is Array or props.layout.size() > 7: return false
		for role in props.layout:
			if role not in ROLES: return false
	if props.has("component_records"):
		if not records(props.component_records) or props.component_records.size() > 7: return false
		for component in props.component_records:
			if component.get("role", "") not in ROLES or not property_shapes(component): return false
	for key in ["mount_level", "capacity_m3_s", "module", "swing", "side"]:
		if props.has(key) and not number(props[key]): return false
	return true

static func valid_v1(data: Dictionary) -> bool:
	return _valid(data, 1, KINDS_V1)

static func valid(data: Dictionary) -> bool:
	return _valid(data, 2, KINDS)

static func _valid(data: Dictionary, version: int, kinds: Array) -> bool:
	if not plain(data): return false
	if data.get("format") != "bas-sandbox-project" or int(data.get("version", 0)) != version: return false
	if not data.get("project_id", "") is String or not number(data.get("next_id", 1)): return false
	if not data.has("floors") or not data.has("objects"): return false
	for key in ["floors", "objects", "rooms", "routes", "bindings", "connections"]:
		if not records(data.get(key, [])): return false
	for key in ["site", "demo_checkpoint"]:
		if not data.get(key, {}) is Dictionary: return false
	var ids := {}
	for item in data.objects:
		var id: Variant = item.get("id")
		if not id is String or id.is_empty() or id in [".", ".."] or id.length() > 128 or id != id.validate_node_name() or ids.has(id): return false
		ids[id] = true
		if item.get("kind") not in kinds or not item.get("floor_id", "") is String: return false
		if not item.get("transform") is Dictionary or not item.get("properties") is Dictionary: return false
		if not point(item.transform.get("position")) or not number(item.transform.get("rotation_y", 0)): return false
		if not property_shapes(item.properties): return false
	var site: Dictionary = data.get("site", {})
	if site.has("spawn") and not point(site.spawn): return false
	if not site.get("open_doors", {}) is Dictionary or not site.get("camera", {}) is Dictionary: return false
	for state in site.get("open_doors", {}).values():
		if not state is bool: return false
	var camera: Dictionary = site.get("camera", {})
	if camera.has("target") and not point(camera.target): return false
	for key in ["pitch", "yaw", "distance"]:
		if camera.has(key) and not number(camera[key]): return false
	if site.has("camera_distance") and not number(site.camera_distance): return false
	var checkpoint: Dictionary = data.get("demo_checkpoint", {})
	if version >= 2:
		for key in ["room_names", "room_types"]:
			if not site.get(key, {}) is Dictionary: return false
			for name in site.get(key, {}).values():
				if not name is String: return false
		for key in ["sim_seconds", "speed"]:
			if checkpoint.has(key) and not number(checkpoint[key]): return false
		return true
	if not checkpoint.get("units", {}) is Dictionary: return false
	for unit in checkpoint.get("units", {}).values():
		if not unit is Dictionary: return false
		for key in unit:
			if key == "enabled":
				if not unit[key] is bool: return false
			elif not simulation_value(String(key), unit[key]): return false
	if not checkpoint.get("rooms", {}) is Dictionary: return false
	for room in checkpoint.get("rooms", {}).values():
		if not room is Dictionary: return false
		for key in room:
			if key in ["label", "id"]:
				if not room[key] is String: return false
			elif key == "connected":
				if not room[key] is bool: return false
			elif not simulation_value(String(key), room[key]): return false
		if room.has("capacitance_j_k") and float(room.capacitance_j_k) <= 0: return false
	for key in ["sim_seconds", "fan_feedback", "accumulator", "speed"]:
		if checkpoint.has(key) and not number(checkpoint[key]): return false
	if checkpoint.has("running") and not checkpoint.running is bool: return false
	if float(checkpoint.get("sim_seconds", 0)) < 0.0 or float(checkpoint.get("speed", 1)) < 0.0 or float(checkpoint.get("speed", 1)) > 60.0: return false
	if checkpoint.has("scenario") and (not checkpoint.scenario is String or checkpoint.scenario not in DemoSimulation.SCENARIOS): return false
	return true
