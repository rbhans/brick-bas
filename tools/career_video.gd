extends "res://tools/demo_video.gd"

# A ~1 minute showcase of Career mode, rendered with Godot's Movie Maker
# (tools/render_demo_video.sh <out.mp4> res://tools/career_video.gd). Same real
# input as demo_video.gd: the scripted mouse glides and clicks on the actual
# job board, briefing, HUD, service panel and results.
#
# One service call, start to finish: pick "It's an oven in here" off the job
# board, drive over, follow the work order to the office's VAV, test the
# damper, replace the actuator that isn't driving it, close out, and get paid.
# Captions say what's happening; the drive and the rest of the day play out as
# the game's own time-lapse. Plays on a throwaway career save, so a real one isn't touched.

const CAREER_SAVE := "user://career_video.json"
const JOB := "t1_hot_office"

var caption_panel: PanelContainer
var caption_label: Label

func _watchdog() -> void:
	for frame in range(roundi(130.0 * FPS)):
		await process_frame
	push_error("career_video: timed out")
	quit(1)

# --- Captions ---------------------------------------------------------------------------------

func _make_overlays() -> void:
	var ToySkin: GDScript = load("res://scripts/ui/toy_theme.gd")
	var layer := CanvasLayer.new()
	layer.layer = 90
	root.add_child(layer)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme = ToySkin.create()
	layer.add_child(holder)
	caption_panel = PanelContainer.new()
	var pill: StyleBoxFlat = ToySkin.card(0.94, 0)
	pill.set_corner_radius_all(999)
	pill.content_margin_left = 26
	pill.content_margin_right = 26
	pill.content_margin_top = 12
	pill.content_margin_bottom = 14
	pill.border_color = Color(ToySkin.YELLOW, 0.55)
	pill.set_border_width_all(2)
	caption_panel.add_theme_stylebox_override("panel", pill)
	caption_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	caption_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caption_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption_panel.offset_bottom = -132
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(caption_panel)
	caption_label = Label.new()
	caption_label.add_theme_font_override("font", ToySkin.font(ToySkin.WEIGHT_STRONG))
	caption_label.add_theme_font_size_override("font_size", 20)
	caption_label.add_theme_color_override("font_color", ToySkin.TEXT)
	caption_panel.add_child(caption_label)
	caption_panel.modulate.a = 0.0

func caption(text: String) -> void:
	if caption_panel.modulate.a > 0.01:
		await fade(caption_panel, 0.0, 0.18)
	caption_label.text = text
	caption_panel.reset_size()
	var width := caption_panel.get_combined_minimum_size().x
	caption_panel.offset_left = -width * 0.5
	caption_panel.offset_right = width * 0.5
	await fade(caption_panel, 1.0, 0.25)

func uncaption() -> void:
	await fade(caption_panel, 0.0, 0.25)

func fade(control: Control, to: float, seconds: float) -> void:
	var from := control.modulate.a
	var frames := maxi(1, roundi(seconds * FPS))
	for frame in range(1, frames + 1):
		control.modulate.a = lerpf(from, to, smooth(float(frame) / frames))
		_process_pointer()
		await process_frame

# --- Finding things on screen ----------------------------------------------------------------

# The button (any kind) showing `text`, or holding a label that does.
func button_for(start: Node, text: String) -> Control:
	for node in start.find_children("*", "", true, false):
		if node is Button and (node as Button).visible and (node as Button).is_visible_in_tree():
			if String((node as Button).text).begins_with(text) or String(node.get("caption") if "caption" in node else "").begins_with(text):
				return node
		if node is Label and String((node as Label).text) == text and (node as Label).is_visible_in_tree():
			var walk: Node = node.get_parent()
			while walk != null and walk != start:
				if walk is Button: return walk
				walk = walk.get_parent()
	return null

func press(start: Node, text: String, glide: float = 0.6) -> void:
	# Panels rebuild their rows as the job moves on, so the button is looked up
	# afresh each frame rather than held.
	var finder := func() -> Control: return button_for(start, text)
	if finder.call() == null:
		push_error("career_video: no button '%s'" % text)
		return
	await move(func() -> Vector2:
		var target: Control = finder.call()
		return center_of(target) if target != null else mouse, glide)
	await clicked(finder, text)

# Clicks the button `finder` returns and makes sure it took: a page that has
# just finished laying out can leave the hover a frame stale, so the pointer
# settles with a 1 px nudge first and the click is repeated if it didn't land.
func clicked(finder: Callable, what: String = "") -> void:
	var fired := [false]
	var note := func() -> void: fired[0] = true
	for attempt in range(3):
		var target: Control = finder.call()
		if target == null:
			return
		if target is BaseButton and not (target as BaseButton).pressed.is_connected(note):
			(target as BaseButton).pressed.connect(note)
		_motion(center_of(target) + Vector2(1, 0))
		await wait(0.05)
		_motion(center_of(target))
		await wait(0.08)
		await click()
		await wait(0.05)
		if fired[0] or not (target is BaseButton):
			return
	push_error("career_video: '%s' didn't take the click" % what)

# --- The session -----------------------------------------------------------------------------

