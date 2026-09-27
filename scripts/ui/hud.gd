extends Control

# Toy-brick HUD: mode tabs up top, a catalogue tray along the bottom, a tool
# strip on the left, clock and speed at bottom-left, and a context card for
# whatever is selected. Everything talks to the game through its public API.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Tray := preload("res://scripts/ui/toy_tray.gd")
const DetailsPanel := preload("res://scripts/ui/details_panel.gd")
const TrendChart := preload("res://scripts/ui/trend_chart.gd")

const BUILD_CATEGORIES := ["Rooms", "Floors", "Walls", "Doors & Windows", "Furniture", "Outdoor"]
const FURNITURE_GROUPS := [["office", "Office"], ["school", "School"], ["lounge", "Lounge"], ["kitchen", "Kitchen"], ["bath", "Bath"], ["mechanical", "Utility"], ["decor", "Decor"]]

var game: Node
var mode_buttons: Array[Button] = []
var tool_strip: VBoxContainer
var strip_buttons: Dictionary = {}
var wall_buttons: Array[Button] = []
var overlay_button: Button
var tray: PanelContainer
var category_row: HBoxContainer
var sub_row: HBoxContainer
var shelf: HBoxContainer
var shelf_scroll: ScrollContainer
var category := "Rooms"
var furniture_group := "office"
var category_tiles: Dictionary = {}
var shelf_tiles: Dictionary = {}
var room_style := "tan"
var room_finish := "oak"
var clock_label: Label
var weather_label: Label
var speed_buttons: Array[Button] = []
var card: PanelContainer
var card_title: Label
var card_body: Label
var card_meter: ProgressBar
var card_trend: Control
var card_actions: HFlowContainer
var card_extra: VBoxContainer
var status_label: Label
var alarm_label: Button
var alarm_panel: PanelContainer
var alarm_list: VBoxContainer
var _alarm_signature := ""
var source_label: Label
var menu: PanelContainer
var graphics_picker: OptionButton
var scenario_picker: OptionButton
var details: Control
var thermostat_panel: PanelContainer
var thermostat_id := ""
var thermostat_title: Label
var thermostat_reading: Label
var thermostat_setpoint: Label
var thermostat_detail: Label
var hint_panel: PanelContainer
var hint_label: Label
var _card_cache := ""

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ToySkin.create()
	_build_top()
	_build_strip()
	_build_tray()
	_build_clock()
	_build_card()
	_build_status()
	_build_menu()
	_build_thermostat()
	details = DetailsPanel.new()
	add_child(details)
	details.setup(game)
	game.selection_changed.connect(func(_id: String) -> void: _card_cache = ""; refresh_card())
	game.mode_changed.connect(func(_mode: int) -> void: refresh_mode())
	game.world_changed.connect(func() -> void: _card_cache = ""; refresh_card())
	refresh_mode()

# --- Top bar ----------------------------------------------------------------------

func _row_at(rect: Vector4, preset: int) -> HBoxContainer:
	var result := HBoxContainer.new()
	add_child(result)
	result.set_anchors_and_offsets_preset(preset)
	result.offset_left = rect.x
	result.offset_top = rect.y
	result.offset_right = rect.z
	result.offset_bottom = rect.w
	result.add_theme_constant_override("separation", 10)
	return result

