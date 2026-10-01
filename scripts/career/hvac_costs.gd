class_name HvacCosts
extends RefCounted

# Installed prices for career install jobs (equipment, labour and material, in
# game dollars). Everything is derived from the model, so undo, moves and
# deletes keep the bill right without tracking events.

const HVAC_KINDS := ["ahu", "vav", "diffuser", "tee", "cross", "duct", "tstat"]
const AHU_BASE := 6500.0            # casing, controller, start-up
const AHU_PER_M3_S := 4200.0        # bigger fan, coils and casing per m³/s of design airflow
const AHU_SECTIONS := {"damper": 900.0, "filter": 450.0, "cooling_coil": 2600.0, "heating_coil": 1500.0, "fan": 0.0}
const VAV_BASE := 950.0
const VAV_PER_M3_S := 900.0
const VAV_SECTIONS := {"damper": 0.0, "heating_coil": 650.0, "cooling_coil": 900.0}
const PIECES := {"diffuser": 160.0, "tee": 210.0, "cross": 320.0, "tstat": 240.0}
const DUCT_PER_M := 48.0
# Air handler sizes offered on the workbench: design airflow in m³/s.
const AHU_SIZES := [0.8, 1.2, 1.6, 2.4, 3.2, 4.0, 5.0, 6.0]
const DEFAULT_AHU_SIZE := 1.6

static func item_cost(item: Dictionary, objects: Array) -> float:
	var props: Dictionary = item.get("properties", {})
	match String(item.get("kind", "")):
		"ahu":
			var total := AHU_BASE + AHU_PER_M3_S * float(props.get("capacity_m3_s", DEFAULT_AHU_SIZE))
			for role in RouteNetwork.layout(props): total += float(AHU_SECTIONS.get(String(role), 0.0))
			return total
		"vav":
			var total := VAV_BASE + VAV_PER_M3_S * float(props.get("capacity_m3_s", 0.45))
			for role in RouteNetwork.layout(props): total += float(VAV_SECTIONS.get(String(role), 0.0))
			return total
		"duct":
			return DUCT_PER_M * duct_length(props, objects)
	return float(PIECES.get(String(item.get("kind", "")), 0.0))

static func duct_length(properties: Dictionary, objects: Array) -> float:
	var points := DuctConnections.path(properties, objects)
	var length := 0.0
	for index in range(1, points.size()): length += points[index - 1].distance_to(points[index])
	return length

# {"total", "by_kind": {kind: dollars}, "count": {kind: n}, "duct_m"}
static func bill(objects: Array) -> Dictionary:
	var by_kind: Dictionary = {}
	var count: Dictionary = {}
	var total := 0.0
	var duct_m := 0.0
	for item in objects:
		var kind := String(item.get("kind", ""))
		if kind not in HVAC_KINDS: continue
		var cost := item_cost(item, objects)
		total += cost
		by_kind[kind] = float(by_kind.get(kind, 0.0)) + cost
		count[kind] = int(count.get(kind, 0)) + 1
		if kind == "duct": duct_m += duct_length(item.properties, objects)
	return {"total": total, "by_kind": by_kind, "count": count, "duct_m": duct_m}

static func total(objects: Array) -> float:
	return float(bill(objects).total)

static func size_label(capacity_m3_s: float) -> String:
	var names := ["Small", "Compact", "Medium", "Large", "Extra large", "Jumbo", "Rooftop", "Central plant"]
	var name := "Custom"
	for index in range(AHU_SIZES.size()):
		if absf(float(AHU_SIZES[index]) - capacity_m3_s) < 0.01: name = names[index]
	return "%s · %s" % [name, Units.flow(capacity_m3_s)]
