class_name PointMatcher
extends RefCounted

# Auto-mapping: given the points under one station device (a VAV controller,
# an AHU controller), guess which point drives each moving part of a piece of
# equipment in the game, by name, the way an integrator reads a points list.
# Names vary by vendor ("DamperPos", "DMPR-FB", "ZN-T", "SF_SPD"), so each role
# has a few patterns, feedback beats command, and setpoints are excluded.

const ROLE_LABELS := {"fan": "Fan", "damper": "Damper", "cooling_coil": "Cooling coil", "heating_coil": "Heating coil", "airflow": "Airflow", "space_temp": "Room temperature"}
const ROLES_BY_KIND := {
	"vav": ["damper", "airflow", "heating_coil", "cooling_coil", "space_temp"],
	"ahu": ["fan", "damper", "cooling_coil", "heating_coil", "airflow"],
	"duct": ["airflow"],
	"tstat": ["space_temp"],
}
# Each role: patterns that must match (any), patterns that disqualify (any).
const RULES := {
	"damper": {"match": ["damper", "dmpr", "dpr", "dmp"], "exclude": ["oa", "outside", "outdoor", "econ", "sp", "setpoint", "stpt", "min", "max"]},
	"airflow": {"match": ["airflow", "air_flow", "air flow", "flow", "cfm", "afl", "sa_fl", "saf"], "exclude": ["sp", "setpoint", "stpt", "min", "max", "design", "fan", "k_factor", "kfactor"]},
	"heating_coil": {"match": ["reheat", "rht", "rh_", "htg", "heat", "hw", "hwv"], "exclude": ["sp", "setpoint", "stpt", "temp", "tmp", "enable", "lock", "mode"]},
	"cooling_coil": {"match": ["clg", "cool", "chw", "chwv", "ccv"], "exclude": ["sp", "setpoint", "stpt", "temp", "tmp", "enable", "lock", "mode"]},
	"space_temp": {"match": ["spacetemp", "space_temp", "space temp", "spt", "zat", "znt", "zn_t", "zn-t", "zonetemp", "zone_temp", "zone temp", "roomtemp", "room_temp", "rmt", "rm_t", "spacet", "zntemp"], "exclude": ["sp", "setpoint", "stpt", "clg", "htg", "cool", "heat", "offset", "adj"]},
	"fan": {"match": ["fanspd", "fan_spd", "fanspeed", "fan_speed", "fan speed", "sf_spd", "sfspd", "supplyfanspd", "vfd", "sf_vfd", "fan", "sf"], "exclude": ["sp", "setpoint", "stpt", "alarm", "fault", "hand", "auto", "exhaust", "return", "ef", "rf"]},
}
# On an air handler the damper that matters is the outdoor-air (economizer) damper.
const AHU_DAMPER := {"match": ["damper", "dmpr", "dpr", "dmp"], "exclude": ["return", "ra", "exhaust", "relief", "ea", "sp", "setpoint", "stpt", "min", "max"]}
# Feedback-ish names beat command-ish names for actuators.
const FEEDBACK := ["fb", "feedback", "pos", "position", "status", "sts", "out", "output", "spd", "speed", "actual"]
const COMMAND := ["cmd", "command", "req", "request"]

# `nodes`: [{ord, name, kind, ...}] (points from a browse or search).
# Returns {role: node} for each role it could fill.
static func match_points(kind: String, nodes: Array) -> Dictionary:
	var result: Dictionary = {}
	var used: Dictionary = {}
	for role in ROLES_BY_KIND.get(kind, []):
		var best: Dictionary = {}
		var best_score := 0
		for node in nodes:
			if String(node.get("kind", "point")) != "point" or used.has(String(node.ord)): continue
			var score := score(String(role), String(node.get("name", "")), kind)
			if score > best_score:
				best = node
				best_score = score
		if not best.is_empty():
			result[role] = best
			used[String(best.ord)] = true
	return result

