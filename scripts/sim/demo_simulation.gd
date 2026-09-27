class_name DemoSimulation
extends RefCounted

# BRICK/BAS demo building. A deterministic sensible-heat gameplay model whose
# job is to produce the point data a BAS front end would show for whatever the
# player built: zones drift with weather, people, lights and open doors; AHUs
# and VAVs run recognisable sequences (optimal start, night cycle, VAV dual-max
# reheat, duct-static and SAT trim & respond, economizer first then mechanical
# cooling). Not an engineering, sizing or code-compliance tool.
#
# One fixed 1 s step: environment -> AHU modes -> VAV loops -> AHU loops ->
# duct airflow -> AHU/VAV air temperatures -> zone heat and CO2 balance.
# SI units: s, m, m², m³, m³/s, Pa, W, J/K, °C, ppm. Commands and feedbacks
# are 0..1 fractions internally and % on points (fan speed stays a fraction).
# docs/SIMULATION.md describes sequences, constants, points and limits.

const STEP_SECONDS := 1.0
const MAX_STEPS_PER_ADVANCE := 3600
const DAY_S := 86400.0
const START_SECONDS := 23400.0 # 06:30: players see the morning start-up.
const SCENARIOS := ["Normal weekday", "Hot afternoon", "Fan failure", "Damper stuck at 25%", "Dirty filter", "Sensor bias", "Data interruption", "Cold morning", "Unoccupied", "Economizer day", "Heat wave"]
# Weather per scenario: [min °C at 05:30, max °C at 15:00, sky clearness 0..1,
# peak solar elevation °, zone °C at start]. Others use Normal weekday.
const WEATHER := {
	"Normal weekday": [17.0, 29.0, 0.85, 65.0, 24.0],
	"Hot afternoon": [24.0, 37.0, 1.0, 70.0, 26.0],
	"Cold morning": [-2.0, 9.0, 0.7, 30.0, 15.0],
	"Economizer day": [8.0, 19.0, 0.9, 55.0, 24.0],
	"Heat wave": [29.0, 42.0, 1.0, 72.0, 27.5],
}

# Schedule and setpoints.
const OCCUPIED_START_S := 25200.0 # 07:00
const OCCUPIED_END_S := 64800.0 # 18:00
const OPTIMAL_START_EARLIEST_S := 18000.0 # 05:00
const OPTIMAL_START_BASE_S := 900.0 # lead = base + per-K × worst zone error
const OPTIMAL_START_PER_K_S := 1200.0
const OPTIMAL_START_MAX_S := 7200.0
const SETPOINT_MIN_C := 16.0
const SETPOINT_MAX_C := 30.0
const MIN_DEADBAND_K := 1.0
const DEFAULT_COOL_C := 23.0
const DEFAULT_HEAT_C := 21.0
const UNOCC_COOL_C := 29.0
const UNOCC_HEAT_C := 16.0
const NIGHT_RECOVERY_K := 2.0 # night cycle heats to 18 / cools to 27, stops at 17 / 28

# Zone envelope and air.
const RHO_CP := 1206.0 # J/(m³·K), air volumetric heat capacity
const CEILING_M := 3.6
const U_WALL := 0.45
const U_WINDOW := 2.8
const U_ROOF := 0.25
const U_PARTITION := 1.8
const INFILTRATION_ACH := 0.3
const DOOR_LEAK_M3_S := 0.01 # per closed exterior door
const SHGC := 0.4
# Two thermal nodes per zone: room air (+ furnishings) and the structure's
# thermally active mass, coupled by interior surface convection. Opaque
# envelope conducts into the mass; windows, air leakage and HVAC act on air.
const FURNISHING_J_M2K := 20000.0 # air node, besides the air itself, per floor m²
const MASS_J_M2K := 110000.0 # structure participating over hours, per floor m²
const SURFACE_W_M2K := 9.0 # air <-> mass, per floor m² (~3 m² surface × 3 W/m²K)
# Share of each gain that is radiant (absorbed by the mass node first).
const SOLAR_RADIANT := 0.7
const PEOPLE_RADIANT := 0.4
const LIGHTS_RADIANT := 0.5
const PLUG_RADIANT := 0.3
const ROOF_ABSORPTANCE := 0.6
const WALL_ABSORPTANCE := 0.5
const OUTSIDE_FILM_W_M2K := 20.0
const DOOR_EXCHANGE_M3_S := 0.10 # open exterior door: wind + 0.07·√ΔT buoyancy
const DOOR_BUOYANCY := 0.07
const WINDOW_EXCHANGE_M3_S := 0.04
const WINDOW_BUOYANCY := 0.025
const DOOR_MIX_M3_S := 0.08 # open interior door, each way
const DOOR_MIX_BUOYANCY := 0.06
const WINDOW_MIX_M3_S := 0.02
const OUTDOOR_CO2_PPM := 420.0
const ZONE_NOISE_K := 0.04
const SENSOR_BIAS_K := 2.0
const NOISE_PERIOD_S := 20.0
# Zone types: [people/m² at peak, sensible W/person, plug W/m², lights W/m²,
# occupancy profile, lights on by schedule, plug fraction after hours,
# CO2 ppm·m³/s per person (0.0052 L/s seated adult = 5.2)].
const ZONE_TYPES := {
	"classroom": [0.40, 70.0, 5.0, 8.0, "school", true, 0.25, 5.2],
	"office": [0.08, 75.0, 10.0, 8.0, "office", true, 0.35, 5.2],
	"conference": [0.35, 75.0, 4.0, 8.0, "meeting", true, 0.25, 5.2],
	"lobby": [0.08, 75.0, 3.0, 8.0, "office", true, 0.3, 5.2],
	"corridor": [0.02, 75.0, 1.0, 5.0, "office", true, 0.5, 5.2],
	"restroom": [0.05, 75.0, 1.0, 6.0, "office", true, 0.5, 5.2],
	"mechanical": [0.0, 75.0, 30.0, 4.0, "none", false, 1.0, 5.2],
	"break_room": [0.15, 75.0, 20.0, 8.0, "lunch", true, 0.4, 5.2],
	"storage": [0.0, 75.0, 1.0, 4.0, "none", false, 1.0, 5.2],
	"gym": [0.12, 150.0, 2.0, 10.0, "school", true, 0.2, 12.0],
	"library": [0.10, 70.0, 6.0, 9.0, "school", true, 0.3, 5.2],
	"room": [0.10, 75.0, 5.0, 8.0, "office", true, 0.3, 5.2],
}
# Fraction of peak occupancy by hour (piecewise linear, occupied hours only).
const PROFILES := {
	"school": [[7.0, 0.0], [7.5, 0.2], [8.0, 0.95], [11.8, 0.95], [12.0, 0.3], [12.8, 0.3], [13.0, 0.9], [15.0, 0.9], [15.3, 0.15], [17.5, 0.1], [18.0, 0.0]],
	"office": [[7.0, 0.0], [7.5, 0.3], [8.5, 0.9], [11.8, 0.9], [12.2, 0.55], [12.9, 0.55], [13.2, 0.9], [16.8, 0.9], [17.5, 0.3], [18.0, 0.0]],
	"meeting": [[7.0, 0.0], [9.0, 0.0], [9.1, 0.9], [10.4, 0.9], [10.5, 0.1], [13.9, 0.1], [14.0, 0.9], [15.9, 0.9], [16.0, 0.0], [18.0, 0.0]],
	"lunch": [[7.0, 0.0], [7.5, 0.3], [8.0, 0.1], [11.5, 0.1], [12.0, 1.0], [13.0, 1.0], [13.3, 0.15], [17.0, 0.1], [18.0, 0.0]],
	"none": [[0.0, 0.0]],
}

# AHU: fan curve P = shutoff·N² − droop·(Q/Qd)²; internal and duct losses ∝ Q².
const FAN_SHUTOFF_PA := 1000.0
const FAN_DROOP_PA := 300.0
const FAN_EFFICIENCY := 0.6
const CASING_PA := 60.0
const DAMPER_PA := 20.0
const COOL_COIL_PA := 110.0
const HEAT_COIL_PA := 40.0
const DUCT_LOSS_PA := 120.0 # AHU outlet to the static sensor at design flow
const FILTER_CLEAN_PA := 70.0
const FILTER_DIRTY_PA := 500.0
const FILTER_LOADING_PA_PER_H := 0.1 # at design flow
const FAN_MIN_SPEED := 0.2
const FAN_RAMP_S := 30.0 # VFD accel/decel, 0 -> 100 %
const FAN_COAST_TAU_S := 12.0
const FAN_PROOF_SPEED := 0.1 # current switch threshold
const FAN_PROOF_DELAY_S := 5.0
const STATIC_KP := 0.12 # per unit of normalised pressure error
const STATIC_KI := 0.006 # per s
const STATIC_SP_INIT_PA := 250.0
const STATIC_SP_MIN_PA := 150.0
const STATIC_SP_MAX_PA := 300.0
const STATIC_TRIM_PA := 6.0
const STATIC_RESPOND_PA := 12.0
const STATIC_RESPOND_MAX_PA := 30.0
const STATIC_NOISE_PA := 2.0
const SAT_MIN_C := 12.8
const SAT_MAX_C := 18.0
const SAT_WARMUP_C := 35.0
const SAT_RESET_OAT_LOW_C := 16.0 # full T&R range below this OAT...
const SAT_RESET_OAT_HIGH_C := 21.0 # ...12.8 °C above this OAT
const SAT_TR_TRIM_K := 0.1
const SAT_TR_RESPOND_K := 0.2
const SAT_TR_RESPOND_MAX_K := 0.6
const SAT_KP := 6.0 # % per K
const SAT_TI_S := 150.0
const SAT_NOISE_K := 0.05
const TR_DELAY_S := 600.0
const TR_INTERVAL_S := 120.0
const ECON_HIGH_LIMIT_C := 21.0
const ECON_DEADBAND_K := 0.5
const OA_MIN_POSITION := 0.2
const DCV_MAX_POSITION := 0.5 # OA minimum rises as worst zone CO2 goes 700 -> 1000 ppm
const DCV_LOW_PPM := 700.0
const DCV_HIGH_PPM := 1000.0
const CHW_C := 6.7 # chilled water supply
const COOL_COIL_EFFECTIVENESS := 0.85 # at low airflow, falling to 0.72 at design flow
const HW_C := 60.0
const HEAT_COIL_EFFECTIVENESS := 0.55
const PLENUM_GAIN_K := 0.4
const DUCT_GAIN_K := 0.3
const OA_DAMPER_STROKE_S := 75.0
const VALVE_STROKE_S := 60.0
const ACTUATOR_DEADBAND := 0.004
const RAT_TAU_S := 60.0
const MAT_TAU_S := 8.0
const SAT_TAU_S := 25.0
const SAT_OFF_TAU_S := 300.0

# VAV terminal (pressure independent, ASHRAE Guideline 36 style dual maximum).
const VAV_MIN_FRACTION := 0.3
const VAV_HEAT_MAX_FRACTION := 0.45
const VAV_CO2_MAX_FRACTION := 0.6 # zone minimum raised as zone CO2 goes 1000 -> 1400 ppm
const VAV_CO2_LOW_PPM := 1000.0
const VAV_CO2_HIGH_PPM := 1400.0
const VAV_OVERSIZE := 1.25 # box flow fully open at design static, relative to max
const DESIGN_STATIC_PA := 250.0
const VAV_DAMPER_STROKE_S := 90.0
const FLOW_TRIM_KI := 0.004
const FLOW_TRIM_MIN := -0.3
const FLOW_TRIM_MAX := 0.6
const DAT_MAX_C := 35.0
const DAT_OVER_SPACE_K := 11.0
const REHEAT_DESIGN_RISE_K := 24.0 # at heating-maximum airflow
const REHEAT_EFFECTIVENESS := 0.75
const TERMINAL_COIL_MIN_C := 10.0
const DAT_TAU_S := 20.0
const DAT_OFF_TAU_S := 180.0
const STUCK_DAMPER := 0.25
const ZONE_LOOP_TI_S := 1200.0
const ZONE_LOOP_CROSSOVER := 1.0 / 900.0 # rad/s used to auto-tune each zone's gain
const FLOW_NOISE := 0.01
const TEMP_NOISE_K := 0.05

