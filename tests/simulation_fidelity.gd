extends SceneTree

# Headless fidelity test for the demo building simulation (numbers only; no
# scene). Run: Godot --headless --path . --script res://tests/simulation_fidelity.gd

const Sim := preload("res://scripts/sim/demo_simulation.gd")
const Alarms := preload("res://scripts/sim/alarm_manager.gd")
const Binding := preload("res://scripts/data/animation_binding.gd")

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	var started := Time.get_ticks_msec()
	var tests: Array[Callable] = [test_blank_and_junk_topology, test_startup_sequence, test_cooling_day, test_economizer,
		test_cold_morning, test_thermostat_response, test_open_doors, test_fan_failure, test_dirty_filter, test_stuck_damper,
		test_sensor_bias, test_data_interruption, test_conservation_all_day, test_reconfigure, test_unconditioned_zone,
		test_unoccupied_and_night_cycle, test_installed_components_only, test_lights, test_point_contract,
		test_accessors_and_snapshot, test_full_days_bounded, test_speed_equivalence, test_checkpoint_restore,
		test_determinism, test_controls_validation, test_controls_sequences, test_schedule_and_people,
		test_targeted_faults, test_targeted_fault_alarms, test_meters, test_wasteful_programming, test_time_lapse, test_performance]
	for test in tests:
		var t0 := Time.get_ticks_msec()
		test.call()
		if OS.get_cmdline_user_args().has("--timings"): print("  %-36s %6d ms" % [test.get_method(), Time.get_ticks_msec() - t0])
	print("elapsed %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if failures.is_empty(): print("SIMULATION_FIDELITY PASS checks=%d" % checks)
	else: print("SIMULATION_FIDELITY FAIL checks=%d failures=%d\n  - %s" % [checks, failures.size(), "\n  - ".join(failures)])
	quit(0 if failures.is_empty() else 1)

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

# ---------------------------------------------------------------- fixtures

# A two-classroom school wing: south windows, a corridor with the entrance
# door (unconditioned), one full AHU, two reheat VAVs on a shared trunk.
func wing(ahu_capacity := 1.0, trunk_capacity := 1.0) -> Dictionary:
	return {
		"zones": {
			"class_a": {"label": "Room 101", "type": "classroom", "area_m2": 64.0, "exterior_wall_m2": 28.0, "roof_m2": 64.0, "window_m2": {"N": 0.0, "E": 0.0, "S": 10.0, "W": 0.0}, "neighbours": {"corridor": 28.0, "class_b": 25.0}, "exterior_doors": 0},
			"class_b": {"label": "Room 102", "type": "classroom", "area_m2": 64.0, "exterior_wall_m2": 40.0, "roof_m2": 64.0, "window_m2": {"S": 10.0, "W": 5.0}, "neighbours": {"corridor": 28.0, "class_a": 25.0}, "exterior_doors": 0},
			"corridor": {"label": "Corridor", "type": "corridor", "area_m2": 48.0, "exterior_wall_m2": 12.0, "roof_m2": 48.0, "window_m2": {"E": 2.0}, "neighbours": {"class_a": 28.0, "class_b": 28.0}, "exterior_doors": 1},
		},
		"units": {"ahu_1": {"label": "AHU-1", "capacity_m3_s": ahu_capacity, "layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"]}},
		"terminals": {
			"vav_a": {"label": "VAV-101", "zone_id": "class_a", "source_id": "ahu_1", "connected": true, "capacity_m3_s": 0.45, "layout": ["damper", "heating_coil"]},
			"vav_b": {"label": "VAV-102", "zone_id": "class_b", "source_id": "ahu_1", "connected": true, "capacity_m3_s": 0.45, "layout": ["damper", "heating_coil"]},
		},
		"limits": {
			"ahu_1": {"capacity_m3_s": ahu_capacity, "weights": {"vav_a": 1.0, "vav_b": 1.0}},
			"trunk": {"capacity_m3_s": trunk_capacity, "weights": {"vav_a": 1.0, "vav_b": 1.0}},
			"vav_a": {"capacity_m3_s": 0.45, "weights": {"vav_a": 1.0}},
			"vav_b": {"capacity_m3_s": 0.45, "weights": {"vav_b": 1.0}},
			"diffuser_a1": {"capacity_m3_s": 0.3, "weights": {"vav_a": 0.5}},
			"diffuser_a2": {"capacity_m3_s": 0.3, "weights": {"vav_a": 0.5}},
		},
		"routes": {
			"trunk": {"capacity_m3_s": trunk_capacity, "weights": {"vav_a": 1.0, "vav_b": 1.0}},
			"run_a": {"capacity_m3_s": 0.45, "weights": {"vav_a": 1.0}},
			"run_b": {"capacity_m3_s": 0.45, "weights": {"vav_b": 1.0}},
			"branch_a1": {"capacity_m3_s": 0.3, "weights": {"vav_a": 0.5}},
		},
	}

# The wing plus a lobby with the front doors and its own VAV.
func lobby_wing() -> Dictionary:
	var topo := wing(1.4, 1.4)
	topo.zones["lobby"] = {"label": "Lobby", "type": "lobby", "area_m2": 40.0, "exterior_wall_m2": 30.0, "roof_m2": 40.0, "window_m2": {"S": 6.0, "E": 4.0}, "neighbours": {"corridor": 20.0}, "exterior_doors": 2}
	topo.zones.corridor.neighbours["lobby"] = 20.0
	topo.terminals["vav_l"] = {"label": "VAV-LOBBY", "zone_id": "lobby", "source_id": "ahu_1", "connected": true, "capacity_m3_s": 0.4, "layout": ["damper", "heating_coil"]}
	topo.limits.ahu_1.weights["vav_l"] = 1.0
	topo.limits.trunk.weights["vav_l"] = 1.0
	topo.routes.trunk.weights["vav_l"] = 1.0
	return topo

func make(topology: Dictionary, scenario := "Normal weekday") -> RefCounted:
	var sim := Sim.new()
	sim.configure(topology)
	sim.reset()
	sim.set_scenario(scenario)
	return sim

# Steps until the clock reaches the given hour of the current day.
func run_to(sim: RefCounted, hour: float) -> void:
	var target := hour * 3600.0
	var now := fposmod(float(sim.sim_seconds), 86400.0)
	var seconds := target - now
	if seconds < 0.0: seconds += 86400.0
	sim.step_for_test(round(seconds))

func points(sim: RefCounted) -> Dictionary:
	var out := {}
	for p in sim.snapshot_points(): out[String(p.point_id)] = p
	return out

func value(sim: RefCounted, id: String) -> Variant:
	for p in sim.snapshot_points():
		if p.point_id == id: return p.value
	return null

# Mass conservation and capacity limits against the topology we supplied.
func audit(sim: RefCounted, topo: Dictionary) -> String:
	for id in sim.terminals:
		var t: Dictionary = sim.terminals[id]
		var q := float(t.flow_actual_m3_s)
		if not is_finite(q) or q < 0.0: return "%s negative/invalid flow" % id
		if q > float(t.capacity_m3_s) + 1.0e-9: return "%s exceeds terminal capacity" % id
		if not bool(t.connected) and q != 0.0: return "%s disconnected but flowing" % id
	for uid in sim.units:
		var u: Dictionary = sim.units[uid]
		var total := 0.0
		for id in sim.terminals:
			var t: Dictionary = sim.terminals[id]
			if bool(t.connected) and String(t.source_id) == uid: total += float(t.flow_actual_m3_s)
		if absf(total - float(u.flow_actual_m3_s)) > 1.0e-9: return "%s supply %.6f != delivered %.6f" % [uid, u.flow_actual_m3_s, total]
		if float(u.flow_actual_m3_s) > float(u.available_flow_m3_s) + 1.0e-9: return "%s supply exceeds available" % uid
		if float(u.available_flow_m3_s) > float(u.capacity_m3_s) * float(u.fan_feedback) + 1.0e-9: return "%s available exceeds capacity × speed" % uid
	for lid in topo.get("limits", {}):
		var limit: Dictionary = topo.limits[lid]
		var flow := 0.0
		for vav in limit.weights:
			if sim.terminals.has(vav): flow += float(sim.terminals[vav].flow_actual_m3_s) * float(limit.weights[vav])
		if flow > float(limit.capacity_m3_s) * (1.0 + 1.0e-9) + 1.0e-12: return "limit %s exceeded (%.6f > %.6f)" % [lid, flow, limit.capacity_m3_s]
	for rid in topo.get("routes", {}):
		var route: Dictionary = topo.routes[rid]
		var flow := 0.0
		for vav in route.weights:
			if sim.terminals.has(vav): flow += float(sim.terminals[vav].flow_actual_m3_s) * float(route.weights[vav])
		if absf(flow - float(sim.route_flows.get(rid, -1.0))) > 1.0e-9: return "route %s airflow mismatch" % rid
	return ""

func finite_points(sim: RefCounted) -> String:
	for p in sim.snapshot_points():
		var v: Variant = p.value
		if (v is float or v is int) and not is_finite(float(v)): return String(p.point_id)
		if not (v is float or v is int or v is bool or v is String): return String(p.point_id)
	return ""

func state_equal(a: RefCounted, b: RefCounted) -> bool:
	var ca: Dictionary = a.checkpoint()
	var cb: Dictionary = b.checkpoint()
	ca.erase("speed")
	cb.erase("speed")
	ca.erase("accumulator")
	cb.erase("accumulator")
	return ca == cb

# ---------------------------------------------------------------- tests

