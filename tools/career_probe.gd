extends SceneTree

# Diagnostic probe: where does a starter's airflow go at 15:00 on a scenario day?
#   Godot --headless --path . --script res://tools/career_probe.gd -- school "Normal weekday"

const Templates := preload("res://scripts/model/templates.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var template := args[0] if args.size() > 0 else "school"
	var scenario := args[1] if args.size() > 1 else "Normal weekday"
	var hour := float(args[2]) if args.size() > 2 else 15.0
	var model := Templates.create(template)
	var index := BuildingIndex.new()
	index.rebuild(model.objects, model.site)
	var network := RouteNetwork.evaluate(model.objects)
	var topology := ZoneTopology.build(index, model.objects, network)
	var sim := DemoSimulation.new()
	sim.configure(topology)
	sim.reset()
	sim.set_scenario(scenario)
	sim.step_for_test(fposmod(hour * 3600.0 - float(sim.sim_seconds), 86400.0))
	print("== %s · %s · %s  OAT %.1f" % [template, scenario, sim.weather().clock, sim.weather().outdoor_temp_c])
	for id in sim.unit_ids():
		var u: Dictionary = sim.unit_state(id)
		print("AHU %s cap %.2f  flow %.2f avail %.2f fan %.2f  SAT %.1f sp %.1f  static %.0f/%.0f  cool %.0f%%  OA %.0f%%" % [u.label, u.capacity_m3_s, u.supply_airflow_m3_s, u.available_airflow_m3_s, u.fan_feedback, u.supply_temp_c, u.supply_setpoint_c, u.duct_pressure_pa, u.duct_pressure_setpoint_pa, u.cooling_output * 100.0, u.oa_fraction * 100.0])
	for id in sim.terminal_ids():
		var t: Dictionary = sim.terminal_state(id)
		var z: Dictionary = sim.zone_state(String(t.zone_id))
		print("  VAV %-22s cap %.2f  sp %.3f act %.3f  damper %3.0f%%  room %.1f (cool sp %.1f)  load %5.0f W  area %.0f" % [t.label, t.capacity_m3_s, t.airflow_target_m3_s, t.airflow_m3_s, t.damper_feedback * 100.0, z.get("true_temp_c", 0.0), t.cool_setpoint_c, float(z.get("internal_gain_w", 0.0)) + float(z.get("solar_gain_w", 0.0)), z.get("area_m2", 0.0)])
	var tight: Array = []
	for id in topology.limits:
		var limit: Dictionary = topology.limits[id]
		var flow := 0.0
		for vav in limit.weights: flow += float(sim.terminals[vav].flow_actual_m3_s) * float(limit.weights[vav])
		if flow > float(limit.capacity_m3_s) * 0.97: tight.append("%s %.2f/%.2f" % [id, flow, limit.capacity_m3_s])
	print("limits at capacity: ", tight)
	quit(0)
