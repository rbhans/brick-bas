class_name UIKit
extends RefCounted

# Small helpers for building the toy-brick HUD out of native Controls. Colours,
# sizes and fonts come from ToySkin (scripts/ui/toy_theme.gd).

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Tile := preload("res://scripts/ui/toy_button.gd")

static func panel(parent: Node, rect: Vector4, preset: int, style: StyleBox = null) -> PanelContainer:
	var result := PanelContainer.new()
	parent.add_child(result)
	result.set_anchors_and_offsets_preset(preset)
	result.offset_left = rect.x
	result.offset_top = rect.y
	result.offset_right = rect.z
	result.offset_bottom = rect.w
	if style != null:
		result.add_theme_stylebox_override("panel", style)
	return result

static func row(parent: Node, separation: int = 8) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	parent.add_child(result)
	return result

static func column(parent: Node, separation: int = 8) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	parent.add_child(result)
	return result

static func label(parent: Node, text: String, size: int = 14, color: Color = Color(0, 0, 0, 0), weight: int = 0) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		result.add_theme_color_override("font_color", color)
	if weight > 0:
		result.add_theme_font_override("font", ToySkin.font(weight))
	parent.add_child(result)
	return result

# A wrapping paragraph.
static func text(parent: Node, value: String, size: int = ToySkin.SIZE_BODY, color: Color = ToySkin.TEXT_2) -> Label:
	var result := label(parent, value, size, color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

# A heading in the card's own voice.
static func title(parent: Node, value: String, size: int = ToySkin.SIZE_TITLE, color: Color = ToySkin.TEXT) -> Label:
	return label(parent, value, size, color, ToySkin.WEIGHT_HEAVY)

# A small section label ("SCHEDULE", "WORK ORDERS").
static func section(parent: Node, value: String, color: Color = ToySkin.LABEL) -> Label:
	return label(parent, value.to_upper(), ToySkin.SIZE_CAPTION, color, ToySkin.WEIGHT_HEAVY)

# variant: "" (charcoal), "PrimaryButton", "GhostButton", "ChipButton", "DangerButton", "RowButton".
static func button(parent: Node, text: String, action: Callable, variant: String = "") -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	result.focus_mode = Control.FOCUS_NONE
	if not variant.is_empty():
		result.theme_type_variation = variant
	if variant == "RowButton":
		result.alignment = HORIZONTAL_ALIGNMENT_LEFT
		result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

# A full-width action with a quiet detail on the right ("4 min", "$260 · 25 min").
static func task(parent: Node, text: String, meta: String, action: Callable) -> Button:
	var result := button(parent, text, action)
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.clip_text = true
	result.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result.custom_minimum_size.y = 38
	var width := ToySkin.font(ToySkin.WEIGHT_BODY).get_string_size(meta, HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_SMALL).x
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var themed := result.get_theme_stylebox(state, result.theme_type_variation)
		if themed == null: continue
		var style := themed.duplicate() as StyleBox
		style.content_margin_right = width + 26.0
		result.add_theme_stylebox_override(state, style)
	if not meta.is_empty():
		var detail := label(result, meta, ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
		detail.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		detail.offset_left = -(width + 14.0)
		detail.offset_right = -12
		detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

# A keyboard key drawn as a small keycap, with what it does beside it.
static func key_hint(parent: Node, key: String, what: String, on_cream: bool = false) -> HBoxContainer:
	var holder := row(parent, 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	var face := ToySkin.fill(ToySkin.CREAM_WELL if on_cream else ToySkin.INK_RAISED, 5, 0)
	face.content_margin_left = 6
	face.content_margin_right = 6
	face.content_margin_top = 1
	face.content_margin_bottom = 2
	face.border_color = Color(0, 0, 0, 0.25)
	face.border_width_bottom = 2
	cap.add_theme_stylebox_override("panel", face)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cap)
	label(cap, key, ToySkin.SIZE_CAPTION, ToySkin.CREAM_TEXT if on_cream else ToySkin.TEXT, ToySkin.WEIGHT_HEAVY)
	if not what.is_empty():
		label(holder, what, ToySkin.SIZE_SMALL, ToySkin.CREAM_TEXT_2 if on_cream else ToySkin.TEXT_2)
	return holder

# Label / value pairs in two columns.
static func stats(parent: Node, rows: Array, value_color: Color = ToySkin.TEXT) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for entry in rows:
		label(grid, String(entry[0]), ToySkin.SIZE_SMALL, ToySkin.TEXT_3)
		var value := label(grid, String(entry[1]), ToySkin.SIZE_SMALL, value_color, ToySkin.WEIGHT_STRONG)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid

# A short fade and rise when a panel appears (skipped with Reduce motion).
static func pop_in(control: Control, reduced_motion: bool = false) -> void:
	if reduced_motion or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, 0.14)

# Empties a container. Safe even when the rebuild was triggered by one of its
# own buttons (still emitting `pressed`): children leave the tree now and are
# freed at the end of the frame.
static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

static func tile(parent: Node, caption: String, glyph: String, action: Callable, size: Vector2 = Vector2(46, 44), layout: String = "icon") -> Button:
	var result := Tile.new()
	result.caption = caption
	result.glyph = glyph
	result.layout_kind = layout
	result.custom_minimum_size = size
	result.tooltip_text = caption
	result.focus_mode = Control.FOCUS_NONE
	result.pressed.connect(action)
	parent.add_child(result)
	return result

static func options(parent: Node, items: Array) -> OptionButton:
	var result := OptionButton.new()
	for item in items:
		result.add_item(String(item))
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result

static func line(parent: Node, placeholder: String) -> LineEdit:
	var result := LineEdit.new()
	result.placeholder_text = placeholder
	parent.add_child(result)
	return result

static func spin(parent: Node, minimum: float, maximum: float, value: float, step: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step
	result.value = value
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

static func spacer(parent: Node) -> Control:
	var result := Control.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

static func separator(parent: Node, vertical: bool = true) -> void:
	var line_node := ColorRect.new()
	line_node.color = Color(ToySkin.TEXT, 0.14)
	line_node.custom_minimum_size = Vector2(1, 28) if vertical else Vector2(0, 1)
	line_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line_node)

static func thumbnail(id: String) -> Texture2D:
	var path := "res://assets/ui/thumbnails/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null

# The floating charcoal card (kept under its old name for existing callers).
static func glass_style(radius: int = ToySkin.RADIUS_CARD, alpha: float = 0.96) -> StyleBoxFlat:
	var style := ToySkin.card(maxf(alpha, 0.92))
	style.set_corner_radius_all(radius)
	return style
