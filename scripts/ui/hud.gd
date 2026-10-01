extends Control

# Toy-brick HUD. Layout at the 1440 × 900 design size, 24 px from every edge:
#   top      brand brick · mode tabs (center) · undo / redo / save / menu
#   left     the tool rail (tools, then view toggles)
#   bottom   clock card (left) · the cream parts tray (center) · data and
#            alarm pills (right)
#   right    the context card for whatever is selected
# plus a status toast under the mode tabs, and the Explore prompt that
# follows what the minifigure faces. Everything talks to the game through its
# public API; colours, type and shapes come from ToySkin.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Tray := preload("res://scripts/ui/toy_tray.gd")
const DetailsPanel := preload("res://scripts/ui/details_panel.gd")
const TrendChart := preload("res://scripts/ui/trend_chart.gd")
const JobPanel := preload("res://scripts/ui/job_panel.gd")
const ServicePanel := preload("res://scripts/ui/service_panel.gd")
const ControlsPanel := preload("res://scripts/ui/controls_panel.gd")
const Symbols := preload("res://scripts/ui/toy_symbols.gd")

const BUILD_CATEGORIES := ["Rooms", "Floors", "Walls", "Doors & Windows", "Furniture", "Outdoor"]
const FURNITURE_GROUPS := [["office", "Office"], ["school", "School"], ["lounge", "Lounge"], ["kitchen", "Kitchen"], ["bath", "Bath"], ["mechanical", "Utility"], ["decor", "Decor"]]
const KIND_NAMES := {"ahu": "Air handler", "vav": "VAV box", "duct": "Supply duct", "diffuser": "Ceiling diffuser", "tee": "Branch tee", "cross": "Trunk cross",
	"tstat": "Thermostat", "wall": "Wall", "door": "Door", "window": "Window", "furniture": "Furniture", "tree": "Tree", "shrub": "Shrub", "parking": "Parking", "floor": "Floor"}
const M := ToySkin.MARGIN
const STATUS_SECONDS := 5.0

var game: Node
var mode_buttons: Array[Button] = []
var tool_strip: PanelContainer
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
var occupancy_label: Label
var energy_label: Label
var speed_buttons: Array[Button] = []
var speed_row: HBoxContainer
var card: PanelContainer
var card_title: Label
var card_subtitle: Label
var card_body: Label
var card_meter: ProgressBar
var card_trend: Control
var card_actions: HFlowContainer
var card_extra: VBoxContainer
var status_panel: PanelContainer
var status_label: Label
var _status_age := 0.0
var source_pill: Button
var alarm_pill: Button
var alarm_panel: PanelContainer
var alarm_list: VBoxContainer
var alarm_scroll: ScrollContainer
var alarm_count: Label
var _alarm_signature := ""
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
var prompt_panel: PanelContainer
var prompt_key: Label
var prompt_text: Label
var prompt_detail: Label
var _prompt_anchor := Vector3.INF
var job_panel: PanelContainer
var service_panel: PanelContainer
var controls_panel: PanelContainer
var job_menu_button: Button
var ack_all_button: Button
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
	_build_prompt()
	_build_menu()
	_build_thermostat()
	details = DetailsPanel.new()
	add_child(details)
	details.setup(game)
	job_panel = JobPanel.new()
	add_child(job_panel)
	job_panel.setup(game)
	service_panel = ServicePanel.new()
	add_child(service_panel)
	service_panel.setup(game)
	controls_panel = ControlsPanel.new()
	add_child(controls_panel)
	controls_panel.setup(game)
	game.selection_changed.connect(func(_id: String) -> void: _card_cache = ""; refresh_card())
	game.mode_changed.connect(func(_mode: int) -> void: refresh_mode())
	game.world_changed.connect(func() -> void: _card_cache = ""; refresh_card())
	refresh_mode()

func _row_at(rect: Vector4, preset: int, separation: int = 10) -> HBoxContainer:
	var result := HBoxContainer.new()
	add_child(result)
	result.set_anchors_and_offsets_preset(preset)
	result.offset_left = rect.x
	result.offset_top = rect.y
	result.offset_right = rect.z
	result.offset_bottom = rect.w
	result.add_theme_constant_override("separation", separation)
	return result

func _card_at(rect: Vector4, preset: int, padding: int = 16) -> PanelContainer:
	var result := UIKit.panel(self, rect, preset, ToySkin.card(0.96, padding))
	return result

# --- Top bar ----------------------------------------------------------------------