static func score(role: String, raw_name: String, kind: String = "vav") -> int:
	var name := raw_name.to_lower()
	var tokens := _tokens(raw_name)
	var rule: Dictionary = AHU_DAMPER if kind == "ahu" and role == "damper" else RULES.get(role, {})
	var hit := 0
	for pattern in rule.get("match", []):
		var key := String(pattern)
		if name == key or tokens.has(key): hit = maxi(hit, 6)
		elif key.length() >= 4 and name.contains(key): hit = maxi(hit, 4)
		elif key.length() >= 2 and _prefix(tokens, key): hit = maxi(hit, 3)
	if hit == 0: return 0
	for pattern in rule.get("exclude", []):
		var key := String(pattern)
		if tokens.has(key) or (key.length() >= 4 and name.contains(key)): return 0
	if role in ["damper", "heating_coil", "cooling_coil", "fan"]:
		for word in FEEDBACK:
			if tokens.has(word) or name.ends_with(word): hit += 2
		for word in COMMAND:
			if tokens.has(word) or name.ends_with(word): hit -= 1
	return maxi(hit, 1)

# Lower-case words of a point name, split at separators, camel case and digits:
# "SupplyFanSpd" -> ["supplyfanspd", "supply", "fan", "spd"]; "ZN-T" -> ["zn-t", "zn", "t"];
# "AirflowCFM" -> ["airflowcfm", "airflow", "cfm"].
static func _tokens(raw: String) -> Array:
	var out: Array = [raw.to_lower()]
	var current := ""
	for index in range(raw.length()):
		var c := raw[index]
		if c in ["_", "-", " ", ".", "/", ":"]:
			if not current.is_empty(): out.append(current.to_lower())
			current = ""
			continue
		var upper := c != c.to_lower()
		var digit := c.is_valid_int()
		if not current.is_empty():
			var last := current[current.length() - 1]
			var last_upper := last != last.to_lower()
			var last_digit := last.is_valid_int()
			# New word: lower -> Upper, digit <-> letter, or the last Upper of an
			# acronym before a lower-case letter ("CFMValue" -> "cfm", "value").
			var acronym_end := upper == false and not digit and last_upper and current.length() > 1 and current[current.length() - 2] != current[current.length() - 2].to_lower()
			if (upper and not last_upper and not last_digit) or digit != last_digit:
				out.append(current.to_lower())
				current = ""
			elif acronym_end:
				out.append(current.left(current.length() - 1).to_lower())
				current = last
		current += c
	if not current.is_empty(): out.append(current.to_lower())
	return out

static func _prefix(tokens: Array, key: String) -> bool:
	for token in tokens:
		if String(token).begins_with(key) and String(token).length() <= key.length() + 3: return true
	return false

# The binding that maps a station point to a role's motion (0..1 level).
static func binding_for(role: String, node: Dictionary, unit: String, capacity_m3_s: float, connection_id: String) -> Dictionary:
	var lower := unit.to_lower()
	var binding := {"source": "niagara", "point_id": String(node.ord), "connection_id": connection_id, "mapping": "number", "input_min": 0.0, "input_max": 100.0, "unit": "", "enum_levels": {}, "invert": false, "command_based": _is_command(String(node.get("name", "")))}
	match role:
		"airflow":
			if lower.contains("l/s"): binding.input_max = capacity_m3_s * 1000.0
			elif lower.contains("m³/s") or lower.contains("m3/s"): binding.input_max = capacity_m3_s
			else: binding.input_max = maxf(100.0, roundf(Units.cfm(capacity_m3_s)))
		"fan":
			if lower.contains("hz"): binding.input_max = 60.0
			elif String(node.get("typeSpec", "")).to_lower().contains("boolean") or lower.is_empty() and String(node.get("name", "")).to_lower().contains("cmd"): binding.mapping = "boolean"
		"space_temp":
			binding.input_min = 0.0
			binding.input_max = 100.0
	return binding

static func _is_command(name: String) -> bool:
	var tokens := _tokens(name.to_lower())
	for word in COMMAND:
		if tokens.has(word) or name.to_lower().ends_with(word): return true
	return false