const UNIT_ROLES := ["damper", "filter", "cooling_coil", "heating_coil", "fan"]
const TERMINAL_ROLES := ["damper", "heating_coil", "cooling_coil"]
const UNIT_MODES := ["Off", "Occupied", "Warm-up", "Cool-down", "Setback", "Setup"]
# Checkpointed state and its clamp range. Everything else is configuration.
const ZONE_STATE := {"true_temp_c": [-40.0, 70.0], "mass_temp_c": [-40.0, 70.0], "co2_ppm": [300.0, 10000.0], "cool_setpoint_c": [17.0, 30.0], "heat_setpoint_c": [16.0, 29.0], "lights_override": [-1.0, 1.0]}
const TERMINAL_STATE := {"cool_i": [0.0, 1.0], "heat_i": [0.0, 1.0], "cooling_loop": [0.0, 1.0], "heating_loop": [0.0, 1.0],
	"flow_sp_m3_s": [0.0, 50.0], "flow_actual_m3_s": [0.0, 50.0], "damper_command": [0.0, 1.0], "damper_feedback": [0.0, 1.0],
	"flow_trim": [-0.3, 0.6], "reheat_command": [0.0, 1.0], "reheat_output": [0.0, 1.0], "cooling_command": [0.0, 1.0],
	"cooling_output": [0.0, 1.0], "discharge_temp_c": [-40.0, 90.0], "heating_w": [0.0, 1.0e7], "cooling_w": [0.0, 1.0e7],
	"active_cool_c": [16.0, 32.0], "active_heat_c": [14.0, 30.0]}
const UNIT_STATE := {"fan_command": [0.0, 1.0], "fan_feedback": [0.0, 1.0], "run_timer_s": [0.0, 3600.0], "static_i": [0.0, 1.0],
	"static_sp_pa": [150.0, 300.0], "duct_pressure_pa": [0.0, 3000.0], "fan_total_pa": [0.0, 3000.0], "sat_sp_c": [5.0, 45.0],
	"sat_tr_c": [12.8, 18.0], "sat_i": [-100.0, 100.0], "sat_u": [-100.0, 100.0], "mode_timer_s": [0.0, 1.0e9], "tr_timer_s": [0.0, 1.0e4],
	"oa_min": [0.0, 1.0], "damper_command": [0.0, 1.0], "damper_feedback": [0.0, 1.0], "cooling_command": [0.0, 1.0],
	"cooling_output": [0.0, 1.0], "heating_command": [0.0, 1.0], "heating_output": [0.0, 1.0], "return_temp_c": [-40.0, 90.0],
	"mixed_temp_c": [-40.0, 90.0], "supply_temp_c": [-40.0, 90.0], "flow_actual_m3_s": [0.0, 100.0], "available_flow_m3_s": [0.0, 100.0],
	"filter_dp_pa": [0.0, 3000.0], "filter_loading_pa": [70.0, 500.0], "cooling_w": [0.0, 1.0e8], "heating_w": [0.0, 1.0e8],
	"fan_w": [0.0, 1.0e8], "oa_fraction": [0.0, 1.0], "co2_return_ppm": [300.0, 10000.0], "co2_supply_ppm": [300.0, 10000.0], "runtime_s": [0.0, 1.0e10]}
const UNIT_FLAGS := ["enabled", "fan_proven", "economizer"]

var running := true
var speed := 1.0
var sim_seconds := START_SECONDS
var scenario := "Normal weekday"
var accumulator := 0.0
# Public state for tests and debugging; UI should use the *_state() accessors.
var zones: Dictionary = {}
var units: Dictionary = {}
var terminals: Dictionary = {}
var rooms: Dictionary = {} # Legacy alias of terminals (same Dictionary).
var route_flows: Dictionary = {}
# Legacy site/first-AHU aliases for older callers.
var fan_feedback := 0.0
var supply_temp_c := 20.0
var available_flow_m3_s := 0.0
var outdoor_temp_c := 20.0
var occupied := false
var solar_w_m2 := 0.0

var _step_index := 0
var _steps_since_reset := 0
var _revision := 0
var _tod := START_SECONDS
var _oat := 20.0
var _sol := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0]) # N, E, S, W vertical and horizontal W/m²
var _profile_now: Dictionary = {}
var _zone_list: Array[Dictionary] = [] # real zones (sorted) then per-terminal dummy zones
var _zone_index: Dictionary = {} # real zone id -> index
var _dummy: Dictionary = {} # vav id -> dummy zone record
var _zone_terms: Array = [] # per zone: PackedInt32Array of terminal indices
var _neighbours: Array = [] # per zone: [[zone index, W/K], ...]
var _open_doors := PackedFloat64Array() # per zone: open exterior doors
var _open_windows := PackedFloat64Array()
var _open_int: Array = [] # per zone: [[zone index, is_door], ...]
var _openings: Array = [] # validated set_open_connections() input
var _unit_list: Array[Dictionary] = []
var _unit_terms: Array = [] # per unit: PackedInt32Array of connected terminal indices
var _unit_zones: Array = [] # per unit: PackedInt32Array of served zone indices
var _unit_b := PackedFloat64Array() # per unit: resistance Pa/(m³/s)² this step
var _term_list: Array[Dictionary] = []
var _term_zone: Array[Dictionary] = []
var _term_unit: Array[Dictionary] = [] # {} when not connected to an AHU
var _term_zone_idx := PackedInt32Array()
var _term_unit_idx := PackedInt32Array() # -1 when not connected
var _unit_index: Dictionary = {} # ahu id -> index
var _term_index: Dictionary = {} # vav id -> index
var _limits: Array = [] # [capacity, PackedInt32Array, PackedFloat64Array]
var _routes: Array = [] # [id, PackedInt32Array, PackedFloat64Array]
var _q := PackedFloat64Array()
var _prev_t := PackedFloat64Array()
var _prev_c := PackedFloat64Array()
var _stash: Dictionary = {"zones": {}, "dummy_zones": {}, "units": {}, "terminals": {}}
var _fault_fan := ""
var _fault_filter := ""
var _fault_damper := ""
var _fault_bias := ""
var _points_cache: Array[Dictionary] = []
var _quality: Array[String] = []
var _points_revision := -1

func _init() -> void:
	rooms = terminals
	reset()

# ---------------------------------------------------------------- lifecycle

# Back to 06:30 on a Normal weekday. Keeps the configured building (topology
# and open doors) but returns every zone, AHU and VAV to its start state.
func reset() -> void:
	sim_seconds = START_SECONDS
	accumulator = 0.0
	scenario = "Normal weekday"
	_step_index = 0
	_steps_since_reset = 0
	for key in _stash: _stash[key].clear()
	_update_environment(false)
	var start_c := _start_temp()
	for z in _zone_list: _init_zone_state(z, start_c)
	for u in _unit_list: _init_unit_state(u, start_c)
	for t in _term_list: _init_terminal_state(t, start_c)
	_after_state_change()

# Fixed 1 s steps: identical results at any speed. A backlog beyond the cap is
# dropped rather than replayed (a long hitch must not freeze the game).
func advance(real_delta: float) -> int:
	if not running or not is_finite(real_delta) or real_delta <= 0.0: return 0
	var rate := clampf(speed, 0.0, 60.0) if is_finite(speed) else 0.0
	accumulator += real_delta * rate
	var count := 0
	while accumulator >= STEP_SECONDS and count < MAX_STEPS_PER_ADVANCE:
		_step()
		accumulator -= STEP_SECONDS
		count += 1
	if accumulator >= STEP_SECONDS: accumulator = 0.0
	return count

func step_for_test(seconds: float) -> void:
	if not is_finite(seconds): return
	for _i in range(int(floor(seconds / STEP_SECONDS + 1.0e-6))): _step()

# Weather and faults switch immediately. Picking a scenario right after
# reset() also applies its start temperatures; entering Cold morning always
# sets the building cold (an explicit initial condition, not a forced value).
func set_scenario(value: String) -> void:
	if value not in SCENARIOS: return
	var cold_start := value == "Cold morning" and scenario != value
	scenario = value
	_update_environment(true)
	if _steps_since_reset == 0 or cold_start: _apply_start_temps(_start_temp())
	_after_state_change()

# ---------------------------------------------------------------- topology

# Builds zones/AHUs/VAVs from the detected building and duct network. State
# for ids that survive is preserved; new ids start sensibly; removed ids drop.
func configure(topology: Dictionary) -> void:
	var zsrc := _dict(topology.get("zones", {}))
	var usrc := _dict(topology.get("units", {}))
	var tsrc := _dict(topology.get("terminals", {}))
	var start_c := _typical_temp()
	# Zones.
	var kept: Dictionary = {}
	for id in _sorted_ids(zsrc):
		var z: Dictionary = zones.get(id, {})
		if z.is_empty(): z = _new_record(id, "zones", start_c)
		_zone_config(z, _dict(zsrc[id]), id)
		kept[id] = z
	zones.clear()
	zones.merge(kept)
	# AHUs.
	kept = {}
	for id in _sorted_ids(usrc):
		var u: Dictionary = units.get(id, {})
		if u.is_empty(): u = _new_record(id, "units", start_c)
		_unit_config(u, _dict(usrc[id]), id)
		kept[id] = u
	units.clear()
	units.merge(kept)
	# VAVs, and a dummy zone for each VAV that discharges outside any room.
	kept = {}
	var dummies: Dictionary = {}
	for id in _sorted_ids(tsrc):
		var t: Dictionary = terminals.get(id, {})
		if t.is_empty(): t = _new_record(id, "terminals", start_c)
		_terminal_config(t, _dict(tsrc[id]), id)
		kept[id] = t
		if String(t.zone_id).is_empty():
			var d: Dictionary = _dummy.get(id, {})
			if d.is_empty(): d = _new_record(id, "dummy_zones", start_c)
			_zone_config(d, {"type": "room", "label": String(t.label) + " space", "area_m2": 20.0, "exterior_wall_m2": 12.0, "roof_m2": 20.0}, id)
			d.dummy = true
			d.people_max = 0.0
			d.lights_w = 0.0
			dummies[id] = d
	terminals.clear()
	terminals.merge(kept)
	_dummy = dummies
	_build_indices(topology, zsrc)
	_after_state_change()

# Legacy adapter for RouteNetwork output without room data (keeps zones).
func apply_network_status(status: Dictionary) -> void:
	var zsrc: Dictionary = {}
	for id in zones: zsrc[id] = _zone_source(zones[id])
	configure({"zones": zsrc, "units": status.get("units", {}), "terminals": status.get("terminals", status.get("rooms", {})), "limits": status.get("limits", {}), "routes": status.get("routes", {})})

func ensure_room(_id: String, _label: String) -> void:
	pass # Legacy no-op: zones now come from configure().

# ---------------------------------------------------------------- player inputs

# Thermostat. Clamped to 16–30 °C with at least 1 K between heat and cool;
# the cooling value wins a conflict. heat_c = NAN keeps the heating setpoint.
func set_zone_setpoints(zone_id: String, cool_c: float, heat_c: float = NAN) -> void:
	var z: Dictionary = zones.get(zone_id, _dummy.get(zone_id, {}))
	if z.is_empty(): return
	var cool := clampf(cool_c if is_finite(cool_c) else float(z.cool_setpoint_c), SETPOINT_MIN_C + MIN_DEADBAND_K, SETPOINT_MAX_C)
	var heat := clampf(heat_c if is_finite(heat_c) else float(z.heat_setpoint_c), SETPOINT_MIN_C, SETPOINT_MAX_C - MIN_DEADBAND_K)
	z.cool_setpoint_c = cool
	z.heat_setpoint_c = minf(heat, cool - MIN_DEADBAND_K)
	_revision += 1

# Thermostats are linked to VAVs: sets the cooling setpoint of the VAV's zone.
func set_terminal_setpoint(vav_id: String, cool_c: float) -> void:
	var t: Dictionary = terminals.get(vav_id, {})
	if t.is_empty(): return
	set_zone_setpoints(String(t.zone_id) if not String(t.zone_id).is_empty() else vav_id, cool_c)

