extends Control

# Full-screen pages over the game: the title screen, Creative's starter
# picker (with the simulated / live data choice on desktop), the Career job
# board, a job's briefing, and its results. Every page is one card: an eyebrow
# and heading, the content, and a footer of actions with the main one in
# yellow on the right.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const ToyButton := preload("res://scripts/ui/toy_button.gd")
const Templates := preload("res://scripts/model/templates.gd")
const Mark := preload("res://scripts/ui/mark.gd")
const PAGE_WIDTH := 860.0
const CARD_WIDTH := 390.0

var app: Node
var panel: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var welcome := false
var live_data := false     # Creative: start on a live station instead of the simulation

func setup(owner_node: Node) -> void:
	app = owner_node
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = ToySkin.create()
	z_index = 60 # over every HUD panel
	var shade := ColorRect.new()
	shade.color = Color(ToySkin.INK_WELL, 0.86)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = PAGE_WIDTH
	var style := ToySkin.card(0.99, 32)
	style.set_corner_radius_all(20)
	style.shadow_size = 30
	style.shadow_offset = Vector2(0, 12)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	resized.connect(_fit)
	body.minimum_size_changed.connect(_fit)
	hide()

# The page scrolls when it is taller than the window.
func _fit() -> void:
	if not is_instance_valid(scroll): return
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(300.0, size.y - 112.0))

func clear() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	scroll.scroll_vertical = 0
	if not visible: UIKit.pop_in(panel, app.reduced_motion)
	show()
	_fit.call_deferred()

# --- Building blocks ------------------------------------------------------------------------

func _header(eyebrow: String, heading: String, lead: String = "", parent: Node = body) -> VBoxContainer:
	var block := UIKit.column(parent, 4)
	if not eyebrow.is_empty(): UIKit.section(block, eyebrow)
	var title := UIKit.label(block, heading, ToySkin.SIZE_DISPLAY, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not lead.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 2
		block.add_child(gap)
		UIKit.text(block, lead, ToySkin.SIZE_LABEL, ToySkin.TEXT_2)
	return block

func _footer() -> HBoxContainer:
	var line := ColorRect.new()
	line.color = ToySkin.LINE
	line.custom_minimum_size.y = 1
	body.add_child(line)
	var row := UIKit.row(body, 10)
	return row

func _action(parent: Node, label: String, callback: Callable, variant: String = "") -> Button:
	var button := UIKit.button(parent, label, callback, variant)
	button.custom_minimum_size = Vector2(maxf(120.0, button.custom_minimum_size.x), 44)
	return button

func _card(parent: Node, height: float, callback: Callable) -> VBoxContainer:
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.custom_minimum_size = Vector2(CARD_WIDTH, height)
	card.focus_mode = Control.FOCUS_NONE
	card.pressed.connect(callback)
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.offset_top = 14
	content.offset_bottom = -14
	content.add_theme_constant_override("separation", 6)
	content.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(content)
	card.set_meta("content", content)
	return content

func _grid(columns: int = 2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	body.add_child(grid)
	return grid

func _picture(parent: Node, id: String, height: float) -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 0))
	frame.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var picture := TextureRect.new()
	picture.texture = UIKit.thumbnail(id)
	picture.custom_minimum_size.y = height
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	gap.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(gap)

func _badge(parent: Node, kind: String, open: bool = true) -> Label:
	var badge := UIKit.label(parent, String(CareerJobs.TYPE_NAMES.get(kind, kind)).to_upper(), ToySkin.SIZE_CAPTION, ToySkin.CREAM_TEXT, ToySkin.WEIGHT_HEAVY)
	var style := ToySkin.fill(CareerJobs.TYPE_COLORS.get(kind, Color.WHITE) if open else Color("56656b"), 999, 0)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	badge.add_theme_stylebox_override("normal", style)
	badge.size_flags_vertical = SIZE_SHRINK_CENTER
	badge.mouse_filter = MOUSE_FILTER_IGNORE
	return badge

