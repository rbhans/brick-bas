extends PanelContainer

# BAS programming: the sequences behind the building, as a front end would
# expose them: the occupied schedule, optimal start, supply-air and duct
# static resets, economizer, demand ventilation, VAV minimums and room
# setpoints. Changes apply to the running simulation (Creative) or to a
# tune-up job while you're adjusting it.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")

var game: Node
var start_pick: OptionButton
var end_pick: OptionButton
var optimal: CheckBox
var sat_reset: CheckBox
var sat_fixed: SpinBox
var static_reset: CheckBox
var static_fixed: SpinBox
var economizer: CheckBox
var dcv: CheckBox
var vav_min: SpinBox
var cool_sp: SpinBox
var heat_sp: SpinBox
var note: Label
var apply_button: Button
var defaults_button: Button
var as_found: Label

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -320
	offset_right = 320
	offset_top = -330
	offset_bottom = 330
	add_theme_stylebox_override("panel", ToySkin.card(0.99, 22))
	z_index = 31
	var column := UIKit.column(self, 12)
	var header := UIKit.row(column, 8)
	var titles := UIKit.column(header, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.section(titles, "Controls")
	UIKit.title(titles, "BAS programming", ToySkin.SIZE_HEADING)
	UIKit.tile(header, "Close · Esc", "close", hide, Vector2(32, 30)).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	note = UIKit.text(column, "", ToySkin.SIZE_BODY, ToySkin.TEXT_2)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 12)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	var form := UIKit.column(gutter, 10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section(form, "Schedule", "When the air handlers run in occupied mode. People are in 07:00–18:00 regardless.")
	var hours := _field(form, "Occupied hours")
	start_pick = UIKit.options(hours, _half_hours(0.0, 23.5))
	UIKit.label(hours, "to", ToySkin.SIZE_BODY, ToySkin.TEXT_3).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	end_pick = UIKit.options(hours, _half_hours(0.5, 24.0))
	optimal = _check(form, "Optimal start: warm up or cool down just early enough before the schedule")
	_section(form, "Air handlers", "Trim & respond resets ease off when no room needs more. Fixed values never do.")
	sat_reset = _check(form, "Supply-air temperature reset (trim & respond)")
	sat_fixed = _spin(_field(form, "Otherwise hold supply air at", true), 50.0, 64.0, 55.0, 0.5)
	sat_fixed.suffix = "°F"
	static_reset = _check(form, "Duct static pressure reset (trim & respond)")
	static_fixed = _spin(_field(form, "Otherwise hold duct static at", true), 0.4, 2.0, 1.0, 0.05)
	static_fixed.suffix = "in. w.c."
	economizer = _check(form, "Economizer: cool with outdoor air when it's cool enough")
	dcv = _check(form, "Demand-controlled ventilation: outdoor air follows CO₂")
	_section(form, "Rooms", "VAV minimums keep air moving (and reheat busy). Setpoints apply to every room.")
	vav_min = _spin(_field(form, "Occupied VAV minimum"), 10.0, 80.0, 30.0, 5.0)
	vav_min.suffix = "%"
	cool_sp = _spin(_field(form, "Cooling setpoint"), 66.0, 80.0, 73.0, 1.0)
	cool_sp.suffix = "°F"
	heat_sp = _spin(_field(form, "Heating setpoint"), 61.0, 78.0, 70.0, 1.0)
	heat_sp.suffix = "°F"
	as_found = UIKit.text(form, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	var line := ColorRect.new()
	line.color = ToySkin.LINE
	line.custom_minimum_size.y = 1
	column.add_child(line)
	var buttons := UIKit.row(column, 8)
	defaults_button = UIKit.button(buttons, "Default sequences", _recommended, "GhostButton")
	UIKit.spacer(buttons)
	UIKit.button(buttons, "Close", hide)
	apply_button = UIKit.button(buttons, "Apply", _apply, "PrimaryButton")
	apply_button.custom_minimum_size.x = 110
	hide()

func _section(parent: Node, heading: String, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	parent.add_child(gap)
	UIKit.section(parent, heading)
	UIKit.text(parent, text, ToySkin.SIZE_SMALL, ToySkin.TEXT_3)

func _spin(row: HBoxContainer, minimum: float, maximum: float, value: float, step: float) -> SpinBox:
	var result := UIKit.spin(row, minimum, maximum, value, step)
	result.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	result.custom_minimum_size.x = 150
	return result

# A form row: the label on the left at a fixed width, the controls after it.
func _field(parent: Node, caption: String, indent: bool = false) -> HBoxContainer:
	var row := UIKit.row(parent, 10)
	var label := UIKit.label(row, caption, ToySkin.SIZE_BODY, ToySkin.TEXT_2)
	label.custom_minimum_size.x = 250
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if indent:
		label.custom_minimum_size.x = 222
		var pad := Control.new()
		pad.custom_minimum_size.x = 18
		row.add_child(pad)
		row.move_child(pad, 0)
	return row

func _check(parent: Node, text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.focus_mode = Control.FOCUS_NONE
	parent.add_child(box)
	return box

static func _half_hours(from: float, to: float) -> Array:
	var out: Array = []
	var hour := from
	while hour <= to + 0.01:
		out.append(CareerJobs.clock(hour) if hour < 24.0 else "24:00")
		hour += 0.5
	return out

func open() -> void:
	game.hud.menu.hide()
	game.hud.details.hide()
	_load(game.sim.controls_state())
	var job: JobSession = game.job
	var locked: bool = job != null and job.phase != "adjust" and job.type == "tune"
	apply_button.disabled = locked or (not game.data.is_demo())
	if not game.data.is_demo():
		note.text = "Live station data: the building's own BAS runs it. These settings drive the simulated building only."
	elif job != null and job.type == "tune":
		note.text = "As found, this is how the building was programmed. Change what you think is wasting energy, apply, then run the verification day." if not locked else "Stop the run to change the programming."
	elif job != null:
		note.text = "Read only during this job."
		apply_button.disabled = true
	else:
		note.text = "Changes apply to the simulated building right away. Watch the trends and the energy cost in the clock panel."
	as_found.text = ""
	# A tune-up is the puzzle of finding the right settings yourself.
	defaults_button.visible = job == null
	if job != null and job.type == "tune":
		as_found.text = "As found: occupied %s–%s, no optimal start, supply air fixed at 55 °F, static fixed at 1.6 in. w.c., economizer and DCV off, VAV minimum 60 %%, setpoints %.0f / %.0f °F." % [CareerJobs.clock(4.0), CareerJobs.clock(22.0), float(job.def.setpoints_f[0]), float(job.def.setpoints_f[1])]
	if not visible: UIKit.pop_in(self, game.reduced_motion)
	show()

func _load(controls: Dictionary) -> void:
	start_pick.select(clampi(roundi(float(controls.occupied_start_h) * 2.0), 0, start_pick.item_count - 1))
	end_pick.select(clampi(roundi(float(controls.occupied_end_h) * 2.0) - 1, 0, end_pick.item_count - 1))
	optimal.button_pressed = bool(controls.optimal_start)
	sat_reset.button_pressed = bool(controls.sat_reset)
	sat_fixed.value = Units.fahrenheit(float(controls.sat_fixed_c))
	static_reset.button_pressed = bool(controls.static_reset)
	static_fixed.value = Units.inwc(float(controls.static_fixed_pa))
	economizer.button_pressed = bool(controls.economizer)
	dcv.button_pressed = bool(controls.dcv)
	vav_min.value = float(controls.vav_min_fraction) * 100.0
	var cool := 0.0
	var heat := 0.0
	var count := 0
	for id in game.sim.zone_ids():
		var zone: Dictionary = game.sim.zone_state(String(id))
		cool += float(zone.cool_setpoint_c)
		heat += float(zone.heat_setpoint_c)
		count += 1
	cool_sp.value = roundf(Units.fahrenheit(cool / count)) if count > 0 else 73.0
	heat_sp.value = roundf(Units.fahrenheit(heat / count)) if count > 0 else 70.0

func _apply() -> void:
	var controls := {
		"occupied_start_h": start_pick.selected * 0.5, "occupied_end_h": (end_pick.selected + 1) * 0.5,
		"optimal_start": optimal.button_pressed, "sat_reset": sat_reset.button_pressed, "sat_fixed_c": (sat_fixed.value - 32.0) / 1.8,
		"static_reset": static_reset.button_pressed, "static_fixed_pa": static_fixed.value / Units.INWC_PER_PA,
		"economizer": economizer.button_pressed, "dcv": dcv.button_pressed, "vav_min_fraction": vav_min.value / 100.0,
	}
	var cool := (cool_sp.value - 32.0) / 1.8
	var heat := (minf(heat_sp.value, cool_sp.value - 2.0) - 32.0) / 1.8
	if game.job != null:
		if not game.job.program(controls, cool, heat):
			game.set_status("Stop the run to change the programming.")
			return
	else:
		game.sim.set_controls(controls)
		for id in game.sim.zone_ids(): game.sim.set_zone_setpoints(String(id), cool, heat)
	game.points.apply_updates(game.data.provider.snapshot())
	game.play_sound("save")
	game.set_status("BAS programming applied · occupied %s–%s" % [CareerJobs.clock(float(controls.occupied_start_h)), CareerJobs.clock(float(controls.occupied_end_h))])
	_load(game.sim.controls_state())

func _recommended() -> void:
	_load(DemoSimulation.DEFAULT_CONTROLS)
	cool_sp.value = CareerJobs.STANDARD_COOL_F
	heat_sp.value = CareerJobs.STANDARD_HEAT_F