# Legacy: accepts a zone id or a VAV id.
func set_room_setpoint(id: String, value_c: float) -> void:
	if zones.has(id): set_zone_setpoints(id, value_c)
	elif terminals.has(id): set_terminal_setpoint(id, value_c)

# Currently open doors/windows: [{"a": zone|"outside", "b": zone|"outside", "kind": "door"|"window"}].
func set_open_connections(connections: Array) -> void:
	_openings.clear()
	for entry in connections:
		if not entry is Dictionary or _openings.size() >= 256: continue
		var a := String(entry.get("a", "")) if entry.get("a", "") is String or entry.get("a", "") is StringName else ""
		var b := String(entry.get("b", "")) if entry.get("b", "") is String or entry.get("b", "") is StringName else ""
		var kind := "window" if String(entry.get("kind", "door")) == "window" else "door"
		if a.is_empty() or b.is_empty() or a == b: continue
		_openings.append({"a": a, "b": b, "kind": kind})
	_build_openings()
	_revision += 1

# Lighting override. Cleared by the next occupancy schedule change (BAS sweep).
func set_lights(zone_id: String, on: bool) -> void:
	var z: Dictionary = zones.get(zone_id, {})
	if z.is_empty(): return
	z.lights_override = 1.0 if on else 0.0
	z.lights_on = on
	_revision += 1

# ---------------------------------------------------------------- read accessors (copies)

func zone_ids() -> Array:
	return zones.keys()

func unit_ids() -> Array:
	return units.keys()

func terminal_ids() -> Array:
	return terminals.keys()

func weather() -> Dictionary:
	var minutes := int(floor(_tod / 60.0))
	return {"outdoor_temp_c": _oat, "solar_w_m2": _sol[4], "occupied": occupied, "time_of_day_s": _tod,
		"clock": "%02d:%02d" % [floori(minutes / 60.0), minutes % 60], "scenario": scenario,
		"occupied_elapsed_s": _tod - OCCUPIED_START_S if occupied else 0.0,
		"irradiance_w_m2": {"N": _sol[0], "E": _sol[1], "S": _sol[2], "W": _sol[3], "horizontal": _sol[4]}}

func zone_state(zone_id: String) -> Dictionary:
	var zi := int(_zone_index.get(zone_id, -1))
	if zi < 0: return {}
	var z: Dictionary = _zone_list[zi]
	var ids: Array = []
	var cool := UNOCC_COOL_C
	var heat := UNOCC_HEAT_C
	if occupied:
		cool = float(z.cool_setpoint_c)
		heat = float(z.heat_setpoint_c)
	var found := false
	for ti in _zone_terms[zi]:
		var t: Dictionary = _term_list[ti]
		ids.append(String(t.id))
		if not found and bool(t.connected):
			found = true
			cool = float(t.active_cool_c)
			heat = float(t.active_heat_c)
	return {"id": zone_id, "label": String(z.label), "type": String(z.type), "temp_c": float(z.measured_temp_c),
		"true_temp_c": float(z.true_temp_c), "mass_temp_c": float(z.mass_temp_c), "cool_setpoint_c": float(z.cool_setpoint_c), "heat_setpoint_c": float(z.heat_setpoint_c),
		"active_cool_setpoint_c": cool, "active_heat_setpoint_c": heat, "mode": _zone_mode(zi), "served": bool(z.served),
		"supply_c": float(z.supply_temp_c), "airflow_m3_s": float(z.supply_airflow_m3_s), "co2_ppm": float(z.co2_ppm),
		"occupants": int(round(float(z.occupants))), "lights_on": bool(z.lights_on), "internal_gain_w": float(z.internal_w),
		"solar_gain_w": float(z.solar_w), "hvac_w": float(z.hvac_w), "outdoor_exchange_m3_s": float(z.outdoor_exchange_m3_s),
		"area_m2": float(z.area_m2), "terminals": ids, "sensor_bias_k": float(z.bias_k)}

func unit_state(ahu_id: String) -> Dictionary:
	var u: Dictionary = units.get(ahu_id, {})
	if u.is_empty(): return {}
	var ui := int(_unit_index[ahu_id])
	var term_ids: Array = []
	var zone_ids_served: Array = []
	for ti in _unit_terms[ui]: term_ids.append(String(_term_list[ti].id))
	for zi in _unit_zones[ui]:
		if not bool(_zone_list[zi].get("dummy", false)): zone_ids_served.append(String(_zone_list[zi].id))
	var state := {"id": ahu_id, "label": String(u.label), "mode": String(u.mode), "capacity_m3_s": float(u.capacity_m3_s),
		"layout": (u.layout as Array).duplicate(), "has_fan": bool(u.has_fan), "fan_running": float(u.fan_feedback) > FAN_PROOF_SPEED,
		"terminals": term_ids, "zones": zone_ids_served,
		"fault": "fan_failure" if bool(u.fan_fault) else ("dirty_filter" if bool(u.filter_fault) else ""),
		"supply_airflow_m3_s": float(u.flow_actual_m3_s), "available_airflow_m3_s": float(u.available_flow_m3_s),
		"duct_pressure_setpoint_pa": float(u.static_sp_pa), "supply_setpoint_c": float(u.sat_sp_c)}
	for key in UNIT_STATE:
		if not state.has(key): state[key] = float(u[key])
	for key in UNIT_FLAGS: state[key] = bool(u[key])
	return state

func terminal_state(vav_id: String) -> Dictionary:
	var t: Dictionary = terminals.get(vav_id, {})
	if t.is_empty(): return {}
	var ti := int(_term_index[vav_id])
	var z: Dictionary = _term_zone[ti]
	var state := {"id": vav_id, "label": String(t.label), "zone_id": String(t.zone_id), "source_id": String(t.source_id),
		"connected": bool(t.connected), "mode": _terminal_mode(ti), "occupied": occupied, "capacity_m3_s": float(t.capacity_m3_s),
		"layout": (t.layout as Array).duplicate(), "space_temp_c": float(z.measured_temp_c), "true_space_temp_c": float(z.true_temp_c),
		"cool_setpoint_c": float(t.active_cool_c), "heat_setpoint_c": float(t.active_heat_c),
		"occ_cool_setpoint_c": float(z.cool_setpoint_c), "occ_heat_setpoint_c": float(z.heat_setpoint_c),
		"airflow_target_m3_s": float(t.flow_sp_m3_s), "airflow_m3_s": float(t.flow_actual_m3_s), "min_airflow_m3_s": float(t.vmin_m3_s),
		"stuck": bool(t.stuck), "co2_ppm": float(z.co2_ppm)}
	for key in TERMINAL_STATE:
		if not state.has(key): state[key] = float(t[key])
	return state

# Which equipment the active fault scenario affects ("" when none).
func fault_targets() -> Dictionary:
	return {"fan_failure": _fault_fan, "dirty_filter": _fault_filter, "stuck_damper": _fault_damper, "sensor_bias": _fault_bias}

# ---------------------------------------------------------------- points

# Rebuilt only when state changed since the last call. The returned array is
# fresh; the point dictionaries are shared with the cache and must be treated
# as read-only (PointStore duplicates what it keeps).
func snapshot_points() -> Array[Dictionary]:
	if _points_revision != _revision:
		_points_cache = _build_points()
		_points_revision = _revision
	return _points_cache.duplicate()

func _build_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stale := scenario == "Data interruption"
	var now := Time.get_unix_time_from_system()
	_quality = [] # one read-only flags array shared by this build's points
	_quality.assign(["stale", "communication_failure"] if stale else ["good"])
	_pt(out, "site.outdoor_temp", _oat + _noise(7, TEMP_NOISE_K), "number", "degC", stale, now)
	_pt(out, "site.occupied", occupied, "bool", "", stale, now)
	_pt(out, "site.solar", _sol[4], "number", "W/m2", stale, now)
	_pt(out, "site.time_of_day", _tod / 3600.0, "number", "h", stale, now)
	for id in zones:
		var z: Dictionary = zones[id]
		_pt(out, id + ".space_temp", float(z.measured_temp_c), "number", "degC", stale, now)
		_pt(out, id + ".co2", float(z.co2_ppm), "number", "ppm", stale, now)
	for id in units:
		var u: Dictionary = units[id]
		var sd := int(u.seed)
		var flow := float(u.flow_actual_m3_s)
		var run := float(u.fan_feedback) > FAN_PROOF_SPEED
		_pt(out, id + ".fan_enable_cmd", bool(u.enabled), "bool", "", stale, now)
		_pt(out, id + ".fan_run_feedback", run, "bool", "", stale, now)
		_pt(out, id + ".fan_state", "Running" if run else "Off", "enum", "", stale, now)
		_pt(out, id + ".fan_speed_command", float(u.fan_command), "number", "fraction", stale, now)
		_pt(out, id + ".fan_speed_feedback", float(u.fan_feedback), "number", "fraction", stale, now)
		_pt(out, id + ".damper_command", float(u.damper_command) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".damper_feedback", float(u.damper_feedback) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".cooling_command", float(u.cooling_command) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".cooling_output", float(u.cooling_output) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".heating_command", float(u.heating_command) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".heating_output", float(u.heating_output) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".return_air_temp", float(u.return_temp_c) + _noise(sd + 17, TEMP_NOISE_K), "number", "degC", stale, now)
		_pt(out, id + ".mixed_air_temp", float(u.mixed_temp_c) + _noise(sd + 13, TEMP_NOISE_K), "number", "degC", stale, now)
		_pt(out, id + ".outdoor_air_fraction", float(u.oa_fraction) * 100.0 if flow > 0.001 else 0.0, "number", "%", stale, now)
		_pt(out, id + ".supply_air_temp", float(u.supply_temp_c) + _noise(sd + 11, SAT_NOISE_K), "number", "degC", stale, now)
		_pt(out, id + ".supply_setpoint", float(u.sat_sp_c), "number", "degC", stale, now)
		_pt(out, id + ".supply_airflow", flow * (1.0 + _noise(sd + 23, FLOW_NOISE)), "number", "m3/s", stale, now)
		_pt(out, id + ".available_airflow", float(u.available_flow_m3_s), "number", "m3/s", stale, now)
		_pt(out, id + ".duct_pressure", maxf(0.0, float(u.duct_pressure_pa) + (_noise(sd + 19, STATIC_NOISE_PA) if run else 0.0)), "number", "Pa", stale, now)
		_pt(out, id + ".duct_pressure_setpoint", float(u.static_sp_pa), "number", "Pa", stale, now)
		_pt(out, id + ".filter_pressure_drop", float(u.filter_dp_pa), "number", "Pa", stale, now)
		_pt(out, id + ".cooling_power", float(u.cooling_w), "number", "W", stale, now)
		_pt(out, id + ".heating_power", float(u.heating_w), "number", "W", stale, now)
		_pt(out, id + ".fan_power", float(u.fan_w), "number", "W", stale, now)
		_pt(out, id + ".economizer", bool(u.economizer), "bool", "", stale, now)
		_pt(out, id + ".mode", String(u.mode), "enum", "", stale, now)
	for ti in range(_term_list.size()):
		var t: Dictionary = _term_list[ti]
		var z: Dictionary = _term_zone[ti]
		var id := String(t.id)
		var sd := int(t.seed)
		_pt(out, id + ".space_temp", float(z.measured_temp_c), "number", "degC", stale, now)
		_pt(out, id + ".true_space_temp", float(z.true_temp_c), "number", "degC", stale, now)
		_pt(out, id + ".cool_setpoint", float(t.active_cool_c), "number", "degC", stale, now)
		_pt(out, id + ".heat_setpoint", float(t.active_heat_c), "number", "degC", stale, now)
		_pt(out, id + ".occ_cool_setpoint", float(z.cool_setpoint_c), "number", "degC", stale, now)
		_pt(out, id + ".occ_heat_setpoint", float(z.heat_setpoint_c), "number", "degC", stale, now)
		_pt(out, id + ".discharge_temp", float(t.discharge_temp_c) + _noise(sd + 31, TEMP_NOISE_K), "number", "degC", stale, now)
		_pt(out, id + ".airflow_target", float(t.flow_sp_m3_s), "number", "m3/s", stale, now)
		_pt(out, id + ".airflow", float(t.flow_actual_m3_s) * (1.0 + _noise(sd + 29, FLOW_NOISE)), "number", "m3/s", stale, now)
		_pt(out, id + ".damper_command", float(t.damper_command) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".damper_feedback", float(t.damper_feedback) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".reheat_command", float(t.reheat_command) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".reheat_output", float(t.reheat_output) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".cooling_command", float(t.cooling_command) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".cooling_output", float(t.cooling_output) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".cooling_loop", float(t.cooling_loop) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".heating_loop", float(t.heating_loop) * 100.0, "number", "%", stale, now)
		_pt(out, id + ".heating_power", float(t.heating_w), "number", "W", stale, now)
		_pt(out, id + ".mode", _terminal_mode(ti), "enum", "", stale, now)
		_pt(out, id + ".occupied", occupied, "bool", "", stale, now)
	for id in route_flows: _pt(out, String(id) + ".airflow", float(route_flows[id]), "number", "m3/s", stale, now)
	return out