func _build_top() -> void:
	var brand := _row_at(Vector4(22, 20, 330, 74), Control.PRESET_TOP_LEFT)
	var logo := UIKit.tile(brand, "Menu", "brick", toggle_menu, Vector2(54, 48))
	logo.face_color = Color("c94435")
	logo.layout_kind = "brand"
	logo.studs = true
	logo.tooltip_text = "Project, simulation and settings"
	var title := UIKit.label(brand, "BRICK / BAS", 23)
	title.add_theme_font_override("font", ToySkin.font(800))
	var modes := _row_at(Vector4(-240, 24, 240, 80), Control.PRESET_CENTER_TOP)
	for entry in [["Build", "build", 0, "Rooms, walls, floors, furniture · 1"], ["Equipment", "fan", 1, "Air handlers, VAVs, ducts · 2"], ["Explore", "explore", 2, "Walk around inside · Tab"]]:
		var mode_index := int(entry[2])
		var choice := UIKit.tile(modes, String(entry[0]), String(entry[1]), func() -> void: game.set_mode(mode_index), Vector2(150, 54), "mode")
		choice.studs = true
		choice.toggle_mode = true
		choice.tooltip_text = String(entry[3])
		mode_buttons.append(choice)
	var actions := _row_at(Vector4(-240, 22, -22, 72), Control.PRESET_TOP_RIGHT)
	actions.alignment = BoxContainer.ALIGNMENT_END
	UIKit.tile(actions, "Undo · Ctrl+Z", "undo", game.undo)
	UIKit.tile(actions, "Redo · Ctrl+Shift+Z", "redo", game.redo)
	UIKit.tile(actions, "Save · Ctrl+S", "save", game.save_project)
	UIKit.tile(actions, "Menu", "settings", toggle_menu)

# --- Tool strip ---------------------------------------------------------------------

func _build_strip() -> void:
	tool_strip = VBoxContainer.new()
	add_child(tool_strip)
	tool_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tool_strip.position = Vector2(24, 96)
	tool_strip.add_theme_constant_override("separation", 7)
	strip_buttons.select = UIKit.tile(tool_strip, "Select · Esc", "select", game.finish_tool, Vector2(46, 42))
	strip_buttons.move = UIKit.tile(tool_strip, "Move selected · M (or drag it)", "move", func() -> void: if not game.selected_id.is_empty() and game.can_move(game.selected_id): game.start_move(game.selected_id), Vector2(46, 42))
	strip_buttons.rotate = UIKit.tile(tool_strip, "Rotate · R", "rotate", game.rotate_selected, Vector2(46, 42))
	strip_buttons.copy = UIKit.tile(tool_strip, "Copy · Ctrl+D", "copy", game.duplicate_selected, Vector2(46, 42))
	strip_buttons.delete = UIKit.tile(tool_strip, "Sledgehammer · H · click or drag an area", "hammer", func() -> void: game.start_tool("delete"), Vector2(46, 42))
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	tool_strip.add_child(gap)
	for entry in [["Walls up", "walls_up", 0], ["Walls cutaway", "walls_cut", 1], ["Walls down", "walls_down", 2]]:
		var value := int(entry[2])
		var button := UIKit.tile(tool_strip, "%s · V cycles" % entry[0], String(entry[1]), func() -> void: game.set_wall_mode(value); refresh_mode(), Vector2(46, 42))
		wall_buttons.append(button)
	overlay_button = UIKit.tile(tool_strip, "BAS view · B · rooms tinted by temperature", "thermo", game.toggle_overlay, Vector2(46, 42))
	UIKit.tile(tool_strip, "Frame the lot · Home", "top", game.frame_lot, Vector2(46, 42))

# --- Catalogue tray -------------------------------------------------------------------

func _build_tray() -> void:
	tray = UIKit.panel(self, Vector4(-470, -236, 470, -44), Control.PRESET_CENTER_BOTTOM, StyleBoxEmpty.new())
	var column := UIKit.column(tray, 6)
	category_row = UIKit.row(column, 6)
	category_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row = UIKit.row(column, 6)
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var box := Tray.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(box)
	shelf_scroll = ScrollContainer.new()
	shelf_scroll.custom_minimum_size = Vector2(860, 118)
	shelf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(shelf_scroll)
	shelf = UIKit.row(shelf_scroll, 8)
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _categories() -> Array:
	return BUILD_CATEGORIES if game.mode == 0 else game.equipment.tray_categories()

func _rebuild_categories() -> void:
	UIKit.clear(category_row)
	category_tiles.clear()
	var names := _categories()
	if category not in names:
		category = String(names[0]) if not names.is_empty() else ""
	for name in names:
		var id := String(name)
		category_tiles[id] = UIKit.tile(category_row, id, "", func() -> void: category = id; rebuild_shelf(), Vector2(maxf(96, id.length() * 9.5 + 26), 34), "line")
	rebuild_shelf()

