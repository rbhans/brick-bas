extends RefCounted

# The BRICK / BAS design system: one palette, one type scale, one font, and
# the Godot Theme every panel uses. Molded-plastic toy pieces (charcoal cards,
# a cream parts tray, yellow selection, the red brand brick) with restrained,
# consistent execution. Anything that draws UI should take its colours, sizes
# and radii from here rather than inventing its own.

# --- Palette -----------------------------------------------------------------------------
# Charcoal plastic: floating cards and the controls on them.
const INK := Color("1e292f")          # card body
const INK_RAISED := Color("2c3a41")   # buttons and fields on a card
const INK_HOVER := Color("374851")
const INK_PRESSED := Color("41545d")
const INK_WELL := Color("141e23")     # inputs, chart wells
const LINE := Color(1, 1, 1, 0.08)    # hairlines and card borders
# Text on charcoal.
const TEXT := Color("f3efe3")
const TEXT_2 := Color("b4c0c4")
const TEXT_3 := Color("7f8e94")
const LABEL := Color("8ed3cb")        # section labels and live values
# Cream plastic: the parts tray.
const CREAM := Color("f1ebd8")
const CREAM_WELL := Color("e5dbc1")
const CREAM_TEXT := Color("2a3236")
const CREAM_TEXT_2 := Color("736f60")
# Accents.
const YELLOW := Color("ffcf45")       # selection, the one active thing
const YELLOW_DEEP := Color("e8b52e")
const GREEN := Color("3db36a")        # go / commit / healthy
const RED := Color("d6453a")          # the brand brick
const DANGER := Color("ef6a56")
const WARN := Color("f2b441")
const INFO := Color("7cc4ea")
const SHADOW := Color(0.01, 0.02, 0.03, 0.38)

# --- Type -----------------------------------------------------------------------------------
const SIZE_CAPTION := 11
const SIZE_SMALL := 12
const SIZE_BODY := 13
const SIZE_LABEL := 14
const SIZE_TITLE := 17
const SIZE_HEADING := 22
const SIZE_DISPLAY := 30
const WEIGHT_BODY := 500
const WEIGHT_STRONG := 650
const WEIGHT_HEAVY := 800

# --- Shape ----------------------------------------------------------------------------------
const RADIUS_SMALL := 6
const RADIUS_CONTROL := 9
const RADIUS_CARD := 14
const GAP := 8
const MARGIN := 24 # from the screen edge, at the 1440 × 900 design size

const FONT_PATH := "res://assets/fonts/geist/geist-latin-wght-normal.woff2"
const FONT_EXT_PATH := "res://assets/fonts/geist/geist-latin-ext-wght-normal.woff2"

static var _fonts: Dictionary = {}

# Geist (OFL, bundled), so desktop and browser builds look the same. Missing
# glyphs fall back to Latin Extended, then Godot's own font.
static func font(weight: int = WEIGHT_BODY) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	var chain: Array[Font] = []
	if ResourceLoader.exists(FONT_EXT_PATH): chain.append(load(FONT_EXT_PATH))
	chain.append(ThemeDB.fallback_font)
	var result := FontVariation.new()
	result.base_font = base
	# The axis must be keyed by its numeric tag: a "wght" string key is ignored.
	result.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	result.fallbacks = chain
	_fonts[weight] = result
	return result

# A molded face: flat colour, soft rounded corners, a lighter rim and a short
# shadow. Used for tiles and the simplest panels.
static func face(color: Color, radius: int = RADIUS_CONTROL, padding: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.corner_detail = 8
	style.set_content_margin_all(padding)
	style.border_color = color.lightened(0.12)
	style.set_border_width_all(1)
	style.shadow_color = SHADOW
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style

# A floating card: the charcoal panels that sit over the scene.
static func card(alpha: float = 0.96, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, alpha)
	style.set_corner_radius_all(RADIUS_CARD)
	style.corner_detail = 8
	style.set_content_margin_all(padding)
	style.border_color = LINE
	style.set_border_width_all(1)
	style.shadow_color = SHADOW
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 5)
	return style