func _pt(out: Array[Dictionary], id: String, value: Variant, value_type: String, unit: String, stale: bool, now: float) -> void:
	out.append({"point_id": id, "value": value, "value_type": value_type, "unit": unit, "source_id": "demo", "quality_flags": _quality,
		"source_timestamp": sim_seconds, "received_at": now, "original_status": "communication_failure" if stale else "ok"})

# ---------------------------------------------------------------- checkpoint

func checkpoint() -> Dictionary:
	var real: Dictionary = {}
	for id in zones: real[id] = _save_record(zones[id], ZONE_STATE, false)
	var dummy: Dictionary = {}
	for id in _dummy: dummy[id] = _save_record(_dummy[id], ZONE_STATE, false)
	var ahus: Dictionary = {}
	for id in units: ahus[id] = _save_record(units[id], UNIT_STATE, true)
	var vavs: Dictionary = {}
	for id in terminals: vavs[id] = _save_record(terminals[id], TERMINAL_STATE, false)
	return {"version": 3, "sim_seconds": sim_seconds, "scenario": scenario, "accumulator": accumulator, "running": running, "speed": speed,
		"step_index": float(_step_index), "steps_since_reset": float(_steps_since_reset),
		"zones": real, "dummy_zones": dummy, "units": ahus, "terminals": vavs, "openings": _openings.duplicate(true)}

# Defensive: unknown ids/fields and invalid values are ignored, numbers are
# clamped. State for ids not configured yet is kept and applied when they
# appear, so restore before or after configure() both work. Version-2 saves
# ("rooms") restore zone temperatures and setpoints.
func restore_checkpoint(state: Dictionary) -> void:
	if state.is_empty(): return
	sim_seconds = _num(state.get("sim_seconds"), sim_seconds, 0.0, 1.0e9)
	var saved_scenario: Variant = state.get("scenario")
	if saved_scenario is String and saved_scenario in SCENARIOS: scenario = saved_scenario
	accumulator = _num(state.get("accumulator"), 0.0, 0.0, STEP_SECONDS * 0.999999)
	if state.get("running") is bool: running = state.running
	speed = _num(state.get("speed"), speed, 0.0, 60.0)
	_step_index = int(_num(state.get("step_index"), round(sim_seconds), 0.0, 1.0e12))
	_steps_since_reset = int(_num(state.get("steps_since_reset"), 1.0, 0.0, 1.0e12))
	_restore_group(state.get("rooms"), zones, ZONE_STATE, false, "zones")
	_restore_group(state.get("zones"), zones, ZONE_STATE, false, "zones")
	_restore_group(state.get("dummy_zones"), _dummy, ZONE_STATE, false, "dummy_zones")
	_restore_group(state.get("units"), units, UNIT_STATE, true, "units")
	_restore_group(state.get("terminals"), terminals, TERMINAL_STATE, false, "terminals")
	if state.get("openings") is Array: set_open_connections(state.openings)
	_update_environment(false)
	_after_state_change()

func _save_record(record: Dictionary, keys: Dictionary, unit: bool) -> Dictionary:
	var out: Dictionary = {}
	for key in keys: out[key] = float(record[key])
	if unit:
		for key in UNIT_FLAGS: out[key] = bool(record[key])
		out.mode = String(record.mode)
	return out

func _restore_group(source: Variant, target: Dictionary, keys: Dictionary, unit: bool, stash_key: String) -> void:
	if not source is Dictionary: return
	var stash: Dictionary = _stash[stash_key]
	for id in source:
		if not (id is String or id is StringName) or not source[id] is Dictionary: continue
		var clean := _sanitize(source[id], keys, unit)
		if clean.is_empty(): continue
		if target.has(String(id)): _apply_state(target[String(id)], clean)
		elif stash.size() < 5000: stash[String(id)] = clean

func _sanitize(record: Dictionary, keys: Dictionary, unit: bool) -> Dictionary:
	var out: Dictionary = {}
	for key in keys:
		if not record.has(key): continue
		var value: Variant = record[key]
		if (value is float or value is int) and is_finite(float(value)):
			var bounds: Array = keys[key]
			out[key] = clampf(float(value), float(bounds[0]), float(bounds[1]))
	if unit:
		for key in UNIT_FLAGS:
			if record.get(key) is bool: out[key] = record[key]
		if record.get("mode") is String and record.mode in UNIT_MODES: out.mode = record.mode
	if out.has("lights_override"): out.lights_override = clampf(round(float(out.lights_override)), -1.0, 1.0)
	return out

func _apply_state(record: Dictionary, clean: Dictionary) -> void:
	for key in clean: record[key] = clean[key]
	if clean.has("true_temp_c") and not clean.has("mass_temp_c"): record.mass_temp_c = clean.true_temp_c # older saves
	if record.has("cool_setpoint_c") and record.has("heat_setpoint_c"):
		record.heat_setpoint_c = minf(float(record.heat_setpoint_c), float(record.cool_setpoint_c) - MIN_DEADBAND_K)

# ---------------------------------------------------------------- step

func _step() -> void:
	var dt := STEP_SECONDS
	sim_seconds += dt
	_step_index += 1
	_steps_since_reset += 1
	_update_environment(true)
	_decide_unit_modes(dt)
	_control_terminals(dt)
	_control_units(dt)
	_solve_airflow()
	_unit_air(dt)
	_terminal_air(dt)
	_zone_heat(dt)
	_refresh_routes()
	_publish_aliases()
	_revision += 1

func _update_environment(sweep: bool) -> void:
	_tod = fposmod(sim_seconds, DAY_S)
	var row: Array = WEATHER.get(scenario, WEATHER["Normal weekday"])
	var hour := _tod / 3600.0
	# Asymmetric diurnal dry bulb: minimum 05:30, maximum 15:00.
	var f := 0.0
	if hour >= 5.5 and hour <= 15.0: f = 0.5 - 0.5 * cos(PI * (hour - 5.5) / 9.5)
	else: f = 0.5 + 0.5 * cos(PI * (hour - 15.0 if hour > 15.0 else hour + 9.0) / 14.5)
	_oat = float(row[0]) + (float(row[1]) - float(row[0])) * f
	# Sun from 06:30 (east) through south at 13:00 to 19:30 (west).
	var x := (hour - 6.5) / 13.0
	for i in range(5): _sol[i] = 0.0
	if x > 0.0 and x < 1.0:
		var clear := float(row[2])
		var elevation := deg_to_rad(float(row[3])) * sin(PI * x)
		var s := sin(elevation)
		var beam := 880.0 * clear * clear * pow(s, 0.3)
		var sky := s * (70.0 + 180.0 * (1.0 - clear))
		var horizontal := beam * s + sky
		var vertical_beam := beam * cos(elevation)
		var diffuse := 0.5 * sky + 0.1 * horizontal # half the sky dome + 0.2 ground albedo
		var azimuth := PI * x
		_sol[0] = diffuse
		_sol[1] = diffuse + vertical_beam * maxf(0.0, cos(azimuth))
		_sol[2] = diffuse + vertical_beam * maxf(0.0, sin(azimuth))
		_sol[3] = diffuse + vertical_beam * maxf(0.0, -cos(azimuth))
		_sol[4] = horizontal
	var occ := scenario != "Unoccupied" and _tod >= OCCUPIED_START_S and _tod < OCCUPIED_END_S
	if sweep and occ != occupied:
		for z in _zone_list: z.lights_override = -1.0
	occupied = occ
	for key in PROFILES: _profile_now[key] = _profile(PROFILES[key], hour) if occ else 0.0
	outdoor_temp_c = _oat
	solar_w_m2 = _sol[4]

func _decide_unit_modes(dt: float) -> void:
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var old := String(u.mode)
		var mode := _unit_mode(u, ui, old)
		if mode == old: u.mode_timer_s = minf(float(u.mode_timer_s) + dt, 1.0e9)
		else:
			u.mode = mode
			u.mode_timer_s = 0.0

func _unit_mode(u: Dictionary, ui: int, old: String) -> String:
	if not bool(u.has_fan): return "Off"
	if occupied: return "Occupied"
	var served: PackedInt32Array = _unit_zones[ui]
	var can_heat := bool(u.can_heat)
	var can_cool := bool(u.can_cool) or (bool(u.has_damper) and _oat < float(u.return_temp_c) - 2.0)
	# Optimal start: begin early enough to reach occupied setpoints by 07:00.
	if scenario != "Unoccupied" and _tod >= OPTIMAL_START_EARLIEST_S and _tod < OCCUPIED_START_S:
		if old == "Warm-up" or old == "Cool-down": return old
		var need_heat := 0.0
		var need_cool := 0.0
		for zi in served:
			var z: Dictionary = _zone_list[zi]
			need_heat = maxf(need_heat, float(z.heat_setpoint_c) - float(z.measured_temp_c))
			need_cool = maxf(need_cool, float(z.measured_temp_c) - float(z.cool_setpoint_c))
		var to_go := OCCUPIED_START_S - _tod
		if can_heat and need_heat > 0.2 and need_heat >= need_cool and to_go <= _lead(need_heat): return "Warm-up"
		if can_cool and need_cool > 0.2 and to_go <= _lead(need_cool): return "Cool-down"
	# Night cycle against the unoccupied setbacks, with recovery hysteresis.
	if old == "Setback":
		for zi in served:
			if float(_zone_list[zi].measured_temp_c) < UNOCC_HEAT_C + NIGHT_RECOVERY_K * 0.5: return "Setback"
	elif old == "Setup":
		for zi in served:
			if float(_zone_list[zi].measured_temp_c) > UNOCC_COOL_C - NIGHT_RECOVERY_K * 0.5: return "Setup"
	for zi in served:
		var temp := float(_zone_list[zi].measured_temp_c)
		if can_heat and temp < UNOCC_HEAT_C: return "Setback"
		if can_cool and temp > UNOCC_COOL_C: return "Setup"
	return "Off"

func _lead(error_k: float) -> float:
	return clampf(OPTIMAL_START_BASE_S + OPTIMAL_START_PER_K_S * error_k, 0.0, OPTIMAL_START_MAX_S)