func test_blank_and_junk_topology() -> void:
	var sim := Sim.new()
	sim.configure({})
	sim.step_for_test(3600)
	var pts: Array = sim.snapshot_points()
	expect(pts.size() == 6 and sim.zone_ids().is_empty() and sim.unit_ids().is_empty() and sim.terminal_ids().is_empty(), "blank canvas: only site points, no equipment")
	expect(value(sim, "site.time_of_day") is float and is_equal_approx(float(value(sim, "site.time_of_day")), 7.5), "blank canvas: clock still runs (06:30 + 1 h)")
	expect(sim.zone_state("nope").is_empty() and sim.unit_state("nope").is_empty() and sim.terminal_state("nope").is_empty(), "unknown ids return empty state")
	sim.set_zone_setpoints("nope", 22.0)
	sim.set_lights("nope", true)
	sim.set_open_connections([{"a": "nope", "b": "outside", "kind": "door"}, 5, {"a": "", "b": "x"}])
	sim.step_for_test(10)
	# Junk values of every kind must be tolerated.
	var junk := {
		"zones": {"z": {"area_m2": NAN, "window_m2": "x", "neighbours": {"ghost": 5.0, "z": 3.0, "y": INF}, "type": 7, "exterior_doors": -4}, "y": {"area_m2": -10.0, "roof_m2": INF, "label": 3}, "": {}},
		"units": {"a": {"capacity_m3_s": INF, "layout": "fan"}, "b": {"capacity_m3_s": -2.0, "layout": ["fan", "fan", "turbo", 4]}, "c": 17},
		"terminals": {"v": {"zone_id": 7, "source_id": "a", "connected": "yes", "capacity_m3_s": -3.0}, "w": {"zone_id": "z", "source_id": "b", "connected": true, "capacity_m3_s": NAN, "layout": null}},
		"limits": {"l": {"capacity_m3_s": NAN, "weights": {"v": INF}}, "m": {"capacity_m3_s": 0.0, "weights": {"w": 1.0, "ghost": 1.0}}, "n": "bad"},
		"routes": {"r": {"weights": {"ghost": 1.0}}, "s": {"weights": {"w": NAN}}, "t": 3},
	}
	sim.configure(junk)
	sim.step_for_test(1800)
	expect(finite_points(sim) == "", "junk topology: every published value stays finite")
	expect(audit(sim, {}) == "", "junk topology: flows stay conserved")
	expect(float(sim.terminals.w.flow_actual_m3_s) == 0.0, "a zero-capacity shared limit blocks its terminal")
	sim.configure({"zones": 5, "units": [], "terminals": null})
	sim.step_for_test(60)
	expect(sim.zone_ids().is_empty() and finite_points(sim) == "", "non-dictionary sections are treated as empty")

func test_startup_sequence() -> void:
	var topo := wing()
	var sim := make(topo)
	expect(String(sim.weather().clock) == "06:30" and not bool(value(sim, "site.occupied")), "day starts at 06:30, unoccupied")
	expect(not bool(value(sim, "ahu_1.fan_enable_cmd")) and float(value(sim, "ahu_1.fan_speed_feedback")) == 0.0, "AHU off before the first step")
	sim.step_for_test(1)
	var u: Dictionary = sim.unit_state("ahu_1")
	expect(String(u.mode) == "Cool-down", "optimal start begins cool-down for a building at 24 °C")
	expect(bool(u.enabled) and float(u.fan_command) > float(u.fan_feedback) and float(u.fan_feedback) > 0.0, "fan command leads ramping feedback")
	expect(not bool(value(sim, "ahu_1.fan_run_feedback")), "run proof lags the start command")
	var speeds: Array = []
	for i in range(90):
		sim.step_for_test(1)
		speeds.append(float(sim.units.ahu_1.fan_feedback))
		if i % 10 == 0: expect(audit(sim, topo) == "", "start-up conserves flow at t=%d s" % (i + 2))
	expect(float(speeds[3]) < 0.25, "fan still ramping after 5 s (%.2f)" % speeds[3])
	expect(float(speeds[40]) > 0.4, "fan well up to speed after ~40 s (%.2f)" % speeds[40])
	var smooth := true
	for i in range(1, 60): smooth = smooth and float(speeds[i]) >= float(speeds[i - 1]) - 0.01 and float(speeds[i]) <= float(speeds[i - 1]) + 1.0 / 30.0 + 1.0e-9
	expect(smooth, "fan speed ramps smoothly (VFD accel limit, no hunting) during the first minute")
	expect(bool(value(sim, "ahu_1.fan_run_feedback")) and String(value(sim, "ahu_1.fan_state")) == "Running", "run proof established")
	expect(float(sim.terminals.vav_a.damper_feedback) > 0.3 and float(sim.terminals.vav_a.flow_actual_m3_s) > 0.05, "VAV dampers open and air flows")
	expect(float(value(sim, "ahu_1.duct_pressure")) > 50.0, "duct static pressure builds")
	run_to(sim, 7.0 + 5.0 / 60.0)
	u = sim.unit_state("ahu_1")
	expect(bool(value(sim, "site.occupied")) and String(u.mode) == "Occupied", "occupied at 07:00")
	expect(float(u.oa_min) >= 0.2 - 1.0e-9 and float(u.damper_command) >= 0.2 - 1.0e-9 and float(u.damper_feedback) >= 0.19, "OA damper at least at minimum position when occupied")
	expect(float(sim.terminals.vav_a.flow_sp_m3_s) >= 0.3 * 0.45 - 1.0e-6, "VAV holds occupied minimum airflow")

func test_cooling_day() -> void:
	var topo := wing()
	var sim := make(topo)
	run_to(sim, 7.75)
	var early := float(sim.terminals.vav_a.flow_actual_m3_s)
	run_to(sim, 10.5)
	var late := float(sim.terminals.vav_a.flow_actual_m3_s)
	var u: Dictionary = sim.unit_state("ahu_1")
	for zone_id in ["class_a", "class_b"]:
		var z: Dictionary = sim.zone_state(zone_id)
		expect(absf(float(z.true_temp_c) - 23.0) < 0.6, "%s settles near its 23 °C cooling setpoint (%.2f)" % [zone_id, z.true_temp_c])
		expect(String(z.mode) == "Cooling", "%s mode is Cooling mid-morning" % zone_id)
	expect(late > early + 0.05, "VAV airflow rises with the load (%.3f -> %.3f m³/s)" % [early, late])
	expect(late > 0.3 * 0.45, "VAV above minimum airflow while cooling")
	expect(absf(float(u.supply_temp_c) - float(u.supply_setpoint_c)) < 0.7, "SAT tracks its setpoint (%.1f vs %.1f)" % [u.supply_temp_c, u.supply_setpoint_c])
	expect(float(u.supply_setpoint_c) < 13.5, "SAT reset to the cold end on a warm day")
	expect(float(u.cooling_output) > 0.05 and float(u.cooling_w) > 1000.0, "chilled-water valve open and removing heat")
	expect(not bool(u.economizer), "economizer locked out above the 21 °C high limit")
	expect(absf(float(u.duct_pressure_pa) - float(u.duct_pressure_setpoint_pa)) < 40.0, "duct static near its (reset) setpoint")
	expect(float(u.return_temp_c) > 22.0 and float(u.return_temp_c) < 25.0, "return air near space temperature plus plenum gain")
	var oat := float(sim.weather().outdoor_temp_c)
	expect(float(u.mixed_temp_c) >= minf(oat, float(u.return_temp_c)) - 0.15 and float(u.mixed_temp_c) <= maxf(oat, float(u.return_temp_c)) + 0.15, "mixed air lies between outdoor and return air (%.2f: OAT %.2f, RAT %.2f)" % [u.mixed_temp_c, oat, u.return_temp_c])
	expect(float(sim.terminals.vav_a.reheat_output) == 0.0, "no reheat while cooling")
	expect(float(sim.zone_state("class_a").co2_ppm) > 600.0 and float(sim.zone_state("class_a").co2_ppm) < 1500.0, "occupied classroom CO2 is plausible (%.0f ppm)" % sim.zone_state("class_a").co2_ppm)
	expect(audit(sim, topo) == "", "cooling day conserves flow")

func test_economizer() -> void:
	var sim := make(wing(), "Economizer day")
	run_to(sim, 7.5)
	var early: Dictionary = sim.unit_state("ahu_1")
	expect(bool(early.economizer) and float(early.damper_feedback) > float(early.oa_min) + 0.1 and float(early.cooling_output) < 0.02, "economizer modulates above minimum at 07:30 (%.2f)" % early.damper_feedback)
	run_to(sim, 11.0)
	var u: Dictionary = sim.unit_state("ahu_1")
	expect(bool(u.economizer) and bool(value(sim, "ahu_1.economizer")), "economizer enabled on a cool morning")
	expect(float(u.damper_feedback) > float(u.oa_min) + 0.1, "OA damper modulates above minimum (%.2f)" % u.damper_feedback)
	expect(float(u.cooling_output) < 0.05, "free cooling first: chilled-water valve stays closed (%.2f)" % u.cooling_output)
	expect(float(u.mixed_temp_c) < float(u.return_temp_c) - 3.0, "mixed air well below return air")
	expect(absf(float(u.supply_temp_c) - float(u.supply_setpoint_c)) < 1.0, "economizer holds SAT near setpoint")
	expect(float(value(sim, "ahu_1.outdoor_air_fraction")) > 30.0, "OA fraction point reflects economizing")
	var cold := make(wing(), "Cold morning")
	run_to(cold, 9.0)
	var c: Dictionary = cold.unit_state("ahu_1")
	expect(float(c.damper_feedback) <= float(c.oa_min) + 0.02, "sub-zero day: OA damper held at its minimum (%.2f)" % c.damper_feedback)
	expect(float(c.heating_output) > 0.05, "AHU heating coil tempers cold mixed air")

func test_cold_morning() -> void:
	var topo := wing()
	var sim := make(topo, "Cold morning")
	expect(absf(float(sim.zone_state("class_a").true_temp_c) - 15.0) < 0.01, "cold morning starts the building cold")
	sim.step_for_test(2)
	var u: Dictionary = sim.unit_state("ahu_1")
	expect(String(u.mode) == "Warm-up" and bool(u.enabled), "optimal start: warm-up")
	run_to(sim, 6.75)
	u = sim.unit_state("ahu_1")
	expect(float(u.damper_feedback) == 0.0 and float(u.damper_command) == 0.0, "OA damper closed during warm-up")
	expect(float(u.heating_output) > 0.3 and float(u.supply_temp_c) > 28.0, "AHU heats supply toward 35 °C in warm-up (%.1f)" % u.supply_temp_c)
	expect(float(sim.terminals.vav_a.flow_actual_m3_s) > 0.1, "warm air delivered at heating airflow")
	run_to(sim, 7.5)
	var t: Dictionary = sim.terminal_state("vav_a")
	var z: Dictionary = sim.zone_state("class_a")
	expect(float(t.reheat_output) > 0.2, "VAV reheat valve open once occupied (%.2f)" % t.reheat_output)
	expect(float(t.discharge_temp_c) > float(z.temp_c) + 3.0, "discharge air warmer than the space (%.1f vs %.1f)" % [t.discharge_temp_c, z.temp_c])
	expect(float(t.discharge_temp_c) <= 35.5, "discharge temperature limited to ~35 °C")
	expect(float(t.heating_w) > 500.0 and String(t.mode) == "Heating", "reheat adds heat, mode Heating")
	expect(float(z.true_temp_c) > 17.0, "zone warming (%.1f)" % z.true_temp_c)
	run_to(sim, 9.0)
	z = sim.zone_state("class_a")
	expect(float(z.true_temp_c) > 20.3 and float(z.true_temp_c) < 23.0, "zone reaches its 21 °C heating setpoint by 09:00 (%.1f)" % z.true_temp_c)
	expect(float(sim.zone_state("corridor").true_temp_c) < float(z.true_temp_c) - 3.0, "unconditioned corridor stays cold")
	expect(audit(sim, topo) == "", "cold morning conserves flow")

