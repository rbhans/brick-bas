extends SceneTree

# Renders every UI state to PNGs for review (needs a window, not --headless):
#   Godot --path . --script res://tools/ui_screens.gd -- --out=/tmp/screens [--only=name] [--set=creative|career|live]

const TEST_CAREER := "user://career_screens.json"

var game: Node
var out := "/tmp/brick-bas-screens"
var only := ""
var subset := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if arg.begins_with("--set="): subset = arg.trim_prefix("--set=")
	DirAccess.make_dir_recursive_absolute(out)
	run.call_deferred()

func frames(count: int) -> void:
	for i in range(count): await process_frame

func until(condition: Callable, limit: int = 30000) -> void:
	for i in range(limit):
		if condition.call(): return
		await process_frame

func shot(name: String) -> void:
	if not only.is_empty() and name != only: return
	await frames(6)
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	root.get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await frames(3)
	game.sound_enabled = false
	if subset in ["", "creative"]: await creative()
	if subset in ["", "career"]: await career()
	if subset in ["", "live"]: await live()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CAREER))
	quit(0)

func creative() -> void:
	game.session_ui.hide()
	game.start_new_game("office", false)
	await frames(30)
	await shot("c01_build")
	game.hud.category = "Furniture"
	game.hud.rebuild_shelf()
	await shot("c02_build_furniture")
	game.set_mode(1)
	await frames(10)
	game.set_speed(60.0)
	await frames(240)
	var ahu := String(game.model.objects_of(["ahu"])[0].id)
	game.select(ahu)
	await frames(20)
	await shot("c03_equipment_ahu")
	var vav := String(game.model.objects_of(["vav"])[2].id)
	game.select(vav)
	await frames(20)
	await shot("c04_equipment_vav")
	game.select("")
	game.hud.toggle_menu()
	await shot("c05_menu")
	game.hud.toggle_menu()
	game.hud.details.open(vav)
	await shot("c06_details_paint")
	game.hud.details.tabs.current_tab = 1
	await shot("c07_details_animate")
	game.hud.details.hide()
	game.set_scenario("Fan failure")
	game.set_speed(60.0)
	await frames(200)
	game.hud.toggle_alarms()
	await shot("c08_alarms")
	game.hud.toggle_alarms()
	game.set_scenario("Normal weekday")
	var tstat := String(game.model.objects_of(["tstat"])[0].id)
	game.select(tstat)
	game.hud.show_thermostat(tstat)
	await frames(10)
	await shot("c09_thermostat")
	game.hud.hide_thermostat()
	game.equipment.open_workbench("vav")
	await frames(20)
	await shot("c10_workbench")
	game.equipment.workbench.close()
	var floor_id := ""
	for item in game.model.objects_of(["floor"]):
		if not game.index.room_at_cell(BuildingIndex.cell_of(item)).is_empty():
			floor_id = String(item.id)
			break
	game.set_mode(0)
	game.select(floor_id)
	await frames(10)
	await shot("c11_room_card")
	game.select("")
	game.show_tour()
	await frames(10)
	await shot("c12_tour")
	game.tour.finish()
	game.set_mode(2)
	game.explorer.teleport_near(game.vector(game.model.find_object(vav).transform.position))
	await frames(60)
	await shot("c13_explore")
	game.set_mode(0)
	game.set_speed(1.0)

func career() -> void:
	game.career = CareerState.load_or_new(TEST_CAREER)
	game.career.reset()
	game.career.record("t1_hot_office", 3, 900.0)
	game.career.record("t1_workshop_fitout", 2, 2400.0)
	game.session_ui.show_home()
	await shot("01_home")
	game.session_ui.show_career()
	await shot("02_career_board")
	game.session_ui.show_briefing(CareerJobs.find("t2_conference_chill"))
	await shot("03_briefing")
	game.session_ui.show_starters()
	await shot("04_creative_starters")
	# A service call: on site, with the job panel and a work order.
	game.session_ui.hide()
	game.start_job(CareerJobs.find("t1_hot_office"))
	await until(func() -> bool: return game.job.phase == "onsite")
	game.sim.run_steps(900)
	await frames(10)
	game.frame_lot()
	await frames(30)
	await shot("05_service_onsite")
	var host := String(game.job.faults[0].host)
	game.hud.open_service(host)
	game.job.go_to(host)
	await until(func() -> bool: return game.job.phase == "onsite")
	game.job.run_check(host, "damper")
	await until(func() -> bool: return game.job.phase == "onsite")
	await frames(20)
	await shot("06_service_panel")
	game.hud.service_panel.close()
	game.job.run_repair(host, "damper_actuator")
	await until(func() -> bool: return game.job.phase == "onsite")
	game.job.close_out()
	await until(func() -> bool: return game.job.phase == "done")
	await shot("07_results")
	game.session_ui.hide()
	game.end_job()
	# An install job, designing.
	game.start_job(CareerJobs.find("t1_workshop_fitout"))
	await frames(10)
	game.frame_lot()
	await frames(30)
	await shot("08_install_design")
	game.equipment.open_workbench("ahu")
	await frames(20)
	await shot("09_workbench_size")
	game.equipment.workbench.close()
	game.end_job()
	# A tune-up: the BAS programming panel.
	game.start_job(CareerJobs.find("t2_office_tuneup"))
	await frames(10)
	game.frame_lot()
	game.hud.open_programming()
	await frames(20)
	await shot("10_programming")
	game.hud.controls_panel.hide()
	game.job.start_run()
	await until(func() -> bool: return game.sim.sim_seconds > 13.0 * 3600.0)
	await shot("11_tune_verify")
	game.end_job()

func live() -> void:
	# Live data from the demo station.
	game.session_ui.hide()
	game.start_new_game("studio", false)
	await frames(5)
	var station: Dictionary = await game.data.start_demo_station()
	if not station.is_empty():
		await game.data.connect_station({"id": "demo", "name": "Demo station", "station_url": station.url, "username": station.user, "tls_mode": "strict"}, String(station.password))
		var vav := String(game.model.objects_of(["vav"])[0].id)
		game.set_mode(1)
		game.select(vav)
		game.hud.details.open(vav)
		game.hud.details._location = "slot:/Drivers/BacnetNetwork/VAV_101"
		game.hud.details._browse("slot:/Drivers/BacnetNetwork/VAV_101/points")
		await frames(30)
		game.hud.details._location = "slot:/Drivers/BacnetNetwork/VAV_101"
		game.hud.details._auto_map()
		await frames(90)
		await shot("12_live_station")
		game.hud.details.hide()
		game.toggle_overlay()
		game.select(vav)
		await frames(60)
		await shot("13_live_card")
	game.data.close()
