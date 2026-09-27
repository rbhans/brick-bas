extends RefCounted

const INK := Color("263239")
const CREAM := Color("eee8d4")
const YELLOW := Color("ffcf45")
const GREEN := Color("39ad64")

static func face(color: Color, radius: int = 10, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	style.border_color = color.lightened(0.17)
	style.set_border_width_all(1)
	style.shadow_color = Color(0.015, 0.025, 0.03, 0.32)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 3)
	return style

static func font(weight: int = 600) -> Font:
	if OS.has_feature("web"):
		# Browsers cannot enumerate native system fonts. Godot's bundled font is
		# available offline and requires no third-party font/CDN request.
		var bundled := FontVariation.new()
		bundled.base_font = ThemeDB.fallback_font
		bundled.variation_embolden = maxf(0, (weight - 400) / 300.0)
		return bundled
	var result := SystemFont.new()
	result.font_names = PackedStringArray(["Avenir Next", "Nunito Sans", "sans-serif"])
	result.font_weight = weight
	return result

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 15
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "PopupMenu", "TabContainer", "TabBar", "ItemList"]:
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_selected_color"]:
			theme.set_color(key, type, CREAM)
		theme.set_color("font_unselected_color", type, Color("a9b4b7"))
		theme.set_color("font_disabled_color", type, Color("7b888d"))
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, face(Color("36454d"), 7, 10))
		theme.set_stylebox("hover", type, face(Color("475963"), 7, 10))
		theme.set_stylebox("pressed", type, face(Color("50616b"), 7, 10))
		theme.set_stylebox("disabled", type, face(Color("2b383e"), 7, 10))
		var focus := face(Color.TRANSPARENT, 7, 10)
		focus.border_color = YELLOW
		focus.set_border_width_all(2)
		theme.set_stylebox("focus", type, focus)
	for type in ["PanelContainer", "PopupMenu", "TabContainer", "ItemList"]:
		theme.set_stylebox("panel", type, face(INK, 14, 16))
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, face(Color("455860"), 7, 10))
		theme.set_stylebox("tab_unselected", type, face(INK, 7, 10))
		theme.set_stylebox("tab_hovered", type, face(Color("35454d"), 7, 10))
	theme.set_stylebox("normal", "LineEdit", face(Color("18242a"), 6, 9))
	theme.set_stylebox("focus", "LineEdit", face(Color("34464e"), 6, 9))
	theme.set_stylebox("selected", "ItemList", face(Color("52616a"), 6, 6))
	theme.set_stylebox("selected_focus", "ItemList", face(Color("52616a"), 6, 6))
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 9)
	return theme
