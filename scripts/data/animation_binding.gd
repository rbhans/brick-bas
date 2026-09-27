class_name AnimationBinding
extends RefCounted

# A renderer consumes a normalized level, never a Niagara value directly.
# Missing/invalid samples stay unknown. False and numeric zero are valid values.
static func evaluate(binding: Dictionary, point: Dictionary, authority: String = "demo") -> Dictionary:
	if String(binding.get("source", "demo")) != authority:
		return unknown("Source inactive")
	if point.is_empty():
		return unknown("Point unavailable")
	if String(point.get("source_id", "")) != authority:
		return unknown("Source mismatch")
	for flag in point.get("quality_flags", []):
		if String(flag) in ["stale", "fault", "down", "disabled", "communication_failure", "unknown"]:
			return unknown(String(flag).capitalize())
	var value: Variant = point.get("value")
	var mapping := String(binding.get("mapping", "number"))
	var level := 0.0
	match mapping:
		"boolean":
			if not value is bool:
				return unknown("Expected Boolean")
			level = 1.0 if value else 0.0
		"enum":
			if not (value is String or value is int):
				return unknown("Expected enum name or ordinal")
			var levels: Dictionary = binding.get("enum_levels", {})
			if not levels.has(str(value)):
				return unknown("Unmapped enum: " + str(value))
			level = float(levels[str(value)])
		"number":
			if not (value is float or value is int) or not is_finite(float(value)):
				return unknown("Expected finite number")
			var minimum := float(binding.get("input_min", 0.0))
			var maximum := float(binding.get("input_max", 100.0))
			if not is_finite(minimum) or not is_finite(maximum) or maximum <= minimum:
				return unknown("Maximum must exceed minimum")
			var expected_unit := String(binding.get("unit", ""))
			var actual_unit := String(point.get("unit", ""))
			var number := float(value)
			if expected_unit != actual_unit and not expected_unit.is_empty():
				if expected_unit == "%" and actual_unit == "fraction":
					number *= 100.0
				elif expected_unit == "fraction" and actual_unit == "%":
					number /= 100.0
				elif expected_unit == "degC" and actual_unit == "degF":
					number = (number - 32.0) / 1.8
				elif expected_unit == "degF" and actual_unit == "degC":
					number = number * 1.8 + 32.0
				else:
					return unknown("Incompatible units")
			level = (number - minimum) / (maximum - minimum)
		_:
			return unknown("Unknown mapping")
	if not is_finite(level):
		return unknown("Invalid mapped level")
	level = clampf(level, 0.0, 1.0)
	if bool(binding.get("invert", false)):
		level = 1.0 - level
	return {"known": true, "level": level, "status": "Command based" if bool(binding.get("command_based", false)) else "Feedback", "value": value}

static func unknown(reason: String) -> Dictionary:
	return {"known": false, "level": 0.0, "status": reason}

static func legacy_defaults(kind: String, room: String = "east_office") -> Dictionary:
	var output := {
		"fan": {"source": "demo", "point_id": "ahu.fan_run_feedback", "mapping": "boolean"},
		"cooling_coil": {"source": "demo", "point_id": "ahu.cooling_output", "mapping": "number", "input_min": 0.0, "input_max": 100.0, "unit": "%"},
		"heating_coil": {"source": "demo", "point_id": room + ".reheat_output", "mapping": "number", "input_min": 0.0, "input_max": 100.0, "unit": "%"},
		"damper": {"source": "demo", "point_id": room + ".damper_feedback", "mapping": "number", "input_min": 0.0, "input_max": 100.0, "unit": "%"},
		"airflow": {"source": "demo", "point_id": "ahu.supply_airflow", "mapping": "number", "input_min": 0.0, "input_max": 0.8, "unit": "m3/s"},
	}
	if kind == "vav":
		output.airflow.point_id = room + ".airflow"
		output.airflow.input_max = 0.45
	return output

static func defaults(kind: String, room: String = "east_office", owner: String = "ahu") -> Dictionary:
	var result := legacy_defaults(kind, room)
	result.fan = {"source": "demo", "point_id": owner + ".fan_speed_feedback", "mapping": "number", "input_min": 0.0, "input_max": 1.0, "unit": "fraction"}
	if kind == "ahu":
		result.cooling_coil.point_id = owner + ".cooling_output"
		result.heating_coil.point_id = owner + ".heating_output"
		result.damper.point_id = owner + ".damper_feedback"
		result.airflow.point_id = owner + ".supply_airflow"
	elif kind == "vav":
		result.cooling_coil.point_id = room + ".cooling_output"
		result.airflow.input_max = 0.42
	elif kind == "duct": result.airflow.point_id = owner + ".airflow"
	for binding in result.values(): binding.automatic = true
	return result

static func for_item(item: Dictionary) -> Dictionary:
	var room := String(item.properties.get("served_room", "east_office"))
	var result := defaults(String(item.kind), room, String(item.id))
	result.airflow.input_max = maxf(0.001, float(item.properties.get("capacity_m3_s", 0.42 if item.kind == "vav" else 0.8)))
	return result

static func refresh_automatic(item: Dictionary) -> void:
	if item.kind not in ["ahu", "vav", "duct"]: return
	var wanted := for_item(item)
	var bindings: Dictionary = item.properties.get("bindings", {}).duplicate(true)
	for role in wanted:
		var current: Dictionary = bindings.get(role, {})
		var migrate := current.is_empty() or bool(current.get("automatic", false))
		if not current.has("automatic") and not item.properties.has("binding_schema"):
			for room in [String(item.properties.get("served_room", "east_office")), "east_office", "west_office"]:
				for kind in ["ahu", "vav", "duct"]:
					if current == legacy_defaults(kind, room)[role]: migrate = true
		if migrate: bindings[role] = wanted[role]
	item.properties.bindings = bindings
	item.properties.binding_schema = 2
