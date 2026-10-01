extends PanelContainer

# Service calls: test and repair one air handler, VAV or thermostat. Tests
# and repairs take clock time and need you standing at the unit (Explore);
# "Walk over" takes you there for two minutes of the clock.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")

var game: Node
var target_id := ""
var title: Label
var live: Label
var place: PanelContainer
var where: Label
var walk_button: Button
var work_box: VBoxContainer
var work_label: Label
var work_bar: ProgressBar
var checks_box: VBoxContainer
var repairs_box: VBoxContainer
var extra_box: HFlowContainer
var _signature := ""

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -(ToySkin.MARGIN + 384)
	offset_right = -ToySkin.MARGIN
	offset_top = 100
	offset_bottom = -(ToySkin.MARGIN + 180) # clear of the parts tray
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_theme_stylebox_override("panel", ToySkin.card(0.98, 18))
	z_index = 29
	var column := UIKit.column(self, 12)
	var header := UIKit.row(column, 8)
	var titles := UIKit.column(header, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.section(titles, "Service")
	title = UIKit.title(titles, "", ToySkin.SIZE_TITLE)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	live = UIKit.label(titles, "", ToySkin.SIZE_SMALL, ToySkin.LABEL)
	live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.tile(header, "Close · Esc", "close", close, Vector2(32, 30)).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	place = PanelContainer.new()
	place.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 10))
	column.add_child(place)
	var place_row := UIKit.row(place, 10)
	where = UIKit.text(place_row, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	walk_button = UIKit.button(place_row, "Walk over · 2 min", func() -> void: if game.job != null: game.job.go_to(target_id), "PrimaryButton")
	walk_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	work_box = UIKit.column(column, 6)
	work_label = UIKit.label(work_box, "", ToySkin.SIZE_SMALL, ToySkin.YELLOW, ToySkin.WEIGHT_STRONG)
	work_bar = ProgressBar.new()
	work_bar.custom_minimum_size.y = 6
	work_bar.show_percentage = false
	work_bar.add_theme_stylebox_override("fill", ToySkin.fill(ToySkin.YELLOW, 999, 0))
	work_box.add_child(work_bar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 10)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	var inner := UIKit.column(gutter, 8)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section(inner, "Tests", "They cost time, not money.")
	checks_box = UIKit.column(inner, 6)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	inner.add_child(gap)
	_section(inner, "Repairs", "The right part fixes it. The wrong one is on you.")
	repairs_box = UIKit.column(inner, 6)
	extra_box = HFlowContainer.new()
	extra_box.add_theme_constant_override("h_separation", 6)
	extra_box.add_theme_constant_override("v_separation", 6)
	column.add_child(extra_box)
	hide()

func _section(parent: Node, heading: String, note: String) -> void:
	var row := UIKit.row(parent, 8)
	UIKit.section(row, heading).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.label(row, note, ToySkin.SIZE_SMALL, ToySkin.TEXT_3)

func open(id: String) -> void:
	if game.job == null or not game.job.is_service_target(id):
		return
	target_id = id
	_signature = ""
	game.hud.details.hide()
	game.hud.menu.hide()
	if not visible: UIKit.pop_in(self, game.reduced_motion)
	show()
	game.select(id)
	game.play_sound("open")
	refresh()

func close() -> void:
	hide()
	target_id = ""
	game.hud.refresh_card()

func refresh() -> void:
	if not visible or game.job == null:
		if visible and game.job == null: hide()
		return
	var job: JobSession = game.job
	var info: Dictionary = job.options_for(target_id)
	if info.is_empty() or String(info.kind).is_empty():
		close()
		return
	title.text = String(info.title)
	live.text = String(info.live)
	var on_site := bool(info.on_site)
	var busy := bool(info.busy)
	where.text = "You're at the unit." if on_site else "You're not at the unit. Walk there in Explore (Tab), or"
	where.add_theme_color_override("font_color", ToySkin.GREEN if on_site else ToySkin.TEXT_2)
	walk_button.visible = not on_site
	walk_button.disabled = busy or job.phase != "onsite"
	work_box.visible = busy and job.phase == "working"
	if work_box.visible:
		work_label.text = "%s… %s" % [String(job.work.get("label", "Working")), game.sim.weather().clock]
		work_bar.value = job.work_progress() * 100.0
	var signature := "%s|%s|%s|%s" % [target_id, str(on_site), str(busy), str(info.checks)]
	if signature == _signature:
		return
	_signature = signature
	UIKit.clear(checks_box)
	UIKit.clear(repairs_box)
	UIKit.clear(extra_box)
	var allowed := on_site and not busy and job.phase == "onsite"
	for check in info.checks:
		var check_id := String(check.id)
		var button := UIKit.task(checks_box, String(check.label), "%d min" % int(check.minutes), func() -> void: job.run_check(target_id, check_id))
		button.disabled = not allowed
		if not String(check.result).is_empty():
			var found := PanelContainer.new()
			var style := ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_SMALL, 10)
			style.border_color = ToySkin.LABEL
			style.border_width_left = 3
			found.add_theme_stylebox_override("panel", style)
			checks_box.add_child(found)
			UIKit.text(found, String(check.result), ToySkin.SIZE_SMALL, ToySkin.TEXT)
	for repair in info.repairs:
		var repair_id := String(repair.id)
		var cost := float(repair.cost)
		var meta := "%s · %d min" % [Units.money(cost) if cost > 0.0 else "no parts", int(repair.minutes)]
		var button := UIKit.task(repairs_box, String(repair.label), meta, func() -> void: job.run_repair(target_id, repair_id))
		button.disabled = not allowed
	if String(info.kind) == "tstat":
		var adjust := UIKit.button(extra_box, "Adjust setpoints", func() -> void: game.hud.show_thermostat(target_id), "ChipButton")
		adjust.disabled = not allowed
	elif String(info.kind) in ["ahu", "vav"]:
		UIKit.button(extra_box, "Open or close the casing", func() -> void: game.equipment.toggle_casing(target_id), "ChipButton")
	UIKit.button(extra_box, "Show trends", func() -> void: close(); game.set_mode(1); game.select(target_id), "ChipButton")