# VAV sequence: cooling and heating PI loops on the zone sensor; cooling loop
# raises airflow min -> max; heating loop 0–50 % raises discharge temperature
# at minimum airflow (reheat valve), 50–100 % raises airflow to heating max.
func _control_terminals(dt: float) -> void:
	for ti in range(_term_list.size()):
		var t: Dictionary = _term_list[ti]
		var z: Dictionary = _term_zone[ti]
		var u: Dictionary = _term_unit[ti]
		var mode := String(u.mode) if not u.is_empty() else "Off"
		var meas := float(z.measured_temp_c)
		var csp := UNOCC_COOL_C
		var hsp := UNOCC_HEAT_C
		if occupied or mode == "Warm-up" or mode == "Cool-down":
			csp = float(z.cool_setpoint_c)
			hsp = float(z.heat_setpoint_c)
		elif mode == "Setback": hsp = UNOCC_HEAT_C + NIGHT_RECOVERY_K
		elif mode == "Setup": csp = UNOCC_COOL_C - NIGHT_RECOVERY_K
		t.active_cool_c = csp
		t.active_heat_c = hsp
		var kp := float(t.kp)
		var cool := _pi(t, "cool_i", meas - csp, kp, kp / ZONE_LOOP_TI_S, dt)
		var heat := _pi(t, "heat_i", hsp - meas, kp, kp / ZONE_LOOP_TI_S, dt)
		t.cooling_loop = cool
		t.heating_loop = heat
		var vmax := float(t.capacity_m3_s)
		var unit_running := mode != "Off" and float(u.get("fan_feedback", 0.0)) > 0.05
		var inlet := float(u.supply_temp_c) + DUCT_GAIN_K if unit_running else meas
		var vmin := 0.0
		if mode == "Occupied":
			vmin = VAV_MIN_FRACTION * vmax
			vmin = lerpf(vmin, maxf(vmin, VAV_CO2_MAX_FRACTION * vmax), clampf((float(z.co2_ppm) - VAV_CO2_LOW_PPM) / (VAV_CO2_HIGH_PPM - VAV_CO2_LOW_PPM), 0.0, 1.0))
		var sp := 0.0
		if mode != "Off":
			sp = vmin
			# Warm supply air cannot cool: hold minimum (GL36).
			if cool > 0.0 and inlet <= meas: sp = vmin + cool * (vmax - vmin)
			if heat > 0.0:
				var heat_max := maxf(vmin, VAV_HEAT_MAX_FRACTION * vmax)
				if inlet > meas + 3.0: sp = maxf(sp, vmin + heat * (heat_max - vmin))
				elif bool(t.has_reheat): sp = maxf(sp, vmin + clampf((heat - 0.5) * 2.0, 0.0, 1.0) * (heat_max - vmin))
		t.flow_sp_m3_s = sp
		t.vmin_m3_s = vmin
		# Damper: feedforward from duct static plus an integral trim on flow.
		var cmd := 1.0
		if bool(t.has_damper):
			var trim := float(t.flow_trim)
			if sp <= 0.0:
				cmd = 0.0
				trim = move_toward(trim, 0.0, dt * 0.01)
			else:
				var pressure := float(u.get("duct_pressure_pa", 0.0))
				var full_open := VAV_OVERSIZE * vmax * sqrt(maxf(pressure, 0.0) / DESIGN_STATIC_PA)
				var ff := sp / full_open if full_open > 1.0e-6 else 1.0
				var err := (sp - float(t.flow_actual_m3_s)) / maxf(vmax, 0.001)
				if unit_running:
					var raw := ff + trim
					if not (raw >= 1.0 and err > 0.0) and not (raw <= 0.0 and err < 0.0):
						trim = clampf(trim + FLOW_TRIM_KI * err * dt, FLOW_TRIM_MIN, FLOW_TRIM_MAX)
				else: trim = move_toward(trim, 0.0, dt * 0.01)
				cmd = clampf(ff + trim, 0.0, 1.0)
			t.flow_trim = trim
		t.damper_command = cmd
		t.damper_feedback = STUCK_DAMPER if bool(t.stuck) else _actuate(float(t.damper_feedback), cmd, dt / VAV_DAMPER_STROKE_S)
		# Reheat valve positioned for the discharge-air setpoint; needs airflow.
		var flow := float(t.flow_actual_m3_s)
		var proven := unit_running and flow > maxf(0.003, 0.05 * vmax)
		var rh := 0.0
		if bool(t.has_reheat) and proven and heat > 0.0:
			var dat_max := minf(meas + DAT_OVER_SPACE_K, DAT_MAX_C)
			var dat_sp := lerpf(inlet, maxf(dat_max, inlet), clampf(heat * 2.0, 0.0, 1.0))
			var capacity := _reheat_capacity(t, flow, inlet)
			rh = clampf((dat_sp - inlet) / capacity, 0.0, 1.0) if capacity > 0.01 else 0.0
		t.reheat_command = rh
		t.reheat_output = _actuate(float(t.reheat_output), rh, dt / VALVE_STROKE_S)
		var cc := 0.0
		if bool(t.has_cooling) and proven and cool > 0.0:
			cc = cool if inlet > meas - 0.5 else clampf((cool - 0.5) * 2.0, 0.0, 1.0)
		t.cooling_command = cc
		t.cooling_output = _actuate(float(t.cooling_output), cc, dt / VALVE_STROKE_S)

func _reheat_capacity(t: Dictionary, flow: float, inlet: float) -> float:
	var vmax := float(t.capacity_m3_s)
	var design_w := RHO_CP * VAV_HEAT_MAX_FRACTION * vmax * REHEAT_DESIGN_RISE_K
	return minf(design_w / (RHO_CP * maxf(flow, 0.02 * vmax + 0.001)), maxf(HW_C - inlet, 0.0) * REHEAT_EFFECTIVENESS)

# AHU: fan VFD on duct static; OA damper minimum/DCV; SAT loop split
# heating coil (−100..0) | economizer damper (0..50) | cooling valve (50..100);
# without an enabled economizer the cooling valve takes the whole 0..100.
func _control_units(dt: float) -> void:
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var mode := String(u.mode)
		var enable := mode != "Off" and bool(u.has_fan)
		if enable and not bool(u.enabled):
			u.static_i = 0.0
			u.static_sp_pa = STATIC_SP_INIT_PA
			u.sat_tr_c = SAT_MAX_C
			u.tr_timer_s = 0.0
			u.sat_i = 0.0
		u.enabled = enable
		var sd := int(u.seed)
		var cmd := 0.0
		if enable:
			var sp := float(u.static_sp_pa)
			var err := (sp - (float(u.duct_pressure_pa) + _noise(sd + 19, STATIC_NOISE_PA))) / sp
			var integral := float(u.static_i)
			var p := STATIC_KP * err
			var raw := FAN_MIN_SPEED + p + integral
			if not (raw >= 1.0 and err > 0.0) and not (raw <= FAN_MIN_SPEED and err < 0.0):
				integral = clampf(integral + STATIC_KI * err * dt, 0.0, 1.0 - FAN_MIN_SPEED)
			u.static_i = integral
			cmd = clampf(FAN_MIN_SPEED + p + integral, FAN_MIN_SPEED, 1.0)
		else: u.static_i = 0.0
		u.fan_command = cmd
		var fb := float(u.fan_feedback)
		if bool(u.fan_fault):
			fb *= exp(-dt / FAN_COAST_TAU_S)
			if fb < 0.002: fb = 0.0
		else: fb = move_toward(fb, cmd, dt / FAN_RAMP_S)
		u.fan_feedback = fb
		var run := fb > FAN_PROOF_SPEED
		u.run_timer_s = minf(float(u.run_timer_s) + dt, 3600.0) if run else 0.0
		var proven := run and float(u.run_timer_s) >= FAN_PROOF_DELAY_S
		u.fan_proven = proven
		_control_air_side(u, ui, mode, proven, dt)

func _control_air_side(u: Dictionary, ui: int, mode: String, proven: bool, dt: float) -> void:
	var econ := false
	var oa_min := 0.0
	var sat_sp := float(u.sat_sp_c)
	if proven:
		if mode == "Occupied" and bool(u.has_damper):
			oa_min = OA_MIN_POSITION + (DCV_MAX_POSITION - OA_MIN_POSITION) * clampf((_max_co2(ui) - DCV_LOW_PPM) / (DCV_HIGH_PPM - DCV_LOW_PPM), 0.0, 1.0)
		if bool(u.has_damper) and (mode == "Occupied" or mode == "Cool-down" or mode == "Setup"):
			var limit := minf(ECON_HIGH_LIMIT_C, float(u.return_temp_c))
			econ = _oat < limit if bool(u.economizer) else _oat < limit - ECON_DEADBAND_K
		if float(u.mode_timer_s) >= TR_DELAY_S:
			u.tr_timer_s = float(u.tr_timer_s) + dt
			if float(u.tr_timer_s) >= TR_INTERVAL_S:
				u.tr_timer_s = 0.0
				_trim_respond(u, ui, mode)
		match mode:
			"Occupied": sat_sp = lerpf(float(u.sat_tr_c), SAT_MIN_C, clampf((_oat - SAT_RESET_OAT_LOW_C) / (SAT_RESET_OAT_HIGH_C - SAT_RESET_OAT_LOW_C), 0.0, 1.0))
			"Cool-down", "Setup": sat_sp = SAT_MIN_C
			"Warm-up", "Setback": sat_sp = SAT_WARMUP_C
	u.sat_sp_c = sat_sp
	u.oa_min = oa_min
	# Bumpless economizer enable/disable: keep the cooling valve where it is.
	var out := float(u.sat_u)
	if econ != bool(u.economizer):
		var shifted := out
		if econ and out > 0.0: shifted = 50.0 + 0.5 * out
		elif not econ and out > 50.0: shifted = (out - 50.0) * 2.0
		elif not econ and out > 0.0: shifted = 0.0
		u.sat_i = float(u.sat_i) + shifted - out
		out = shifted
	u.economizer = econ
	var damper := 0.0
	var cool := 0.0
	var heat := 0.0
	if proven:
		var lo := -100.0 if bool(u.has_heating) else 0.0
		var hi := 100.0 if bool(u.has_cooling) else (50.0 if econ else 0.0)
		var err := float(u.supply_temp_c) + _noise(int(u.seed) + 11, SAT_NOISE_K) - sat_sp
		var p := SAT_KP * err
		var integral := float(u.sat_i)
		var raw := p + integral
		if not (raw >= hi and err > 0.0) and not (raw <= lo and err < 0.0):
			integral += SAT_KP / SAT_TI_S * err * dt
		integral = clampf(integral, lo, hi)
		u.sat_i = integral
		out = clampf(p + integral, lo, hi)
		if econ:
			damper = oa_min + (1.0 - oa_min) * clampf(out / 50.0, 0.0, 1.0)
			cool = clampf((out - 50.0) / 50.0, 0.0, 1.0)
		else:
			damper = oa_min
			cool = clampf(out / 100.0, 0.0, 1.0)
		if not bool(u.has_cooling): cool = 0.0
		heat = clampf(-out / 100.0, 0.0, 1.0) if bool(u.has_heating) else 0.0
	else:
		u.sat_i = 0.0
		out = 0.0
	u.sat_u = out
	if not bool(u.has_damper): damper = 0.0
	u.damper_command = damper
	u.cooling_command = cool
	u.heating_command = heat
	u.damper_feedback = _actuate(float(u.damper_feedback), damper, dt / OA_DAMPER_STROKE_S)
	u.cooling_output = _actuate(float(u.cooling_output), cool, dt / VALVE_STROKE_S)
	u.heating_output = _actuate(float(u.heating_output), heat, dt / VALVE_STROKE_S)

# GL36-style trim & respond for SAT (cooling requests) and duct static
# (pressure requests: VAV dampers nearly wide open).
func _trim_respond(u: Dictionary, ui: int, mode: String) -> void:
	var idxs: PackedInt32Array = _unit_terms[ui]
	var n := idxs.size()
	if n == 0: return
	var ignores := 0 if n <= 4 else (1 if n <= 10 else 2)
	var sat_requests := 0
	var sp_requests := 0
	for ti in idxs:
		var t: Dictionary = _term_list[ti]
		var over := float(_term_zone[ti].measured_temp_c) - float(t.active_cool_c)
		if over > 3.0: sat_requests += 3
		elif over > 1.5: sat_requests += 2
		elif float(t.cooling_loop) > 0.95: sat_requests += 1
		if float(t.flow_sp_m3_s) > 0.0 and float(t.damper_command) > 0.95:
			sp_requests += 2 if float(t.flow_actual_m3_s) < 0.7 * float(t.flow_sp_m3_s) else 1
	if mode == "Occupied":
		if sat_requests > ignores: u.sat_tr_c = maxf(SAT_MIN_C, float(u.sat_tr_c) - minf(SAT_TR_RESPOND_K * (sat_requests - ignores), SAT_TR_RESPOND_MAX_K))
		else: u.sat_tr_c = minf(SAT_MAX_C, float(u.sat_tr_c) + SAT_TR_TRIM_K)
	if sp_requests > ignores: u.static_sp_pa = minf(STATIC_SP_MAX_PA, float(u.static_sp_pa) + minf(STATIC_RESPOND_PA * (sp_requests - ignores), STATIC_RESPOND_MAX_PA))
	else: u.static_sp_pa = maxf(STATIC_SP_MIN_PA, float(u.static_sp_pa) - STATIC_TRIM_PA)