func test_thermostat_response() -> void:
	var sim := make(wing())
	run_to(sim, 10.0)
	var t0 := float(sim.zone_state("class_a").true_temp_c)
	var f0 := float(sim.terminals.vav_a.flow_sp_m3_s)
	var d0 := float(sim.terminals.vav_a.damper_command)
	sim.set_zone_setpoints("class_a", 21.0)
	var z: Dictionary = sim.zone_state("class_a")
	expect(float(z.cool_setpoint_c) == 21.0 and float(z.heat_setpoint_c) == 20.0, "lower cooling setpoint pushes heating down to keep 1 K deadband")
	sim.step_for_test(60)
	expect(float(sim.terminals.vav_a.flow_sp_m3_s) > f0 + 0.05, "airflow setpoint jumps up after the thermostat change")
	expect(float(sim.terminals.vav_a.damper_command) > d0, "damper opens further")
	sim.step_for_test(840)
	var t15 := float(sim.zone_state("class_a").true_temp_c)
	expect(t15 < t0 - 0.7, "zone cools within 15 min (%.2f -> %.2f)" % [t0, t15])
	expect(float(value(sim, "vav_a.cool_setpoint")) == 21.0 and float(value(sim, "vav_a.occ_cool_setpoint")) == 21.0, "setpoint points follow the thermostat")
	# Raising the setpoint well above the space drops the box to minimum.
	var warm := make(wing())
	run_to(warm, 10.0)
	var w0 := float(warm.zone_state("class_b").true_temp_c)
	var damper0 := float(warm.terminals.vav_b.damper_feedback)
	warm.set_terminal_setpoint("vav_b", 26.0)
	expect(float(warm.zone_state("class_b").cool_setpoint_c) == 26.0, "VAV-linked thermostat sets its zone")
	warm.step_for_test(900)
	var tb: Dictionary = warm.terminal_state("vav_b")
	expect(float(tb.cooling_loop) == 0.0 and absf(float(tb.airflow_target_m3_s) - float(tb.min_airflow_m3_s)) < 1.0e-9 and float(tb.min_airflow_m3_s) < 0.6 * 0.45, "box back to its (ventilation) minimum airflow")
	expect(float(warm.terminals.vav_b.damper_feedback) < damper0 - 0.1, "damper closes toward minimum")
	expect(float(warm.zone_state("class_b").true_temp_c) > w0 + 0.25, "zone floats warmer after the setpoint rise (%.2f -> %.2f)" % [w0, warm.zone_state("class_b").true_temp_c])
	# Clamping and legacy entry points.
	sim.set_zone_setpoints("class_a", 10.0)
	expect(float(sim.zones.class_a.cool_setpoint_c) == 17.0 and float(sim.zones.class_a.heat_setpoint_c) == 16.0, "cooling setpoint clamps to 17 so heating can stay ≥ 16")
	sim.set_zone_setpoints("class_a", 24.0, 26.0)
	expect(float(sim.zones.class_a.heat_setpoint_c) == 23.0, "heating setpoint kept 1 K under cooling")
	sim.set_zone_setpoints("class_a", 40.0, NAN)
	expect(float(sim.zones.class_a.cool_setpoint_c) == 30.0, "cooling setpoint clamps to 30 °C")
	sim.set_zone_setpoints("class_a", NAN, 18.0)
	expect(float(sim.zones.class_a.cool_setpoint_c) == 30.0 and float(sim.zones.class_a.heat_setpoint_c) == 18.0, "NAN keeps the other setpoint")
	sim.set_room_setpoint("class_a", 22.0)
	sim.set_room_setpoint("vav_b", 22.5)
	expect(float(sim.zones.class_a.cool_setpoint_c) == 22.0 and float(sim.zones.class_b.cool_setpoint_c) == 22.5, "legacy set_room_setpoint accepts zone or VAV ids")

func test_open_doors() -> void:
	var topo := lobby_wing()
	var control := make(topo, "Hot afternoon")
	var open := make(topo, "Hot afternoon")
	run_to(control, 14.0)
	run_to(open, 14.0)
	open.set_open_connections([{"a": "lobby", "b": "outside", "kind": "door"}])
	control.step_for_test(600)
	open.step_for_test(600)
	var zc: Dictionary = control.zone_state("lobby")
	var zo: Dictionary = open.zone_state("lobby")
	expect(float(zo.true_temp_c) > float(zc.true_temp_c) + 0.5, "propped front door warms the lobby (%.2f vs %.2f)" % [zo.true_temp_c, zc.true_temp_c])
	expect(float(zo.true_temp_c) < float(zc.true_temp_c) + 6.0, "door drift stays plausible over 10 min")
	expect(float(open.terminals.vav_l.flow_sp_m3_s) >= float(control.terminals.vav_l.flow_sp_m3_s) - 1.0e-6 and float(open.terminals.vav_l.cooling_loop) > float(control.terminals.vav_l.cooling_loop), "lobby VAV ramps up")
	expect(float(zo.outdoor_exchange_m3_s) > 0.25, "open door exchanges outdoor air (%.2f m³/s)" % zo.outdoor_exchange_m3_s)
	expect(float(zo.co2_ppm) < float(zc.co2_ppm), "outdoor air dilutes lobby CO2")
	expect(audit(open, topo) == "", "door scenario conserves flow")
	open.set_open_connections([])
	open.step_for_test(3600)
	expect(absf(float(open.zone_state("lobby").true_temp_c) - float(control.zone_state("lobby").true_temp_c)) < absf(float(zo.true_temp_c) - float(zc.true_temp_c)), "closing the door lets the lobby recover")
	# Interior door: mixing pulls the unconditioned corridor toward the classroom.
	var shut := make(topo, "Hot afternoon")
	var mixed := make(topo, "Hot afternoon")
	run_to(shut, 11.0)
	run_to(mixed, 11.0)
	mixed.set_open_connections([{"a": "class_a", "b": "corridor", "kind": "door"}])
	shut.step_for_test(1200)
	mixed.step_for_test(1200)
	var gap_shut := float(shut.zone_state("corridor").true_temp_c) - float(shut.zone_state("class_a").true_temp_c)
	var gap_mixed := float(mixed.zone_state("corridor").true_temp_c) - float(mixed.zone_state("class_a").true_temp_c)
	expect(gap_mixed < gap_shut - 0.3, "open interior door mixes corridor and classroom (%.2f vs %.2f K)" % [gap_mixed, gap_shut])
	# Exterior window on a cold morning cools the room.
	var sealed := make(topo, "Cold morning")
	var airy := make(topo, "Cold morning")
	run_to(sealed, 9.0)
	run_to(airy, 9.0)
	airy.set_open_connections([{"a": "outside", "b": "class_b", "kind": "window"}])
	sealed.step_for_test(900)
	airy.step_for_test(900)
	expect(float(airy.terminals.vav_b.heating_loop) > float(sealed.terminals.vav_b.heating_loop) or float(airy.zone_state("class_b").true_temp_c) < float(sealed.zone_state("class_b").true_temp_c) - 0.2, "open window on a cold day calls for more heat")

func test_fan_failure() -> void:
	var topo := wing()
	var sim := make(topo)
	var alarms := Alarms.new()
	run_to(sim, 10.0)
	for i in range(60):
		sim.step_for_test(1)
		alarms.evaluate(sim, 1.0)
	expect(alarms.summary() == "ALARMS  0 • system normal" and alarms.list().is_empty(), "no alarms in normal operation")
	var t0 := float(sim.zone_state("class_a").true_temp_c)
	sim.set_scenario("Fan failure")
	expect(String(sim.fault_targets().fan_failure) == "ahu_1", "fan failure targets the first AHU")
	var conserved := true
	var raised_at := -1
	for second in range(180):
		sim.step_for_test(1)
		alarms.evaluate(sim, 1.0)
		conserved = conserved and audit(sim, topo) == ""
		if raised_at < 0 and alarms.active.has("fan_failure:ahu_1"): raised_at = second
	var p := points(sim)
	expect(conserved, "flows conserved throughout the coast-down")
	expect(bool(p["ahu_1.fan_enable_cmd"].value) and not bool(p["ahu_1.fan_run_feedback"].value) and String(p["ahu_1.fan_state"].value) == "Off", "command stays on while run feedback is lost")
	expect(float(p["ahu_1.fan_speed_feedback"].value) < 0.01 and float(p["ahu_1.fan_speed_command"].value) > 0.9, "feedback coasts to zero while the VFD command winds up")
	expect(float(sim.units.ahu_1.flow_actual_m3_s) == 0.0 and float(p["vav_a.airflow"].value) == 0.0 and float(p["trunk.airflow"].value) == 0.0, "all airflow collapses")
	expect(float(sim.units.ahu_1.cooling_output) == 0.0 and float(sim.units.ahu_1.cooling_w) == 0.0 and float(sim.units.ahu_1.heating_w) == 0.0, "coils interlocked off after proof lost")
	expect(float(sim.units.ahu_1.damper_command) == 0.0 and float(sim.units.ahu_1.filter_dp_pa) == 0.0, "OA damper closes, no filter ΔP without flow")
	expect(float(sim.terminals.vav_a.damper_command) > 0.9, "starved VAVs drive their dampers open")
	expect(raised_at >= 15 and raised_at <= 60, "fan-failure alarm after its 20 s delay (raised at +%d s)" % raised_at)
	var listed: Array = alarms.list()
	expect(not listed.is_empty() and String(listed[0].id) == "fan_failure:ahu_1" and String(listed[0].severity) == "critical" and not bool(listed[0].acknowledged), "alarm list reports the critical fan failure first")
	expect(alarms.summary().begins_with("ALARMS  1 active"), "summary counts the alarm (%s)" % alarms.summary())
	for i in range(120):
		sim.step_for_test(30)
		alarms.evaluate(sim, 30.0)
	expect(float(sim.zone_state("class_a").true_temp_c) > t0 + 1.5, "zones drift warm without airflow (%.2f -> %.2f)" % [t0, sim.zone_state("class_a").true_temp_c])
	expect(alarms.active.has("high_temp:class_a"), "high space temperature alarm follows")
	alarms.acknowledge_all()
	expect(alarms.summary().ends_with("0 unacknowledged"), "acknowledge all")
	sim.set_scenario("Normal weekday")
	for i in range(120):
		sim.step_for_test(1)
		alarms.evaluate(sim, 1.0)
	expect(bool(value(sim, "ahu_1.fan_run_feedback")) and not alarms.active.has("fan_failure:ahu_1"), "fan restarts and the alarm clears")