func rebuild_shelf() -> void:
	for id in category_tiles:
		category_tiles[id].marked = id == category
		category_tiles[id].queue_redraw()
	UIKit.clear(shelf)
	UIKit.clear(sub_row)
	shelf_tiles.clear()
	sub_row.visible = false
	if game.mode == 1:
		for entry in game.equipment.tray_items(category):
			if entry.has("note"):
				_note(String(entry.note))
				continue
			_item(String(entry.id), String(entry.label), entry.action, entry.get("glyph", ""), entry.get("color", Color("e5dfca")), String(entry.get("tooltip", entry.label)))
		return
	match category:
		"Rooms":
			var style_label: String = ArchitectureRenderer.WALL_STYLES[room_style].label
			var finish_label: String = ArchitectureRenderer.FLOOR_FINISHES[room_finish].label
			_item("tool_room", "Room", func() -> void: game.start_tool("room", {"style": room_style, "finish": room_finish}), "room", Color("f1d98c"), "Drag a rectangle: walls (%s) and floor (%s) together" % [style_label, finish_label])
			_item("tool_wall", "Wall", func() -> void: game.start_tool("wall", {"style": room_style}), "wallpen", Color("e8c9a0"), "Drag along the grid to build walls · Ctrl-drag removes")
			_item("tool_unwall", "Remove walls", func() -> void: game.start_tool("wall", {"style": room_style, "erase": true}), "hammer", Color("d9a597"), "Drag along walls to knock them down")
			_item("tool_floor", "Floor", func() -> void: game.start_tool("floor", {"finish": room_finish}), "floor", Color("d8cfb4"), "Paint %s · Shift-click fills a room" % finish_label)
			_item("tool_unfloor", "Lift floor", func() -> void: game.start_tool("floor", {"finish": room_finish, "erase": true}), "hammer", Color("d9a597"), "Drag across tiles to lift them")
			_item("tool_door", "Door", func() -> void: game.start_tool("door", {"style": "door"}), "door", Color("e0c7a8"), "Fit a door into a wall section · R flips its swing")
			_item("tool_window", "Window", func() -> void: game.start_tool("window", {"style": "window"}), "window", Color("c7dce4"), "Fit a window into a wall section")
			_note("New rooms: %s walls · %s" % [style_label, finish_label])
		"Floors":
			for finish in ArchitectureRenderer.FLOOR_FINISHES:
				var key := String(finish)
				if key in ["paving", "paving_tan", "asphalt"]: continue
				var spec: Dictionary = ArchitectureRenderer.FLOOR_FINISHES[key]
				_swatch("floor_" + key, String(spec.label), Bricks.color(spec.colors[0]), func() -> void: room_finish = key; game.start_tool("floor", {"finish": key}); rebuild_shelf(), key == room_finish)
		"Walls":
			for style in ArchitectureRenderer.WALL_STYLES:
				var key := String(style)
				var spec: Dictionary = ArchitectureRenderer.WALL_STYLES[key]
				_swatch("wall_" + key, String(spec.label), Bricks.color(spec.body), func() -> void: room_style = key; game.start_tool("paint", {"style": key}); rebuild_shelf(), key == room_style)
			_note("Click walls to repaint · Shift-click a room · new walls use the marked style")
		"Doors & Windows":
			for style in ArchitectureRenderer.DOOR_STYLES:
				var key := String(style)
				_item("door_" + key, String(ArchitectureRenderer.DOOR_STYLES[key].label), func() -> void: game.start_tool("door", {"style": key}), "door", Bricks.color(ArchitectureRenderer.DOOR_STYLES[key].leaf).lightened(0.35))
			for style in ArchitectureRenderer.WINDOW_STYLES:
				var key := String(style)
				_item("window_" + key, String(ArchitectureRenderer.WINDOW_STYLES[key].label), func() -> void: game.start_tool("window", {"style": key}), "window", Color("c7dce4"))
		"Furniture":
			sub_row.visible = true
			for group in FURNITURE_GROUPS:
				var id := String(group[0])
				var chip := UIKit.tile(sub_row, String(group[1]), "", func() -> void: furniture_group = id; rebuild_shelf(), Vector2(86, 28), "line")
				chip.marked = id == furniture_group
			var items := Placement.furniture_items()
			var any := false
			for item_id in items:
				var spec: Dictionary = items[item_id]
				if String(spec.get("category", "")) != furniture_group: continue
				any = true
				var key := String(item_id)
				_item(key, String(spec.label), func() -> void: game.start_tool("place", {"kind": "furniture", "item": key}), "sofa")
			if not any:
				_note("Furniture for this room type is on its way.")
		"Outdoor":
			for variant in ArchitectureRenderer.TREES:
				var key := String(variant)
				_item("tree_" + key, "%s tree" % key.capitalize(), func() -> void: game.start_tool("place", {"kind": "tree", "item": key}), "tree", Color("b9d9a8"))
			_item("shrub", "Shrub", func() -> void: game.start_tool("place", {"kind": "shrub"}), "tree", Color("c7e0b0"))
			_item("parking", "Parking stall", func() -> void: game.start_tool("place", {"kind": "parking"}), "floor", Color("b4bcc2"))
			for finish in ["paving", "paving_tan", "asphalt", "concrete"]:
				var key := String(finish)
				var spec: Dictionary = ArchitectureRenderer.FLOOR_FINISHES[key]
				_swatch("floor_" + key, String(spec.label), Bricks.color(spec.colors[0]), func() -> void: game.start_tool("floor", {"finish": key}), false)
			var items := Placement.furniture_items()
			for item_id in items:
				if String(items[item_id].get("category", "")) != "outdoor": continue
				var key := String(item_id)
				_item(key, String(items[item_id].label), func() -> void: game.start_tool("place", {"kind": "furniture", "item": key}), "tree")

