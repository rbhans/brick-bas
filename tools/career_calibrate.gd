extends SceneTree

# Calibration for career jobs: runs each starter building (as seeded) through
# a scenario day with default and wasteful BAS programming and with faults,
# and prints energy and comfort. Job targets are derived from these at runtime;
# this tool shows the margins so the jobs stay winnable.
#   Godot --headless --path . --script res://tools/career_calibrate.gd

const Templates := preload("res://scripts/model/templates.gd")
const WASTEFUL := {"occupied_start_h": 4.0, "occupied_end_h": 22.0, "sat_reset": false, "sat_fixed_c": 12.8, "static_reset": false, "static_fixed_pa": 400.0, "economizer": false, "dcv": false, "vav_min_fraction": 0.6}

func _init() -> void:
	for template in ["studio", "office", "school"]:
		var model := Templates.create(template)
		var index := BuildingIndex.new()
		index.rebuild(model.objects, model.site)
		var topology := ZoneTopology.build(index, model.objects, RouteNetwork.evaluate(model.objects))
		var comfort_zones: Array = []
		for room in index.rooms:
			if String(room.type) not in ["corridor", "restroom", "storage", "mechanical"]: comfort_zones.append(String(room.id))
		print("== %s: %d zones, %d AHUs, %d VAVs, %d comfort rooms" % [template, topology.zones.size(), topology.units.size(), topology.terminals.size(), comfort_zones.size()])
		for scenario in ["Normal weekday", "Hot afternoon", "Economizer day", "Cold morning", "Heat wave"]:
			for programming in ["default", "wasteful"]:
				var sim := DemoSimulation.new()
				sim.configure(topology)
				sim.reset()
				sim.set_scenario(scenario)
				if programming == "wasteful": sim.set_controls(WASTEFUL)
				var started := Time.get_ticks_msec()
				sim.step_for_test(fposmod(-float(sim.sim_seconds), 86400.0))
				sim.reset_meters()
				sim.step_for_test(86400)
				var e: Dictionary = sim.energy()
				var c: Dictionary = sim.comfort(comfort_zones)
				print("  %-15s %-9s $%7.2f  %6.1f kWh %5.1f thm  setpoint %5.1f%%  range %5.1f%%  air %5.1f%%  (%d ms)" % [scenario, programming, e.cost_usd, e.electric_kwh, e.heating_therms, c.setpoint_pct, c.range_pct, c.air_pct, Time.get_ticks_msec() - started])
	quit(0)