func test_dirty_filter() -> void:
	var clean := make(wing(0.8, 0.8))
	var dirty := make(wing(0.8, 0.8), "Dirty filter")
	var alarms := Alarms.new()
	run_to(clean, 14.0)
	run_to(dirty, 13.9)
	for i in range(36):
		dirty.step_for_test(10)
		alarms.evaluate(dirty, 10.0)
	var c: Dictionary = clean.unit_state("ahu_1")
	var d: Dictionary = dirty.unit_state("ahu_1")
	expect(String(dirty.fault_targets().dirty_filter) == "ahu_1", "dirty filter targets the AHU with a filter")
	expect(float(d.filter_dp_pa) > 2.5 * float(c.filter_dp_pa), "dirty filter ΔP much higher (%.0f vs %.0f Pa)" % [d.filter_dp_pa, c.filter_dp_pa])
	expect(float(d.fan_feedback) >= float(c.fan_feedback) - 0.01, "fan works harder for the same demand (%.2f vs %.2f)" % [d.fan_feedback, c.fan_feedback])
	expect(alarms.active.has("filter:ahu_1") and String(alarms.active["filter:ahu_1"].severity) == "notice", "filter ΔP alarm raised")
	expect(float(c.filter_dp_pa) > 40.0 and float(c.filter_dp_pa) < 100.0, "clean filter ΔP plausible (%.0f Pa)" % c.filter_dp_pa)
	# At maximum demand the loaded filter limits what the fan can deliver.
	for sim in [clean, dirty]:
		sim.set_zone_setpoints("class_a", 18.0)
		sim.set_zone_setpoints("class_b", 18.0)
		sim.step_for_test(600)
	c = clean.unit_state("ahu_1")
	d = dirty.unit_state("ahu_1")
	expect(float(d.fan_feedback) > 0.99 and float(d.available_flow_m3_s) < float(c.available_flow_m3_s) - 0.03, "fan capacity reduced (%.3f vs %.3f m³/s)" % [d.available_flow_m3_s, c.available_flow_m3_s])
	expect(float(d.flow_actual_m3_s) < float(c.flow_actual_m3_s) - 0.05, "less air delivered at peak demand (%.3f vs %.3f)" % [d.flow_actual_m3_s, c.flow_actual_m3_s])

func test_stuck_damper() -> void:
	var topo := wing()
	var sim := make(topo, "Damper stuck at 25%")
	var alarms := Alarms.new()
	expect(String(sim.fault_targets().stuck_damper) == "vav_a", "stuck damper is the first VAV id")
	var always := true
	for i in range(1440):
		sim.step_for_test(10)
		alarms.evaluate(sim, 10.0)
		always = always and float(sim.terminals.vav_a.damper_feedback) == 0.25
	var t: Dictionary = sim.terminal_state("vav_a")
	expect(always and float(value(sim, "vav_a.damper_feedback")) == 25.0, "damper feedback frozen at 25 %")
	expect(float(t.damper_command) > 0.45 and bool(t.stuck), "controller commands it further open (%.2f)" % t.damper_command)
	expect(float(t.airflow_m3_s) < float(t.airflow_target_m3_s) - 0.05, "airflow short of its setpoint")
	expect(float(sim.zone_state("class_a").true_temp_c) > float(sim.zone_state("class_b").true_temp_c) + 0.3, "starved zone runs warm")
	expect(alarms.active.has("damper:vav_a") and not alarms.active.has("damper:vav_b"), "damper alarm on the stuck box only")
	expect(float(sim.units.ahu_1.static_sp_pa) > 200.0, "rogue zone drives the static pressure reset up")
	expect(audit(sim, topo) == "", "stuck damper conserves flow")

func test_sensor_bias() -> void:
	var sim := make(wing(), "Sensor bias")
	expect(String(sim.fault_targets().sensor_bias) == "class_a", "sensor bias on the first served zone")
	run_to(sim, 11.0)
	var z: Dictionary = sim.zone_state("class_a")
	expect(absf(float(z.temp_c) - float(z.true_temp_c) - 2.0) < 0.1, "measured reads 2 K high (%.2f vs %.2f)" % [z.temp_c, z.true_temp_c])
	expect(absf(float(value(sim, "vav_a.space_temp")) - float(value(sim, "vav_a.true_space_temp")) - 2.0) < 0.1, "published measured vs true differ")
	expect(float(z.true_temp_c) < 22.0, "control on the biased sensor overcools the real room (%.2f)" % z.true_temp_c)
	var b: Dictionary = sim.zone_state("class_b")
	expect(absf(float(b.temp_c) - float(b.true_temp_c)) < 0.06, "other zones read true within sensor noise")

func test_data_interruption() -> void:
	var sim := make(wing())
	run_to(sim, 9.0)
	sim.set_scenario("Data interruption")
	var alarms := Alarms.new()
	var before := float(sim.sim_seconds)
	var temp := float(sim.zones.class_a.true_temp_c)
	for i in range(60):
		sim.step_for_test(1)
		alarms.evaluate(sim, 1.0)
	var stale := true
	for p in sim.snapshot_points():
		stale = stale and p.quality_flags == ["stale", "communication_failure"] and p.original_status == "communication_failure"
	expect(stale, "every point flagged stale")
	var fan: Dictionary = Binding.defaults("ahu", "vav_a", "ahu_1").fan
	expect(fan.point_id == "ahu_1.fan_speed_feedback" and not Binding.evaluate(fan, points(sim)["ahu_1.fan_speed_feedback"]).known, "stale data cannot animate equipment")
	expect(float(sim.sim_seconds) == before + 60.0 and float(sim.zones.class_a.true_temp_c) != temp and float(sim.units.ahu_1.fan_feedback) > 0.2, "model keeps running underneath")
	expect(alarms.active.has("comm_failure"), "communication failure alarm")
	sim.set_scenario("Normal weekday")
	expect(points(sim)["ahu_1.fan_speed_feedback"].quality_flags == ["good"], "quality restored")
	expect(Binding.evaluate(fan, points(sim)["ahu_1.fan_speed_feedback"]).known and float(Binding.evaluate(fan, points(sim)["ahu_1.fan_speed_feedback"]).level) > 0.2, "fan binding animates from speed feedback")

func test_conservation_all_day() -> void:
	# Tight trunk so the shared limit is active for much of the day.
	var topo := wing(1.0, 0.55)
	var sim := make(topo, "Hot afternoon")
	var first := ""
	var limited := 0
	for i in range(17280):
		sim.step_for_test(5)
		var err := audit(sim, topo)
		if err != "" and first == "": first = "%s at %s" % [err, sim.weather().clock]
		if float(sim.route_flows.trunk) > 0.55 - 1.0e-6: limited += 1
	expect(first == "", "mass conservation and every capacity limit hold all day (%s)" % first)
	expect(limited > 100, "the shared trunk limit actually binds (%d samples)" % limited)
	expect(absf(float(sim.route_flows.run_a) - float(sim.terminals.vav_a.flow_actual_m3_s)) < 1.0e-12 and absf(float(sim.route_flows.branch_a1) - 0.5 * float(sim.terminals.vav_a.flow_actual_m3_s)) < 1.0e-12, "route airflow follows its weights")

func test_reconfigure() -> void:
	var topo := wing()
	var sim := make(topo)
	run_to(sim, 9.0)
	var zone_a: Dictionary = sim.zones.class_a.duplicate(true)
	var vav_a: Dictionary = sim.terminals.vav_a.duplicate(true)
	var ahu: Dictionary = sim.units.ahu_1.duplicate(true)
	sim.set_zone_setpoints("class_a", 22.5)
	var edited := wing()
	edited.zones.erase("class_b")
	edited.zones.class_a.neighbours.erase("class_b")
	edited.zones.corridor.neighbours.erase("class_b")
	edited.zones["office_c"] = {"label": "Office", "type": "office", "area_m2": 20.0, "exterior_wall_m2": 12.0, "window_m2": {"N": 3.0}, "neighbours": {"corridor": 12.0}}
	edited.terminals.erase("vav_b")
	edited.terminals["vav_c"] = {"label": "VAV-C", "zone_id": "office_c", "source_id": "ahu_1", "connected": true, "capacity_m3_s": 0.2, "layout": ["damper", "heating_coil"]}
	for lid in edited.limits: edited.limits[lid].weights.erase("vav_b")
	edited.limits.erase("vav_b")
	edited.limits.trunk.weights["vav_c"] = 1.0
	edited.routes.erase("run_b")
	edited.routes.trunk.weights.erase("vav_b")
	edited.routes.trunk.weights["vav_c"] = 1.0
	sim.configure(edited)
	expect(float(sim.zones.class_a.true_temp_c) == float(zone_a.true_temp_c) and float(sim.zones.class_a.co2_ppm) == float(zone_a.co2_ppm), "surviving zone keeps its temperature and CO2")
	expect(float(sim.zones.class_a.cool_setpoint_c) == 22.5, "surviving zone keeps its thermostat")
	expect(float(sim.terminals.vav_a.damper_feedback) == float(vav_a.damper_feedback) and float(sim.terminals.vav_a.cool_i) == float(vav_a.cool_i), "surviving VAV keeps damper and loop state")
	expect(float(sim.units.ahu_1.fan_feedback) == float(ahu.fan_feedback) and float(sim.units.ahu_1.supply_temp_c) == float(ahu.supply_temp_c), "surviving AHU keeps its state")
	expect(sim.zone_ids() == ["class_a", "corridor", "office_c"] and sim.terminal_ids() == ["vav_a", "vav_c"], "removed ids dropped, new ids added")
	var p := points(sim)
	expect(not p.has("vav_b.airflow") and not p.has("class_b.space_temp") and not p.has("run_b.airflow"), "removed equipment publishes nothing")
	expect(p.has("vav_c.airflow") and float(p["vav_c.airflow"].value) == 0.0 and p.has("office_c.space_temp"), "new VAV and zone published")
	var office := float(sim.zone_state("office_c").true_temp_c)
	expect(office > 20.0 and office < 27.0, "new zone starts at the building average (%.1f)" % office)
	expect(audit(sim, edited) == "", "reconfigure leaves flows consistent")
	sim.step_for_test(1800)
	expect(float(sim.terminals.vav_c.flow_actual_m3_s) > 0.03 and audit(sim, edited) == "", "new VAV comes on line")
	# Disconnect and shrink while paused: flows reduce immediately.
	var cut := edited.duplicate(true)
	cut.terminals.vav_a.connected = false
	cut.units.ahu_1.capacity_m3_s = 0.05
	sim.configure(cut)
	expect(float(sim.terminals.vav_a.flow_actual_m3_s) == 0.0 and float(sim.units.ahu_1.flow_actual_m3_s) <= 0.05 + 1.0e-9, "disconnect/capacity edits apply without advancing time")
	expect(audit(sim, cut) == "" and String(sim.terminal_state("vav_a").mode) == "Disconnected", "disconnected VAV reported")
	expect(not bool(sim.zone_state("class_a").served) and String(sim.zone_state("class_a").mode) == "Unconditioned", "zone without a connected VAV is unconditioned")
	# A VAV whose diffusers are outside any room gets its own small space.
	var loose := edited.duplicate(true)
	loose.terminals.vav_c.zone_id = ""
	sim.configure(loose)
	sim.step_for_test(600)
	expect(points(sim).has("vav_c.space_temp") and not sim.zone_ids().has("") and float(sim.terminals.vav_c.flow_actual_m3_s) > 0.0, "roomless VAV still simulates airflow")
	expect(finite_points(sim) == "" and audit(sim, loose) == "", "roomless VAV stays consistent")
	sim.configure({})
	expect(sim.snapshot_points().size() == 6, "clearing the building removes everything")

