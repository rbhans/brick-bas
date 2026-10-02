extends PanelContainer

# Piece details drawer: recolour parts, link animations to BAS points, and
# (desktop) the live station: connect through the read-only baskStream bridge,
# browse or search the station, and link its points to the piece, by hand or
# auto-mapped from a controller's points list.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const ROLES := ["fan", "cooling_coil", "heating_coil", "damper", "airflow", "space_temp"]
const PAINT_ROLES := ["all", "housing", "fan", "cooling_coil", "heating_coil", "damper", "filter", "sensor"]

var game: Node
var target_id := ""
var tabs: TabContainer
var title: Label
var paint_color: ColorPickerButton
var paint_role: OptionButton
var paint_scope: OptionButton
var binding_role: OptionButton
var point_picker: OptionButton
var reference: LineEdit
var mapping: OptionButton
var range_min: SpinBox
var range_max: SpinBox
var unit: LineEdit
var enum_map: LineEdit
var inverted: CheckBox
var command_based: CheckBox
var binding_status: Label
var connection_status: Label
var connection_detail: Label
var station_alias: LineEdit
var station_name: LineEdit
var station_url: LineEdit
var station_username: LineEdit
var station_password: LineEdit
var station_insecure: CheckBox
var station_form: VBoxContainer
var browser_box: VBoxContainer
var search_line: LineEdit
var where_label: Label
var node_list: ItemList
var selected_label: Label
var link_role: OptionButton
var target_label: Label
var linked_label: Label
var _nodes: Array = []        # what node_list shows
var _location := "slot:/"
var _trail: Array[String] = []
var _selected: Dictionary = {}
var swatches: Array[Button] = []

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -(ToySkin.MARGIN + 404)
	offset_right = -ToySkin.MARGIN
	offset_top = 100
	offset_bottom = -(ToySkin.MARGIN + 180) # clear of the parts tray
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_theme_stylebox_override("panel", ToySkin.card(0.98, 18))
	z_index = 28
	var body := UIKit.column(self, 12)
	var header := UIKit.row(body, 8)
	var titles := UIKit.column(header, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.section(titles, "Details")
	title = UIKit.title(titles, "", ToySkin.SIZE_TITLE)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIKit.tile(header, "Close · Esc", "close", hide, Vector2(32, 30)).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	_paint_page()
	_binding_page()
	if not game.demo_only:
		_connection_page()
		game.data.changed.connect(refresh_connection)
	game.selection_changed.connect(_follow_selection)
	hide()

# While open, the drawer works on whatever is selected in the game.
func _follow_selection(id: String) -> void:
	if not visible or id.is_empty() or id == target_id or game.model.find_object(id).is_empty():
		return
	target_id = id
	if tabs.current_tab != 2: title.text = game.describe(id)
	load_binding()
	refresh()
	if is_instance_valid(target_label): _refresh_target()

func _page(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.add_theme_constant_override("margin_right", 12)
	gutter.add_theme_constant_override("margin_top", 4)
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(gutter)
	var body := UIKit.column(gutter, 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return body

# A labelled form field: a small caption over whatever goes in it.
func _field(parent: Node, caption: String) -> VBoxContainer:
	var field := UIKit.column(parent, 5)
	UIKit.label(field, caption, ToySkin.SIZE_SMALL, ToySkin.TEXT_3, ToySkin.WEIGHT_STRONG)
	return field

func _buttons(parent: Node) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	parent.add_child(row)
	return row

func open(id: String) -> void:
	target_id = id
	if game.model.find_object(id).is_empty():
		return
	title.text = game.describe(id)
	tabs.current_tab = 0
	if not visible: UIKit.pop_in(self, game.reduced_motion)
	show()
	game.hud.menu.hide()
	game.hud.refresh_card()
	load_binding()
	# On a live station, linking points is what the details are for.
	if game.data.is_live() and tabs.get_tab_count() > 2 and String(game.model.find_object(id).kind) in ["ahu", "vav", "duct", "tstat"]:
		tabs.current_tab = 2
		refresh_connection()
		if node_list.item_count == 0: _browse(_location)

func open_connections() -> void:
	if tabs.get_tab_count() < 3:
		return
	if not game.selected_id.is_empty(): target_id = game.selected_id
	title.text = "Live station"
	if not visible: UIKit.pop_in(self, game.reduced_motion)
	show()
	game.hud.menu.hide()
	tabs.current_tab = 2
	load_connection_profile()
	refresh_connection()
	if game.data.is_live() and node_list.item_count == 0: _browse(_location)

func refresh() -> void:
	if is_instance_valid(binding_status) and not target_id.is_empty():
		binding_status.text = game.binding_description(target_id, _role())
	if is_instance_valid(linked_label) and tabs.current_tab == 2 and game.data.is_live():
		_refresh_target()

# --- Paint -------------------------------------------------------------------------

func _paint_page() -> void:
	var body := _page("Paint")
	UIKit.text(body, "Recolour a part or the whole piece. Walls and floors are painted with the Walls and Floors tools.", ToySkin.SIZE_BODY, ToySkin.TEXT_2)
	var colour := _field(body, "Colour")
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	colour.add_child(grid)
	for name in ["white", "light_bluish_gray", "dark_bluish_gray", "black", "tan", "medium_nougat", "reddish_brown", "dark_red", "red", "orange", "yellow", "bright_green", "dark_green", "sand_green", "medium_blue", "sand_blue"]:
		var chosen := Bricks.color(name)
		var swatch := UIKit.tile(grid, String(name).replace("_", " ").capitalize(), "", func() -> void: _pick_colour(chosen), Vector2(36, 32))
		swatch.face_color = chosen
		swatch.toggle_look = "ring"
		swatch.set_meta("colour", chosen)
		swatches.append(swatch)
	var custom := UIKit.row(colour, 10)
	paint_color = ColorPickerButton.new()
	paint_color.color = Bricks.color("light_bluish_gray")
	paint_color.custom_minimum_size = Vector2(64, 34)
	paint_color.tooltip_text = "Pick any colour"
	paint_color.color_changed.connect(func(_value: Color) -> void: _mark_swatches())
	custom.add_child(paint_color)
	UIKit.label(custom, "Current colour · click it for any other", ToySkin.SIZE_SMALL, ToySkin.TEXT_3).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paint_role = UIKit.options(_field(body, "Part"), ["All parts", "Housing / structure", "Fan", "Cooling coil", "Heating coil", "Damper", "Filter", "Sensor"])
	paint_scope = UIKit.options(_field(body, "Apply to"), ["This piece", "Every piece of this kind"])
	var actions := _buttons(body)
	UIKit.button(actions, "Apply paint", func() -> void: game.paint_object(target_id, PAINT_ROLES[paint_role.selected], paint_color.color, paint_scope.selected == 1), "PrimaryButton")
	UIKit.button(actions, "Restore original colours", func() -> void: game.paint_object(target_id, "", Color.WHITE, paint_scope.selected == 1), "GhostButton")
	_mark_swatches()

func _pick_colour(colour: Color) -> void:
	paint_color.color = colour
	_mark_swatches()

func _mark_swatches() -> void:
	for swatch in swatches:
		swatch.marked = (swatch.get_meta("colour") as Color).is_equal_approx(paint_color.color)
		swatch.queue_redraw()

# --- Animation bindings ---------------------------------------------------------------

func _binding_page() -> void:
	var body := _page("Animate")
	UIKit.text(body, "Each moving part follows a BAS point: fan speed, damper position, valve output, airflow. Pick a point and how its value maps to motion.", ToySkin.SIZE_BODY, ToySkin.TEXT_2)
	binding_role = UIKit.options(_field(body, "Moving part"), ROLES.map(func(role: String) -> String: return String(PointMatcher.ROLE_LABELS.get(role, role))))
	binding_role.item_selected.connect(func(_index: int) -> void: load_binding())
	var point := _field(body, "Point")
	point_picker = UIKit.options(point, [])
	point_picker.clip_text = true
	point_picker.item_selected.connect(_choose_point)
	reference = UIKit.line(point, "Point id" if game.demo_only else "Point id or station ORD (slot:/…)")
	mapping = UIKit.options(_field(body, "Mapping"), ["Numeric range", "On / off", "State map"])
	var limits := UIKit.row(_field(body, "Input range for 0 to 100 % motion"), 8)
	range_min = UIKit.spin(limits, -100000, 100000, 0, 0.1)
	UIKit.label(limits, "to", ToySkin.SIZE_BODY, ToySkin.TEXT_3).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	range_max = UIKit.spin(limits, -100000, 100000, 100, 0.1)
	unit = UIKit.line(_field(body, "Unit"), "%, fraction, degC, m3/s…")
	enum_map = UIKit.line(_field(body, "States"), "Off=0, Running=1")
	inverted = CheckBox.new()
	inverted.text = "Reverse motion"
	inverted.focus_mode = Control.FOCUS_NONE
	body.add_child(inverted)
	command_based = CheckBox.new()
	command_based.text = "This is a command, not feedback"
	command_based.focus_mode = Control.FOCUS_NONE
	body.add_child(command_based)
	var actions := _buttons(body)
	UIKit.button(actions, "Link point", _save_binding, "PrimaryButton")
	UIKit.button(actions, "Reset to automatic", func() -> void: game.reset_binding(target_id, _role()); load_binding(), "GhostButton")
	binding_status = UIKit.text(body, "", ToySkin.SIZE_SMALL, ToySkin.LABEL)

func _role() -> String:
	return ROLES[binding_role.selected]

func load_binding() -> void:
	if not is_instance_valid(binding_role) or target_id.is_empty():
		return
	var data: Dictionary = game.binding_for(target_id, _role())
	reference.text = String(data.get("point_id", ""))
	mapping.select(maxi(0, ["number", "boolean", "enum"].find(String(data.get("mapping", "number")))))
	range_min.value = float(data.get("input_min", 0))
	range_max.value = float(data.get("input_max", 100))
	unit.text = String(data.get("unit", ""))
	inverted.button_pressed = bool(data.get("invert", false))
	command_based.button_pressed = bool(data.get("command_based", false))
	var pairs: Array[String] = []
	for key in data.get("enum_levels", {}):
		pairs.append("%s=%s" % [key, data.enum_levels[key]])
	enum_map.text = ", ".join(pairs)
	point_picker.clear()
	for point in game.points.all_points():
		point_picker.add_item(String(point.point_id))
		if String(point.point_id) == reference.text:
			point_picker.select(point_picker.item_count - 1)
	refresh()

func _choose_point(index: int) -> void:
	reference.text = point_picker.get_item_text(index)
	var point: Dictionary = game.points.get_point(reference.text)
	var type := String(point.get("value_type", "number"))
	mapping.select(1 if type == "bool" else (2 if type == "enum" else 0))
	unit.text = String(point.get("unit", ""))
	range_min.value = 0
	range_max.value = 1 if unit.text == "fraction" else (1.2 if unit.text == "m3/s" else 100)
	if type == "enum":
		enum_map.text = "Off=0, Running=1"
	command_based.button_pressed = reference.text.contains("command") or reference.text.ends_with("_cmd")

func _save_binding() -> void:
	range_min.apply()
	range_max.apply()
	var levels := {}
	for pair in enum_map.text.split(",", false):
		var fields := pair.split("=")
		if fields.size() == 2 and fields[1].strip_edges().is_valid_float():
			levels[fields[0].strip_edges()] = fields[1].strip_edges().to_float()
	var known: Dictionary = game.points.get_point(reference.text.strip_edges())
	var niagara: bool = not game.demo_only and (reference.text.begins_with("slot:") or reference.text.contains("station:|") or String(known.get("source_id", "")) == "niagara")
	var point_id := reference.text.strip_edges()
	# Stations report points by their slot ORD; keep links in that form.
	if niagara and point_id.contains("slot:/"): point_id = point_id.substr(point_id.find("slot:/"))
	var data := {"source": "niagara" if niagara else "demo", "point_id": point_id, "connection_id": String(game.data.saved_profile().get("id", "local-station")), "mapping": ["number", "boolean", "enum"][mapping.selected], "input_min": range_min.value, "input_max": range_max.value, "unit": unit.text.strip_edges(), "enum_levels": levels, "invert": inverted.button_pressed, "command_based": command_based.button_pressed}
	game.attach_binding(target_id, _role(), data)
	refresh()

# --- Live station (desktop) --------------------------------------------------------------

func _connection_page() -> void:
	var body := _page("Live station")
	var state := PanelContainer.new()
	state.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 12))
	body.add_child(state)
	var state_column := UIKit.column(state, 4)
	connection_status = UIKit.label(state_column, "", ToySkin.SIZE_LABEL, ToySkin.TEXT, ToySkin.WEIGHT_STRONG)
	connection_detail = UIKit.text(state_column, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	station_form = UIKit.column(body, 10)
	station_name = UIKit.line(_field(station_form, "Name"), "Friendly name")
	station_alias = UIKit.line(_field(station_form, "Connection id"), "Used by point links")
	station_url = UIKit.line(_field(station_form, "Station address"), "https://station-address")
	var login := _field(station_form, "Login")
	station_username = UIKit.line(login, "Niagara username")
	station_password = UIKit.line(login, "Password · kept in memory only")
	station_password.secret = true
	station_password.text_submitted.connect(func(_text: String) -> void: _submit(false))
	station_insecure = CheckBox.new()
	station_insecure.text = "Allow this station's self-signed certificate"
	station_insecure.focus_mode = Control.FOCUS_NONE
	station_form.add_child(station_insecure)
	UIKit.text(station_form, "Read-only through the baskStream SDK: nothing is written to the station. The address, username and certificate choice save with the build. The password never does.", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	var actions := _buttons(station_form)
	UIKit.button(actions, "Connect", func() -> void: _submit(false), "PrimaryButton")
	UIKit.button(actions, "Test", func() -> void: _submit(true))
	UIKit.button(actions, "Try the demo station", _demo_station, "GhostButton")
	var back := _buttons(body)
	UIKit.button(back, "Back to the simulation", func() -> void: game.data.use_demo(); refresh_connection(), "ChipButton")
	UIKit.button(back, "Change station", func() -> void: station_form.visible = true, "ChipButton")
	# Station browser and point links (once connected).
	browser_box = UIKit.column(body, 8)
	UIKit.section(browser_box, "Station")
	var search := UIKit.row(browser_box, 6)
	search_line = UIKit.line(search, "Search: SpaceTemp, VAV_101…")
	search_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_line.text_submitted.connect(func(_text: String) -> void: _search())
	UIKit.button(search, "Search", _search)
	var nav := UIKit.row(browser_box, 8)
	UIKit.button(nav, "Up", _up, "ChipButton")
	where_label = UIKit.label(nav, "slot:/", ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
	where_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	where_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node_list = ItemList.new()
	node_list.custom_minimum_size.y = 190
	node_list.item_activated.connect(_open_node)
	node_list.item_selected.connect(_select_node)
	browser_box.add_child(node_list)
	selected_label = UIKit.text(browser_box, "Double-click a folder to open it. Select a point to read it.", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	browser_box.add_child(gap)
	UIKit.section(browser_box, "Link to the selected piece")
	target_label = UIKit.text(browser_box, "", ToySkin.SIZE_SMALL, ToySkin.TEXT)
	var link := UIKit.row(browser_box, 6)
	link_role = UIKit.options(link, ROLES.map(func(role: String) -> String: return String(PointMatcher.ROLE_LABELS.get(role, role))))
	link_role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.button(link, "Link", _link_selected, "PrimaryButton")
	UIKit.button(browser_box, "Auto-map from this folder", _auto_map).tooltip_text = "Open a controller's folder (or its points folder), then match its points to this piece by name"
	linked_label = UIKit.text(browser_box, "", ToySkin.SIZE_SMALL, ToySkin.TEXT_2)

func _submit(test_only: bool) -> void:
	var profile := {"id": station_alias.text.strip_edges(), "name": station_name.text.strip_edges(), "station_url": station_url.text.strip_edges(), "username": station_username.text.strip_edges(), "tls_mode": "insecure" if station_insecure.button_pressed else "strict"}
	var ok: bool = await game.data.connect_station(profile, station_password.text, test_only)
	station_password.text = ""
	if ok and not test_only:
		_location = "slot:/"
		_trail.clear()
		_browse(_location)
	refresh_connection()

# Starts the stand-in station that ships with the game and fills the form.
func _demo_station() -> void:
	connection_status.text = "Starting the demo station…"
	var station: Dictionary = await game.data.start_demo_station()
	if station.is_empty():
		connection_status.text = "Couldn't start the demo station"
		connection_detail.text = "It needs Node.js 20+ and `npm install` in the project folder."
		return
	station_name.text = "Demo station"
	station_alias.text = "demo-station"
	station_url.text = String(station.url)
	station_username.text = String(station.user)
	station_password.text = String(station.password)
	station_insecure.button_pressed = false
	_submit(false)

func load_connection_profile() -> void:
	if not is_instance_valid(station_url):
		return
	var profile: Dictionary = game.data.saved_profile()
	station_alias.text = String(profile.get("id", "local-station"))
	station_name.text = String(profile.get("name", "Niagara station"))
	station_url.text = String(profile.get("station_url", ""))
	station_username.text = String(profile.get("username", ""))
	station_insecure.button_pressed = String(profile.get("tls_mode", "strict")) == "insecure"

func refresh_connection() -> void:
	if not is_instance_valid(connection_status):
		return
	connection_status.text = String(game.data.status)
	connection_detail.text = String(game.data.detail)
	var live: bool = game.data.is_live()
	browser_box.visible = live
	if live: station_form.visible = false
	elif not game.data.busy: station_form.visible = true
	_refresh_target()

func _live() -> LiveStation:
	return game.data.live if game.data.is_live() else null

func _browse(ord: String) -> void:
	var live := _live()
	if live == null: return
	where_label.text = ord
	selected_label.text = "Loading…"
	live.browse(ord, func(reply: Dictionary) -> void:
		if String(reply.get("op", "")) == "error":
			selected_label.text = String(reply.get("message", "Couldn't open that."))
			return
		_location = String(reply.get("node", {}).get("ord", ord))
		where_label.text = _location
		_show_nodes(reply.get("children", []))
		selected_label.text = "Double-click a folder to open it; select a point to read it.")

func _search() -> void:
	var live := _live()
	var query := search_line.text.strip_edges()
	if live == null or query.is_empty(): return
	selected_label.text = "Searching…"
	live.search(query, func(reply: Dictionary) -> void:
		if String(reply.get("op", "")) == "error":
			selected_label.text = String(reply.get("message", "Search failed."))
			return
		where_label.text = "Search: %s" % query
		_show_nodes(reply.get("nodes", []))
		selected_label.text = "%d found%s." % [(reply.get("nodes", []) as Array).size(), " (more on the station: narrow the search)" if bool(reply.get("truncated", false)) else ""])

func _show_nodes(nodes: Array) -> void:
	_nodes = nodes
	node_list.clear()
	for node in nodes:
		var point := String(node.get("kind", "")) == "point"
		node_list.add_item(("•  " if point else "›  ") + String(node.get("display", node.get("name", ""))))
		node_list.set_item_tooltip(node_list.item_count - 1, String(node.get("ord", "")))
	_selected = {}

func _open_node(index: int) -> void:
	var node: Dictionary = _nodes[index]
	if String(node.get("kind", "")) == "point" or not bool(node.get("hasChildren", false)):
		_select_node(index)
		return
	_trail.append(_location)
	_browse(String(node.ord))

func _up() -> void:
	if _trail.is_empty():
		var parent := _location.get_base_dir() if _location.count("/") > 1 else "slot:/"
		_browse(parent if not parent.is_empty() else "slot:/")
		return
	_browse(_trail.pop_back())

func _select_node(index: int) -> void:
	_selected = _nodes[index]
	var live := _live()
	if live == null or String(_selected.get("kind", "")) != "point":
		selected_label.text = "%s · %s" % [String(_selected.get("name", "")), String(_selected.get("typeSpec", ""))]
		return
	var ord := String(_selected.ord)
	selected_label.text = "%s · reading…" % ord
	live.read([ord], func(reply: Dictionary) -> void:
		var values: Array = reply.get("points", [])
		if values.is_empty():
			selected_label.text = "%s · %s" % [ord, String(reply.get("message", "no value"))]
			return
		var value: Dictionary = values[0]
		selected_label.text = "%s\n= %s  %s" % [ord, String(value.get("display", value.get("value", ""))), String(value.get("status", ""))]
		var guess := _guess_role(String(_selected.get("name", "")))
		if guess >= 0: link_role.select(guess))

func _guess_role(name: String) -> int:
	var best := -1
	var best_score := 0
	for index in range(ROLES.size()):
		var score := PointMatcher.score(String(ROLES[index]), name, String(_target().get("kind", "vav")))
		if score > best_score:
			best = index
			best_score = score
	return best

func _target() -> Dictionary:
	return game.model.find_object(target_id)

func _refresh_target() -> void:
	if not is_instance_valid(target_label): return
	var item := _target()
	if item.is_empty() or String(item.kind) not in ["ahu", "vav", "duct", "tstat"]:
		target_label.text = "Select an air handler, VAV, duct or thermostat in the game, then open its Details to link points to it."
		linked_label.text = ""
		return
	target_label.text = "%s · roles: %s" % [game.describe(target_id), ", ".join((PointMatcher.ROLES_BY_KIND.get(String(item.kind), []) as Array).map(func(role: String) -> String: return String(PointMatcher.ROLE_LABELS[role]).to_lower()))]
	var lines: Array[String] = []
	var bindings: Dictionary = item.properties.get("bindings", {})
	for role in bindings:
		var binding: Dictionary = bindings[role]
		if String(binding.get("source", "")) != "niagara": continue
		var point: Dictionary = game.points.get_point(String(binding.point_id))
		lines.append("%s: %s%s" % [String(PointMatcher.ROLE_LABELS.get(role, role)), String(binding.point_id).get_file(), (" = " + String(point.get("display", point.get("value", "")))) if not point.is_empty() else ""])
	linked_label.text = "Linked: none yet" if lines.is_empty() else "Linked:\n" + "\n".join(lines)

func _link_selected() -> void:
	var item := _target()
	if item.is_empty() or String(_selected.get("kind", "")) != "point":
		game.set_status("Select a point in the station list, and a piece of equipment in the game.")
		return
	# Captured now: the reply may arrive after the selection has moved on.
	var piece := target_id
	var node: Dictionary = _selected.duplicate()
	var role := String(ROLES[link_role.selected])
	var capacity := float(item.properties.get("capacity_m3_s", 0.45))
	var connection := String(game.data.saved_profile().get("id", "local-station"))
	var live := _live()
	if live != null:
		live.read([String(node.ord)], func(reply: Dictionary) -> void:
			var values: Array = reply.get("points", [])
			var units := String(values[0].get("units", "")) if not values.is_empty() and values[0].get("units") != null else ""
			_apply_links(piece, {role: PointMatcher.binding_for(role, node, units, capacity, connection)}))
	else:
		_apply_links(piece, {role: PointMatcher.binding_for(role, node, "", capacity, connection)})

# Reads the folder (and a "points" folder inside it) and links every role the
# names make clear.
func _auto_map() -> void:
	var item := _target()
	var live := _live()
	if item.is_empty() or live == null:
		game.set_status("Select a piece of equipment in the game, then open a controller's folder here.")
		return
	var kind := String(item.kind)
	var piece := target_id
	selected_label.text = "Reading the points list…"
	live.browse(_location, func(reply: Dictionary) -> void:
		var children: Array = reply.get("children", [])
		var folder := ""
		for child in children:
			if String(child.get("name", "")).to_lower() == "points" and bool(child.get("hasChildren", false)): folder = String(child.ord)
		if folder.is_empty():
			_finish_auto_map(piece, kind, item, children)
		else:
			live.browse(folder, func(inner: Dictionary) -> void: _finish_auto_map(piece, kind, item, children + (inner.get("children", []) as Array))))

func _finish_auto_map(piece: String, kind: String, item: Dictionary, nodes: Array) -> void:
	var matches: Dictionary = PointMatcher.match_points(kind, nodes)
	if matches.is_empty():
		selected_label.text = "No points here look like a %s's. Open the controller's folder first." % kind.to_upper()
		return
	var ords: Array = matches.values().map(func(node: Dictionary) -> String: return String(node.ord))
	var live := _live()
	if live == null: return
	live.read(ords, func(reply: Dictionary) -> void:
		var units: Dictionary = {}
		for value in reply.get("points", []): units[String(value.get("point", ""))] = String(value.get("units", "")) if value.get("units") != null else ""
		var links: Dictionary = {}
		for role in matches:
			var node: Dictionary = matches[role]
			links[role] = PointMatcher.binding_for(String(role), node, String(units.get(String(node.ord), "")), float(item.properties.get("capacity_m3_s", 0.45)), String(game.data.saved_profile().get("id", "local-station")))
		_apply_links(piece, links)
		selected_label.text = "Linked %d: %s." % [links.size(), ", ".join(links.keys().map(func(role: String) -> String: return "%s: %s" % [String(PointMatcher.ROLE_LABELS[role]).to_lower(), String(matches[role].name)]))])

func _apply_links(piece: String, links: Dictionary) -> void:
	var item: Dictionary = game.model.find_object(piece)
	if item.is_empty(): return
	var changed: Dictionary = item.duplicate(true)
	var bindings: Dictionary = changed.properties.get("bindings", {}).duplicate(true)
	for role in links:
		bindings[role] = links[role].duplicate(true)
		bindings[role].automatic = false
	changed.properties.bindings = bindings
	changed.properties.binding_schema = 2
	game.apply("Link station points", [], [], [changed])
	game.data.refresh_subscriptions()
	game.play_sound("place")
	_refresh_target()
