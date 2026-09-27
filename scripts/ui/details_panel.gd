extends PanelContainer

# Piece details drawer: recolour parts, link animations to BAS points, and
# (desktop only) the parked Niagara/baskStream connection profile.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const ROLES := ["fan", "cooling_coil", "heating_coil", "damper", "airflow"]
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

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -370
	offset_right = -22
	offset_top = 90
	offset_bottom = -50
	add_theme_stylebox_override("panel", UIKit.glass_style(16, 0.97))
	z_index = 28
	var body := UIKit.column(self, 8)
	var header := UIKit.row(body)
	title = UIKit.label(header, "PIECE DETAILS", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UIKit.tile(header, "Close", "close", hide, Vector2(30, 28))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	_paint_page()
	_binding_page()
	if not game.demo_only:
		_connection_page()
		game.data.changed.connect(refresh_connection)
	hide()

func _page(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var body := UIKit.column(scroll, 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return body

func open(id: String) -> void:
	target_id = id
	if game.model.find_object(id).is_empty():
		return
	title.text = game.describe(id).to_upper()
	tabs.current_tab = 0
	show()
	game.hud.menu.hide()
	game.hud.refresh_card()
	load_binding()

func open_connections() -> void:
	if tabs.get_tab_count() < 3:
		return
	title.text = "DATA CONNECTION"
	show()
	tabs.current_tab = 2
	load_connection_profile()
	refresh_connection()

func refresh() -> void:
	if is_instance_valid(binding_status) and not target_id.is_empty():
		binding_status.text = game.binding_description(target_id, _role())

# --- Paint -------------------------------------------------------------------------

func _paint_page() -> void:
	var body := _page("Paint")
	var hint := UIKit.label(body, "Recolour a part or the whole piece. Walls and floors are painted with the Walls and Floors tools.", 13, Color("c3cdd0"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paint_color = ColorPickerButton.new()
	paint_color.color = Bricks.color("light_bluish_gray")
	paint_color.custom_minimum_size.y = 40
	body.add_child(paint_color)
	var swatches := GridContainer.new()
	swatches.columns = 8
	body.add_child(swatches)
	for name in ["white", "light_bluish_gray", "dark_bluish_gray", "black", "tan", "medium_nougat", "reddish_brown", "dark_red", "red", "orange", "yellow", "bright_green", "dark_green", "sand_green", "medium_blue", "sand_blue"]:
		var chosen := Bricks.color(name)
		var swatch := UIKit.tile(swatches, String(name).replace("_", " ").capitalize(), "", func() -> void: paint_color.color = chosen, Vector2(30, 30))
		swatch.face_color = chosen
	paint_role = UIKit.options(body, ["All parts", "Housing / structure", "Fan", "Cooling coil", "Heating coil", "Damper", "Filter", "Sensor"])
	paint_scope = UIKit.options(body, ["This piece", "Every piece of this kind"])
	UIKit.button(body, "Apply paint", func() -> void: game.paint_object(target_id, PAINT_ROLES[paint_role.selected], paint_color.color, paint_scope.selected == 1))
	UIKit.button(body, "Restore original colours", func() -> void: game.paint_object(target_id, "", Color.WHITE, paint_scope.selected == 1))

# --- Animation bindings ---------------------------------------------------------------

func _binding_page() -> void:
	var body := _page("Animate")
	var hint := UIKit.label(body, "Each moving part follows a BAS point: fan speed, damper position, valve output, airflow. Pick a point and how its value maps to motion.", 13, Color("c3cdd0"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	binding_role = UIKit.options(body, ROLES.map(func(role: String) -> String: return role.replace("_", " ").capitalize()))
	binding_role.item_selected.connect(func(_index: int) -> void: load_binding())
	point_picker = UIKit.options(body, [])
	point_picker.item_selected.connect(_choose_point)
	reference = UIKit.line(body, "Point id" if game.demo_only else "Point id or Niagara ORD")
	mapping = UIKit.options(body, ["Numeric range", "On / off", "State map"])
	UIKit.label(body, "Input range → 0 to 100 % motion", 12, Color("b1bcbf"))
	var limits := UIKit.row(body)
	range_min = UIKit.spin(limits, -100000, 100000, 0, 0.1)
	range_max = UIKit.spin(limits, -100000, 100000, 100, 0.1)
	unit = UIKit.line(body, "Unit: %, fraction, degC, m3/s…")
	enum_map = UIKit.line(body, "States: Off=0, Running=1")
	inverted = CheckBox.new()
	inverted.text = "Reverse motion"
	body.add_child(inverted)
	command_based = CheckBox.new()
	command_based.text = "This is a command, not feedback"
	body.add_child(command_based)
	UIKit.button(body, "Link point", _save_binding)
	UIKit.button(body, "Reset to automatic", func() -> void: game.reset_binding(target_id, _role()); load_binding())
	binding_status = UIKit.label(body, "", 12, Color("9fd9d3"))
	binding_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	var levels := {}
	for pair in enum_map.text.split(",", false):
		var fields := pair.split("=")
		if fields.size() == 2 and fields[1].strip_edges().is_valid_float():
			levels[fields[0].strip_edges()] = fields[1].strip_edges().to_float()
	var niagara: bool = not game.demo_only and reference.text.contains(":") and not game.points.get_point(reference.text).has("point_id")
	var data := {"source": "niagara" if niagara else "demo", "point_id": reference.text.strip_edges(), "connection_id": String(game.data.saved_profile().get("id", "local-station")), "mapping": ["number", "boolean", "enum"][mapping.selected], "input_min": range_min.value, "input_max": range_max.value, "unit": unit.text.strip_edges(), "enum_levels": levels, "invert": inverted.button_pressed, "command_based": command_based.button_pressed}
	game.attach_binding(target_id, _role(), data)
	refresh()

# --- Connection (desktop) -------------------------------------------------------------

func _connection_page() -> void:
	var body := _page("Connection")
	connection_status = UIKit.label(body, "", 15)
	connection_detail = UIKit.label(body, "", 12, Color("c3cdd0"))
	connection_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	station_name = UIKit.line(body, "Friendly name")
	station_alias = UIKit.line(body, "Connection id used by bindings")
	station_url = UIKit.line(body, "https://station or wss://station/stream")
	station_username = UIKit.line(body, "Niagara username")
	station_password = UIKit.line(body, "Password · kept in memory only")
	station_password.secret = true
	station_insecure = CheckBox.new()
	station_insecure.text = "Allow this station's self-signed certificate"
	body.add_child(station_insecure)
	var warning := UIKit.label(body, "Read-only. Endpoint, username and TLS choice are saved with the project; the password and session cookies never are.", 12, Color("8f9ea3"))
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := UIKit.row(body)
	UIKit.button(actions, "Test", func() -> void: _submit(true))
	UIKit.button(actions, "Connect", func() -> void: _submit(false))
	UIKit.button(actions, "Use demo", game.data.use_demo)
	UIKit.button(body, "Protocol fixture (no station)", game.data.toggle_fixture)

func _submit(test_only: bool) -> void:
	var profile := {"id": station_alias.text.strip_edges(), "name": station_name.text.strip_edges(), "station_url": station_url.text.strip_edges(), "username": station_username.text.strip_edges(), "tls_mode": "insecure" if station_insecure.button_pressed else "strict"}
	game.data.connect_station(profile, station_password.text, test_only)

func load_connection_profile() -> void:
	if not is_instance_valid(station_url):
		return
	var profile: Dictionary = game.data.saved_profile()
	station_alias.text = String(profile.get("id", "local-station"))
	station_name.text = String(profile.get("name", "Local Niagara station"))
	station_url.text = String(profile.get("station_url", ""))
	station_username.text = String(profile.get("username", ""))
	station_insecure.button_pressed = String(profile.get("tls_mode", "strict")) == "insecure"

func refresh_connection() -> void:
	if not is_instance_valid(connection_status):
		return
	connection_status.text = String(game.data.status)
	connection_detail.text = String(game.data.detail)