# A flat, borderless fill (wells, chips, inputs).
static func fill(color: Color, radius: int = RADIUS_SMALL, padding: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.corner_detail = 6
	style.set_content_margin_all(padding)
	return style

static func _button(color: Color, radius: int = RADIUS_CONTROL, h_pad: int = 14, v_pad: int = 8) -> StyleBoxFlat:
	var style := fill(color, radius, 0)
	style.content_margin_left = h_pad
	style.content_margin_right = h_pad
	style.content_margin_top = v_pad
	style.content_margin_bottom = v_pad
	style.border_color = color.lightened(0.1)
	style.border_width_top = 1
	return style

static func _button_set(theme: Theme, type: String, base: Color, hover: Color, pressed: Color, text: Color, radius: int = RADIUS_CONTROL, h_pad: int = 14, v_pad: int = 8) -> void:
	theme.set_stylebox("normal", type, _button(base, radius, h_pad, v_pad))
	theme.set_stylebox("hover", type, _button(hover, radius, h_pad, v_pad))
	theme.set_stylebox("pressed", type, _button(pressed, radius, h_pad, v_pad))
	theme.set_stylebox("hover_pressed", type, _button(pressed, radius, h_pad, v_pad))
	var disabled := _button(Color(base, base.a * 0.45), radius, h_pad, v_pad)
	disabled.border_width_top = 0
	theme.set_stylebox("disabled", type, disabled)
	var focus := fill(Color.TRANSPARENT, radius, 0)
	focus.draw_center = false
	focus.border_color = YELLOW
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(2)
	theme.set_stylebox("focus", type, focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(key, type, text)
	theme.set_color("font_disabled_color", type, Color(text, 0.4))
	theme.set_color("icon_normal_color", type, text)

# Large clickable cards (game modes, starters, jobs): a raised charcoal slab
# whose rim turns yellow under the pointer.
static func _card_buttons(theme: Theme) -> void:
	theme.set_type_variation("CardButton", "Button")
	var states := {"normal": [INK_RAISED, LINE, 1], "hover": [INK_HOVER, YELLOW, 2], "pressed": [INK_PRESSED, YELLOW_DEEP, 2], "hover_pressed": [INK_PRESSED, YELLOW_DEEP, 2], "disabled": [Color(INK_RAISED, 0.5), Color(1, 1, 1, 0.04), 1]}
	for state in states:
		var spec: Array = states[state]
		var style := fill(spec[0], RADIUS_CARD - 2, 0)
		style.border_color = spec[1]
		style.set_border_width_all(int(spec[2]))
		style.shadow_color = Color(SHADOW, 0.25)
		style.shadow_size = 6 if state != "disabled" else 0
		style.shadow_offset = Vector2(0, 3)
		theme.set_stylebox(state, "CardButton", style)
	var focus := fill(Color.TRANSPARENT, RADIUS_CARD - 2, 0)
	focus.draw_center = false
	focus.border_color = YELLOW
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "CardButton", focus)

static var _theme: Theme

# One shared Theme for every panel (built once).
static func create() -> Theme:
	if _theme == null: _theme = _build()
	return _theme

static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font = font(WEIGHT_BODY)
	theme.default_font_size = SIZE_LABEL
	theme.set_color("font_color", "Label", TEXT)
	theme.set_constant("line_spacing", "Label", 2)
	# Buttons: secondary (charcoal) by default, plus variations.
	_button_set(theme, "Button", INK_RAISED, INK_HOVER, INK_PRESSED, TEXT)
	theme.set_font("font", "Button", font(WEIGHT_STRONG))
	for variation in ["PrimaryButton", "GhostButton", "ChipButton", "DangerButton", "RowButton"]:
		theme.set_type_variation(variation, "Button")
	_button_set(theme, "PrimaryButton", YELLOW, YELLOW.lightened(0.12), YELLOW_DEEP, CREAM_TEXT)
	# A disabled main action reads as unavailable charcoal, not muddy yellow.
	var waiting := _button(Color(INK_RAISED, 0.7))
	waiting.border_width_top = 0
	theme.set_stylebox("disabled", "PrimaryButton", waiting)
	theme.set_color("font_disabled_color", "PrimaryButton", TEXT_3)
	_button_set(theme, "GhostButton", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), TEXT_2)
	_button_set(theme, "ChipButton", INK_RAISED, INK_HOVER, INK_PRESSED, TEXT_2, 999, 10, 4)
	theme.set_font_size("font_size", "ChipButton", SIZE_SMALL)
	_button_set(theme, "DangerButton", Color("4a2b29"), Color("5a3330"), Color("6a3a36"), Color("ffb4a8"))
	# Full-width list rows (menu entries): left aligned, roomy.
	_button_set(theme, "RowButton", Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.1), TEXT, RADIUS_CONTROL, 12, 9)
	theme.set_constant("h_separation", "Button", 8)
	_card_buttons(theme)
	# Dropdowns and their menus.
	_button_set(theme, "OptionButton", INK_RAISED, INK_HOVER, INK_PRESSED, TEXT, RADIUS_CONTROL, 12, 7)
	theme.set_font("font", "OptionButton", font(WEIGHT_STRONG))
	theme.set_constant("arrow_margin", "OptionButton", 10)
	var popup := card(1.0, 6)
	popup.shadow_size = 10
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", fill(INK_HOVER, RADIUS_SMALL, 6))
	theme.set_color("font_color", "PopupMenu", TEXT_2)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_3)
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_constant("item_start_padding", "PopupMenu", 10)
	theme.set_constant("item_end_padding", "PopupMenu", 10)
	# Text fields.
	var field := fill(INK_WELL, RADIUS_CONTROL, 0)
	field.content_margin_left = 12
	field.content_margin_right = 12
	field.content_margin_top = 8
	field.content_margin_bottom = 8
	field.border_color = LINE
	field.set_border_width_all(1)
	theme.set_stylebox("normal", "LineEdit", field)
	var focused := field.duplicate()
	focused.border_color = Color(YELLOW, 0.7)
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_3)
	theme.set_color("caret_color", "LineEdit", YELLOW)
	theme.set_color("selection_color", "LineEdit", Color(YELLOW, 0.3))
	# Check boxes.
	for type in ["CheckBox", "CheckButton"]:
		_button_set(theme, type, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), TEXT, RADIUS_CONTROL, 6, 6)
		theme.set_font("font", type, font(WEIGHT_BODY))
		theme.set_constant("h_separation", type, 10)
	theme.set_icon("checked", "CheckBox", _check_icon(true, false))
	theme.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	theme.set_icon("radio_checked", "CheckBox", _check_icon(true, true))
	theme.set_icon("radio_unchecked", "CheckBox", _check_icon(false, true))
	for state in ["checked_disabled", "unchecked_disabled"]: theme.set_icon(state, "CheckBox", _check_icon(state.begins_with("checked"), false, 0.4))
	# Panels and tabs.
	theme.set_stylebox("panel", "PanelContainer", card())
	var tab_panel := fill(Color(1, 1, 1, 0.03), RADIUS_CONTROL, 14)
	theme.set_stylebox("panel", "TabContainer", tab_panel)
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, _tab(INK_PRESSED, true))
		theme.set_stylebox("tab_unselected", type, _tab(Color(1, 1, 1, 0.0), false))
		theme.set_stylebox("tab_hovered", type, _tab(Color(1, 1, 1, 0.06), false))
		theme.set_stylebox("tab_focus", type, _tab(Color(1, 1, 1, 0.0), false))
		theme.set_color("font_selected_color", type, TEXT)
		theme.set_color("font_unselected_color", type, TEXT_3)
		theme.set_color("font_hovered_color", type, TEXT_2)
		theme.set_font("font", type, font(WEIGHT_STRONG))
		theme.set_font_size("font_size", type, SIZE_BODY)
	theme.set_constant("side_margin", "TabContainer", 0)
	# Lists.
	theme.set_stylebox("panel", "ItemList", fill(INK_WELL, RADIUS_CONTROL, 6))
	theme.set_stylebox("selected", "ItemList", fill(INK_PRESSED, RADIUS_SMALL, 4))
	theme.set_stylebox("selected_focus", "ItemList", fill(INK_PRESSED, RADIUS_SMALL, 4))
	theme.set_stylebox("hovered", "ItemList", fill(Color(1, 1, 1, 0.05), RADIUS_SMALL, 4))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", TEXT_2)
	theme.set_color("font_selected_color", "ItemList", TEXT)
	theme.set_color("font_hovered_color", "ItemList", TEXT)
	theme.set_color("guide_color", "ItemList", Color(1, 1, 1, 0.0))
	theme.set_constant("v_separation", "ItemList", 6)
	# Scrollbars: thin, out of the way.
	for type in ["VScrollBar", "HScrollBar"]:
		var track := fill(Color(1, 1, 1, 0.0), 999, 0)
		track.content_margin_left = 3 if type == "VScrollBar" else 0
		track.content_margin_right = 3 if type == "VScrollBar" else 0
		track.content_margin_top = 3 if type == "HScrollBar" else 0
		track.content_margin_bottom = 3 if type == "HScrollBar" else 0
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		theme.set_stylebox("grabber", type, fill(Color(1, 1, 1, 0.16), 999, 3))
		theme.set_stylebox("grabber_highlight", type, fill(Color(1, 1, 1, 0.26), 999, 3))
		theme.set_stylebox("grabber_pressed", type, fill(Color(1, 1, 1, 0.32), 999, 3))
		for icon in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]:
			theme.set_icon(icon, type, ImageTexture.new())
	# Progress bars.
	theme.set_stylebox("background", "ProgressBar", fill(INK_WELL, 999, 0))
	theme.set_stylebox("fill", "ProgressBar", fill(GREEN, 999, 0))
	# Tooltips.
	var tip := card(0.98, 0)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	tip.content_margin_top = 6
	tip.content_margin_bottom = 6
	tip.shadow_size = 8
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", SIZE_SMALL)
	theme.set_font("font", "TooltipLabel", font(WEIGHT_BODY))
	# Dialogs.
	theme.set_stylebox("panel", "AcceptDialog", card(1.0, 18))
	theme.set_stylebox("embedded_border", "Window", card(1.0, 0))
	theme.set_stylebox("embedded_unfocused_border", "Window", card(1.0, 0))
	theme.set_color("title_color", "Window", TEXT)
	theme.set_font("title_font", "Window", font(WEIGHT_STRONG))
	# Separators and spin boxes.
	var rule := StyleBoxLine.new()
	rule.color = LINE
	rule.thickness = 1
	theme.set_stylebox("separator", "HSeparator", rule)
	theme.set_constant("separation", "HSeparator", 12)
	theme.set_constant("separation", "VBoxContainer", GAP)
	theme.set_constant("separation", "HBoxContainer", GAP)
	return theme