func test_unconditioned_zone() -> void:
	var topo := wing()
	topo.zones["store"] = {"label": "Store", "type": "storage", "area_m2": 20.0, "exterior_wall_m2": 20.0, "roof_m2": 20.0}
	var sim := make(topo, "Hot afternoon")
	var start := float(sim.zone_state("store").true_temp_c)
	run_to(sim, 16.0)
	var store: Dictionary = sim.zone_state("store")
	expect(not bool(store.served) and String(store.mode) == "Unconditioned", "zone with no VAV is unconditioned")
	expect(float(store.true_temp_c) > start + 3.0, "unconditioned store drifts toward the hot outdoors (%.1f -> %.1f)" % [start, store.true_temp_c])
	expect(float(store.true_temp_c) > float(sim.zone_state("class_a").true_temp_c) + 3.0, "conditioned classroom stays much cooler")
	expect(points(sim).has("store.space_temp") and points(sim).has("store.co2"), "every zone publishes space temperature and CO2")
	var cold := make(topo, "Cold morning")
	run_to(cold, 10.0)
	expect(float(cold.zone_state("store").true_temp_c) < 15.0 and float(cold.zone_state("class_a").true_temp_c) > 20.0, "cold day: store cools while the classroom is heated")

func test_unoccupied_and_night_cycle() -> void:
	var topo := wing()
	var sim := make(topo, "Unoccupied")
	run_to(sim, 12.0)
	var u: Dictionary = sim.unit_state("ahu_1")
	expect(not bool(value(sim, "site.occupied")) and String(u.mode) == "Off" and not bool(u.enabled), "unoccupied: AHU off within setback limits")
	expect(float(u.damper_feedback) == 0.0 and float(u.flow_actual_m3_s) == 0.0 and float(u.fan_feedback) == 0.0, "fan and OA damper closed")
	expect(float(value(sim, "vav_a.cool_setpoint")) == 29.0 and float(value(sim, "vav_a.heat_setpoint")) == 16.0, "setback setpoints 16 / 29 °C")
	expect(String(sim.zone_state("class_a").mode) == "Unoccupied" and String(value(sim, "vav_a.mode")) == "Unoccupied", "zones report Unoccupied")
	expect(float(sim.zone_state("class_a").internal_gain_w) < 400.0, "no people or lights when unoccupied")
	# Night cycle heating: served zones below 16 °C restart the AHU.
	for id in sim.zones:
		sim.zones[id].true_temp_c = 13.5
		sim.zones[id].mass_temp_c = 13.5
	sim.step_for_test(2)
	u = sim.unit_state("ahu_1")
	expect(String(u.mode) == "Setback" and bool(u.enabled), "night cycle: setback heating starts")
	sim.step_for_test(900)
	u = sim.unit_state("ahu_1")
	expect(float(u.damper_command) == 0.0 and float(u.heating_output) > 0.3 and float(u.supply_temp_c) > 25.0, "setback: OA closed, AHU heating")
	var stopped := -1
	for i in range(240):
		sim.step_for_test(60)
		if String(sim.units.ahu_1.mode) == "Off":
			stopped = i
			break
	expect(stopped > 0, "night cycle ends once zones recover")
	expect(float(sim.zone_state("class_a").true_temp_c) >= 16.9, "zones recovered above 17 °C (%.1f)" % sim.zone_state("class_a").true_temp_c)
	# Night cycle cooling.
	for id in sim.zones:
		sim.zones[id].true_temp_c = 31.0
		sim.zones[id].mass_temp_c = 31.0
	sim.step_for_test(2)
	expect(String(sim.units.ahu_1.mode) == "Setup", "night cycle: setup cooling starts above 29 °C")
	sim.step_for_test(900)
	expect(float(sim.units.ahu_1.cooling_output) > 0.2 or float(sim.units.ahu_1.damper_feedback) > 0.3, "setup cools with coil or economizer")
	expect(audit(sim, topo) == "", "night cycle conserves flow")

func test_installed_components_only() -> void:
	var topo := {
		"zones": {
			"room_x": {"type": "office", "area_m2": 30.0, "exterior_wall_m2": 15.0, "window_m2": {"W": 6.0}},
			"room_n": {"type": "office", "area_m2": 30.0, "exterior_wall_m2": 15.0},
			"room_t": {"type": "office", "area_m2": 30.0, "exterior_wall_m2": 15.0, "window_m2": {"S": 6.0}},
		},
		"units": {
			"ahu_fan_only": {"capacity_m3_s": 0.6, "layout": ["fan"]},
			"ahu_no_fan": {"capacity_m3_s": 0.6, "layout": ["damper", "filter", "cooling_coil", "heating_coil"]},
			"ahu_vent": {"capacity_m3_s": 0.6, "layout": ["damper", "filter", "fan"]},
		},
		"terminals": {
			"vav_x": {"zone_id": "room_x", "source_id": "ahu_fan_only", "connected": true, "capacity_m3_s": 0.3, "layout": ["damper"]},
			"vav_n": {"zone_id": "room_n", "source_id": "ahu_no_fan", "connected": true, "capacity_m3_s": 0.3, "layout": ["damper", "heating_coil"]},
			"vav_t": {"zone_id": "room_t", "source_id": "ahu_vent", "connected": true, "capacity_m3_s": 0.3, "layout": ["damper", "cooling_coil"]},
		},
	}
	for scenario in ["Hot afternoon", "Cold morning"]:
		var sim := make(topo, scenario)
		var ok := true
		for i in range(288):
			sim.step_for_test(150)
			var fo: Dictionary = sim.units.ahu_fan_only
			var nf: Dictionary = sim.units.ahu_no_fan
			ok = ok and float(fo.cooling_output) == 0.0 and float(fo.heating_output) == 0.0 and float(fo.damper_feedback) == 0.0 and not bool(fo.economizer) and float(fo.filter_dp_pa) == 0.0 and float(fo.cooling_w) == 0.0
			ok = ok and float(sim.terminals.vav_x.reheat_output) == 0.0 and float(sim.terminals.vav_x.heating_w) == 0.0
			ok = ok and float(nf.fan_feedback) == 0.0 and float(nf.flow_actual_m3_s) == 0.0 and float(nf.cooling_output) == 0.0 and float(sim.terminals.vav_n.flow_actual_m3_s) == 0.0
			ok = ok and float(sim.terminals.vav_t.reheat_output) == 0.0
		expect(ok, "%s: only installed components act (no coil, no damper, no fan => no effect)" % scenario)
	var faults := make(topo, "Fan failure")
	expect(String(faults.fault_targets().fan_failure) == "ahu_fan_only", "fan failure skips an AHU without a fan")
	faults.set_scenario("Dirty filter")
	expect(String(faults.fault_targets().dirty_filter) == "ahu_no_fan", "dirty filter picks the first AHU with a filter")
	faults.set_scenario("Sensor bias")
	expect(String(faults.fault_targets().sensor_bias) == "room_n", "sensor bias picks the first served zone")
	var hot := make(topo, "Hot afternoon")
	run_to(hot, 14.0)
	var t: Dictionary = hot.terminal_state("vav_t")
	expect(float(t.cooling_output) > 0.1 and float(t.discharge_temp_c) < float(hot.units.ahu_vent.supply_temp_c), "terminal cooling coil cools a ventilation-only AHU's air")
	expect(float(hot.units.ahu_fan_only.flow_actual_m3_s) > 0.0 and float(hot.units.ahu_fan_only.oa_fraction) == 0.0, "no OA damper: recirculation only")

func test_lights() -> void:
	var sim := make(wing())
	run_to(sim, 10.0)
	var on: Dictionary = sim.zone_state("class_a")
	expect(bool(on.lights_on), "lights on by schedule when occupied")
	sim.set_lights("class_a", false)
	sim.step_for_test(1)
	var off: Dictionary = sim.zone_state("class_a")
	expect(not bool(off.lights_on) and float(on.internal_gain_w) - float(off.internal_gain_w) > 400.0, "switching lights off removes ~8 W/m² of gain")
	run_to(sim, 18.02)
	expect(not bool(sim.zone_state("class_a").lights_on), "after hours lights are off")
	sim.set_lights("class_a", true)
	sim.step_for_test(1)
	expect(bool(sim.zone_state("class_a").lights_on), "manual override at night")
	run_to(sim, 7.02)
	expect(bool(sim.zone_state("class_a").lights_on) and float(sim.zones.class_a.lights_override) == -1.0, "schedule change sweeps the override")