func _item(id: String, caption: String, action: Callable, glyph: String = "", face: Color = Color("e5dfca"), tooltip: String = "") -> Button:
	var result := UIKit.tile(shelf, caption, glyph, action, Vector2(100, 108), "part")
	result.face_color = face
	result.thumbnail = UIKit.thumbnail(id)
	result.tooltip_text = tooltip if not tooltip.is_empty() else caption
	shelf_tiles[id] = result
	return result

func _swatch(id: String, caption: String, colour: Color, action: Callable, marked: bool) -> void:
	var result := _item(id, caption, action, "", colour.lerp(Color.WHITE, 0.08))
	result.marked = marked
	if result.thumbnail == null:
		result.glyph = "brick"

func _note(text: String) -> void:
	var note := UIKit.label(shelf, text, 12, ToySkin.INK)
	note.custom_minimum_size.x = 150
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func tool_changed() -> void:
	var active_id: String = game.tool.id if game.tool != null else "select"
	for id in strip_buttons:
		strip_buttons[id].marked = (id == "select" and active_id == "select") or (id == "delete" and active_id == "delete")
		strip_buttons[id].queue_redraw()
	var mode_value: int = game.effective_wall_mode()
	for index in range(wall_buttons.size()):
		wall_buttons[index].marked = index == mode_value
		wall_buttons[index].queue_redraw()
	overlay_button.marked = game.overlay
	overlay_button.queue_redraw()

# --- Clock and speed -------------------------------------------------------------------

func _build_clock() -> void:
	var box := UIKit.panel(self, Vector4(22, -128, 262, -46), Control.PRESET_BOTTOM_LEFT, UIKit.glass_style(14, 0.88))
	var column := UIKit.column(box, 4)
	var top := UIKit.row(column, 8)
	clock_label = UIKit.label(top, "08:00", 24)
	clock_label.add_theme_font_override("font", ToySkin.font(800))
	weather_label = UIKit.label(top, "", 12, Color("b7c4c8"))
	weather_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weather_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var speeds := UIKit.row(column, 6)
	for entry in [["Pause", "pause", 0.0], ["Normal speed", "play", 1.0], ["Fast · 10×", "fast", 10.0], ["Very fast · 60×", "faster", 60.0]]:
		var speed := float(entry[2])
		var button := UIKit.tile(speeds, String(entry[0]), String(entry[1]), func() -> void: game.set_speed(speed), Vector2(48, 34))
		button.set_meta("speed", speed)
		speed_buttons.append(button)