func run() -> void:
	_watchdog()
	root.mouse_passthrough = true
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.set_graphics("high", false)
	# A career a couple of jobs in, on a save of its own.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAREER_SAVE))
	game.career = CareerState.load_or_new(CAREER_SAVE)
	game.career.reset()
	game.career.record("t1_workshop_fitout", 2, 2400.0)
	game.career.record("t1_cold_start", 2, 1100.0)
	game.session_ui.show_home()
	_make_pointer()
	_make_overlays()
	mouse = Vector2(1150, 720)
	await wait(1.4)

	# Title screen: Career.
	await press(game.session_ui.body, "Career", 0.8)
	await wait(0.3)
	await caption("Career: run a controls contracting business")
	await wait(1.4)
	# The job board: a hot afternoon service call.
	var job: Dictionary = CareerJobs.find(JOB)
	var job_card := button_for(game.session_ui.body, String(job.title))
	await move(func() -> Vector2: return center_of(job_card), 0.8)
	await wait(0.9)
	await clicked(func() -> Control: return button_for(game.session_ui.body, String(job.title)), String(job.title))
	await wait(0.4)
	await caption("Every job has a brief, a fee and stars to earn")
	await move(Vector2(980, 420), 1.6)
	await wait(1.2)
	await caption("Start, and the clock races ahead to your %s arrival" % CareerJobs.clock(float(job.arrive_h)))
	await press(game.session_ui.body, "Start the job", 0.7)
	# The drive over is a short time-lapse of the morning.
	await until_phase("onsite", 8.0)
	game.frame_lot()
	await wait(0.8)
	await caption("On site: one work order, the office is too hot. Deadline 17:00")
	await wait(2.4)

	# Follow the work order to the room, then to the VAV that serves it.
	await press(game.hud.job_panel, "Show the room", 0.7)
	await wait(1.6)
	var host := String(game.job.faults[0].host)
	var vav_root: Node3D = game.equipment.roots[host]
	var vav_at := vav_root.global_position + Vector3(0, 0.4, 0)
	await caption("Its VAV box: cooling, but the room is still hot")
	await move(func() -> Vector2: return at(vav_at), 0.8)
	await wait(0.2)
	await click()
	if game.selected_id != host:
		game.select(host) # the click landed on a duct or a diffuser in front of it
	await wait(1.6)
	if card_action("Service") != null:
		await move(func() -> Vector2: return center_of(card_action("Service")), 0.7)
		await clicked(func() -> Control: return card_action("Service"), "Service")
	else:
		game.hud.open_service(host)
	await wait(0.8)
	await press(game.hud.service_panel, "Walk over", 0.7)
	await uncaption()
	await until_free(5.0)
	await wait(1.0)

	# Test before you replace anything.
	await caption("Tests cost time, not money. Test before you replace")
	await wait(0.6)
	await press(game.hud.service_panel, "Stroke the damper", 0.8)
	await wait(0.2)
	await until_free(5.0)
	await wait(0.5)
	var finding := button_for(game.hud.service_panel, "Stroke the damper")
	if finding != null:
		await move(func() -> Vector2: return center_of(finding) + Vector2(-40, 46), 0.6)
	await caption("Commanded open, the blade won't move: the actuator")
	await wait(2.6)
	await press(game.hud.service_panel, "Replace the damper actuator", 0.8)
	await until_free(6.0)
	await caption("The right part fixes it. The wrong one comes out of your fee")
	await wait(2.4)
	# Close out: the rest of the day decides the comfort star.
	await press(game.hud.service_panel, "Close", 0.6)
	await wait(0.5)
	await uncaption()
	await caption("Close out: the rest of the day plays out to 17:00")
	await press(game.hud.job_panel, "Close out the job", 0.8)
	# The afternoon time-lapses; comfort is measured right up to the deadline.
	for frame in range(roundi(10.0 * FPS)):
		if game.session_ui.visible: break
		_process_pointer()
		await process_frame
	await uncaption()
	await wait(0.3)

	# Results: stars and pay, then back to the board.
	await move(Vector2(820, 300), 0.8)
	await wait(2.2)
	await caption("Stars unlock bigger jobs: installs, tune-ups, a whole school")
	await press(game.session_ui.body, "Job board", 0.9)
	await wait(0.6)
	await move(Vector2(1180, 260), 1.4)
	await wait(1.8)
	await uncaption()
	await wait(0.4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAREER_SAVE))
	print("CAREER_VIDEO done: %.1f s, job %s, stars %d" % [Engine.get_process_frames() / FPS, JOB, game.career.stars_for(JOB)])
	quit()

# Waits for the job to reach `phase` (a time-lapse running), up to `limit` seconds.
func until_phase(phase: String, limit: float) -> void:
	for frame in range(roundi(limit * FPS)):
		if game.job == null or game.job.phase == phase:
			return
		_process_pointer()
		await process_frame

# Waits while the job is busy (walking, testing, repairing), up to `limit` seconds.
func until_free(limit: float) -> void:
	for frame in range(roundi(limit * FPS)):
		if game.job == null or game.job.phase != "working":
			return
		_process_pointer()
		await process_frame
