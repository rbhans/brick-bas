extends PanelContainer

# The career job tracker, top left: the job, its phase, the objectives (live),
# work orders on a service call, the budget on an install, a tip, and the
# buttons that move the job along.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Mark := preload("res://scripts/ui/mark.gd")
const STATE_COLORS := {"done": ToySkin.GREEN, "failed": ToySkin.DANGER, "open": ToySkin.TEXT_3}
const STATE_MARKS := {"done": "check", "failed": "cross", "open": "ring"}

var game: Node
var badge: Label
var title: Label
var phase_label: Label
var progress: ProgressBar
var objectives_box: VBoxContainer
var tickets_box: VBoxContainer
var budget_box: VBoxContainer
var budget_bar: ProgressBar
var budget_label: Label
var hint_box: PanelContainer
var hint_label: Label
var actions: HFlowContainer
var collapse_button: Button
var collapsed := false
var body: VBoxContainer
var _signature := ""
var _action_signature := ""
var _ticket_signature := ""

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(ToySkin.MARGIN + 72, 100)
	custom_minimum_size = Vector2(340, 0)
	add_theme_stylebox_override("panel", ToySkin.card(0.96, 16))
	z_index = 12
	var column := UIKit.column(self, 10)
	var header := UIKit.row(column, 8)
	badge = UIKit.label(header, "SERVICE", ToySkin.SIZE_CAPTION, ToySkin.CREAM_TEXT, ToySkin.WEIGHT_HEAVY)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.spacer(header)
	collapse_button = UIKit.button(header, "Hide", func() -> void: collapsed = not collapsed; body.visible = not collapsed; collapse_button.text = "Show" if collapsed else "Hide", "ChipButton")
	title = UIKit.title(column, "", ToySkin.SIZE_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body = UIKit.column(column, 12)
	var phase := UIKit.column(body, 6)
	phase_label = UIKit.text(phase, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 6
	progress.show_percentage = false
	progress.add_theme_stylebox_override("fill", ToySkin.fill(ToySkin.YELLOW, 999, 0))
	phase.add_child(progress)
	objectives_box = UIKit.column(body, 6)
	budget_box = UIKit.column(body, 6)
	var budget_row := UIKit.row(budget_box, 8)
	UIKit.section(budget_row, "Budget")
	UIKit.spacer(budget_row)
	budget_label = UIKit.label(budget_row, "", ToySkin.SIZE_SMALL, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
	budget_bar = ProgressBar.new()
	budget_bar.custom_minimum_size.y = 6
	budget_bar.show_percentage = false
	budget_box.add_child(budget_bar)
	tickets_box = UIKit.column(body, 6)
	hint_box = PanelContainer.new()
	hint_box.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 12))
	body.add_child(hint_box)
	var hint_column := UIKit.column(hint_box, 4)
	var hint_row := UIKit.row(hint_column, 4)
	UIKit.section(hint_row, "Tip", ToySkin.YELLOW).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.spacer(hint_row)
	UIKit.button(hint_row, "Next tip", func() -> void: if game.job != null: game.job.next_hint(), "GhostButton").add_theme_font_size_override("font_size", ToySkin.SIZE_SMALL)
	hint_label = UIKit.text(hint_column, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	body.add_child(actions)
	hide()

func refresh() -> void:
	var job: JobSession = game.job
	visible = job != null and not game.session_ui.visible
	if job == null:
		return
	var kind := String(job.type)
	badge.text = String(CareerJobs.TYPE_NAMES.get(kind, kind)).to_upper()
	var pill := ToySkin.fill(CareerJobs.TYPE_COLORS.get(kind, Color.WHITE), 999, 0)
	pill.content_margin_left = 9
	pill.content_margin_right = 9
	pill.content_margin_top = 2
	pill.content_margin_bottom = 3
	badge.add_theme_stylebox_override("normal", pill)
	title.text = job.title()
	phase_label.text = job.phase_text()
	var running: bool = game.turbo_until > game.sim.sim_seconds
	progress.visible = running or job.phase in ["working", "wrapup"]
	progress.value = _progress(job) * 100.0
	_refresh_objectives(job)
	budget_box.visible = kind == "install"
	if kind == "install":
		var spent: float = job.spent()
		budget_label.text = "%s of %s" % [Units.money(spent), Units.money(job.budget)]
		budget_label.add_theme_color_override("font_color", ToySkin.TEXT if spent <= job.budget else ToySkin.DANGER)
		budget_bar.max_value = maxf(job.budget, 1.0)
		budget_bar.value = minf(spent, job.budget)
		budget_bar.add_theme_stylebox_override("fill", ToySkin.fill(ToySkin.GREEN if spent <= job.budget else ToySkin.DANGER, 999, 0))
	_refresh_tickets(job)
	var tip: String = job.hint()
	hint_box.visible = not tip.is_empty() and job.phase not in ["commission", "verify", "travel", "done"]
	hint_label.text = tip
	_refresh_actions(job)

func _progress(job: JobSession) -> float:
	if job.phase == "working": return job.work_progress()
	var now: float = game.sim.sim_seconds
	match job.phase:
		"commission": return clampf((now - JobSession.COMMISSION_START_S) / (JobSession.COMMISSION_END_S - JobSession.COMMISSION_START_S), 0.0, 1.0)
		"verify": return clampf(now / 86400.0, 0.0, 1.0)
		"wrapup": return clampf((now - job.closed_at) / maxf(1.0, job.deadline - job.closed_at), 0.0, 1.0)
		"travel":
			var arrive := float(job.def.get("arrive_h", 9.0)) * 3600.0
			return clampf((now - JobSession.COMMISSION_START_S) / maxf(1.0, arrive - JobSession.COMMISSION_START_S), 0.0, 1.0)
	return 0.0

func _refresh_objectives(job: JobSession) -> void:
	var list: Array = job.objectives()
	var signature := str(list)
	if signature == _signature:
		return
	_signature = signature
	UIKit.clear(objectives_box)
	UIKit.section(objectives_box, "Objectives")
	for objective in list:
		var row := UIKit.row(objectives_box, 8)
		var state := String(objective.state)
		var mark := Mark.make(row, String(STATE_MARKS.get(state, "ring")), STATE_COLORS.get(state, Color.WHITE), 15.0)
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var text := UIKit.column(row, 1)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var line := UIKit.row(text, 6)
		var name := UIKit.text(line, String(objective.label), ToySkin.SIZE_BODY, ToySkin.TEXT if state != "done" else ToySkin.TEXT_2)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not bool(objective.required): Mark.make(line, "star", ToySkin.YELLOW, 12.0).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if not String(objective.detail).is_empty():
			UIKit.text(text, String(objective.detail), ToySkin.SIZE_SMALL, ToySkin.TEXT_3)

func _refresh_tickets(job: JobSession) -> void:
	var signature := "%s|%s" % [job.phase, str(job.tickets)]
	if signature == _ticket_signature:
		return
	_ticket_signature = signature
	UIKit.clear(tickets_box)
	if job.type != "service" or job.phase in ["travel", ""]:
		tickets_box.visible = false
		return
	tickets_box.visible = true
	UIKit.section(tickets_box, "Work orders")
	if job.tickets.is_empty():
		UIKit.label(tickets_box, "No calls yet.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	for ticket in job.tickets.slice(-6):
		var closed := float(ticket.closed_at) >= 0.0
		var row := UIKit.row(tickets_box, 8)
		var dot := Control.new()
		dot.custom_minimum_size = Vector2(10, 16)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var tint := ToySkin.TEXT_3 if closed else ToySkin.DANGER
		dot.draw.connect(func() -> void: dot.draw_circle(Vector2(5, 9), 3.5, tint, true, -1, true))
		row.add_child(dot)
		var words := UIKit.column(row, 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.label(words, String(ticket.room) + ("  ·  closed" if closed else ""), ToySkin.SIZE_SMALL, ToySkin.TEXT_3 if closed else ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
		UIKit.text(words, String(ticket.text), ToySkin.SIZE_SMALL, ToySkin.TEXT_3 if closed else ToySkin.TEXT_2)
		var room_id := String(ticket.room_id)
		if not room_id.is_empty():
			UIKit.tile(row, "Show the room", "eye", func() -> void: game.focus_on(room_id), Vector2(32, 30)).size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _refresh_actions(job: JobSession) -> void:
	var stars: int = job.stars_now()
	var signature := "%s|%d|%s|%s" % [job.phase, stars, job.can_run(), str(game.turbo_until > game.sim.sim_seconds)]
	if signature == _action_signature:
		return
	_action_signature = signature
	UIKit.clear(actions)
	match job.phase:
		"design":
			var reason: String = job.can_run()
			var run := UIKit.button(actions, "Run commissioning day", job.start_run, "PrimaryButton")
			run.disabled = not reason.is_empty()
			run.tooltip_text = reason if not reason.is_empty() else "Simulate 06:30–18:00 in time-lapse and measure comfort and energy"
		"adjust":
			UIKit.button(actions, "Run verification day", job.start_run, "PrimaryButton")
			UIKit.button(actions, "BAS programming", game.hud.open_programming)
		"commission", "verify":
			UIKit.button(actions, "Stop", job.stop_run)
		"review":
			if stars > 0:
				UIKit.button(actions, "Hand over · %d of 3 stars" % stars, job.hand_over, "PrimaryButton")
				UIKit.button(actions, "Keep improving", job.stop_run)
			else:
				UIKit.button(actions, "Back to the drawing board" if job.type == "install" else "Back to programming", job.stop_run, "PrimaryButton")
		"onsite":
			UIKit.button(actions, "Close out the job", _confirm_close, "PrimaryButton")
	UIKit.button(actions, "Leave job", _confirm_leave, "GhostButton")

func _confirm_close() -> void:
	var job: JobSession = game.job
	if job == null: return
	var open: int = job.faults.size() - job.fixed_count()
	if open > 0:
		_confirm("%d problem%s still open. Close out anyway? The job won't count as done." % [open, "" if open == 1 else "s"], job.close_out)
	else:
		job.close_out()

func _confirm_leave() -> void:
	_confirm("Leave this job? You keep the building to look around, but the job won't count.", func() -> void: game.end_job(); game.session_ui.show_career())

func _confirm(text: String, then: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Are you sure?"
	dialog.dialog_text = text
	dialog.ok_button_text = "Yes"
	dialog.cancel_button_text = "No"
	dialog.theme = ToySkin.create()
	dialog.confirmed.connect(func() -> void: then.call(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	game.hud.add_child(dialog)
	dialog.popup_centered(Vector2i(420, 140))

func reset() -> void:
	_signature = ""
	_action_signature = ""
	_ticket_signature = ""
	collapsed = false
	body.visible = true
	collapse_button.text = "Hide"