# Duct airflow. Per AHU, closed form of fan curve = internal + duct losses +
# static, with VAV boxes as orifices Q_i = k_i·√P. Then terminal capacity, AHU
# availability and shared duct/fitting limits (monotone reductions, so every
# limit holds after the pass). AHU supply = Σ delivered terminal flow.
func _solve_airflow() -> void:
	_q.fill(0.0)
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var idxs: PackedInt32Array = _unit_terms[ui]
		var n := float(u.fan_feedback) if bool(u.has_fan) else 0.0
		var qd := maxf(float(u.capacity_m3_s), 0.001)
		var b := _unit_resistance_pa(u) / (qd * qd)
		_unit_b[ui] = b
		var avail := 0.0
		if n > 0.001 and float(u.capacity_m3_s) > 0.001:
			avail = n * minf(qd, sqrt(FAN_SHUTOFF_PA / b))
			var ktot := 0.0
			for ti in idxs:
				var t: Dictionary = _term_list[ti]
				var k := VAV_OVERSIZE * float(t.capacity_m3_s) * _opening(t) / sqrt(DESIGN_STATIC_PA)
				_q[ti] = k
				ktot += k
			if ktot > 1.0e-9:
				var root_p := n * sqrt(FAN_SHUTOFF_PA / (1.0 / (ktot * ktot) + b)) / ktot
				var total := 0.0
				for ti in idxs:
					var q := minf(_q[ti] * root_p, float(_term_list[ti].capacity_m3_s))
					_q[ti] = q
					total += q
				if total > avail and total > 0.0:
					var f := avail / total
					for ti in idxs: _q[ti] *= f
		else:
			for ti in idxs: _q[ti] = 0.0
		u.available_flow_m3_s = avail
	for limit in _limits: _apply_limit(limit, 0.0)
	for ti in range(_term_list.size()): _term_list[ti].flow_actual_m3_s = _q[ti]
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var total := 0.0
		for ti in _unit_terms[ui]: total += _q[ti]
		u.flow_actual_m3_s = total
		var n := float(u.fan_feedback) if bool(u.has_fan) else 0.0
		var qd := maxf(float(u.capacity_m3_s), 0.001)
		if n > 0.001:
			u.duct_pressure_pa = maxf(0.0, FAN_SHUTOFF_PA * n * n - _unit_b[ui] * total * total)
			u.fan_total_pa = maxf(0.0, FAN_SHUTOFF_PA * n * n - FAN_DROOP_PA * (total / qd) * (total / qd))
		else:
			u.duct_pressure_pa = 0.0
			u.fan_total_pa = 0.0

func _apply_limit(limit: Array, tolerance: float) -> void:
	var cap := float(limit[0])
	var idx: PackedInt32Array = limit[1]
	var w: PackedFloat64Array = limit[2]
	var total := 0.0
	for k in range(idx.size()): total += _q[idx[k]] * w[k]
	if total > cap * (1.0 + tolerance) and total > 1.0e-12:
		var f := cap / total
		for k in range(idx.size()): _q[idx[k]] *= f

func _opening(t: Dictionary) -> float:
	return float(t.damper_feedback) if bool(t.has_damper) else 1.0

func _unit_resistance_pa(u: Dictionary) -> float:
	var r := FAN_DROOP_PA + CASING_PA + DUCT_LOSS_PA
	if bool(u.has_damper): r += DAMPER_PA
	if bool(u.has_cooling): r += COOL_COIL_PA
	if bool(u.has_heating): r += HEAT_COIL_PA
	if bool(u.has_filter): r += FILTER_DIRTY_PA if bool(u.filter_fault) else float(u.filter_loading_pa)
	return r

# AHU air: return (flow weighted + plenum), mixing by OA damper position, then
# the installed components in airflow order; coils have leaving-air limits.
func _unit_air(dt: float) -> void:
	var a_rat := 1.0 - exp(-dt / RAT_TAU_S)
	var a_mat := 1.0 - exp(-dt / MAT_TAU_S)
	var a_sat := 1.0 - exp(-dt / SAT_TAU_S)
	var a_off := 1.0 - exp(-dt / SAT_OFF_TAU_S)
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var flow := float(u.flow_actual_m3_s)
		var qd := maxf(float(u.capacity_m3_s), 0.001)
		var sum_q := 0.0
		var sum_t := 0.0
		var sum_c := 0.0
		for ti in _unit_terms[ui]:
			var q := _q[ti]
			sum_q += q
			sum_t += q * float(_term_zone[ti].true_temp_c)
			sum_c += q * float(_term_zone[ti].co2_ppm)
		var rat := float(u.return_temp_c)
		var co2_ret := float(u.co2_return_ppm)
		if sum_q > 1.0e-4:
			rat = sum_t / sum_q + PLENUM_GAIN_K
			co2_ret = sum_c / sum_q
		else:
			var served: PackedInt32Array = _unit_zones[ui]
			if not served.is_empty():
				var t_avg := 0.0
				var c_avg := 0.0
				for zi in served:
					t_avg += float(_zone_list[zi].true_temp_c)
					c_avg += float(_zone_list[zi].co2_ppm)
				rat = t_avg / served.size()
				co2_ret = c_avg / served.size()
		u.return_temp_c = lerpf(float(u.return_temp_c), rat, a_rat)
		u.co2_return_ppm = co2_ret
		var oaf := float(u.damper_feedback) if bool(u.has_damper) else 0.0
		var mat := oaf * _oat + (1.0 - oaf) * float(u.return_temp_c)
		u.mixed_temp_c = lerpf(float(u.mixed_temp_c), mat, a_mat)
		var n := float(u.fan_feedback)
		var fan_running := n > 0.05
		var d_cool := 0.0
		var d_heat := 0.0
		if fan_running:
			var coil_flow := maxf(flow, 0.05 * qd) # casing leakage keeps air over the coils
			var temp := mat
			for role in u.roles:
				match String(role):
					"cooling_coil":
						# Leaving air can approach, never reach, the chilled water.
						var effectiveness := COOL_COIL_EFFECTIVENESS - 0.13 * clampf(coil_flow / qd, 0.0, 1.2)
						d_cool = float(u.cooling_output) * effectiveness * maxf(temp - CHW_C, 0.0)
						temp -= d_cool
					"heating_coil":
						d_heat = float(u.heating_output) * maxf(HW_C - temp, 0.0) * HEAT_COIL_EFFECTIVENESS
						temp += d_heat
					"fan":
						temp += float(u.fan_total_pa) / (FAN_EFFICIENCY * RHO_CP)
			u.supply_temp_c = lerpf(float(u.supply_temp_c), temp, a_sat)
			u.fan_w = float(u.fan_total_pa) * maxf(flow, 0.2 * n * qd) / FAN_EFFICIENCY
		else:
			u.supply_temp_c = lerpf(float(u.supply_temp_c), float(u.return_temp_c), a_off)
			u.fan_w = 0.0
		u.cooling_w = RHO_CP * flow * d_cool
		u.heating_w = RHO_CP * flow * d_heat
		u.oa_fraction = oaf if fan_running else 0.0
		u.co2_supply_ppm = (oaf * OUTDOOR_CO2_PPM + (1.0 - oaf) * co2_ret) if fan_running else co2_ret
		var ratio := flow / qd
		if bool(u.has_filter):
			u.filter_loading_pa = minf(FILTER_DIRTY_PA, float(u.filter_loading_pa) + FILTER_LOADING_PA_PER_H / 3600.0 * ratio * ratio * dt)
			u.filter_dp_pa = (FILTER_DIRTY_PA if bool(u.filter_fault) else float(u.filter_loading_pa)) * ratio * ratio
		else: u.filter_dp_pa = 0.0
		if fan_running: u.runtime_s = float(u.runtime_s) + dt

func _terminal_air(dt: float) -> void:
	var a_on := 1.0 - exp(-dt / DAT_TAU_S)
	var a_off := 1.0 - exp(-dt / DAT_OFF_TAU_S)
	for ti in range(_term_list.size()):
		var t: Dictionary = _term_list[ti]
		var q := _q[ti]
		var d_heat := 0.0
		var d_cool := 0.0
		if q > 0.002:
			var inlet := float(_term_unit[ti].supply_temp_c) + DUCT_GAIN_K
			if bool(t.has_reheat): d_heat = float(t.reheat_output) * _reheat_capacity(t, q, inlet)
			if bool(t.has_cooling): d_cool = float(t.cooling_output) * maxf(inlet - TERMINAL_COIL_MIN_C, 0.0) * 0.8
			t.discharge_temp_c = lerpf(float(t.discharge_temp_c), inlet + d_heat - d_cool, a_on)
		else:
			t.discharge_temp_c = lerpf(float(t.discharge_temp_c), float(_term_zone[ti].true_temp_c), a_off)
		t.heating_w = RHO_CP * q * d_heat
		t.cooling_w = RHO_CP * q * d_cool

# Zone heat balance, two nodes each integrated exponentially (stable for any
# step; coupled terms use the previous step): air <- windows, outdoor air
# (infiltration, open doors/windows), supply air, partitions and open interior
# doors, convective gains; mass <- sol-air walls/roof, radiant gains.
func _zone_heat(dt: float) -> void:
	var count := _zone_list.size()
	for zi in range(count):
		_prev_t[zi] = float(_zone_list[zi].true_temp_c)
		_prev_c[zi] = float(_zone_list[zi].co2_ppm)
	var t_roof := _oat + ROOF_ABSORPTANCE * _sol[4] / OUTSIDE_FILM_W_M2K
	var t_wall := _oat + WALL_ABSORPTANCE * (_sol[0] + _sol[1] + _sol[2] + _sol[3]) * 0.25 / OUTSIDE_FILM_W_M2K
	for zi in range(count):
		var z: Dictionary = _zone_list[zi]
		var tz := _prev_t[zi]
		var tm := float(z.mass_temp_c)
		var g_am := float(z.g_mass_w_k)
		var ua_window := float(z.ua_window_w_k)
		var g := g_am + ua_window
		var gt := g_am * tm + ua_window * _oat
		var rise := sqrt(absf(tz - _oat))
		var q_out := float(z.inf_m3_s) + _open_doors[zi] * (DOOR_EXCHANGE_M3_S + DOOR_BUOYANCY * rise) + _open_windows[zi] * (WINDOW_EXCHANGE_M3_S + WINDOW_BUOYANCY * rise)
		g += RHO_CP * q_out
		gt += RHO_CP * q_out * _oat
		var q_air := q_out
		var co2_in := q_out * OUTDOOR_CO2_PPM
		var q_sup := 0.0
		var qt_sup := 0.0
		for ti in _zone_terms[zi]:
			var q := _q[ti]
			if q <= 0.0: continue
			var dat := float(_term_list[ti].discharge_temp_c)
			g += RHO_CP * q
			gt += RHO_CP * q * dat
			q_sup += q
			qt_sup += q * dat
			q_air += q
			co2_in += q * float(_term_unit[ti].co2_supply_ppm)
		for pair in _neighbours[zi]:
			var gw := float(pair[1])
			g += gw
			gt += gw * _prev_t[int(pair[0])]
		for pair in _open_int[zi]:
			var j := int(pair[0])
			var qm := (DOOR_MIX_M3_S + DOOR_MIX_BUOYANCY * sqrt(absf(tz - _prev_t[j]))) if bool(pair[1]) else WINDOW_MIX_M3_S
			g += RHO_CP * qm
			gt += RHO_CP * qm * _prev_t[j]
			q_air += qm
			co2_in += qm * _prev_c[j]
		var people := float(z.people_max) * float(_profile_now.get(z.profile, 0.0))
		var override := float(z.lights_override)
		var lights_on := override > 0.5 or (override < -0.5 and occupied and bool(z.lights_default))
		var people_w := people * float(z.person_w)
		var lights_w := float(z.lights_w) if lights_on else 0.0
		var plug_w := float(z.plug_w) * (1.0 if occupied else float(z.plug_night))
		var solar := float(z.aperture_n) * _sol[0] + float(z.aperture_e) * _sol[1] + float(z.aperture_s) * _sol[2] + float(z.aperture_w) * _sol[3]
		var radiant := SOLAR_RADIANT * solar + PEOPLE_RADIANT * people_w + LIGHTS_RADIANT * lights_w + PLUG_RADIANT * plug_w
		var internal := people_w + lights_w + plug_w
		var t_eq := (gt + internal + solar - radiant) / g
		var tn := t_eq + (tz - t_eq) * exp(-g * dt / float(z.c_air_j_k))
		var ua_wall := float(z.ua_wall_w_k)
		var ua_roof := float(z.ua_roof_w_k)
		var gm := g_am + ua_wall + ua_roof
		var m_eq := (g_am * tz + ua_wall * t_wall + ua_roof * t_roof + radiant) / gm
		z.mass_temp_c = m_eq + (tm - m_eq) * exp(-gm * dt / float(z.c_mass_j_k))
		z.true_temp_c = tn
		var c_eq := (co2_in + people * float(z.co2_per_person)) / q_air
		z.co2_ppm = c_eq + (_prev_c[zi] - c_eq) * exp(-q_air * dt / float(z.volume_m3))
		z.measured_temp_c = tn + float(z.bias_k) + _noise(int(z.seed), ZONE_NOISE_K)
		z.internal_w = internal
		z.solar_w = solar
		z.occupants = people
		z.lights_on = lights_on
		z.hvac_w = RHO_CP * (qt_sup - q_sup * tn)
		z.supply_airflow_m3_s = q_sup
		z.supply_temp_c = qt_sup / q_sup if q_sup > 1.0e-6 else tn
		z.outdoor_exchange_m3_s = q_out