func _ignore(control: Control) -> Control:
	control.mouse_filter = MOUSE_FILTER_IGNORE
	return control

# --- Title screen -------------------------------------------------------------------------

func show_home() -> void:
	clear()
	welcome = true
	var brand := UIKit.row(body, 18)
	var logo := ToyButton.new()
	logo.layout_kind = "brand"
	logo.face_color = ToySkin.RED
	logo.studs = true
	logo.custom_minimum_size = Vector2(72, 64)
	logo.mouse_filter = MOUSE_FILTER_IGNORE
	logo.focus_mode = Control.FOCUS_NONE
	logo.size_flags_vertical = SIZE_SHRINK_CENTER
	brand.add_child(logo)
	var words := UIKit.column(brand, 2)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	UIKit.label(words, "BRICK / BAS", 40, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	UIKit.label(words, "Build a brick building, bring its HVAC to life, and keep it running.", ToySkin.SIZE_TITLE, ToySkin.TEXT_2)
	var grid := _grid()
	var career: CareerState = app.career
	var stars := career.total_stars()
	var career_card := _mode_card(grid, "Career", "starter_school", "Run a controls contracting business. Install systems on a budget, chase down faults on service calls and re-program wasteful buildings.", show_career)
	var standing := UIKit.row(career_card, 8)
	Mark.make(standing, "star", ToySkin.YELLOW, 14.0)
	_ignore(UIKit.label(standing, "%d · %s · %s in the bank" % [stars, CareerJobs.rank(stars), Units.money(career.money)], ToySkin.SIZE_SMALL, ToySkin.LABEL, ToySkin.WEIGHT_STRONG))
	var creative_text := "Build anything and watch it run on the simulated building%s." % ("" if OS.has_feature("web") else ", or on live points from your Niagara station")
	var creative_card := _mode_card(grid, "Creative", "starter_office", creative_text, show_starters)
	_ignore(UIKit.label(creative_card, "No goals · every piece editable", ToySkin.SIZE_SMALL, ToySkin.LABEL, ToySkin.WEIGHT_STRONG))
	var buttons := _footer()
	var load_button := _action(buttons, "Continue my saved build", func() -> void: if app.load_project(): hide(); welcome = false)
	load_button.disabled = not app.has_save()
	if OS.has_feature("web"):
		_action(buttons, "Import a backup", func() -> void: app.browser_files.choose(), "GhostButton")
		UIKit.spacer(buttons)
		var note := UIKit.label(buttons, "Saves stay in this browser.\nDownload a backup before clearing site data.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.size_flags_vertical = SIZE_SHRINK_CENTER

func _mode_card(parent: Node, name: String, picture_id: String, detail: String, callback: Callable) -> VBoxContainer:
	var content := _card(parent, 336, callback)
	_picture(content, picture_id, 150)
	var row := UIKit.row(content, 8)
	_ignore(row)
	_ignore(UIKit.label(row, name, ToySkin.SIZE_HEADING, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY))
	UIKit.spacer(row)
	var go := Control.new()
	go.custom_minimum_size = Vector2(20, 20)
	go.size_flags_vertical = SIZE_SHRINK_CENTER
	go.mouse_filter = MOUSE_FILTER_IGNORE
	go.draw.connect(func() -> void: preload("res://scripts/ui/toy_symbols.gd").draw_icon(go, "right", Rect2(Vector2.ZERO, go.size), ToySkin.YELLOW))
	row.add_child(go)
	_ignore(UIKit.text(content, detail, ToySkin.SIZE_BODY, ToySkin.TEXT_2))
	var push := Control.new()
	push.size_flags_vertical = SIZE_EXPAND_FILL
	push.mouse_filter = MOUSE_FILTER_IGNORE
	content.add_child(push)
	return content

# --- Creative -----------------------------------------------------------------------------

func show_starters() -> void:
	clear()
	_header("Creative", "Choose a starter", "Furnished, zoned and already running. Change anything, or start from an empty lot.")
	if not OS.has_feature("web"):
		var well := PanelContainer.new()
		well.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL + 2, 14))
		body.add_child(well)
		var column := UIKit.column(well, 6)
		var source := UIKit.row(column, 18)
		var caption := UIKit.section(source, "Data source")
		caption.custom_minimum_size.x = 110
		caption.size_flags_vertical = SIZE_SHRINK_CENTER
		var simulated := CheckBox.new()
		var live := CheckBox.new()
		var group := ButtonGroup.new()
		simulated.button_group = group
		live.button_group = group
		simulated.text = "Simulated building"
		live.text = "Live Niagara station (baskStream)"
		simulated.button_pressed = not live_data
		live.button_pressed = live_data
		simulated.toggled.connect(func(on: bool) -> void: if on: live_data = false)
		live.toggled.connect(func(on: bool) -> void: if on: live_data = true)
		source.add_child(simulated)
		source.add_child(live)
		UIKit.text(column, "Live: the equipment you build animates from real points, read-only. After the starter loads you connect, browse the station and link points.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	var grid := _grid()
	for spec in Templates.PRESETS:
		var id: String = spec.id
		var content := _card(grid, 252, func() -> void: _start_creative(id))
		_picture(content, "starter_" + id, 118)
		var header := _ignore(UIKit.row(content, 8))
		var name_label := UIKit.label(header, String(spec.name), ToySkin.SIZE_TITLE, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		_ignore(name_label)
		_ignore(UIKit.label(header, String(spec.size), ToySkin.SIZE_SMALL, ToySkin.TEXT_3))
		_ignore(UIKit.text(content, String(spec.detail), ToySkin.SIZE_SMALL, ToySkin.TEXT_2))
	var buttons := _footer()
	_action(buttons, "Back" if welcome else "Keep building", show_home if welcome else hide, "GhostButton")

func _start_creative(template: String) -> void:
	app.end_job()
	app.start_new_game(template)
	welcome = false
	hide()
	if live_data and not OS.has_feature("web"):
		app.hud.details.open_connections()
	else:
		app.maybe_start_tour()

# --- Career -------------------------------------------------------------------------------

func show_career() -> void:
	clear()
	var career: CareerState = app.career
	var stars := career.total_stars()
	_header("Career", career.company)
	# Standing: rank, stars, the bank, and the way to the next rank.
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL + 2, 14))
	body.add_child(well)
	var standing := UIKit.row(well, 22)
	_stat(standing, "Rank", CareerJobs.rank(stars))
	var star_stat := _stat(standing, "Stars", "")
	var star_row := UIKit.row(star_stat, 6)
	Mark.make(star_row, "star", ToySkin.YELLOW, 16.0)
	UIKit.label(star_row, str(stars), ToySkin.SIZE_TITLE, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	_stat(standing, "Bank", Units.money(career.money))
	var next := CareerJobs.next_rank(stars)
	var goal := UIKit.column(standing, 6)
	goal.size_flags_horizontal = SIZE_EXPAND_FILL
	goal.size_flags_vertical = SIZE_SHRINK_CENTER
	if next.is_empty():
		UIKit.label(goal, "Top rank. Every job pays and earns its stars.", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	else:
		UIKit.label(goal, "%s at %s" % [String(next[1]), _stars(int(next[0]))], ToySkin.SIZE_SMALL, ToySkin.TEXT_2, ToySkin.WEIGHT_STRONG)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
		bar.max_value = float(next[0])
		bar.value = float(stars)
		goal.add_child(bar)
	for tier in CareerJobs.TIERS:
		var open := stars >= int(tier.stars)
		_tier_header(String(tier.name), "" if open else "Earn %s to unlock" % _stars(int(tier.stars)), open)
		var grid := _grid()
		for job in CareerJobs.all():
			if int(job.tier) != int(tier.tier): continue
			_job_card(grid, job, open, career.stars_for(String(job.id)))
	var on_call_open := stars >= 1
	_tier_header("On call", "Random service calls, endless" if on_call_open else "Finish any job to go on call", on_call_open)
	if on_call_open:
		_job_card(_grid(), CareerJobs.on_call(career.on_call_done, stars), true, 0)
	var buttons := _footer()
	_action(buttons, "Back", show_home if welcome else hide, "GhostButton")
	UIKit.spacer(buttons)
	_action(buttons, "Start the career over", _confirm_reset, "DangerButton")

func _stat(parent: Node, caption: String, value: String) -> VBoxContainer:
	var column := UIKit.column(parent, 2)
	column.size_flags_vertical = SIZE_SHRINK_CENTER
	UIKit.label(column, caption.to_upper(), ToySkin.SIZE_CAPTION, ToySkin.TEXT_3, ToySkin.WEIGHT_HEAVY)
	if not value.is_empty(): UIKit.label(column, value, ToySkin.SIZE_TITLE, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	return column

func _tier_header(name: String, note: String, open: bool) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	body.add_child(gap)
	var row := UIKit.row(body, 10)
	UIKit.label(row, name, ToySkin.SIZE_TITLE, ToySkin.TEXT if open else ToySkin.TEXT_3, ToySkin.WEIGHT_HEAVY)
	if not note.is_empty():
		UIKit.label(row, note, ToySkin.SIZE_SMALL, ToySkin.TEXT_3).size_flags_vertical = SIZE_SHRINK_CENTER

func _job_card(parent: Node, job: Dictionary, open: bool, stars: int) -> void:
	var content := _card(parent, 134, func() -> void: show_briefing(job))
	(content.get_parent() as Button).disabled = not open
	var top := _ignore(UIKit.row(content, 8))
	var kind := String(job.type)
	_badge(top, kind, open)
	UIKit.spacer(top)
	var rating := Mark.make(top, "star", ToySkin.YELLOW, 14.0, 3, stars)
	rating.dim = Color(1, 1, 1, 0.22)
	var name := UIKit.label(content, String(job.title), ToySkin.SIZE_TITLE, ToySkin.TEXT if open else ToySkin.TEXT_3, ToySkin.WEIGHT_STRONG)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ignore(name)
	var building := String(Templates.definition(String(job.template)).name)
	_ignore(UIKit.label(content, "%s · %s" % [String(job.client), building], ToySkin.SIZE_SMALL, ToySkin.TEXT_3))
	var bottom := _ignore(UIKit.row(content, 8))
	bottom.size_flags_vertical = SIZE_EXPAND_FILL
	var scenario := UIKit.label(bottom, String(job.scenario), ToySkin.SIZE_SMALL, ToySkin.TEXT_2 if open else ToySkin.TEXT_3)
	scenario.size_flags_vertical = SIZE_SHRINK_END
	_ignore(scenario)
	UIKit.spacer(bottom)
	var fee := UIKit.label(bottom, Units.money(float(job.fee)), ToySkin.SIZE_LABEL, ToySkin.YELLOW if open else ToySkin.TEXT_3, ToySkin.WEIGHT_HEAVY)
	fee.size_flags_vertical = SIZE_SHRINK_END
	_ignore(fee)

func show_briefing(job: Dictionary) -> void:
	clear()
	var kind := String(job.type)
	var top := UIKit.row(body, 10)
	_badge(top, kind)
	UIKit.label(top, "%s · %s" % [String(job.client), String(Templates.definition(String(job.template)).name)], ToySkin.SIZE_SMALL, ToySkin.LABEL, ToySkin.WEIGHT_STRONG).size_flags_vertical = SIZE_SHRINK_CENTER
	_header("", String(job.title), CareerJobs.scenario_line(job))
	# The call itself, as the client put it.
	var brief := PanelContainer.new()
	var quote := ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 16)
	quote.border_color = ToySkin.YELLOW
	quote.border_width_left = 3
	brief.add_theme_stylebox_override("panel", quote)
	body.add_child(brief)
	UIKit.text(brief, String(job.brief), ToySkin.SIZE_LABEL, ToySkin.TEXT)
	var budget := 0.0
	if kind == "install":
		budget = ceilf(HvacCosts.total(Templates.create(String(job.template)).objects) * float(job.get("budget_factor", 1.3)) / 500.0) * 500.0
	var details: Array[String] = []
	match kind:
		"service":
			details.append("Arrive %s, finish by %s." % [CareerJobs.clock(float(job.arrive_h)), CareerJobs.clock(float(job.deadline_h))])
			details.append("Tests cost time. Parts that fix nothing come out of your fee.")
			for ticket in job.get("tickets", []): details.append("Call from %s: %s" % [String(ticket.room), String(ticket.text)])
		"install":
			details.append("Budget %s for equipment, ducts and labour. Over budget comes out of your fee." % Units.money(budget))
			details.append("Commission over a %s: comfort is measured 07:00–18:00." % String(job.scenario).to_lower())
		"tune":
			details.append("As found: %s a day. Measured over a full day, midnight to midnight." % Units.money(float(job.get("baseline_usd", 0.0))))
			details.append("Comfort is judged at 68–76.5 °F and CO₂ under %d ppm, with people in 07:00–18:00." % roundi(DemoSimulation.FRESH_AIR_CO2_PPM))
	var columns := UIKit.row(body, 28)
	var left := UIKit.column(columns, 8)
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	UIKit.section(left, "The job")
	for line in details: _bullet(left, line, ToySkin.TEXT_2)
	var right := UIKit.column(columns, 8)
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	UIKit.section(right, "Objectives")
	for entry in JobSession.preview_objectives(job, budget):
		var row := UIKit.row(right, 10)
		if bool(entry[1]): Mark.make(row, "star", ToySkin.YELLOW, 14.0)
		else: Mark.make(row, "ring", ToySkin.TEXT_2, 14.0)
		var line := UIKit.text(row, String(entry[0]), ToySkin.SIZE_BODY, ToySkin.TEXT)
		line.size_flags_horizontal = SIZE_EXPAND_FILL
	UIKit.label(right, "Finish the ringed ones. Each starred one earns a star.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	var buttons := _footer()
	var fee := UIKit.column(buttons, 0)
	UIKit.label(fee, "FEE", ToySkin.SIZE_CAPTION, ToySkin.TEXT_3, ToySkin.WEIGHT_HEAVY)
	var amount := UIKit.row(fee, 8)
	UIKit.label(amount, Units.money(float(job.fee)), ToySkin.SIZE_HEADING, ToySkin.YELLOW, ToySkin.WEIGHT_HEAVY)
	UIKit.label(amount, "repeatable for stars" if not bool(job.get("on_call", false)) else "one call", ToySkin.SIZE_SMALL, ToySkin.TEXT_3).size_flags_vertical = SIZE_SHRINK_CENTER
	UIKit.spacer(buttons)
	_action(buttons, "Back to the job board", show_career, "GhostButton").size_flags_vertical = SIZE_SHRINK_CENTER
	var start := _action(buttons, "Start the job", func() -> void: _start_job(job), "PrimaryButton")
	start.custom_minimum_size.x = 180
	start.size_flags_vertical = SIZE_SHRINK_CENTER

func _bullet(parent: Node, value: String, colour: Color) -> void:
	var row := UIKit.row(parent, 10)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(14, 18)
	dot.size_flags_vertical = SIZE_SHRINK_BEGIN
	dot.draw.connect(func() -> void: dot.draw_circle(Vector2(7, 9), 2.5, ToySkin.LABEL, true, -1, true))
	row.add_child(dot)
	UIKit.text(row, value, ToySkin.SIZE_BODY, colour).size_flags_horizontal = SIZE_EXPAND_FILL

func _start_job(job: Dictionary) -> void:
	welcome = false
	hide()
	app.start_job(job)

func show_results(result: Dictionary) -> void:
	clear()
	var stars := int(result.stars)
	var done := stars > 0
	var head := UIKit.column(body, 8)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	var status := UIKit.label(head, "JOB COMPLETE" if done else "JOB NOT FINISHED", ToySkin.SIZE_SMALL, ToySkin.GREEN if done else ToySkin.DANGER, ToySkin.WEIGHT_HEAVY)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var name := UIKit.label(head, String(result.title), ToySkin.SIZE_DISPLAY, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var star_row := CenterContainer.new()
	head.add_child(star_row)
	var rating := Mark.make(star_row, "star", ToySkin.YELLOW, 44.0, 3, stars)
	rating.dim = Color(1, 1, 1, 0.18)
	var columns := UIKit.row(body, 16)
	var objectives := PanelContainer.new()
	objectives.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL + 2, 16))
	objectives.size_flags_horizontal = SIZE_EXPAND_FILL
	objectives.size_flags_stretch_ratio = 1.5
	columns.add_child(objectives)
	var list := UIKit.column(objectives, 10)
	UIKit.section(list, "Objectives")
	for objective in result.objectives:
		var state := String(objective.state)
		var row := UIKit.row(list, 10)
		Mark.make(row, {"done": "check", "failed": "cross"}.get(state, "ring"), {"done": ToySkin.GREEN, "failed": ToySkin.DANGER}.get(state, ToySkin.TEXT_3), 16.0)
		var words := UIKit.column(row, 1)
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		var title_row := UIKit.row(words, 6)
		UIKit.text(title_row, String(objective.label), ToySkin.SIZE_BODY, ToySkin.TEXT).size_flags_horizontal = SIZE_EXPAND_FILL
		if not bool(objective.required): Mark.make(title_row, "star", ToySkin.YELLOW, 12.0).size_flags_vertical = SIZE_SHRINK_BEGIN
		if not String(objective.detail).is_empty(): UIKit.text(words, String(objective.detail), ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	var side := UIKit.column(columns, 10)
	side.size_flags_horizontal = SIZE_EXPAND_FILL
	UIKit.section(side, "The numbers")
	UIKit.stats(side, result.get("stats", []))
	for note in result.get("notes", []): UIKit.text(side, String(note), ToySkin.SIZE_SMALL, ToySkin.WARN)
	var career: CareerState = app.career
	var buttons := _footer()
	var pay := UIKit.column(buttons, 0)
	var earned := UIKit.row(pay, 10)
	UIKit.label(earned, "Earned %s" % Units.money(float(result.get("earned", 0.0))), ToySkin.SIZE_HEADING, ToySkin.YELLOW, ToySkin.WEIGHT_HEAVY)
	if int(result.get("new_stars", 0)) > 0:
		UIKit.label(earned, "+%s" % _stars(int(result.new_stars)), ToySkin.SIZE_LABEL, ToySkin.YELLOW, ToySkin.WEIGHT_STRONG).size_flags_vertical = SIZE_SHRINK_CENTER
	UIKit.label(pay, "Bank %s · %s · %s" % [Units.money(career.money), CareerJobs.rank(career.total_stars()), _stars(career.total_stars())], ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	UIKit.spacer(buttons)
	var job_id := String(result.job_id)
	_action(buttons, "Stay and look around", func() -> void: app.end_job(); hide(), "GhostButton").size_flags_vertical = SIZE_SHRINK_CENTER
	if not job_id.begins_with("oncall"):
		_action(buttons, "Try again", func() -> void: _start_job(CareerJobs.find(job_id))).size_flags_vertical = SIZE_SHRINK_CENTER
	_action(buttons, "Job board", func() -> void: app.end_job(); show_career(), "PrimaryButton").size_flags_vertical = SIZE_SHRINK_CENTER

func _confirm_reset() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Start over?"
	dialog.dialog_text = "Start the career over? Stars and money go back to zero."
	dialog.ok_button_text = "Start over"
	dialog.theme = ToySkin.create()
	dialog.confirmed.connect(func() -> void: app.career.reset(); show_career(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 140))

static func _stars(count: int) -> String:
	return "%d star%s" % [count, "" if count == 1 else "s"]

func refresh_readout() -> void:
	pass