func refresh_simulation_controls() -> void:
	for button in speed_buttons:
		var speed := float(button.get_meta("speed"))
		button.marked = (speed == 0.0 and not game.sim.running) or (game.sim.running and is_equal_approx(speed, game.sim.speed))
		button.queue_redraw()
	if is_instance_valid(scenario_picker):
		var index: int = DemoSimulation.SCENARIOS.find(game.sim.scenario)
		if index >= 0: scenario_picker.select(index)

# --- Context card -----------------------------------------------------------------------

func _build_card() -> void:
	card = UIKit.panel(self, Vector4(-300, 96, -22, 96), Control.PRESET_TOP_RIGHT, UIKit.glass_style(14, 0.92))
	card.grow_vertical = Control.GROW_DIRECTION_END
	var body := UIKit.column(card, 8)
	var header := UIKit.row(body, 6)
	card_title = UIKit.label(header, "", 19)
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card_title.add_theme_font_override("font", ToySkin.font(800))
	UIKit.tile(header, "Details · paint · point links", "more", func() -> void: details.open(game.selected_id), Vector2(34, 30))
	card_body = UIKit.label(body, "", 13, Color("d3dcdf"))
	card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_body.custom_minimum_size.x = 244
	card_meter = ProgressBar.new()
	card_meter.custom_minimum_size.y = 7
	card_meter.show_percentage = false
	card_meter.add_theme_stylebox_override("background", ToySkin.face(Color("142328"), 4, 0))
	card_meter.add_theme_stylebox_override("fill", ToySkin.face(ToySkin.GREEN, 4, 0))
	body.add_child(card_meter)
	card_trend = TrendChart.new()
	body.add_child(card_trend)
	card_trend.setup(game)
	card_trend.hide()
	card_extra = UIKit.column(body, 6)
	# Actions wrap onto more rows rather than running off the screen edge.
	card_actions = HFlowContainer.new()
	card_actions.add_theme_constant_override("h_separation", 6)
	card_actions.add_theme_constant_override("v_separation", 6)
	body.add_child(card_actions)
	card.visible = false

func refresh_card() -> void:
	var id: String = game.selected_id
	var item: Dictionary = game.model.find_object(id)
	card.visible = not item.is_empty() and game.mode != 2 and not menu.visible and not details.visible
	if item.is_empty():
		return
	card_title.text = game.describe(id)
	var info: Dictionary = game.inspect(id)
	card_body.text = String(info.get("text", ""))
	card_meter.visible = info.has("level")
	card_meter.value = float(info.get("level", 0.0)) * 100.0
	card_trend.show_series(info.get("trends", []))
	var signature := id + "|" + str(info.get("actions", []))
	if signature == _card_cache:
		return
	_card_cache = signature
	UIKit.clear(card_actions)
	UIKit.clear(card_extra)
	for action in info.get("actions", []):
		var callback: Callable = action.call
		UIKit.tile(card_actions, String(action.label), String(action.glyph), callback, Vector2(46, 40))
	if info.has("room"):
		_room_editor(info.room)

func _room_editor(room: Dictionary) -> void:
	var line := UIKit.line(card_extra, "Room name")
	line.text = String(room.label)
	line.text_submitted.connect(func(text: String) -> void: game.rename_room(String(room.id), text); line.release_focus())
	line.focus_exited.connect(func() -> void: game.rename_room(String(room.id), line.text))
	var types := ["room", "office", "open_office", "conference", "classroom", "library", "lobby", "corridor", "break_room", "restroom", "storage", "mechanical", "gym", "workshop"]
	var picker := UIKit.options(card_extra, types.map(func(value: String) -> String: return value.replace("_", " ").capitalize()))
	picker.select(maxi(0, types.find(String(room.type))))
	picker.item_selected.connect(func(index: int) -> void: game.set_room_type(String(room.id), types[index]))

# --- Status line ----------------------------------------------------------------------------