func test_point_contract() -> void:
	var sim := make(wing())
	run_to(sim, 9.0)
	var p := points(sim)
	var site := {"site.outdoor_temp": ["number", "degC"], "site.occupied": ["bool", ""], "site.solar": ["number", "W/m2"], "site.time_of_day": ["number", "h"]}
	var ahu := {"fan_enable_cmd": ["bool", ""], "fan_run_feedback": ["bool", ""], "fan_state": ["enum", ""], "fan_speed_command": ["number", "fraction"],
		"fan_speed_feedback": ["number", "fraction"], "damper_command": ["number", "%"], "damper_feedback": ["number", "%"], "cooling_command": ["number", "%"],
		"cooling_output": ["number", "%"], "heating_command": ["number", "%"], "heating_output": ["number", "%"], "return_air_temp": ["number", "degC"],
		"mixed_air_temp": ["number", "degC"], "outdoor_air_fraction": ["number", "%"], "supply_air_temp": ["number", "degC"], "supply_setpoint": ["number", "degC"],
		"supply_airflow": ["number", "m3/s"], "available_airflow": ["number", "m3/s"], "duct_pressure": ["number", "Pa"], "duct_pressure_setpoint": ["number", "Pa"],
		"filter_pressure_drop": ["number", "Pa"], "cooling_power": ["number", "W"], "heating_power": ["number", "W"], "economizer": ["bool", ""]}
	var vav := {"space_temp": ["number", "degC"], "true_space_temp": ["number", "degC"], "cool_setpoint": ["number", "degC"], "heat_setpoint": ["number", "degC"],
		"discharge_temp": ["number", "degC"], "airflow_target": ["number", "m3/s"], "airflow": ["number", "m3/s"], "damper_command": ["number", "%"],
		"damper_feedback": ["number", "%"], "reheat_command": ["number", "%"], "reheat_output": ["number", "%"], "cooling_output": ["number", "%"],
		"cooling_loop": ["number", "%"], "heating_loop": ["number", "%"], "heating_power": ["number", "W"], "mode": ["enum", ""], "occupied": ["bool", ""]}
	var missing: Array = []
	for id in site:
		if not p.has(id) or p[id].value_type != site[id][0] or p[id].unit != site[id][1]: missing.append(id)
	for suffix in ahu:
		var id: String = "ahu_1." + suffix
		if not p.has(id) or p[id].value_type != ahu[suffix][0] or p[id].unit != ahu[suffix][1]: missing.append(id)
	for owner in ["vav_a", "vav_b"]:
		for suffix in vav:
			var id: String = owner + "." + suffix
			if not p.has(id) or p[id].value_type != vav[suffix][0] or p[id].unit != vav[suffix][1]: missing.append(id)
	for zone in ["class_a", "class_b", "corridor"]:
		if not p.has(zone + ".space_temp") or p[zone + ".co2"].unit != "ppm": missing.append(zone)
	for route in ["trunk", "run_a", "run_b", "branch_a1"]:
		if not p.has(route + ".airflow") or p[route + ".airflow"].unit != "m3/s": missing.append(route)
	expect(missing.is_empty(), "every contracted point id exists with its type and unit %s" % str(missing))
	var shape := true
	for point in sim.snapshot_points():
		shape = shape and point.source_id == "demo" and point.quality_flags == ["good"] and point.original_status == "ok" and float(point.source_timestamp) == float(sim.sim_seconds) and point.has("received_at")
		if String(point.unit) == "%": shape = shape and float(point.value) >= 0.0 and float(point.value) <= 100.0
		if String(point.unit) == "fraction": shape = shape and float(point.value) >= 0.0 and float(point.value) <= 1.0
	expect(shape, "point dictionaries have the provider shape and bounded percentages")
	expect(String(p["vav_a.mode"].value) in ["Cooling", "Heating", "Satisfied", "Unoccupied", "Disconnected"] and String(p["ahu_1.fan_state"].value) in ["Running", "Off"], "enum values from the documented sets")
	var noisy := absf(float(p["vav_a.space_temp"].value) - float(p["vav_a.true_space_temp"].value))
	expect(noisy > 0.0 and noisy <= 0.041, "measured space temperature carries tiny sensor noise (%.3f K)" % noisy)
	var damper: Dictionary = Binding.defaults("vav", "vav_a", "vav_a").damper
	var airflow: Dictionary = Binding.defaults("duct", "vav_a", "trunk").airflow
	expect(damper.point_id == "vav_a.damper_feedback" and Binding.evaluate(damper, p["vav_a.damper_feedback"]).known, "VAV damper binding resolves")
	expect(airflow.point_id == "trunk.airflow" and Binding.evaluate(airflow, p["trunk.airflow"]).known, "duct airflow binding resolves")
	var coil: Dictionary = Binding.defaults("ahu", "vav_a", "ahu_1").cooling_coil
	expect(coil.point_id == "ahu_1.cooling_output" and Binding.evaluate(coil, p["ahu_1.cooling_output"]).known, "AHU coil binding resolves")

func test_accessors_and_snapshot() -> void:
	var sim := make(wing())
	run_to(sim, 8.0)
	var z: Dictionary = sim.zone_state("class_a")
	z.true_temp_c = 99.0
	(z.terminals as Array).append("junk")
	var u: Dictionary = sim.unit_state("ahu_1")
	(u.layout as Array).clear()
	var t: Dictionary = sim.terminal_state("vav_a")
	t.damper_feedback = 5.0
	var w: Dictionary = sim.weather()
	w.outdoor_temp_c = -99.0
	expect(float(sim.zone_state("class_a").true_temp_c) < 40.0 and sim.zone_state("class_a").terminals == ["vav_a"], "zone_state returns a copy")
	expect((sim.units.ahu_1.layout as Array).size() == 5 and float(sim.terminals.vav_a.damper_feedback) <= 1.0, "unit/terminal state are copies")
	expect(float(sim.weather().outdoor_temp_c) > 0.0 and String(sim.weather().clock) == "08:00", "weather is a copy with a clock")
	var first: Array = sim.snapshot_points()
	first.append({"point_id": "junk"})
	var second: Array = sim.snapshot_points()
	expect(second.size() == first.size() - 1, "snapshot array is fresh each call")
	var values_a: Array = second.map(func(p: Dictionary) -> Variant: return p.value)
	var values_b: Array = sim.snapshot_points().map(func(p: Dictionary) -> Variant: return p.value)
	expect(values_a == values_b, "snapshot stable when nothing changed")
	sim.step_for_test(1)
	var values_c: Array = sim.snapshot_points().map(func(p: Dictionary) -> Variant: return p.value)
	expect(values_c != values_b, "snapshot refreshes after a step")
	sim.running = false
	expect(sim.advance(1.0) == 0, "paused: no steps")
	sim.running = true
	sim.speed = 60.0
	expect(sim.advance(1000.0) == 3600 and float(sim.accumulator) < 1.0, "advance caps at 3600 steps and drops the backlog")
	expect(sim.advance(NAN) == 0 and sim.advance(-1.0) == 0 and sim.advance(INF) == 0, "advance rejects invalid deltas")

func test_full_days_bounded() -> void:
	var topo := lobby_wing()
	topo.zones["store"] = {"type": "storage", "area_m2": 12.0, "exterior_wall_m2": 12.0}
	# Full days for the most demanding scenarios, the morning for the rest.
	var full_day := ["Normal weekday", "Cold morning", "Fan failure", "Heat wave"]
	for scenario in Sim.SCENARIOS:
		var sim := make(topo, scenario)
		var bad := ""
		var samples := 288 if scenario in full_day else 72
		for i in range(samples):
			sim.step_for_test(300)
			var nan := finite_points(sim)
			if nan != "" and bad == "": bad = "non-finite " + nan
			for id in sim.zones:
				var temp := float(sim.zones[id].true_temp_c)
				var co2 := float(sim.zones[id].co2_ppm)
				if (temp < -5.0 or temp > 50.0 or co2 < 350.0 or co2 > 9000.0) and bad == "": bad = "%s out of range %.1f °C %.0f ppm at %s" % [id, temp, co2, sim.weather().clock]
			for id in sim.units:
				var sat := float(sim.units[id].supply_temp_c)
				if (sat < 5.0 or sat > 45.0 or float(sim.units[id].duct_pressure_pa) > 1000.0) and bad == "": bad = "%s SAT/pressure out of range" % id
			if audit(sim, topo) != "" and bad == "": bad = audit(sim, topo)
		expect(bad == "", "%s: %d h bounded and finite (%s)" % [scenario, samples / 12, bad])
		expect(float(sim.sim_seconds) == 23400.0 + samples * 300.0, "%s: clock advanced exactly" % scenario)

func test_speed_equivalence() -> void:
	var a := make(wing())
	var b := make(wing())
	b.speed = 60.0
	for i in range(7200): a.advance(0.5)
	for i in range(120): b.advance(0.5)
	expect(float(a.sim_seconds) == float(b.sim_seconds) and float(a.sim_seconds) == 23400.0 + 3600.0, "1× and 60× advance the same simulated time")
	expect(state_equal(a, b), "1× and 60× produce identical state")
	var va: Array = a.snapshot_points().map(func(p: Dictionary) -> Variant: return p.value)
	var vb: Array = b.snapshot_points().map(func(p: Dictionary) -> Variant: return p.value)
	expect(va == vb, "1× and 60× publish identical values")

func test_checkpoint_restore() -> void:
	var topo := lobby_wing()
	var a := make(topo, "Hot afternoon")
	run_to(a, 10.0)
	a.set_zone_setpoints("class_b", 22.0)
	a.set_lights("class_a", false)
	a.set_open_connections([{"a": "lobby", "b": "outside", "kind": "door"}])
	a.step_for_test(123)
	var state: Dictionary = a.checkpoint()
	var b := Sim.new()
	b.configure(topo)
	b.restore_checkpoint(state)
	var c := Sim.new()
	c.restore_checkpoint(state)
	c.configure(topo)
	expect(state_equal(a, b), "restore after configure reproduces the state")
	expect(state_equal(a, c), "restore before configure applies stashed state")
	a.step_for_test(3600)
	b.step_for_test(3600)
	c.step_for_test(3600)
	expect(state_equal(a, b) and state_equal(a, c), "restored simulations continue identically for an hour")
	var parsed: Variant = JSON.parse_string(JSON.stringify(state))
	var d := Sim.new()
	d.configure(topo)
	d.restore_checkpoint(parsed)
	d.step_for_test(3600)
	expect(absf(float(d.zones.lobby.true_temp_c) - float(a.zones.lobby.true_temp_c)) < 0.05 and d.scenario == "Hot afternoon", "JSON round-trip restore continues closely")
	var e := make(topo)
	e.restore_checkpoint({"version": 99, "sim_seconds": -5.0, "scenario": "Nope", "speed": 1.0e9, "accumulator": "x", "running": "yes", "step_index": NAN,
		"zones": {"class_a": {"true_temp_c": NAN, "co2_ppm": 1.0e9, "cool_setpoint_c": "hot", "heat_setpoint_c": 29.0}, 7: {}, "ghost": {"true_temp_c": 20.0}},
		"units": {"ahu_1": {"fan_feedback": 7.0, "mode": "Turbo", "enabled": "yes", "damper_feedback": -3.0}}, "terminals": 5, "openings": "door"})
	e.step_for_test(600)
	expect(float(e.speed) == 60.0 and float(e.sim_seconds) >= 600.0 and e.scenario == "Normal weekday", "garbage checkpoint fields are clamped or ignored")
	expect(float(e.zones.class_a.co2_ppm) <= 10000.0 and float(e.units.ahu_1.fan_feedback) <= 1.0 and float(e.zones.class_a.heat_setpoint_c) <= float(e.zones.class_a.cool_setpoint_c) - 1.0, "restored values clamped and deadband enforced")
	expect(finite_points(e) == "" and audit(e, topo) == "", "garbage checkpoint leaves a consistent model")
	var old := make(topo)
	old.restore_checkpoint({"version": 2, "sim_seconds": 30000.0, "scenario": "Cold morning", "rooms": {"class_a": {"true_temp_c": 18.5, "cool_setpoint_c": 21.0, "label": "East", "connected": true}}, "units": {"ahu": {"fan_feedback": 0.5}}})
	expect(float(old.zones.class_a.true_temp_c) == 18.5 and float(old.zones.class_a.cool_setpoint_c) == 21.0 and old.scenario == "Cold morning", "version-2 room data restores zone temperature and setpoint")
	old.restore_checkpoint({})
	old.step_for_test(60)
	expect(finite_points(old) == "", "empty checkpoint is a no-op")

