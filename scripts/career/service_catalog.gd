extends RefCounted

# What a service tech can do at a piece of equipment: tests (cost time, tell
# you something true about the equipment) and repairs (cost time and parts;
# fix a fault only when it is the right part). Replacing a part that wasn't
# broken fixes nothing and comes out of your pocket, as a callback would.

const CHECKS := {
	"ahu": [
		{"id": "fan", "label": "Inspect the supply fan and belt", "minutes": 6},
		{"id": "filter", "label": "Read the filter pressure drop", "minutes": 3, "needs": "filter"},
		{"id": "chw_valve", "label": "Stroke the cooling valve", "minutes": 6, "needs": "cooling_coil"},
		{"id": "oa_damper", "label": "Stroke the outdoor-air damper", "minutes": 5, "needs": "damper"},
		{"id": "temps", "label": "Read the air temperatures", "minutes": 3},
	],
	"vav": [
		{"id": "damper", "label": "Stroke the damper", "minutes": 4},
		{"id": "reheat", "label": "Stroke the reheat valve", "minutes": 4, "needs": "heating_coil"},
		{"id": "discharge", "label": "Measure the discharge air", "minutes": 3},
	],
	"tstat": [
		{"id": "sensor", "label": "Compare with a reference thermometer", "minutes": 4},
		{"id": "setpoints", "label": "Read its setpoints", "minutes": 1},
	],
}

const REPAIRS := {
	"ahu": [
		{"id": "belt", "label": "Replace the fan belt", "cost": 140.0, "minutes": 30, "fixes": ["fan_failure"]},
		{"id": "filters", "label": "Change the filters", "cost": 380.0, "minutes": 25, "fixes": ["dirty_filter"], "needs": "filter"},
		{"id": "chw_actuator", "label": "Replace the cooling valve actuator", "cost": 460.0, "minutes": 35, "fixes": ["chw_valve_stuck"], "needs": "cooling_coil"},
		{"id": "oa_actuator", "label": "Replace the outdoor-air damper actuator", "cost": 390.0, "minutes": 35, "fixes": ["oa_damper_stuck"], "needs": "damper"},
		{"id": "vfd", "label": "Replace the fan drive (VFD)", "cost": 2400.0, "minutes": 90, "fixes": []},
		{"id": "controller", "label": "Replace the AHU controller", "cost": 1800.0, "minutes": 60, "fixes": []},
	],
	"vav": [
		{"id": "damper_actuator", "label": "Replace the damper actuator", "cost": 260.0, "minutes": 25, "fixes": ["stuck_damper"]},
		{"id": "reheat_actuator", "label": "Replace the reheat valve actuator", "cost": 320.0, "minutes": 30, "fixes": ["reheat_stuck"], "needs": "heating_coil"},
		{"id": "vav_controller", "label": "Replace the VAV controller", "cost": 650.0, "minutes": 45, "fixes": []},
	],
	"tstat": [
		{"id": "calibrate", "label": "Recalibrate the sensor", "cost": 0.0, "minutes": 10, "fixes": ["sensor_bias"]},
		{"id": "replace_tstat", "label": "Replace the thermostat", "cost": 240.0, "minutes": 25, "fixes": ["sensor_bias", "setpoint"]},
		{"id": "reset_setpoints", "label": "Reset to standard setpoints (73 / 70 °F)", "cost": 0.0, "minutes": 2, "fixes": ["setpoint"]},
	],
}

# Which equipment a fault lives on (for matching repairs to faults).
const FAULT_HOST := {"fan_failure": "ahu", "dirty_filter": "ahu", "chw_valve_stuck": "ahu", "oa_damper_stuck": "ahu",
	"stuck_damper": "vav", "reheat_stuck": "vav", "sensor_bias": "tstat", "setpoint": "tstat"}

static func checks_for(kind: String, layout: Array) -> Array:
	return CHECKS.get(kind, []).filter(func(entry: Dictionary) -> bool: return not entry.has("needs") or String(entry.needs) in layout)

static func repairs_for(kind: String, layout: Array) -> Array:
	return REPAIRS.get(kind, []).filter(func(entry: Dictionary) -> bool: return not entry.has("needs") or String(entry.needs) in layout)

static func find(table: Dictionary, kind: String, id: String) -> Dictionary:
	for entry in table.get(kind, []):
		if String(entry.id) == id: return entry
	return {}

