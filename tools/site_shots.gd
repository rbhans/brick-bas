extends "res://tools/demo_video.gd"

# Stills for the project page at 1440 × 900, from real play (needs a window):
#   Godot --path . --resolution 1440x900 --script res://tools/site_shots.gd -- --out=/tmp/shots
# Uses a throwaway career save, so a real one isn't touched.

const CAREER_SAVE := "user://career_shots.json"

var out := "user://site_shots"

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	run.call_deferred()

func _watchdog() -> void:
	for frame in range(roundi(240.0 * FPS)):
		await process_frame
	push_error("site_shots: timed out")
	quit(1)

func shot(name: String) -> void:
	await wait(0.6)
	DirAccess.make_dir_recursive_absolute(out)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("SHOT ", name)

func until(condition: Callable, limit: float = 30.0) -> void:
	for frame in range(roundi(limit * FPS)):
		if condition.call(): return
		await process_frame

func run() -> void:
	_watchdog()
	root.mouse_passthrough = true
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_graphics("high", false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAREER_SAVE))
	game.career = CareerState.load_or_new(CAREER_SAVE)
	game.career.reset()
	game.session_ui.hide()

	# The school, mid-morning, with a VAV's card and its trend.
	game.start_new_game("school", false)
	preroll(10.4)
	game.set_mode(1)
	var vav := find("vav", "Library")
	if vav.is_empty(): vav = game.model.objects_of(["vav"])[2]
	game.select(String(vav.id))
	game.rig.set_view(Vector3(-4.0, 0, -6.0), -0.7, -0.62, 46.0, true)
	await shot("school-equipment")

	# Building: the parts tray, walls cut away around the view.
	game.select("")
	game.set_mode(0)
	game.rig.set_view(Vector3(2.0, 0, -4.0), -0.5, -0.7, 34.0, true)
	await wait(0.8)
	await shot("build")

	# Walking a classroom at minifigure height, its thermostat at hand, the
	# camera back in the room so the walls between are cut away.
	game.set_mode(2)
	await wait(0.5)
	var tstat := find("tstat", "Classroom")
	if tstat.is_empty(): tstat = game.model.objects_of(["tstat"])[0]
	var at_tstat := DuctConnections.vector(tstat.transform.position)
	var room: Dictionary = game.thermostat_room(String(tstat.id))
	var middle: Vector3 = room.get("center", at_tstat)
	game.explorer.teleport_near(at_tstat)
	await wait(0.3)
	var player: Vector3 = game.explorer.player.global_position
	var into_room := atan2(middle.x - player.x, middle.z - player.z)
	var variants := [[into_room, -0.72, 11.5], [into_room + 0.9, -0.42, 8.0], [into_room - 0.9, -0.42, 8.0], [into_room, -0.3, 6.5]]
	for index in range(variants.size()):
		game.explorer.goal_yaw = float(variants[index][0])
		game.explorer.goal_pitch = float(variants[index][1])
		game.explorer.goal_distance = float(variants[index][2])
		await wait(1.6)
		await shot("explore_%d" % index)

	# Ductwork and an open VAV, close up.
	game.set_mode(1)
	await wait(0.3)
	var near_vav: Vector3 = (game.equipment.roots[String(vav.id)] as Node3D).global_position
	game.equipment.open_casings[String(vav.id)] = true
	game.select("")
	game.rig.set_view(near_vav, 0.85, -0.55, 13.0, true)
	await wait(1.2)
	await shot("ductwork")
	game.equipment.open_casings[String(vav.id)] = false

	# The air handler on the workbench.
	game.select("")
	game.equipment.open_workbench("ahu")
	await wait(0.8)
	await shot("workbench")
	game.equipment.workbench.close()

	# Career: a couple of jobs in, the job board.
	game.career.record("t1_workshop_fitout", 2, 2400.0)
	game.career.record("t1_cold_start", 2, 1100.0)
	game.career.record("t2_office_tuneup", 1, 2600.0)
	game.session_ui.show_career()
	await shot("career-board")
	# The briefing for the hot office.
	game.session_ui.show_briefing(CareerJobs.find("t1_hot_office"))
	await shot("career-briefing")
	# On site at the stuck VAV, the damper test's finding on the panel.
	game.session_ui.hide()
	game.start_job(CareerJobs.find("t1_hot_office"))
	await until(func() -> bool: return game.job.phase == "onsite")
	var host := String(game.job.faults[0].host)
	game.hud.open_service(host)
	game.job.go_to(host)
	await until(func() -> bool: return game.job.phase == "onsite")
	game.job.run_check(host, "damper")
	await until(func() -> bool: return game.job.phase == "onsite")
	game.explorer.goal_distance = 7.0
	game.explorer.goal_pitch = -0.42
	await wait(1.2)
	await shot("service-call")
	# Fixed, closed out, paid.
	game.hud.service_panel.close()
	game.job.run_repair(host, "damper_actuator")
	await until(func() -> bool: return game.job.phase == "onsite")
	game.job.close_out()
	await until(func() -> bool: return game.session_ui.visible, 60.0)
	await shot("career-results")
	game.session_ui.hide()
	game.end_job()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAREER_SAVE))
	quit()