func test_determinism() -> void:
	var a := make(lobby_wing(), "Hot afternoon")
	var b := make(lobby_wing(), "Hot afternoon")
	run_to(a, 12.0)
	run_to(b, 12.0)
	expect(state_equal(a, b), "two runs are bit-identical")
	var va: Array = a.snapshot_points().map(func(p: Dictionary) -> Variant: return p.value)
	var vb: Array = b.snapshot_points().map(func(p: Dictionary) -> Variant: return p.value)
	expect(va == vb, "published values (including sensor noise) are deterministic")
	var c := make(lobby_wing(), "Hot afternoon")
	c.reset()
	c.set_scenario("Hot afternoon")
	run_to(c, 12.0)
	expect(state_equal(a, c), "reset() returns to an identical start")

func test_performance() -> void:
	# 40 zones, 8 AHUs, 40 VAVs: a large player building.
	var topo := {"zones": {}, "units": {}, "terminals": {}, "limits": {}, "routes": {}}
	var types := ["classroom", "office", "corridor", "conference", "restroom", "library", "gym", "break_room"]
	for u in range(8):
		var ahu := "ahu_%d" % u
		topo.units[ahu] = {"capacity_m3_s": 2.2, "layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"]}
		topo.limits[ahu + "_trunk"] = {"capacity_m3_s": 2.0, "weights": {}}
		topo.routes[ahu + "_main"] = {"capacity_m3_s": 2.0, "weights": {}}
		for k in range(5):
			var i := u * 5 + k
			var zone := "zone_%02d" % i
			var neighbours := {}
			if i > 0: neighbours["zone_%02d" % (i - 1)] = 20.0
			if i < 39: neighbours["zone_%02d" % (i + 1)] = 20.0
			topo.zones[zone] = {"type": types[i % types.size()], "area_m2": 30.0 + (i % 5) * 15.0, "exterior_wall_m2": 20.0, "window_m2": {"N": 2.0, "E": 1.0, "S": 4.0, "W": 1.0}, "neighbours": neighbours, "exterior_doors": 1 if i % 7 == 0 else 0}
			var vav := "vav_%02d" % i
			topo.terminals[vav] = {"zone_id": zone, "source_id": ahu, "connected": true, "capacity_m3_s": 0.45, "layout": ["damper", "heating_coil"]}
			topo.limits[ahu + "_trunk"].weights[vav] = 1.0
			topo.routes[ahu + "_main"].weights[vav] = 1.0
			topo.limits[vav] = {"capacity_m3_s": 0.45, "weights": {vav: 1.0}}
			topo.routes[vav + "_run"] = {"capacity_m3_s": 0.45, "weights": {vav: 1.0}}
	var sim := make(topo)
	sim.set_open_connections([{"a": "zone_03", "b": "outside", "kind": "door"}, {"a": "zone_10", "b": "zone_11", "kind": "door"}])
	run_to(sim, 9.0)
	var started := Time.get_ticks_usec()
	sim.step_for_test(600)
	var per_step_ms := float(Time.get_ticks_usec() - started) / 600.0 / 1000.0
	started = Time.get_ticks_usec()
	var count := 0
	for i in range(20):
		sim.step_for_test(1)
		count = sim.snapshot_points().size()
	var snapshot_ms := float(Time.get_ticks_usec() - started) / 20.0 / 1000.0 - per_step_ms
	print("PERF 40 zones / 8 AHUs / 40 VAVs: %.3f ms per 1 s step (%.4f ms per zone), snapshot %d points %.2f ms" % [per_step_ms, per_step_ms / 40.0, count, snapshot_ms])
	expect(per_step_ms < 8.0, "step cost under 0.2 ms per zone (%.3f ms for 40 zones)" % per_step_ms)
	expect(audit(sim, topo) == "" and finite_points(sim) == "", "large building stays consistent")
	var served := 0
	for id in sim.zone_ids():
		var z: Dictionary = sim.zone_state(id)
		if absf(float(z.true_temp_c) - 23.0) < 1.5: served += 1
	expect(served >= 30, "large building mostly at setpoint by 09:10 (%d of 40)" % served)

# ---------------------------------------------------------------- BAS programming, targeted faults, meters

func test_controls_validation() -> void:
	var sim := make(wing())
	expect(sim.controls_state() == Sim.DEFAULT_CONTROLS, "controls start at the documented defaults")
	sim.set_controls({"occupied_start_h": -5.0, "occupied_end_h": 99.0, "sat_fixed_c": 3.0, "static_fixed_pa": 9000.0, "vav_min_fraction": 2.0, "economizer": "no", "junk": 1, "dcv": false})
	var c: Dictionary = sim.controls_state()
	expect(float(c.occupied_start_h) == 0.0 and float(c.occupied_end_h) == 24.0 and float(c.sat_fixed_c) == 10.0 and float(c.static_fixed_pa) == 500.0, "numeric controls are clamped")
	expect(float(c.vav_min_fraction) == 0.8 and bool(c.economizer) and not bool(c.dcv) and not c.has("junk"), "booleans need bools, unknown keys ignored")
	sim.set_controls({"occupied_start_h": 12.0, "occupied_end_h": 9.0})
	c = sim.controls_state()
	expect(float(c.occupied_end_h) >= float(c.occupied_start_h) + 0.5, "schedule always at least 30 min long (%.1f-%.1f)" % [c.occupied_start_h, c.occupied_end_h])
	sim.set_controls({"occupied_start_h": NAN, "sat_fixed_c": INF})
	expect(float(sim.controls_state().occupied_start_h) == float(c.occupied_start_h), "non-finite values ignored")
	var state: Dictionary = sim.checkpoint()
	var copy := make(wing())
	copy.restore_checkpoint(JSON.parse_string(JSON.stringify(state)))
	expect(copy.controls_state() == sim.controls_state(), "controls survive a checkpoint")

func test_controls_sequences() -> void:
	# Economizer off on a mild day: no free cooling, the chilled-water valve works instead.
	var econ := make(wing(), "Economizer day")
	var mech := make(wing(), "Economizer day")
	mech.set_controls({"economizer": false})
	run_to(econ, 10.5)
	run_to(mech, 10.5)
	expect(bool(econ.unit_state("ahu_1").economizer) and not bool(mech.unit_state("ahu_1").economizer), "economizer enable follows the setting")
	expect(float(mech.units.ahu_1.damper_feedback) <= Sim.DCV_MAX_POSITION + 0.01 and float(mech.units.ahu_1.cooling_output) > float(econ.units.ahu_1.cooling_output) + 0.05, "without it the OA damper stays at minimum and the cooling valve opens (%.2f vs %.2f)" % [mech.units.ahu_1.cooling_output, econ.units.ahu_1.cooling_output])
	# SAT reset off: a fixed supply setpoint.
	var fixed := make(wing())
	fixed.set_controls({"sat_reset": false, "sat_fixed_c": 14.0})
	run_to(fixed, 9.0)
	expect(absf(float(fixed.units.ahu_1.sat_sp_c) - 14.0) < 1.0e-9, "SAT setpoint held at the fixed value (%.2f)" % fixed.units.ahu_1.sat_sp_c)
	# Static reset off: a fixed duct static setpoint the fan chases.
	var stat := make(wing())
	stat.set_controls({"static_reset": false, "static_fixed_pa": 400.0})
	run_to(stat, 10.0)
	expect(absf(float(stat.units.ahu_1.static_sp_pa) - 400.0) < 1.0e-9 and absf(float(stat.units.ahu_1.duct_pressure_pa) - 400.0) < 40.0, "fan holds the fixed static (%.0f Pa)" % stat.units.ahu_1.duct_pressure_pa)
	# DCV off: design minimum outdoor air whatever the CO2.
	var dcv := make(wing(), "Hot afternoon")
	dcv.set_controls({"dcv": false})
	run_to(dcv, 8.0)
	expect(absf(float(dcv.units.ahu_1.damper_command) - Sim.DCV_OFF_POSITION) < 1.0e-6, "without DCV the OA damper holds its design minimum (%.2f)" % dcv.units.ahu_1.damper_command)
	# VAV minimum airflow.
	var vmin := make(wing())
	vmin.set_controls({"vav_min_fraction": 0.5})
	run_to(vmin, 7.25)
	expect(absf(float(vmin.terminal_state("vav_a").min_airflow_m3_s) - 0.225) < 1.0e-6, "occupied VAV minimum follows the setting (%.3f)" % vmin.terminal_state("vav_a").min_airflow_m3_s)
	run_to(vmin, 10.0)
	expect(audit(vmin, wing()) == "" and audit(stat, wing()) == "" and audit(mech, wing()) == "", "flows stay conserved under every setting")

func test_schedule_and_people() -> void:
	# A late HVAC schedule: people arrive at 07:00 anyway.
	var late := make(wing(), "Hot afternoon")
	late.set_controls({"occupied_start_h": 9.0, "optimal_start": false})
	run_to(late, 8.0)
	var weather: Dictionary = late.weather()
	expect(bool(weather.people_present) and not bool(weather.occupied), "people present before the HVAC schedule starts")
	expect(String(late.units.ahu_1.mode) == "Off" and float(late.zone_state("class_a").occupants) > 1.0, "AHU off while classes are in")
	var on_time := make(wing(), "Hot afternoon")
	run_to(on_time, 8.75)
	run_to(late, 8.75)
	expect(float(late.zone_state("class_a").true_temp_c) > float(on_time.zone_state("class_a").true_temp_c) + 0.8, "the late start leaves rooms warm (%.1f vs %.1f)" % [late.zone_state("class_a").true_temp_c, on_time.zone_state("class_a").true_temp_c])
	run_to(late, 9.5)
	expect(String(late.units.ahu_1.mode) == "Occupied", "AHU starts on its schedule")
	# Optimal start follows the schedule's start time.
	var early := make(wing(), "Cold morning")
	early.set_controls({"occupied_start_h": 9.0})
	run_to(early, 7.5)
	expect(String(early.units.ahu_1.mode) == "Warm-up", "optimal start moves with the schedule (%s at 07:30)" % early.units.ahu_1.mode)
	# A 24/7 schedule keeps the fan running at night.
	var always := make(wing())
	always.set_controls({"occupied_start_h": 0.0, "occupied_end_h": 24.0})
	run_to(always, 22.0)
	expect(String(always.units.ahu_1.mode) == "Occupied" and not bool(always.weather().people_present), "24/7 schedule runs after people leave")