func _refresh_routes() -> void:
	for route in _routes:
		var idx: PackedInt32Array = route[1]
		var w: PackedFloat64Array = route[2]
		var flow := 0.0
		for k in range(idx.size()): flow += _q[idx[k]] * w[k]
		route_flows[route[0]] = flow

func _publish_aliases() -> void:
	if _unit_list.is_empty():
		fan_feedback = 0.0
		available_flow_m3_s = 0.0
		return
	var u: Dictionary = _unit_list[0]
	fan_feedback = float(u.fan_feedback)
	supply_temp_c = float(u.supply_temp_c)
	available_flow_m3_s = float(u.available_flow_m3_s)

# ---------------------------------------------------------------- helpers: control

func _pi(record: Dictionary, key: String, err: float, kp: float, ki: float, dt: float) -> float:
	var integral := float(record[key])
	var p := kp * err
	if not (p + integral >= 1.0 and err > 0.0): integral = clampf(integral + ki * err * dt, 0.0, 1.0)
	record[key] = integral
	return clampf(p + integral, 0.0, 1.0)

# Rate-limited actuator with a small deadband; end stops are always reached.
func _actuate(position: float, command: float, rate: float) -> float:
	if absf(command - position) < ACTUATOR_DEADBAND and command > 0.0 and command < 1.0: return position
	return move_toward(position, command, rate)

func _max_co2(ui: int) -> float:
	var worst := OUTDOOR_CO2_PPM
	for zi in _unit_zones[ui]: worst = maxf(worst, float(_zone_list[zi].co2_ppm))
	return worst

func _zone_mode(zi: int) -> String:
	var z: Dictionary = _zone_list[zi]
	if not bool(z.served): return "Unconditioned"
	var heating := false
	var cooling := false
	var active := false
	for ti in _zone_terms[zi]:
		var t: Dictionary = _term_list[ti]
		if not bool(t.connected): continue
		if String(_term_unit[ti].get("mode", "Off")) != "Off": active = true
		heating = heating or float(t.heating_loop) > 0.01
		cooling = cooling or float(t.cooling_loop) > 0.01
	if not occupied and not active: return "Unoccupied"
	if heating: return "Heating"
	if cooling: return "Cooling"
	return "Satisfied"

func _terminal_mode(ti: int) -> String:
	var t: Dictionary = _term_list[ti]
	if not bool(t.connected): return "Disconnected"
	var active := String(_term_unit[ti].get("mode", "Off")) != "Off"
	if not occupied and not active: return "Unoccupied"
	if float(t.heating_loop) > 0.01: return "Heating"
	if float(t.cooling_loop) > 0.01: return "Cooling"
	return "Satisfied"

# Smooth deterministic sensor noise (value noise, 20 s knots) in ±amplitude.
func _noise(key: int, amplitude: float) -> float:
	var x := float(_step_index) / NOISE_PERIOD_S
	var k := int(floor(x))
	var f := x - float(k)
	f = f * f * (3.0 - 2.0 * f)
	return amplitude * lerpf(_hash_unit(key, k), _hash_unit(key, k + 1), f)

static func _hash_unit(key: int, k: int) -> float:
	var h := (key ^ (k * 0x9E3779B1)) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 2147483647.5 - 1.0

static func _profile(points: Array, hour: float) -> float:
	var prev: Array = points[0]
	if hour <= float(prev[0]): return float(prev[1])
	for i in range(1, points.size()):
		var p: Array = points[i]
		if hour <= float(p[0]):
			var span := float(p[0]) - float(prev[0])
			return lerpf(float(prev[1]), float(p[1]), (hour - float(prev[0])) / span) if span > 0.0 else float(p[1])
		prev = p
	return float(prev[1])

# ---------------------------------------------------------------- helpers: state

func _start_temp() -> float:
	return float(WEATHER.get(scenario, WEATHER["Normal weekday"])[4])

# Starting temperature for a zone/AHU added while running: the building average.
func _typical_temp() -> float:
	var real := 0
	var sum := 0.0
	for id in zones:
		sum += float(zones[id].true_temp_c)
		real += 1
	return sum / real if real > 0 else _start_temp()

func _apply_start_temps(start_c: float) -> void:
	for z in _zone_list:
		z.true_temp_c = start_c
		z.mass_temp_c = start_c
		z.measured_temp_c = start_c
	for u in _unit_list:
		u.return_temp_c = start_c
		u.mixed_temp_c = start_c
		u.supply_temp_c = start_c
	for t in _term_list: t.discharge_temp_c = start_c

func _new_record(id: String, kind: String, start_c: float) -> Dictionary:
	var record := {"id": id, "seed": id.hash() & 0x7FFFFFFF, "served": false, "bias_k": 0.0, "dummy": false}
	match kind:
		"zones", "dummy_zones": _init_zone_state(record, start_c)
		"units": _init_unit_state(record, start_c)
		"terminals": _init_terminal_state(record, start_c)
	var stash: Dictionary = _stash[kind]
	if stash.has(id):
		_apply_state(record, stash[id])
		stash.erase(id)
	return record

func _init_zone_state(z: Dictionary, start_c: float) -> void:
	z.true_temp_c = start_c
	z.mass_temp_c = start_c
	z.measured_temp_c = start_c
	z.co2_ppm = 450.0
	z.cool_setpoint_c = DEFAULT_COOL_C
	z.heat_setpoint_c = DEFAULT_HEAT_C
	z.lights_override = -1.0
	z.lights_on = false
	z.internal_w = 0.0
	z.solar_w = 0.0
	z.hvac_w = 0.0
	z.occupants = 0.0
	z.supply_airflow_m3_s = 0.0
	z.supply_temp_c = start_c
	z.outdoor_exchange_m3_s = 0.0

func _init_unit_state(u: Dictionary, start_c: float) -> void:
	for key in UNIT_STATE: u[key] = 0.0
	for key in UNIT_FLAGS: u[key] = false
	u.mode = "Off"
	u.static_sp_pa = STATIC_SP_INIT_PA
	u.sat_sp_c = SAT_MAX_C
	u.sat_tr_c = SAT_MAX_C
	u.filter_loading_pa = FILTER_CLEAN_PA
	u.return_temp_c = start_c
	u.mixed_temp_c = start_c
	u.supply_temp_c = start_c
	u.co2_return_ppm = 450.0
	u.co2_supply_ppm = 450.0
	u.fan_fault = false
	u.filter_fault = false

func _init_terminal_state(t: Dictionary, start_c: float) -> void:
	for key in TERMINAL_STATE: t[key] = 0.0
	t.discharge_temp_c = start_c
	t.active_cool_c = UNOCC_COOL_C
	t.active_heat_c = UNOCC_HEAT_C
	t.vmin_m3_s = 0.0
	t.stuck = false

func _zone_config(z: Dictionary, src: Dictionary, id: String) -> void:
	var type := String(src.get("type", "room")) if src.get("type", "room") is String else "room"
	if not ZONE_TYPES.has(type): type = "room"
	var area := _num(src.get("area_m2"), 30.0, 1.0, 5000.0)
	var windows := {"N": 0.0, "E": 0.0, "S": 0.0, "W": 0.0}
	var wsrc := _dict(src.get("window_m2", {}))
	for key in windows: windows[key] = _num(wsrc.get(key), 0.0, 0.0, 5000.0)
	var window_total := float(windows.N) + float(windows.E) + float(windows.S) + float(windows.W)
	var wall := _num(src.get("exterior_wall_m2"), 0.0, 0.0, 20000.0)
	var roof := _num(src.get("roof_m2"), area, 0.0, 20000.0)
	var doors := _num(src.get("exterior_doors"), 0.0, 0.0, 20.0)
	var spec: Array = ZONE_TYPES[type]
	var volume := area * CEILING_M
	z.label = String(src.get("label", id)) if src.get("label", id) is String else id
	z.type = type
	z.area_m2 = area
	z.volume_m3 = volume
	z.window_m2 = windows
	z.exterior_wall_m2 = wall
	z.roof_m2 = roof
	z.exterior_doors = doors
	z.c_air_j_k = area * (CEILING_M * RHO_CP + FURNISHING_J_M2K)
	z.c_mass_j_k = area * MASS_J_M2K
	z.capacitance_j_k = float(z.c_air_j_k) + float(z.c_mass_j_k)
	z.g_mass_w_k = area * SURFACE_W_M2K
	z.ua_wall_w_k = U_WALL * maxf(wall - window_total, 0.0) # exterior wall area is gross
	z.ua_window_w_k = U_WINDOW * window_total
	z.ua_roof_w_k = U_ROOF * roof
	z.inf_m3_s = INFILTRATION_ACH * volume / 3600.0 + DOOR_LEAK_M3_S * floor(doors)
	z.aperture_n = SHGC * float(windows.N)
	z.aperture_e = SHGC * float(windows.E)
	z.aperture_s = SHGC * float(windows.S)
	z.aperture_w = SHGC * float(windows.W)
	z.people_max = float(spec[0]) * area
	z.person_w = float(spec[1])
	z.plug_w = float(spec[2]) * area
	z.lights_w = float(spec[3]) * area
	z.profile = String(spec[4])
	z.lights_default = bool(spec[5])
	z.plug_night = float(spec[6])
	z.co2_per_person = float(spec[7])
	z.dummy = false

func _zone_source(z: Dictionary) -> Dictionary:
	return {"label": z.label, "type": z.type, "area_m2": z.area_m2, "exterior_wall_m2": z.exterior_wall_m2, "roof_m2": z.roof_m2,
		"window_m2": (z.window_m2 as Dictionary).duplicate(), "exterior_doors": z.exterior_doors, "neighbours": z.get("neighbours", {}).duplicate()}

func _unit_config(u: Dictionary, src: Dictionary, id: String) -> void:
	u.label = String(src.get("label", id)) if src.get("label", id) is String else id
	u.capacity_m3_s = _num(src.get("capacity_m3_s"), 1.0, 0.0, 50.0)
	var layout: Array = _roles(src.get("layout", UNIT_ROLES), UNIT_ROLES)
	u.layout = layout
	var roles: Array = []
	for role in layout:
		if role not in roles: roles.append(role)
	u.roles = roles # first instance of each role acts; duplicates share its valve
	u.has_fan = "fan" in roles
	u.has_damper = "damper" in roles
	u.has_filter = "filter" in roles
	u.has_cooling = "cooling_coil" in roles
	u.has_heating = "heating_coil" in roles