static func _tab(color: Color, selected: bool) -> StyleBoxFlat:
	var style := fill(color, RADIUS_CONTROL, 0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	if selected:
		style.border_color = YELLOW
		style.border_width_bottom = 2
	return style

# Check box and radio icons, drawn into small textures (no image assets).
static func _check_icon(checked: bool, radio: bool, alpha: float = 1.0) -> Texture2D:
	var size := 18
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var box := Color(YELLOW, alpha) if checked else Color(TEXT_3, alpha)
	var center := Vector2(size, size) * 0.5 - Vector2(0.5, 0.5)
	for y in range(size):
		for x in range(size):
			var p := Vector2(x, y)
			var inside := false
			var edge := false
			if radio:
				var d := p.distance_to(center)
				inside = d <= 8.0
				edge = d > 6.5 and d <= 8.0
			else:
				var q := (p - center).abs() - Vector2(5.5, 5.5)
				var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - 2.5
				inside = d <= 0.5
				edge = d > -1.0 and d <= 0.5
			if checked and inside: image.set_pixel(x, y, box)
			elif edge: image.set_pixel(x, y, box)
	if checked:
		var ink := Color(CREAM_TEXT, alpha)
		if radio:
			for y in range(size):
				for x in range(size):
					if Vector2(x, y).distance_to(center) <= 3.2: image.set_pixel(x, y, ink)
		else:
			for point in [[5, 9], [6, 10], [7, 11], [8, 12], [9, 11], [10, 10], [11, 9], [12, 8], [13, 7]]:
				for dy in range(-1, 1): image.set_pixel(point[0], point[1] + dy, ink)
	return ImageTexture.create_from_image(image)
