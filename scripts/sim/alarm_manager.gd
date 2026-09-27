class_name AlarmManager
extends RefCounted

# BAS-style alarms evaluated from the demo simulation's read accessors. A
# condition must hold for its delay (simulated seconds) before the alarm is
# raised; it clears when the condition clears. Acknowledgement is kept while
# the alarm stays active. Equipment removed from the building drops its alarms.

const FAN_FAILURE_DELAY_S := 20.0
const SPACE_TEMP_BAND_K := 2.0
const SPACE_TEMP_DELAY_S := 300.0
const OCCUPIED_GRACE_S := 1800.0 # no comfort alarms during the first 30 min of occupancy
const FILTER_DP_LIMIT_PA := 180.0
const FILTER_DELAY_S := 120.0
const DAMPER_MISMATCH := 0.20
const DAMPER_DELAY_S := 180.0
const COMM_DELAY_S := 30.0
const SEVERITY_RANK := {"critical": 0, "warning": 1, "notice": 2}

var active: Dictionary = {}
var timers: Dictionary = {}

func evaluate(simulation: RefCounted, dt: float) -> void:
	if simulation == null or not is_finite(dt) or dt <= 0.0: return
	var seen: Dictionary = {}
	var stale := String(simulation.scenario) == "Data interruption"
	_evaluate(seen, "comm_failure", stale, dt, COMM_DELAY_S, "BAS network: controller data stale (communication failure)", "critical")
	if stale:
		# The front end cannot see equipment through a comms loss: hold the rest.
		for id in active: seen[id] = true
		for id in timers: seen[id] = true
		_prune(seen)
		return
	var weather: Dictionary = simulation.weather()
	var comfort := bool(weather.get("occupied", false)) and float(weather.get("occupied_elapsed_s", 0.0)) >= OCCUPIED_GRACE_S
	for id in simulation.unit_ids():
		var unit: Dictionary = simulation.unit_state(id)
		var label := String(unit.get("label", id))
		var failed := bool(unit.get("enabled", false)) and bool(unit.get("has_fan", false)) and not bool(unit.get("fan_running", false))
		_evaluate(seen, "fan_failure:" + id, failed, dt, FAN_FAILURE_DELAY_S, label + ": supply fan commanded on without run proof", "critical")
		var filter_dp := float(unit.get("filter_dp_pa", 0.0))
		_evaluate(seen, "filter:" + id, filter_dp > FILTER_DP_LIMIT_PA, dt, FILTER_DELAY_S, label + ": filter differential pressure high (%s)" % Units.pressure(filter_dp), "notice")
	for id in simulation.zone_ids():
		var zone: Dictionary = simulation.zone_state(id)
		if not bool(zone.get("served", false)): continue
		var label := String(zone.get("label", id))
		var temp := float(zone.get("temp_c", 0.0))
		var high := comfort and temp > float(zone.get("active_cool_setpoint_c", 99.0)) + SPACE_TEMP_BAND_K
		var low := comfort and temp < float(zone.get("active_heat_setpoint_c", -99.0)) - SPACE_TEMP_BAND_K
		_evaluate(seen, "high_temp:" + id, high, dt, SPACE_TEMP_DELAY_S, label + ": high space temperature (%s)" % Units.temp(temp, 1), "warning")
		_evaluate(seen, "low_temp:" + id, low, dt, SPACE_TEMP_DELAY_S, label + ": low space temperature (%s)" % Units.temp(temp, 1), "warning")
	for id in simulation.terminal_ids():
		var terminal: Dictionary = simulation.terminal_state(id)
		var mismatch := absf(float(terminal.get("damper_command", 0.0)) - float(terminal.get("damper_feedback", 0.0)))
		var stuck := bool(terminal.get("connected", false)) and mismatch > DAMPER_MISMATCH
		_evaluate(seen, "damper:" + id, stuck, dt, DAMPER_DELAY_S, String(terminal.get("label", id)) + ": damper not following command", "warning")
	_prune(seen)

func _evaluate(seen: Dictionary, id: String, condition: bool, dt: float, delay: float, message: String, severity: String) -> void:
	seen[id] = true
	if condition:
		timers[id] = float(timers.get(id, 0.0)) + dt
		if float(timers[id]) >= delay and not active.has(id):
			active[id] = {"id": id, "message": message, "severity": severity, "acknowledged": false}
	else:
		timers.erase(id)
		active.erase(id)

func _prune(seen: Dictionary) -> void:
	for id in active.keys():
		if not seen.has(id): active.erase(id)
	for id in timers.keys():
		if not seen.has(id): timers.erase(id)

func acknowledge_all() -> void:
	for id in active:
		active[id].acknowledged = true

func acknowledge(id: String) -> void:
	if active.has(id): active[id].acknowledged = true

# Active alarms, most severe first: [{id, message, severity, acknowledged}].
func list() -> Array:
	var result: Array = []
	for alarm in active.values(): result.append(alarm.duplicate())
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a := int(SEVERITY_RANK.get(a.severity, 9))
		var rank_b := int(SEVERITY_RANK.get(b.severity, 9))
		return rank_a < rank_b if rank_a != rank_b else String(a.id) < String(b.id))
	return result

func summary() -> String:
	if active.is_empty():
		return "ALARMS  0 • system normal"
	var unacknowledged := 0
	for alarm in active.values():
		if not bool(alarm.acknowledged):
			unacknowledged += 1
	return "ALARMS  %d active • %d unacknowledged" % [active.size(), unacknowledged]