func _build_top() -> void:
	var brand := _row_at(Vector4(M, M, 360, M + 52), Control.PRESET_TOP_LEFT, 12)
	var logo := UIKit.tile(brand, "Menu", "brick", toggle_menu, Vector2(54, 50))
	logo.face_color = ToySkin.RED
	logo.layout_kind = "brand"
	logo.studs = true
	logo.tooltip_text = "Menu: project, simulation and settings"
	var wordmark := UIKit.label(brand, "BRICK / BAS", ToySkin.SIZE_HEADING, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	wordmark.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	wordmark.add_theme_constant_override("shadow_offset_y", 2)
	wordmark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var modes := _row_at(Vector4(-238, M + 2, 238, M + 56), Control.PRESET_CENTER_TOP, 10)
	modes.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in [["Build", "build", 0, "Rooms, walls, floors and furniture"], ["Equipment", "fan", 1, "Air handlers, VAVs and ducts"], ["Explore", "explore", 2, "Walk around inside · Tab"]]:
		var mode_index := int(entry[2])
		var choice := UIKit.tile(modes, String(entry[0]), String(entry[1]), func() -> void: game.set_mode(mode_index), Vector2(148, 52), "mode")
		choice.studs = true
		choice.toggle_mode = true
		choice.tooltip_text = String(entry[3])
		mode_buttons.append(choice)
	var actions := _row_at(Vector4(-240, M + 2, -M, M + 50), Control.PRESET_TOP_RIGHT, 8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	UIKit.tile(actions, "Undo · Ctrl+Z", "undo", game.undo, Vector2(46, 46))
	UIKit.tile(actions, "Redo · Ctrl+Shift+Z", "redo", game.redo, Vector2(46, 46))
	UIKit.tile(actions, "Save · Ctrl+S", "save", game.save_project, Vector2(46, 46))
	UIKit.tile(actions, "Menu · Esc", "settings", toggle_menu, Vector2(46, 46))

# --- Tool rail ---------------------------------------------------------------------

func _build_strip() -> void:
	tool_strip = UIKit.panel(self, Vector4(M, 100, M + 60, 100), Control.PRESET_TOP_LEFT, ToySkin.card(0.92, 6))
	tool_strip.grow_vertical = Control.GROW_DIRECTION_END
	var rail := UIKit.column(tool_strip, 6)
	var size := Vector2(46, 42)
	strip_buttons.select = UIKit.tile(rail, "Select · Esc", "select", game.finish_tool, size)
	strip_buttons.move = UIKit.tile(rail, "Move the selected piece · M (or drag it)", "move", func() -> void: if not game.selected_id.is_empty() and game.can_move(game.selected_id): game.start_move(game.selected_id), size)
	strip_buttons.rotate = UIKit.tile(rail, "Rotate · R", "rotate", game.rotate_selected, size)
	strip_buttons.copy = UIKit.tile(rail, "Copy · Ctrl+D", "copy", game.duplicate_selected, size)
	strip_buttons.delete = UIKit.tile(rail, "Sledgehammer · H · click a piece or drag an area", "hammer", func() -> void: game.start_tool("delete"), size)
	UIKit.separator(rail, false)
	for entry in [["Walls up", "walls_up", 0], ["Walls cut away near the view", "walls_cut", 1], ["Walls down", "walls_down", 2]]:
		var value := int(entry[2])
		var button := UIKit.tile(rail, "%s · V cycles" % entry[0], String(entry[1]), func() -> void: game.set_wall_mode(value); refresh_mode(), size)
		button.toggle_look = "ring"
		wall_buttons.append(button)
	overlay_button = UIKit.tile(rail, "BAS view · B · rooms tinted by temperature", "thermo", game.toggle_overlay, size)
	overlay_button.toggle_look = "ring"
	UIKit.tile(rail, "Frame the lot · Home", "top", game.frame_lot, size)

# --- Parts tray ----------------------------------------------------------------------

func _build_tray() -> void:
	tray = UIKit.panel(self, Vector4(-436, -260, 436, -M), Control.PRESET_CENTER_BOTTOM, StyleBoxEmpty.new())
	tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UIKit.column(tray, 8)
	column.alignment = BoxContainer.ALIGNMENT_END
	category_row = UIKit.row(column, 6)
	category_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row = UIKit.row(column, 6)
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var box := Tray.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(box)
	shelf_scroll = ScrollContainer.new()
	shelf_scroll.custom_minimum_size = Vector2(808, 110)
	shelf_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shelf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	box.add_child(shelf_scroll)
	shelf = UIKit.row(shelf_scroll, 7)
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
	var font := ToySkin.font(ToySkin.WEIGHT_STRONG)
	for name in names:
		var id := String(name)
		var width := font.get_string_size(id, HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_BODY).x + 32.0
		category_tiles[id] = UIKit.tile(category_row, id, "", func() -> void: category = id; rebuild_shelf(), Vector2(maxf(84.0, width), 34), "line")
	rebuild_shelf()

func rebuild_shelf() -> void:
	for id in category_tiles:
		category_tiles[id].marked = id == category
		category_tiles[id].queue_redraw()
	UIKit.clear(shelf)
	UIKit.clear(sub_row)
	shelf_tiles.clear()
	sub_row.visible = false
	shelf_scroll.scroll_horizontal = 0
	if game.mode == 1:
		for entry in game.equipment.tray_items(category):
			if entry.has("note"):
				_note(String(entry.note))
				continue
			_item(String(entry.id), String(entry.label), entry.action, entry.get("glyph", ""), entry.get("color", ToySkin.CREAM_WELL), String(entry.get("tooltip", entry.label)))
		return
	match category:
		"Rooms":
			var style_label: String = ArchitectureRenderer.WALL_STYLES[room_style].label
			var finish_label: String = ArchitectureRenderer.FLOOR_FINISHES[room_finish].label
			_item("tool_room", "Room", func() -> void: game.start_tool("room", {"style": room_style, "finish": room_finish}), "room", Color("f3d98a"), "Drag a rectangle: walls (%s) and floor (%s) together" % [style_label, finish_label])
			_item("tool_wall", "Wall", func() -> void: game.start_tool("wall", {"style": room_style}), "wallpen", Color("ecd2ab"), "Drag along the grid to build walls · Ctrl-drag removes")
			_item("tool_unwall", "Remove walls", func() -> void: game.start_tool("wall", {"style": room_style, "erase": true}), "hammer", Color("e6b6a8"), "Drag along walls to knock them down")
			_item("tool_floor", "Floor", func() -> void: game.start_tool("floor", {"finish": room_finish}), "floor", Color("e3d8bb"), "Paint %s · Shift-click fills a room" % finish_label)
			_item("tool_unfloor", "Lift floor", func() -> void: game.start_tool("floor", {"finish": room_finish, "erase": true}), "hammer", Color("e6b6a8"), "Drag across tiles to lift them")
			_item("tool_door", "Door", func() -> void: game.start_tool("door", {"style": "door"}), "door", Color("e7cfaf"), "Fit a door into a wall section · R flips its swing")
			_item("tool_window", "Window", func() -> void: game.start_tool("window", {"style": "window"}), "window", Color("cfe2e8"), "Fit a window into a wall section")
			_note("New rooms\n%s walls · %s" % [style_label, finish_label])
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
			_note("Click a wall to repaint it\nShift-click paints a room")
		"Doors & Windows":
			for style in ArchitectureRenderer.DOOR_STYLES:
				var key := String(style)
				_item("door_" + key, String(ArchitectureRenderer.DOOR_STYLES[key].label), func() -> void: game.start_tool("door", {"style": key}), "door", Bricks.color(ArchitectureRenderer.DOOR_STYLES[key].leaf).lightened(0.35))
			for style in ArchitectureRenderer.WINDOW_STYLES:
				var key := String(style)
				_item("window_" + key, String(ArchitectureRenderer.WINDOW_STYLES[key].label), func() -> void: game.start_tool("window", {"style": key}), "window", Color("cfe2e8"))
		"Furniture":
			sub_row.visible = true
			var font := ToySkin.font(ToySkin.WEIGHT_STRONG)
			for group in FURNITURE_GROUPS:
				var id := String(group[0])
				var width := font.get_string_size(String(group[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_SMALL).x + 26.0
				var chip := UIKit.tile(sub_row, String(group[1]), "", func() -> void: furniture_group = id; rebuild_shelf(), Vector2(maxf(64.0, width), 28), "line")
				chip.caption_size = ToySkin.SIZE_SMALL
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
				_item("tree_" + key, "%s tree" % key.capitalize(), func() -> void: game.start_tool("place", {"kind": "tree", "item": key}), "tree", Color("c3dfb2"))
			_item("shrub", "Shrub", func() -> void: game.start_tool("place", {"kind": "shrub"}), "tree", Color("cee6ba"))
			_item("parking", "Parking stall", func() -> void: game.start_tool("place", {"kind": "parking"}), "floor", Color("c2c9cd"))
			for finish in ["paving", "paving_tan", "asphalt", "concrete"]:
				var key := String(finish)
				var spec: Dictionary = ArchitectureRenderer.FLOOR_FINISHES[key]
				_swatch("floor_" + key, String(spec.label), Bricks.color(spec.colors[0]), func() -> void: game.start_tool("floor", {"finish": key}), false)
			var items := Placement.furniture_items()
			for item_id in items:
				if String(items[item_id].get("category", "")) != "outdoor": continue
				var key := String(item_id)
				_item(key, String(items[item_id].label), func() -> void: game.start_tool("place", {"kind": "furniture", "item": key}), "tree")

func _item(id: String, caption: String, action: Callable, glyph: String = "", face: Color = ToySkin.CREAM_WELL, tooltip: String = "") -> Button:
	var result := UIKit.tile(shelf, caption, glyph, action, Vector2(90, 104), "part")
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
	var note := UIKit.label(shelf, text, ToySkin.SIZE_SMALL, ToySkin.CREAM_TEXT_2, ToySkin.WEIGHT_STRONG)
	note.custom_minimum_size.x = 128
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	note.size_flags_vertical = Control.SIZE_FILL

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

# --- Clock card -----------------------------------------------------------------------

func _build_clock() -> void:
	var box := _card_at(Vector4(M, -152, M + 248, -M), Control.PRESET_BOTTOM_LEFT, 14)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var column := UIKit.column(box, 6)
	var top := UIKit.row(column, 12)
	clock_label = UIKit.label(top, "08:00", 30, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	clock_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var facts := UIKit.column(top, 0)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weather_label = UIKit.label(facts, "", ToySkin.SIZE_BODY, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
	occupancy_label = UIKit.label(facts, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	energy_label = UIKit.label(column, "", ToySkin.SIZE_SMALL, ToySkin.LABEL, ToySkin.WEIGHT_STRONG)
	energy_label.tooltip_text = "Power the building draws now · energy cost since the day (or the job's measurement) started"
	energy_label.mouse_filter = Control.MOUSE_FILTER_STOP
	var speeds := UIKit.row(column, 6)
	speed_row = speeds
	for entry in [["Pause", "pause", 0.0], ["Normal speed", "play", 1.0], ["Fast · 10×", "fast", 10.0], ["Very fast · 60×", "faster", 60.0]]:
		var speed := float(entry[2])
		var button := UIKit.tile(speeds, String(entry[0]), String(entry[1]), func() -> void: game.set_speed(speed), Vector2(50, 36))
		button.set_meta("speed", speed)
		speed_buttons.append(button)

func refresh_simulation_controls() -> void:
	var turbo: bool = game.turbo_until > game.sim.sim_seconds
	var locked: bool = turbo or (game.job != null and game.job.phase != "onsite") or not game.data.is_demo()
	for button in speed_buttons:
		var speed := float(button.get_meta("speed"))
		button.marked = not turbo and game.data.is_demo() and ((speed == 0.0 and not game.sim.running) or (game.sim.running and is_equal_approx(speed, game.sim.speed)))
		button.disabled = locked
		button.queue_redraw()
	if is_instance_valid(scenario_picker):
		var index: int = DemoSimulation.SCENARIOS.find(game.sim.scenario)
		if index >= 0: scenario_picker.select(index)
		scenario_picker.disabled = game.job != null

# --- Context card -----------------------------------------------------------------------

func _build_card() -> void:
	card = _card_at(Vector4(-(M + 304), 100, -M, 100), Control.PRESET_TOP_RIGHT, 16)
	card.grow_vertical = Control.GROW_DIRECTION_END
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var body := UIKit.column(card, 10)
	var header := UIKit.row(body, 8)
	var titles := UIKit.column(header, 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_title = UIKit.title(titles, "", ToySkin.SIZE_TITLE)
	card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_title.custom_minimum_size.x = 180
	card_subtitle = UIKit.label(titles, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	card_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var more := UIKit.button(header, "Details", func() -> void: details.open(game.selected_id), "GhostButton")
	more.tooltip_text = "Paint, point links and the live station"
	more.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card_body = UIKit.text(body, "", ToySkin.SIZE_BODY, ToySkin.TEXT_2)
	card_body.custom_minimum_size.x = 270
	card_body.add_theme_constant_override("line_spacing", 4)
	card_meter = ProgressBar.new()
	card_meter.custom_minimum_size.y = 6
	card_meter.show_percentage = false
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
	var was_visible := card.visible
	card.visible = not item.is_empty() and game.mode != 2 and not menu.visible and not details.visible and not service_panel.visible and not controls_panel.visible
	if item.is_empty():
		return
	if card.visible and not was_visible: UIKit.pop_in(card, game.reduced_motion)
	var info: Dictionary = game.inspect(id)
	card_title.text = String(info.get("title", game.describe(id)))
	card_subtitle.text = String(info.get("subtitle", KIND_NAMES.get(String(item.kind), String(item.kind).capitalize())))
	card_body.text = String(info.get("text", ""))
	card_body.visible = not card_body.text.is_empty()
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
		var full := String(action.label)
		var short := full.get_slice(" · ", 0)
		var tile := UIKit.tile(card_actions, short, String(action.glyph), callback, Vector2(133, 36), "chip")
		tile.tooltip_text = full
		if String(action.glyph) == "hammer": tile.ink_color = ToySkin.DANGER
	if info.has("room"):
		_room_editor(info.room)

func _room_editor(room: Dictionary) -> void:
	UIKit.section(card_extra, "Room")
	var line := UIKit.line(card_extra, "Room name")
	line.text = String(room.label)
	line.text_submitted.connect(func(text: String) -> void: game.rename_room(String(room.id), text); line.release_focus())
	line.focus_exited.connect(func() -> void: game.rename_room(String(room.id), line.text))
	var types := ["room", "office", "open_office", "conference", "classroom", "library", "lobby", "corridor", "break_room", "restroom", "storage", "mechanical", "gym", "workshop"]
	var picker := UIKit.options(card_extra, types.map(func(value: String) -> String: return value.replace("_", " ").capitalize()))
	picker.select(maxi(0, types.find(String(room.type))))
	picker.item_selected.connect(func(index: int) -> void: game.set_room_type(String(room.id), types[index]))

# --- Status toast, data and alarm pills -------------------------------------------------------

func _build_status() -> void:
	status_panel = UIKit.panel(self, Vector4(0, 94, 0, 94), Control.PRESET_CENTER_TOP, ToySkin.card(0.92, 0))
	var pill: StyleBoxFlat = ToySkin.card(0.92, 0)
	pill.set_corner_radius_all(999)
	pill.content_margin_left = 16
	pill.content_margin_right = 16
	pill.content_margin_top = 7
	pill.content_margin_bottom = 8
	status_panel.add_theme_stylebox_override("panel", pill)
	status_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label = UIKit.label(status_panel, "", ToySkin.SIZE_BODY, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_panel.modulate.a = 0.0
	var pills := UIKit.column(self, 6)
	pills.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	pills.offset_left = -(M + 236)
	pills.offset_right = -M
	pills.offset_top = -(M + 78)
	pills.offset_bottom = -M
	pills.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pills.alignment = BoxContainer.ALIGNMENT_END
	source_pill = _pill(pills, "Simulation", "dot", func() -> void: if not game.demo_only: details.open_connections())
	source_pill.tooltip_text = "Where the building's data comes from"
	alarm_pill = _pill(pills, "No alarms", "bell", toggle_alarms)
	alarm_pill.tooltip_text = "Show active alarms"
	_build_alarm_panel()
	hint_panel = UIKit.panel(self, Vector4(0, -(M + 44), 0, -M), Control.PRESET_CENTER_BOTTOM, ToySkin.card(0.88, 0))
	var hint_style: StyleBoxFlat = ToySkin.card(0.88, 0)
	hint_style.set_corner_radius_all(999)
	hint_style.content_margin_left = 16
	hint_style.content_margin_right = 16
	hint_style.content_margin_top = 8
	hint_style.content_margin_bottom = 8
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var keys := UIKit.row(hint_panel, 14)
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [["WASD", "walk"], ["Shift", "run"], ["Space", "jump"], ["E", "use"], ["Drag", "look"], ["Tab", "build"]]:
		UIKit.key_hint(keys, String(pair[0]), String(pair[1]))
	_center(hint_panel)

# Shrinks a centre-anchored panel to its content, keeping it centred.
func _center(panel: Control) -> void:
	var width := panel.get_combined_minimum_size().x
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5

# A rounded pill button: a coloured pictogram and a short label.
func _pill(parent: Node, text: String, glyph: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", ToySkin.SIZE_SMALL)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style: StyleBoxFlat = ToySkin.card(0.94 if state == "normal" else 1.0, 0)
		if state != "normal": style.bg_color = ToySkin.INK_RAISED
		style.set_corner_radius_all(999)
		style.content_margin_left = 34
		style.content_margin_right = 14
		style.shadow_size = 8
		button.add_theme_stylebox_override(state, style)
	button.set_meta("glyph", glyph)
	button.set_meta("tint", ToySkin.GREEN)
	button.draw.connect(func() -> void: Symbols.draw_icon(button, String(button.get_meta("glyph")), Rect2(Vector2(10, button.size.y * 0.5 - 8), Vector2(16, 16)), button.get_meta("tint")))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_alarm_panel() -> void:
	alarm_panel = _card_at(Vector4(-(M + 400), -(M + 88), -M, -(M + 88)), Control.PRESET_BOTTOM_RIGHT, 16)
	alarm_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	alarm_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	alarm_panel.z_index = 26
	var body := UIKit.column(alarm_panel, 10)
	var header := UIKit.row(body, 8)
	UIKit.title(header, "Alarms")
	alarm_count = UIKit.label(header, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	alarm_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.spacer(header)
	ack_all_button = UIKit.button(header, "Acknowledge all", func() -> void: game.alarms.acknowledge_all(); _refresh_alarms(true), "GhostButton")
	UIKit.tile(header, "Close", "close", func() -> void: alarm_panel.hide(), Vector2(32, 30))
	alarm_scroll = ScrollContainer.new()
	alarm_scroll.custom_minimum_size = Vector2(368, 60)
	alarm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(alarm_scroll)
	alarm_list = UIKit.column(alarm_scroll, 8)
	# The popover fits its rows, up to a scrolling maximum.
	alarm_list.minimum_size_changed.connect(func() -> void: alarm_scroll.custom_minimum_size.y = clampf(alarm_list.get_combined_minimum_size().y, 48.0, 320.0))
	alarm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alarm_panel.hide()

func toggle_alarms() -> void:
	alarm_panel.visible = not alarm_panel.visible
	ack_all_button.visible = game.data.is_demo()
	if alarm_panel.visible: UIKit.pop_in(alarm_panel, game.reduced_motion)
	_refresh_alarms(true)

# Alarms: the simulation's, or on a live station its open alarms (read-only:
# acknowledge them in Niagara).
func _alarm_rows() -> Array:
	if game.data.is_demo():
		return game.alarms.list()
	var rows: Array = []
	for alarm in game.data.station_alarms:
		var priority := int(alarm.get("priority", 200)) if alarm.get("priority") != null else 200
		rows.append({"id": "station:" + String(alarm.get("source", "")), "message": String(alarm.get("message", "Alarm")), "severity": "critical" if priority < 100 else ("warning" if priority < 200 else "notice"),
			"acknowledged": String(alarm.get("ackState", "")) == "acked", "source": String(alarm.get("source", "")), "live": true})
	return rows

func _refresh_alarms(force: bool = false) -> void:
	var alarms: Array = _alarm_rows()
	var signature := str(alarms)
	if not force and signature == _alarm_signature:
		return
	_alarm_signature = signature
	UIKit.clear(alarm_list)
	alarm_count.text = "%d active" % alarms.size() if not alarms.is_empty() else ""
	if alarms.is_empty():
		var calm := UIKit.row(alarm_list, 10)
		var mark := preload("res://scripts/ui/mark.gd").make(calm, "check", ToySkin.GREEN, 18.0)
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var words := UIKit.column(calm, 2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.label(words, "All systems normal", ToySkin.SIZE_LABEL, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
		UIKit.text(words, "Want something to troubleshoot? Menu, Simulation has fan failures, stuck dampers and dirty filters." if game.data.is_demo() else "The station reports no open alarms.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
		return
	var colours := {"critical": ToySkin.DANGER, "warning": ToySkin.WARN, "notice": ToySkin.INFO}
	for alarm in alarms:
		var acknowledged := bool(alarm.acknowledged)
		var entry := PanelContainer.new()
		var style := ToySkin.fill(Color(1, 1, 1, 0.03 if acknowledged else 0.06), ToySkin.RADIUS_CONTROL, 10)
		style.border_color = colours.get(String(alarm.severity), Color.WHITE)
		style.border_width_left = 3
		entry.add_theme_stylebox_override("panel", style)
		alarm_list.add_child(entry)
		var row := UIKit.row(entry, 8)
		var words := UIKit.column(row, 2)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.label(words, String(alarm.severity).capitalize() + ("  ·  acknowledged" if acknowledged else ""), ToySkin.SIZE_CAPTION, colours.get(String(alarm.severity), Color.WHITE), ToySkin.WEIGHT_HEAVY)
		UIKit.text(words, String(alarm.message), ToySkin.SIZE_BODY, ToySkin.TEXT_2 if acknowledged else ToySkin.TEXT)
		if bool(alarm.get("live", false)):
			var owner: String = game.owner_of_point(String(alarm.source))
			if not owner.is_empty(): UIKit.tile(row, "Show the linked equipment", "eye", func() -> void: game.focus_on(owner), Vector2(34, 32)).size_flags_vertical = Control.SIZE_SHRINK_CENTER
			continue
		var target := String(alarm.id).get_slice(":", 1)
		UIKit.tile(row, "Show it", "eye", func() -> void: game.focus_on(target), Vector2(34, 32)).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not acknowledged:
			var id := String(alarm.id)
			UIKit.tile(row, "Acknowledge", "check", func() -> void: game.alarms.acknowledge(id); _refresh_alarms(true), Vector2(34, 32)).size_flags_vertical = Control.SIZE_SHRINK_CENTER

func set_status(text: String) -> void:
	if not is_instance_valid(status_label) or text.is_empty():
		return
	status_label.text = text
	_status_age = 0.0
	status_panel.modulate.a = 1.0
	_center(status_panel)

func _process(delta: float) -> void:
	if not is_instance_valid(status_panel):
		return
	# The status toast stays a few seconds, then fades.
	_status_age += delta
	if _status_age > STATUS_SECONDS:
		status_panel.modulate.a = maxf(0.0, status_panel.modulate.a - delta * (8.0 if game.reduced_motion else 2.5))
	status_panel.visible = status_panel.modulate.a > 0.01 and not game.session_ui.visible and not (is_instance_valid(game.tour) and game.tour.visible)
	_place_prompt()

# --- Explore prompt ------------------------------------------------------------------------

func _build_prompt() -> void:
	prompt_panel = UIKit.panel(self, Vector4(0, 0, 0, 0), Control.PRESET_TOP_LEFT, ToySkin.card(0.94, 0))
	var style: StyleBoxFlat = ToySkin.card(0.94, 0)
	style.content_margin_left = 8
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	prompt_panel.add_theme_stylebox_override("panel", style)
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.z_index = 5
	var row := UIKit.row(prompt_panel, 10)
	var cap := PanelContainer.new()
	var face := ToySkin.fill(ToySkin.YELLOW, 7, 0)
	face.content_margin_left = 10
	face.content_margin_right = 10
	face.content_margin_top = 3
	face.content_margin_bottom = 5
	face.border_color = ToySkin.YELLOW_DEEP.darkened(0.2)
	face.border_width_bottom = 3
	cap.add_theme_stylebox_override("panel", face)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	prompt_key = UIKit.label(cap, "E", ToySkin.SIZE_LABEL, ToySkin.CREAM_TEXT, ToySkin.WEIGHT_HEAVY)
	var words := UIKit.column(row, 0)
	prompt_text = UIKit.label(words, "", ToySkin.SIZE_LABEL, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
	prompt_detail = UIKit.label(words, "", ToySkin.SIZE_SMALL, ToySkin.LABEL)
	prompt_panel.hide()

# What the minifigure can use, beside it on screen (from the explorer).
func show_prompt(action_text: String, detail: String, anchor: Vector3) -> void:
	prompt_text.text = action_text
	prompt_detail.text = detail
	prompt_detail.visible = not detail.is_empty()
	_prompt_anchor = anchor
	if not prompt_panel.visible:
		prompt_panel.show()
		UIKit.pop_in(prompt_panel, game.reduced_motion)
		prompt_panel.reset_size()
	_place_prompt()

func hide_prompt() -> void:
	prompt_panel.hide()
	_prompt_anchor = Vector3.INF

func _place_prompt() -> void:
	if not prompt_panel.visible or _prompt_anchor == Vector3.INF:
		return
	var camera: Camera3D = game.active_camera()
	if camera == null or camera.is_position_behind(_prompt_anchor):
		return
	prompt_panel.reset_size()
	var point := camera.unproject_position(_prompt_anchor)
	var place := point + Vector2(28, -prompt_panel.size.y * 0.5)
	prompt_panel.position = place.clamp(Vector2(M, 96), size - prompt_panel.size - Vector2(M, 120))

# --- Menu -----------------------------------------------------------------------------------

func _build_menu() -> void:
	menu = _card_at(Vector4(-(M + 340), 100, -M, -M), Control.PRESET_RIGHT_WIDE, 18)
	menu.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	menu.z_index = 30
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 12)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	var body := UIKit.column(gutter, 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UIKit.row(body)
	UIKit.title(title, "Menu", ToySkin.SIZE_HEADING)
	UIKit.spacer(title)
	UIKit.tile(title, "Close · Esc", "close", func() -> void: menu.hide(); refresh_card(), Vector2(34, 32))
	_menu_section(body, "Game")
	var files := UIKit.row(body, 8)
	UIKit.button(files, "Save", game.save_project, "PrimaryButton").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.button(files, "Load", func() -> void: game.load_project(); menu.hide()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if OS.has_feature("web"):
		var backups := UIKit.row(body, 8)
		UIKit.button(backups, "Download backup", func() -> void: game.browser_files.download()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UIKit.button(backups, "Import backup", func() -> void: game.browser_files.choose()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(body, "New lot or starter", func() -> void: menu.hide(); game.end_job(); game.session_ui.show_starters())
	job_menu_button = _row(body, "Career job board", func() -> void: menu.hide(); game.session_ui.show_career())
	_row(body, "Title screen", func() -> void: menu.hide(); game.session_ui.show_home())
	_menu_section(body, "Simulation")
	var day := UIKit.row(body, 10)
	UIKit.label(day, "Day", ToySkin.SIZE_BODY, ToySkin.TEXT_2).custom_minimum_size.x = 64
	scenario_picker = UIKit.options(day, DemoSimulation.SCENARIOS)
	scenario_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scenario_picker.clip_text = true
	scenario_picker.item_selected.connect(func(index: int) -> void: game.set_scenario(DemoSimulation.SCENARIOS[index]))
	_row(body, "BAS programming", open_programming)
	_row(body, "Restart the day", game.reset_simulation)
	if not game.demo_only:
		_menu_section(body, "Data")
		_row(body, "Connect a live station", func() -> void: menu.hide(); game.end_job(); details.open_connections())
		_row(body, "Use the simulation", game.data.use_demo)
		UIKit.text(body, "Live points come from a Niagara station through the baskStream SDK, read-only. Needs Node.js.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	_menu_section(body, "Settings")
	var quality := UIKit.row(body, 10)
	UIKit.label(quality, "Graphics", ToySkin.SIZE_BODY, ToySkin.TEXT_2).custom_minimum_size.x = 64
	graphics_picker = UIKit.options(quality, ["Auto", "High", "Low (faster)"])
	graphics_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_picker.item_selected.connect(func(index: int) -> void: game.set_graphics(["auto", "high", "low"][index]))
	var motion := CheckBox.new()
	motion.text = "Reduce motion"
	motion.focus_mode = Control.FOCUS_NONE
	motion.button_pressed = game.reduced_motion
	motion.toggled.connect(func(value: bool) -> void: game.reduced_motion = value; Settings.store("reduced_motion", value))
	body.add_child(motion)
	var sound := CheckBox.new()
	sound.text = "Sounds"
	sound.focus_mode = Control.FOCUS_NONE
	sound.button_pressed = game.sound_enabled
	sound.toggled.connect(func(value: bool) -> void: game.sound_enabled = value; Settings.store("sounds", value))
	body.add_child(sound)
	_row(body, "Show the quick tour", func() -> void: menu.hide(); refresh_card(); game.show_tour())
	if OS.has_feature("web"):
		_row(body, "Credits and licenses", func() -> void: game.browser_files.browser.credits())
	_menu_section(body, "Keys")
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 12)
	keys.add_theme_constant_override("v_separation", 6)
	body.add_child(keys)
	for pair in [["Right-drag", "orbit"], ["Wheel", "zoom"], ["Q / E", "turn 45°"], ["Home", "frame the lot"], ["R", "rotate"], ["M", "move"], ["Del", "delete"], ["Ctrl+D", "copy"], ["V", "wall view"], ["B", "BAS view"], ["Tab", "walk inside"], ["E", "use (inside)"]]:
		UIKit.key_hint(keys, String(pair[0]), String(pair[1]))
	menu.hide()

func _menu_section(parent: Node, title: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	parent.add_child(gap)
	UIKit.section(parent, title)

func _row(parent: Node, text: String, action: Callable) -> Button:
	var button := UIKit.button(parent, text, action, "RowButton")
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return button

func toggle_menu() -> void:
	menu.visible = not menu.visible
	if menu.visible:
		details.hide()
		UIKit.pop_in(menu, game.reduced_motion)
		refresh_simulation_controls()
		graphics_picker.select(["auto", "high", "low"].find(game.graphics))
	refresh_card()

func close_panels() -> bool:
	var bench: Control = game.equipment.workbench
	if is_instance_valid(bench) and bench.visible:
		bench.close()
		return true
	if controls_panel.visible:
		controls_panel.hide()
		refresh_card()
		return true
	if service_panel.visible:
		service_panel.close()
		return true
	if alarm_panel.visible:
		alarm_panel.hide()
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
	thermostat_panel = UIKit.panel(self, Vector4(0, 0, 250, 0), Control.PRESET_TOP_LEFT, ToySkin.card(0.97, 16))
	thermostat_panel.z_index = 25
	var body := UIKit.column(thermostat_panel, 6)
	thermostat_title = UIKit.label(body, "Thermostat", ToySkin.SIZE_SMALL, ToySkin.TEXT_3, ToySkin.WEIGHT_STRONG)
	thermostat_reading = UIKit.label(body, "--.- °F", 38, ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	var controls := UIKit.row(body, 8)
	UIKit.tile(controls, "Cooler · − or wheel", "left", func() -> void: nudge_thermostat(-1.0), Vector2(42, 38))
	thermostat_setpoint = UIKit.label(controls, "Set 72 °F", ToySkin.SIZE_TITLE, ToySkin.YELLOW, ToySkin.WEIGHT_STRONG)
	thermostat_setpoint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thermostat_setpoint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.tile(controls, "Warmer · + or wheel", "right", func() -> void: nudge_thermostat(1.0), Vector2(42, 38))
	thermostat_detail = UIKit.text(body, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	thermostat_detail.custom_minimum_size.x = 226
	thermostat_panel.hide()

func show_thermostat(id: String) -> void:
	thermostat_id = id
	if not thermostat_panel.visible:
		thermostat_panel.show()
		UIKit.pop_in(thermostat_panel, game.reduced_motion)
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
	thermostat_title.text = String(info.get("title", "Thermostat")).to_upper()
	thermostat_reading.text = Units.temp(float(info.get("temp_c", 0.0)), 1) if info.has("temp_c") else "-- °F"
	var setpoint := float(info.get("setpoint_c", NAN))
	thermostat_setpoint.text = ("Set %s" % Units.temp(setpoint)) if is_finite(setpoint) else ("Live · read-only" if not game.data.is_demo() else "Not linked")
	thermostat_detail.text = String(info.get("detail", ""))
	var anchor: Vector3 = info.get("anchor", Vector3.INF)
	var camera: Camera3D = game.active_camera()
	var place := Vector2(size.x - 300, 110)
	if anchor != Vector3.INF and not camera.is_position_behind(anchor):
		place = camera.unproject_position(anchor) + Vector2(30, -120)
	thermostat_panel.position = place.clamp(Vector2(M, 96), size - Vector2(280, 240))

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
	# In a career job the tray only shows when its pieces can be placed.
	var tray_locked: bool = not game.edit_block("architecture" if mode == 0 else "equipment").is_empty()
	tray.visible = mode != 2 and not (is_instance_valid(bench) and bench.visible) and not tray_locked
	for id in ["move", "rotate", "copy", "delete"]:
		strip_buttons[id].visible = game.job == null or game.job.can_edit_equipment()
	hint_panel.visible = mode == 2
	if mode != 2: hide_prompt()
	_rebuild_categories()
	tool_changed()
	_card_cache = ""
	refresh_card()

func refresh() -> void:
	var weather: Dictionary = game.sim.weather()
	if game.data.is_demo():
		clock_label.text = String(weather.get("clock", "--:--"))
		weather_label.text = "%s outside" % Units.temp(float(weather.get("outdoor_temp_c", 0.0)))
		var paused: bool = not game.sim.running and game.turbo_until <= game.sim.sim_seconds
		occupancy_label.text = ("Occupied" if bool(weather.get("occupied", false)) else "Unoccupied") + (" · paused" if paused else "") + (" · fast-forward" if game.turbo_until > game.sim.sim_seconds else "")
	else:
		var now := Time.get_time_dict_from_system()
		clock_label.text = "%02d:%02d" % [int(now.hour), int(now.minute)]
		weather_label.text = "Live station"
		occupancy_label.text = "connected" if game.data.live != null and game.data.live.state == "ready" else String(game.data.live.state if game.data.live != null else "offline")
	# A live station runs on its own clock: nothing to pause or speed up.
	speed_row.visible = game.data.is_demo()
	var rows := _alarm_rows()
	var unacknowledged: int = rows.filter(func(alarm: Dictionary) -> bool: return not bool(alarm.acknowledged)).size()
	if rows.is_empty():
		alarm_pill.text = "No alarms" if game.data.is_demo() else "No station alarms"
		alarm_pill.set_meta("tint", ToySkin.GREEN)
		alarm_pill.add_theme_color_override("font_color", ToySkin.TEXT_2)
	else:
		alarm_pill.text = "%d alarm%s%s" % [rows.size(), "" if rows.size() == 1 else "s", " · %d new" % unacknowledged if unacknowledged > 0 else ""]
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006) if unacknowledged > 0 and not game.reduced_motion else 1.0
		alarm_pill.set_meta("tint", (ToySkin.DANGER if unacknowledged > 0 else ToySkin.WARN).lerp(ToySkin.YELLOW, 1.0 - pulse))
		alarm_pill.add_theme_color_override("font_color", ToySkin.TEXT)
	alarm_pill.queue_redraw()
	if alarm_panel.visible: _refresh_alarms()
	source_pill.text = ("Career job" if game.job != null else "Simulation") if game.data.is_demo() else "Live station"
	source_pill.set_meta("tint", ToySkin.GREEN if game.data.is_demo() else ToySkin.INFO)
	source_pill.queue_redraw()
	if game.data.is_demo():
		var energy: Dictionary = game.sim.energy()
		energy_label.text = "%.1f kW now · %s so far" % [float(energy.electric_kw) + float(energy.gas_kw), Units.money(float(energy.cost_usd))]
	else:
		energy_label.text = String(game.data.status)
	job_panel.refresh()
	service_panel.refresh()
	refresh_card()
	if thermostat_open():
		_refresh_thermostat()
	if details.visible:
		details.refresh()

# --- Career -------------------------------------------------------------------------------------

func job_started() -> void:
	job_panel.reset()
	service_panel.hide()
	controls_panel.hide()
	refresh_job()
	refresh_simulation_controls()
	refresh_mode()

func refresh_job() -> void:
	job_panel.refresh()
	if service_panel.visible: service_panel.refresh()

func open_service(id: String) -> void:
	hide_thermostat()
	service_panel.open(id)

func open_programming() -> void:
	controls_panel.open()