# What a test finds, from the simulation's real state and the hidden faults.
# `faults` are the job's unfixed faults on this piece of equipment.
static func check_result(check_id: String, item: Dictionary, sim: DemoSimulation, faults: Array, room: Dictionary) -> String:
	var kinds: Dictionary = {}
	for fault in faults: kinds[String(fault.kind)] = fault
	var id := String(item.get("id", ""))
	match check_id:
		"fan":
			var unit := sim.unit_state(id)
			if kinds.has("fan_failure"):
				return "The motor hums along but the fan wheel is barely turning: the belt has snapped. The drive is fine."
			if not bool(unit.get("enabled", false)):
				return "Fan is off: the air handler isn't called to run right now. Belt tight, bearings quiet."
			return "Fan turning at %d %% speed. Belt tight, bearings quiet, no vibration. OK." % roundi(float(unit.get("fan_feedback", 0.0)) * 100.0)
		"filter":
			var unit := sim.unit_state(id)
			var dp := float(unit.get("filter_dp_pa", 0.0))
			var flow := Units.flow(float(unit.get("supply_airflow_m3_s", 0.0)))
			if kinds.has("dirty_filter"):
				return "Filter pressure drop %s at %s. The filters are grey and caked: well past their change point." % [Units.pressure(dp), flow]
			return "Filter pressure drop %s at %s. Filters are clean enough." % [Units.pressure(dp), flow]
		"chw_valve":
			if kinds.has("chw_valve_stuck"):
				return "Commanded 0 to 100 %%: the valve stem doesn't move (stuck at %d %%). The actuator has failed." % roundi(float(kinds.chw_valve_stuck.value) * 100.0)
			return "Commanded 0 to 100 %: the valve strokes fully and the coil goes cold. OK."
		"oa_damper":
			if kinds.has("oa_damper_stuck"):
				return "Commanded closed: the outdoor-air damper stays %d %% open. The linkage is fine; the actuator is dead." % roundi(float(kinds.oa_damper_stuck.value) * 100.0)
			return "Commanded closed and open: the outdoor-air damper follows within a minute. OK."
		"temps":
			var unit := sim.unit_state(id)
			return "Return %s · mixed %s · supply %s (setpoint %s) · outdoor air %d %%." % [Units.temp(float(unit.get("return_temp_c", 0.0)), 1), Units.temp(float(unit.get("mixed_temp_c", 0.0)), 1), Units.temp(float(unit.get("supply_temp_c", 0.0)), 1), Units.temp(float(unit.get("supply_setpoint_c", 0.0)), 1), roundi(float(unit.get("oa_fraction", 0.0)) * 100.0)]
		"damper":
			if kinds.has("stuck_damper"):
				return "Commanded 0 to 100 %%: the blade stays at %d %%. The actuator isn't driving it." % roundi(float(kinds.stuck_damper.value) * 100.0)
			return "Commanded 0 to 100 %: the blade strokes fully in about 90 s. Damper and actuator OK."
		"reheat":
			if kinds.has("reheat_stuck"):
				var stuck := float(kinds.reheat_stuck.value)
				if stuck < 0.5: return "Commanded open: the valve stays shut, so the coil stays cold. The actuator has failed."
				return "Commanded shut: the valve stays %d %% open, so hot water keeps flowing. The actuator has failed." % roundi(stuck * 100.0)
			return "Commanded open and shut: the reheat valve follows and the coil warms and cools. OK."
		"discharge":
			var terminal := sim.terminal_state(id)
			return "Discharge air %s at %s (airflow setpoint %s) · reheat command %d %%." % [Units.temp(float(terminal.get("discharge_temp_c", 0.0)), 1), Units.flow(float(terminal.get("airflow_m3_s", 0.0))), Units.flow(float(terminal.get("airflow_target_m3_s", 0.0))), roundi(float(terminal.get("reheat_command", 0.0)) * 100.0)]
		"sensor":
			if room.is_empty(): return "This thermostat isn't in a room."
			var zone := sim.zone_state(String(room.id))
			var reads := float(zone.get("temp_c", 0.0))
			var actual := float(zone.get("true_temp_c", 0.0))
			if absf(reads - actual) > 0.6:
				return "Reference thermometer %s, the thermostat reads %s: its sensor is %.1f °F off." % [Units.temp(actual, 1), Units.temp(reads, 1), absf(reads - actual) * 1.8]
			return "Reference thermometer %s, the thermostat reads %s. Agrees. OK." % [Units.temp(actual, 1), Units.temp(reads, 1)]
		"setpoints":
			if room.is_empty(): return "This thermostat isn't in a room."
			var zone := sim.zone_state(String(room.id))
			return "Cooling %s · heating %s (standard is 73 / 70 °F)." % [Units.temp(float(zone.get("cool_setpoint_c", 23.0))), Units.temp(float(zone.get("heat_setpoint_c", 21.0)))]
	return "Nothing to report."