func _build_status() -> void:
	var footer := _row_at(Vector4(278, -36, -300, -10), Control.PRESET_BOTTOM_WIDE)
	status_label = UIKit.label(footer, "", 13)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_color_override("font_shadow_color", Color("111a1f"))
	status_label.add_theme_constant_override("shadow_offset_y", 1)
	var right := _row_at(Vector4(-290, -36, -22, -10), Control.PRESET_BOTTOM_RIGHT)
	right.alignment = BoxContainer.ALIGNMENT_END
	source_label = UIKit.label(right, "● DEMO", 12, Color("73d398"))
	alarm_label = Button.new()
	alarm_label.flat = true
	alarm_label.focus_mode = Control.FOCUS_NONE
	alarm_label.add_theme_font_size_override("font_size", 12)
	alarm_label.tooltip_text = "Show active alarms"
	alarm_label.pressed.connect(toggle_alarms)
	right.add_child(alarm_label)
	_build_alarm_panel()
	hint_panel = UIKit.panel(self, Vector4(-330, -104, 330, -52), Control.PRESET_CENTER_BOTTOM, UIKit.glass_style(12, 0.78))
	hint_label = UIKit.label(hint_panel, "WASD walk · Shift run · Space jump · E use · drag to look · wheel zoom · Tab build", 13)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_alarm_panel() -> void:
	alarm_panel = UIKit.panel(self, Vector4(-430, -330, -22, -44), Control.PRESET_BOTTOM_RIGHT, UIKit.glass_style(14, 0.97))
	alarm_panel.z_index = 26
	var body := UIKit.column(alarm_panel, 8)
	var header := UIKit.row(body)
	UIKit.label(header, "ALARMS", 15).add_theme_font_override("font", ToySkin.font(800))
	UIKit.spacer(header)
	UIKit.button(header, "Acknowledge all", func() -> void: game.alarms.acknowledge_all(); _refresh_alarms(true))
	UIKit.tile(header, "Close", "close", func() -> void: alarm_panel.hide(), Vector2(30, 28))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	alarm_list = UIKit.column(scroll, 6)
	alarm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alarm_panel.hide()

func toggle_alarms() -> void:
	alarm_panel.visible = not alarm_panel.visible
	_refresh_alarms(true)