func test_targeted_faults() -> void:
	var topo := wing()
	var sim := make(topo)
	sim.set_faults([{"kind": "stuck_damper", "target": "vav_b", "value": 0.1}, {"kind": "stuck_damper", "target": "vav_b", "value": 0.9},
		{"kind": "nope", "target": "vav_a"}, {"kind": "fan_failure", "target": ""}, "junk", {"kind": "sensor_bias", "target": "class_a", "value": -40.0},
		{"kind": "reheat_stuck", "target": "vav_a", "value": 7.0}])
	var listed: Array = sim.faults()
	expect(listed.size() == 3, "invalid and duplicate faults dropped (%d kept)" % listed.size())
	expect(float(listed[0].value) == 0.1 and float(listed[1].value) == -6.0 and float(listed[2].value) == 1.0, "fault values clamped")
	run_to(sim, 10.0)
	expect(float(sim.terminals.vav_b.damper_feedback) == 0.1 and bool(sim.terminal_state("vav_b").stuck) and not bool(sim.terminal_state("vav_a").stuck), "targeted damper frozen at its value")
	expect(String(sim.fault_targets().stuck_damper) == "", "no scenario fault involved")
	var z: Dictionary = sim.zone_state("class_a")
	expect(absf(float(z.temp_c) - float(z.true_temp_c) + 6.0) < 0.05, "sensor bias aimed at one zone (%.2f vs %.2f)" % [z.temp_c, z.true_temp_c])
	expect(float(sim.terminals.vav_a.reheat_output) == 1.0 and bool(sim.terminal_state("vav_a").reheat_stuck), "reheat valve frozen open")
	expect(audit(sim, topo) == "", "faulted building conserves flow")
	# Repairs.
	expect(sim.clear_fault("vav_b", "stuck_damper") and not sim.clear_fault("vav_b", "stuck_damper"), "clear_fault reports what it removed")
	sim.step_for_test(240)
	expect(float(sim.terminals.vav_b.damper_feedback) != 0.1 and absf(float(sim.terminals.vav_b.damper_feedback) - float(sim.terminals.vav_b.damper_command)) < 0.05, "repaired damper follows its command again")
	sim.clear_fault("vav_a")
	sim.clear_fault("class_a")
	sim.step_for_test(60)
	z = sim.zone_state("class_a")
	expect(sim.faults().is_empty() and absf(float(z.temp_c) - float(z.true_temp_c)) < 0.05, "every fault cleared")
	# A fault aimed at equipment that does not exist yet waits for it.
	var later := make(topo)
	later.set_faults([{"kind": "fan_failure", "target": "ahu_9"}])
	var bigger := topo.duplicate(true)
	bigger.units["ahu_9"] = {"label": "AHU-9", "capacity_m3_s": 0.5, "layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"]}
	later.configure(bigger)
	expect(bool(later.units.ahu_9.fan_fault) and not bool(later.units.ahu_1.fan_fault), "fault applies once its target is configured")
	var copy := make(bigger)
	copy.restore_checkpoint(JSON.parse_string(JSON.stringify(later.checkpoint())))
	expect(copy.faults() == later.faults() and bool(copy.units.ahu_9.fan_fault), "faults survive a checkpoint")
	# Cold morning with the reheat valve stuck shut: the room cannot warm up.
	var cold := make(topo, "Cold morning")
	var stuck := make(topo, "Cold morning")
	stuck.set_faults([{"kind": "reheat_stuck", "target": "vav_a", "value": 0.0}])
	run_to(cold, 9.0)
	run_to(stuck, 9.0)
	var t: Dictionary = stuck.terminal_state("vav_a")
	expect(float(t.reheat_command) > 0.3 and float(t.reheat_output) == 0.0, "controller asks for reheat the valve cannot give (%.2f)" % t.reheat_command)
	expect(float(stuck.zone_state("class_a").true_temp_c) < float(cold.zone_state("class_a").true_temp_c) - 0.5, "room stays cold (%.1f vs %.1f)" % [stuck.zone_state("class_a").true_temp_c, cold.zone_state("class_a").true_temp_c])

func test_targeted_fault_alarms() -> void:
	# Chilled-water valve stuck shut on a hot day: SAT climbs, the alarm follows.
	var topo := wing()
	var sim := make(topo, "Hot afternoon")
	var alarms := Alarms.new()
	run_to(sim, 11.0)
	sim.set_faults([{"kind": "chw_valve_stuck", "target": "ahu_1", "value": 0.0}])
	for i in range(90):
		sim.step_for_test(10)
		alarms.evaluate(sim, 10.0)
	var u: Dictionary = sim.unit_state("ahu_1")
	expect(float(u.cooling_output) == 0.0 and float(u.cooling_command) > 0.9, "valve stays shut while the loop calls for cooling")
	expect(float(u.supply_temp_c) > float(u.supply_setpoint_c) + 4.0, "supply air runs warm (%.1f vs %.1f)" % [u.supply_temp_c, u.supply_setpoint_c])
	expect(alarms.active.has("sat_high:ahu_1"), "supply-air-temperature-high alarm")
	# Outdoor-air damper stuck wide open on a hot day: more cooling load.
	var normal := make(topo, "Hot afternoon")
	var open := make(topo, "Hot afternoon")
	open.set_faults([{"kind": "oa_damper_stuck", "target": "ahu_1", "value": 1.0}])
	run_to(normal, 14.0)
	run_to(open, 14.0)
	expect(float(open.units.ahu_1.oa_fraction) == 1.0 and float(open.units.ahu_1.cooling_w) > float(normal.units.ahu_1.cooling_w) * 1.15, "100%% outdoor air raises the cooling load (%.0f vs %.0f W)" % [open.units.ahu_1.cooling_w, normal.units.ahu_1.cooling_w])
	var quiet := make(topo)
	var none := Alarms.new()
	run_to(quiet, 9.0)
	for i in range(120):
		quiet.step_for_test(30)
		none.evaluate(quiet, 30.0)
	expect(none.list().is_empty(), "no SAT alarm on a normal day (%s)" % str(none.list()))

func test_meters() -> void:
	var topo := wing()
	var sim := make(topo)
	run_to(sim, 7.0)
	sim.reset_meters()
	expect(float(sim.energy().cost_usd) == 0.0 and sim.comfort().zones.is_empty(), "meters start at zero")
	run_to(sim, 18.0)
	var e: Dictionary = sim.energy()
	var c: Dictionary = sim.comfort(["class_a", "class_b"])
	expect(absf(float(e.hours) - 11.0) < 0.01 and float(e.electric_kwh) > 1.0 and float(e.cost_usd) > 0.0 and float(e.peak_kw) > 0.0, "an occupied day uses energy (%.1f kWh, $%.2f)" % [e.electric_kwh, e.cost_usd])
	expect(absf(float(e.electric_kwh) - float(e.fan_kwh) - float(e.cooling_kwh)) < 1.0e-6, "electricity = fans + chilled water / COP")
	expect(absf(float(c.occupied_h) - 22.0) < 0.05 and absf(float(c.zones.class_a.occupied_h) - 11.0) < 0.01, "comfort counts the hours people are in (%.2f)" % c.occupied_h)
	expect(float(c.setpoint_pct) > 85.0 and float(c.range_pct) > 85.0, "a healthy building is comfortable (%.0f %% / %.0f %%)" % [c.setpoint_pct, c.range_pct])
	expect(not sim.comfort().zones.has("corridor") or float(sim.comfort().zones.corridor.occupied_h) > 0.0, "comfort zones are rooms with people")
	var p := points(sim)
	expect(p.has("site.electric_power") and p.has("site.energy_cost") and absf(float(p["site.energy_cost"].value) - float(e.cost_usd)) < 1.0e-9, "site energy points published")
	var copy := make(topo)
	copy.restore_checkpoint(JSON.parse_string(JSON.stringify(sim.checkpoint())))
	expect(absf(float(copy.energy().cost_usd) - float(e.cost_usd)) < 1.0e-6 and absf(float(copy.comfort(["class_a", "class_b"]).setpoint_pct) - float(c.setpoint_pct)) < 1.0e-6, "meters survive a checkpoint")
	# A dead fan ruins comfort.
	var broken := make(topo, "Hot afternoon")
	broken.set_faults([{"kind": "fan_failure", "target": "ahu_1"}])
	run_to(broken, 7.0)
	broken.reset_meters()
	run_to(broken, 18.0)
	var bc: Dictionary = broken.comfort(["class_a", "class_b"])
	expect(float(bc.setpoint_pct) < 40.0 and float(bc.zones.class_a.warm_kh) > 5.0, "no airflow, no comfort (%.0f %%, %.1f K·h warm)" % [bc.setpoint_pct, bc.zones.class_a.warm_kh])
	expect(float(broken.energy().fan_kwh) == 0.0, "a failed fan uses no fan energy")

func test_wasteful_programming() -> void:
	# The tune-up jobs rely on bad programming costing real money.
	var good := make(lobby_wing(), "Economizer day")
	var bad := make(lobby_wing(), "Economizer day")
	bad.set_controls({"occupied_start_h": 4.0, "occupied_end_h": 22.0, "sat_reset": false, "sat_fixed_c": 12.8, "static_reset": false, "static_fixed_pa": 400.0, "economizer": false, "dcv": false, "vav_min_fraction": 0.6})
	for sim in [good, bad]:
		run_to(sim, 0.0)
		sim.reset_meters()
		sim.step_for_test(86400)
	var cost_good := float(good.energy().cost_usd)
	var cost_bad := float(bad.energy().cost_usd)
	expect(cost_bad > cost_good * 1.35, "wasteful programming costs much more ($%.2f vs $%.2f)" % [cost_bad, cost_good])
	var zones := ["class_a", "class_b", "lobby"]
	expect(float(good.comfort(zones).range_pct) > 90.0, "good programming stays comfortable (%.0f %%)" % good.comfort(zones).range_pct)

func test_time_lapse() -> void:
	var a := make(wing())
	var b := make(wing())
	a.speed = Sim.MAX_SPEED
	var steps := 0
	for frame in range(120): steps += a.advance(1.0 / 60.0)
	b.step_for_test(steps)
	expect(steps == 3600 and state_equal(a, b), "time-lapse at %.0f× matches fixed steps (%d steps)" % [Sim.MAX_SPEED, steps])
	a.speed = 1.0e9
	expect(a.advance(1.0) == int(Sim.MAX_SPEED) and a.advance(10.0) == Sim.MAX_STEPS_PER_ADVANCE and float(a.accumulator) < 1.0, "speed capped and backlog bounded")
	expect(float(a.checkpoint().speed) <= Sim.SAVED_SPEED_MAX, "time-lapse speed is not saved")
	var day := make(wing())
	day.set_time_of_day(9.0 * 3600.0)
	expect(String(day.weather().clock) == "09:00" and bool(day.weather().occupied), "set_time_of_day jumps the clock")