func _terminal_config(t: Dictionary, src: Dictionary, id: String) -> void:
	t.label = String(src.get("label", id)) if src.get("label", id) is String else id
	var zone_id: Variant = src.get("zone_id", "")
	t.zone_id = String(zone_id) if (zone_id is String or zone_id is StringName) and zones.has(String(zone_id)) else ""
	var source: Variant = src.get("source_id", "")
	t.source_id = String(source) if source is String or source is StringName else ""
	t.connected = src.get("connected", false) is bool and bool(src.connected) and units.has(String(t.source_id))
	t.capacity_m3_s = _num(src.get("capacity_m3_s"), 0.45, 0.0, 10.0)
	var layout: Array = _roles(src.get("layout", ["damper", "heating_coil"]), TERMINAL_ROLES)
	t.layout = layout
	t.has_damper = "damper" in layout
	t.has_reheat = "heating_coil" in layout
	t.has_cooling = "cooling_coil" in layout
	if not bool(t.connected): t.flow_actual_m3_s = 0.0

func _build_indices(topology: Dictionary, zsrc: Dictionary) -> void:
	_zone_list.clear()
	_zone_index.clear()
	for id in zones:
		_zone_index[id] = _zone_list.size()
		_zone_list.append(zones[id])
	var dummy_index: Dictionary = {}
	for id in _dummy:
		dummy_index[id] = _zone_list.size()
		_zone_list.append(_dummy[id])
	_unit_list.clear()
	_unit_index.clear()
	for id in units:
		_unit_index[id] = _unit_list.size()
		_unit_list.append(units[id])
	_term_list.clear()
	_term_zone.clear()
	_term_unit.clear()
	_term_zone_idx.clear()
	_term_unit_idx.clear()
	_term_index.clear()
	var term_index := _term_index
	_zone_terms.clear()
	for _i in range(_zone_list.size()): _zone_terms.append(PackedInt32Array())
	for id in terminals:
		var t: Dictionary = terminals[id]
		var ti := _term_list.size()
		term_index[id] = ti
		_term_list.append(t)
		var zi := int(_zone_index[t.zone_id]) if not String(t.zone_id).is_empty() else int(dummy_index[id])
		_term_zone.append(_zone_list[zi])
		_term_zone_idx.append(zi)
		_zone_terms[zi].append(ti)
		_term_unit.append(units[t.source_id] if bool(t.connected) else {})
		_term_unit_idx.append(int(_unit_index[t.source_id]) if bool(t.connected) else -1)
	_unit_terms.clear()
	_unit_zones.clear()
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var idxs := PackedInt32Array()
		var zis := PackedInt32Array()
		var can_heat := bool(u.has_heating)
		var can_cool := bool(u.has_cooling)
		for ti in range(_term_list.size()):
			if _term_unit_idx[ti] != ui: continue
			idxs.append(ti)
			var zi := _term_zone_idx[ti]
			if not zis.has(zi): zis.append(zi)
			can_heat = can_heat or bool(_term_list[ti].has_reheat)
			can_cool = can_cool or bool(_term_list[ti].has_cooling)
		u.can_heat = can_heat
		u.can_cool = can_cool
		_unit_terms.append(idxs)
		_unit_zones.append(zis)
	_unit_b.resize(_unit_list.size())
	_q.resize(_term_list.size())
	_prev_t.resize(_zone_list.size())
	_prev_c.resize(_zone_list.size())
	# Served zones and auto-tuned zone loop gains (same crossover everywhere).
	for zi in range(_zone_list.size()):
		var z: Dictionary = _zone_list[zi]
		var vmax_total := 0.0
		var served := false
		for ti in _zone_terms[zi]:
			vmax_total += float(_term_list[ti].capacity_m3_s)
			served = served or bool(_term_list[ti].connected)
		z.served = served
		var gain := RHO_CP * maxf(vmax_total, 0.01) * 0.7 * 10.0 / float(z.c_air_j_k)
		for ti in _zone_terms[zi]: _term_list[ti].kp = clampf(ZONE_LOOP_CROSSOVER / gain, 0.3, 3.0)
	# Partitions: symmetric, the larger declared shared area wins.
	var shared: Dictionary = {}
	for id in zones:
		var nsrc := _dict(_dict(zsrc.get(id, {})).get("neighbours", {}))
		var clean: Dictionary = {}
		for other in _sorted_ids(nsrc):
			if other == id or not zones.has(other): continue
			var area := _num(nsrc[other], 0.0, 0.0, 10000.0)
			if area <= 0.0: continue
			clean[other] = area
			var key: String = String(id) + "\n" + other if String(id) < other else other + "\n" + String(id)
			shared[key] = maxf(float(shared.get(key, 0.0)), area)
		zones[id].neighbours = clean
	_neighbours.clear()
	for _i in range(_zone_list.size()): _neighbours.append([])
	var pair_keys: Array = shared.keys()
	pair_keys.sort()
	for key in pair_keys:
		var ids: PackedStringArray = String(key).split("\n")
		var a := int(_zone_index[ids[0]])
		var b := int(_zone_index[ids[1]])
		var g := U_PARTITION * float(shared[key])
		_neighbours[a].append([b, g])
		_neighbours[b].append([a, g])
	# Shared duct/fitting limits and per-duct routes.
	_limits.clear()
	var lsrc := _dict(topology.get("limits", {}))
	for id in _sorted_ids(lsrc):
		var entry := _weighted(_dict(lsrc[id]), term_index)
		if entry.is_empty(): continue
		var cap := _num(_dict(lsrc[id]).get("capacity_m3_s"), -1.0, 0.0, 100.0)
		if cap < 0.0: continue
		_limits.append([cap, entry[0], entry[1]])
	_routes.clear()
	route_flows.clear()
	var rsrc := _dict(topology.get("routes", {}))
	for id in _sorted_ids(rsrc):
		var entry := _weighted(_dict(rsrc[id]), term_index)
		if entry.is_empty(): entry = [PackedInt32Array(), PackedFloat64Array()]
		_routes.append([id, entry[0], entry[1]])
		route_flows[id] = 0.0
	_build_openings()

func _weighted(src: Dictionary, term_index: Dictionary) -> Array:
	var weights := _dict(src.get("weights", {}))
	var idx := PackedInt32Array()
	var w := PackedFloat64Array()
	for vav in _sorted_ids(weights):
		if not term_index.has(vav): continue
		var value := _num(weights[vav], 0.0, 0.0, 100.0)
		if value <= 0.0: continue
		idx.append(int(term_index[vav]))
		w.append(value)
	return [] if idx.is_empty() else [idx, w]

func _build_openings() -> void:
	var count := _zone_list.size()
	_open_doors.resize(count)
	_open_doors.fill(0.0)
	_open_windows.resize(count)
	_open_windows.fill(0.0)
	_open_int.clear()
	for _i in range(count): _open_int.append([])
	for entry in _openings:
		var a := String(entry.a)
		var b := String(entry.b)
		var door := String(entry.kind) == "door"
		if a == "outside" or b == "outside":
			var zi := int(_zone_index.get(b if a == "outside" else a, -1))
			if zi < 0: continue
			if door: _open_doors[zi] += 1.0
			else: _open_windows[zi] += 1.0
		elif _zone_index.has(a) and _zone_index.has(b):
			var ia := int(_zone_index[a])
			var ib := int(_zone_index[b])
			_open_int[ia].append([ib, door])
			_open_int[ib].append([ia, door])

func _update_fault_targets() -> void:
	_fault_fan = ""
	_fault_filter = ""
	_fault_damper = ""
	_fault_bias = ""
	match scenario:
		"Fan failure":
			for u in _unit_list:
				if bool(u.has_fan):
					_fault_fan = String(u.id)
					break
		"Dirty filter":
			for u in _unit_list:
				if bool(u.has_filter):
					_fault_filter = String(u.id)
					break
		"Damper stuck at 25%":
			if not _term_list.is_empty(): _fault_damper = String(_term_list[0].id)
		"Sensor bias":
			for id in zones:
				if bool(zones[id].served):
					_fault_bias = String(id)
					break
			if _fault_bias.is_empty() and not zones.is_empty(): _fault_bias = String(zones.keys()[0])
	for u in _unit_list:
		u.fan_fault = String(u.id) == _fault_fan
		u.filter_fault = String(u.id) == _fault_filter
	for t in _term_list:
		t.stuck = String(t.id) == _fault_damper
		if bool(t.stuck): t.damper_feedback = STUCK_DAMPER
	for z in _zone_list: z.bias_k = SENSOR_BIAS_K if not bool(z.dummy) and String(z.id) == _fault_bias else 0.0

# After reset/configure/restore/scenario: refresh derived values without
# advancing time. Flows are only ever reduced here (never invented) so a
# paused building stays consistent after an edit.
func _after_state_change() -> void:
	_update_fault_targets()
	for z in _zone_list: z.measured_temp_c = float(z.true_temp_c) + float(z.bias_k) + _noise(int(z.seed), ZONE_NOISE_K)
	for ti in range(_term_list.size()):
		var t: Dictionary = _term_list[ti]
		_q[ti] = clampf(float(t.flow_actual_m3_s), 0.0, float(t.capacity_m3_s)) if bool(t.connected) else 0.0
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var n := float(u.fan_feedback) if bool(u.has_fan) else 0.0
		var avail := minf(float(u.available_flow_m3_s), n * float(u.capacity_m3_s))
		u.available_flow_m3_s = maxf(avail, 0.0)
		var total := 0.0
		for ti in _unit_terms[ui]: total += _q[ti]
		if total > avail * (1.0 + 1.0e-12) and total > 0.0:
			for ti in _unit_terms[ui]: _q[ti] *= maxf(avail, 0.0) / total
	for limit in _limits: _apply_limit(limit, 1.0e-12)
	for ti in range(_term_list.size()):
		var t: Dictionary = _term_list[ti]
		var old := float(t.flow_actual_m3_s)
		if _q[ti] != old:
			var ratio := _q[ti] / old if old > 0.0 else 0.0
			t.heating_w = float(t.heating_w) * ratio
			t.cooling_w = float(t.cooling_w) * ratio
			t.flow_actual_m3_s = _q[ti]
	for ui in range(_unit_list.size()):
		var u: Dictionary = _unit_list[ui]
		var total := 0.0
		for ti in _unit_terms[ui]: total += _q[ti]
		var old := float(u.flow_actual_m3_s)
		if total != old:
			var ratio := total / old if old > 0.0 else 0.0
			u.cooling_w = float(u.cooling_w) * ratio
			u.heating_w = float(u.heating_w) * ratio
			var loading := FILTER_DIRTY_PA if bool(u.filter_fault) else float(u.filter_loading_pa)
			var r := total / maxf(float(u.capacity_m3_s), 0.001)
			u.filter_dp_pa = loading * r * r if bool(u.has_filter) else 0.0
			u.flow_actual_m3_s = total
		if not bool(u.has_filter): u.filter_dp_pa = 0.0
	_refresh_routes()
	_publish_aliases()
	_revision += 1

# ---------------------------------------------------------------- helpers: parsing

static func _num(value: Variant, fallback: float, lo: float, hi: float) -> float:
	if (value is float or value is int) and is_finite(float(value)): return clampf(float(value), lo, hi)
	return fallback

static func _finite_or(value: float, fallback: float) -> float:
	return value if is_finite(value) else fallback

static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _sorted_ids(source: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for key in source:
		if (key is String or key is StringName) and not String(key).is_empty() and String(key).length() <= 256:
			ids.append(String(key))
	ids.sort()
	return ids

static func _roles(value: Variant, allowed: Array) -> Array:
	var out: Array = []
	if not value is Array: return out
	for role in value:
		if (role is String or role is StringName) and String(role) in allowed and out.size() < 16: out.append(String(role))
	return out