func _refresh_alarms(force: bool = false) -> void:
	var alarms: Array = game.alarms.list()
	var signature := str(alarms)
	if not force and signature == _alarm_signature:
		return
	_alarm_signature = signature
	UIKit.clear(alarm_list)
	if alarms.is_empty():
		UIKit.label(alarm_list, "All systems normal. Try a fault scenario from the menu: fan failure, stuck damper, dirty filter…", 12, Color("b9c4c7")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var colours := {"critical": Color("ef5a48"), "warning": Color("f2b441"), "notice": Color("8cc8e8")}
	for alarm in alarms:
		var row := UIKit.row(alarm_list, 6)
		var dot := ColorRect.new()
		dot.color = colours.get(String(alarm.severity), Color.WHITE)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var text := UIKit.label(row, String(alarm.message), 12, Color("eee8d4") if not bool(alarm.acknowledged) else Color("8f9ea3"))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var target := String(alarm.id).get_slice(":", 1)
		UIKit.tile(row, "Show", "eye", func() -> void: game.focus_on(target), Vector2(32, 28))
		if not bool(alarm.acknowledged):
			var id := String(alarm.id)
			UIKit.tile(row, "Acknowledge", "close", func() -> void: game.alarms.acknowledge(id); _refresh_alarms(true), Vector2(32, 28))

func set_status(text: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = text

# --- Menu -----------------------------------------------------------------------------------

func _build_menu() -> void:
	menu = UIKit.panel(self, Vector4(-340, 90, -22, -50), Control.PRESET_RIGHT_WIDE, UIKit.glass_style(16, 0.97))
	menu.z_index = 30
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(scroll)
	var body := UIKit.column(scroll, 9)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIKit.row(body)
	UIKit.label(title, "YOUR LOT", 17).add_theme_font_override("font", ToySkin.font(800))
	UIKit.spacer(title)
	UIKit.tile(title, "Close", "close", func() -> void: menu.hide(); refresh_card(), Vector2(30, 28))
	var files := UIKit.row(body)
	UIKit.button(files, "Save", game.save_project)
	UIKit.button(files, "Load", func() -> void: game.load_project(); menu.hide())
	if OS.has_feature("web"):
		var backups := UIKit.row(body)
		UIKit.button(backups, "Download backup", func() -> void: game.browser_files.download())
		UIKit.button(backups, "Import backup", func() -> void: game.browser_files.choose())
	UIKit.button(body, "New lot / choose a starter", func() -> void: menu.hide(); game.session_ui.show_starters())
	UIKit.label(body, "Simulation", 13, Color("b1bcbf"))
	scenario_picker = UIKit.options(body, DemoSimulation.SCENARIOS)
	scenario_picker.item_selected.connect(func(index: int) -> void: game.set_scenario(DemoSimulation.SCENARIOS[index]))
	UIKit.button(body, "Restart the day", game.reset_simulation)
	if not game.demo_only:
		UIKit.label(body, "Data source (desktop)", 13, Color("b1bcbf"))
		var sources := UIKit.row(body)
		UIKit.button(sources, "Niagara connection", func() -> void: menu.hide(); details.open_connections())
		UIKit.button(sources, "Use demo", game.data.use_demo)
		var hint := UIKit.label(body, "Live Niagara via baskStream is read-only and parked until the SDK is final. The demo simulation is the default.", 12, Color("8f9ea3"))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.label(body, "Options", 13, Color("b1bcbf"))
	var quality := UIKit.row(body, 8)
	UIKit.label(quality, "Graphics", 13, Color("d3dcdf"))
	graphics_picker = UIKit.options(quality, ["Auto", "High", "Low (faster)"])
	graphics_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_picker.item_selected.connect(func(index: int) -> void: game.set_graphics(["auto", "high", "low"][index]))
	var motion := CheckBox.new()
	motion.text = "Reduce motion"
	motion.button_pressed = game.reduced_motion
	motion.toggled.connect(func(value: bool) -> void: game.reduced_motion = value; Settings.store("reduced_motion", value))
	body.add_child(motion)
	var sound := CheckBox.new()
	sound.text = "Sounds"
	sound.button_pressed = game.sound_enabled
	sound.toggled.connect(func(value: bool) -> void: game.sound_enabled = value; Settings.store("sounds", value))
	body.add_child(sound)
	UIKit.button(body, "Show the quick tour", func() -> void: menu.hide(); refresh_card(); game.show_tour())
	var help := UIKit.label(body, "BUILD\n  Drag rooms, walls and floors on the grid\n  Right-drag orbit · middle-drag / WASD pan\n  Wheel zoom · Q / E rotate 45° · Home frame lot\n  R rotate · M move · Del delete · Ctrl+D copy\n  V wall view · B BAS view · Esc back\nEXPLORE (Tab)\n  WASD walk · Shift run · Space jump\n  E use / open · drag to look · wheel zoom\n  Doors open as you walk into them", 12, Color("b9c4c7"))
	help.add_theme_constant_override("line_spacing", 2)
	if OS.has_feature("web"):
		UIKit.button(body, "Credits / licenses", func() -> void: game.browser_files.browser.credits())
	menu.hide()

func toggle_menu() -> void:
	menu.visible = not menu.visible
	if menu.visible:
		details.hide()
		refresh_simulation_controls()
		graphics_picker.select(["auto", "high", "low"].find(game.graphics))
	refresh_card()

func close_panels() -> bool:
	var bench: Control = game.equipment.workbench
	if is_instance_valid(bench) and bench.visible:
		bench.close()
		return true
	if menu.visible:
		menu.hide()
		refresh_card()
		return true
	if details.visible:
		details.hide()
		refresh_card()
		return true
	if thermostat_open():
		hide_thermostat()
		return true
	return false

func typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is SpinBox

# --- Thermostat -----------------------------------------------------------------------------

func _build_thermostat() -> void:
	thermostat_panel = UIKit.panel(self, Vector4(0, 0, 250, 0), Control.PRESET_TOP_LEFT, UIKit.glass_style(18, 0.95))
	thermostat_panel.z_index = 25
	var body := UIKit.column(thermostat_panel, 6)
	thermostat_title = UIKit.label(body, "Thermostat", 15, Color("b9c4c7"))
	thermostat_reading = UIKit.label(body, "--.- °F", 34)
	thermostat_reading.add_theme_font_override("font", ToySkin.font(800))
	var controls := UIKit.row(body, 8)
	UIKit.tile(controls, "Cooler · − or wheel", "left", func() -> void: nudge_thermostat(-1.0), Vector2(40, 36))
	thermostat_setpoint = UIKit.label(controls, "Set 72 °F", 17)
	thermostat_setpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thermostat_setpoint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.tile(controls, "Warmer · + or wheel", "right", func() -> void: nudge_thermostat(1.0), Vector2(40, 36))
	thermostat_detail = UIKit.label(body, "", 12, Color("b9c4c7"))
	thermostat_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	thermostat_detail.custom_minimum_size.x = 220
	thermostat_panel.hide()

func show_thermostat(id: String) -> void:
	thermostat_id = id
	thermostat_panel.show()
	_refresh_thermostat()

func hide_thermostat() -> void:
	if thermostat_panel.visible:
		game.play_sound("close")
	thermostat_panel.hide()
	thermostat_id = ""

func thermostat_open() -> bool:
	return thermostat_panel.visible

func nudge_thermostat(step: float) -> void:
	if thermostat_id.is_empty():
		return
	if game.adjust_thermostat(thermostat_id, step):
		game.play_sound("tick")
	_refresh_thermostat()

func _refresh_thermostat() -> void:
	if thermostat_id.is_empty():
		return
	var info: Dictionary = game.thermostat_info(thermostat_id)
	thermostat_title.text = String(info.get("title", "Thermostat"))
	thermostat_reading.text = Units.temp(float(info.get("temp_c", 0.0)), 1) if info.has("temp_c") else "-- °F"
	thermostat_setpoint.text = "Set %s" % Units.temp(float(info.get("setpoint_c", 22.0))) if info.has("setpoint_c") else "Not linked"
	thermostat_detail.text = String(info.get("detail", ""))
	var anchor: Vector3 = info.get("anchor", Vector3.INF)
	var camera: Camera3D = game.active_camera()
	var place := Vector2(size.x - 290, 110)
	if anchor != Vector3.INF and not camera.is_position_behind(anchor):
		place = camera.unproject_position(anchor) + Vector2(30, -120)
	thermostat_panel.position = place.clamp(Vector2(10, 90), size - Vector2(270, 220))

# --- Refresh --------------------------------------------------------------------------------

func refresh_mode() -> void:
	var mode: int = game.mode
	for index in range(mode_buttons.size()):
		mode_buttons[index].set_pressed_no_signal(index == mode)
		mode_buttons[index].queue_redraw()
	tool_strip.visible = mode != 2
	var bench: Control = game.equipment.workbench
	if is_instance_valid(bench) and bench.visible and mode != 1:
		bench.hide()
	tray.visible = mode != 2 and not (is_instance_valid(bench) and bench.visible)
	hint_panel.visible = mode == 2
	_rebuild_categories()
	tool_changed()
	_card_cache = ""
	refresh_card()

func refresh() -> void:
	var weather: Dictionary = game.sim.weather()
	clock_label.text = String(weather.get("clock", "--:--"))
	weather_label.text = "%s outside\n%s%s" % [Units.temp(float(weather.get("outdoor_temp_c", 0.0))), "Occupied" if bool(weather.get("occupied", false)) else "Unoccupied", " · paused" if not game.sim.running else ""]
	alarm_label.text = game.alarms.summary()
	var unacknowledged: int = game.alarms.list().filter(func(alarm: Dictionary) -> bool: return not bool(alarm.acknowledged)).size()
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
	alarm_label.add_theme_color_override("font_color", Color("ef5a48").lerp(Color("ffd17a"), pulse) if unacknowledged > 0 else Color("73d398"))
	if alarm_panel.visible: _refresh_alarms()
	source_label.text = "● DEMO" if game.data.is_demo() else "● NIAGARA"
	source_label.add_theme_color_override("font_color", Color("73d398") if game.data.is_demo() else Color("8cc8e8"))
	undo_state()
	refresh_card()
	if thermostat_open():
		_refresh_thermostat()
	if details.visible:
		details.refresh()

func undo_state() -> void:
	pass
