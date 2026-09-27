class_name UIKit
extends RefCounted

# Small helpers for building the toy-brick HUD out of native Controls.

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

static func label(parent: Node, text: String, size: int = 14, color: Color = Color(0, 0, 0, 0)) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result

static func button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	result.focus_mode = Control.FOCUS_NONE
	parent.add_child(result)
	return result

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

static func separator(parent: Node) -> void:
	var line_node := ColorRect.new()
	line_node.color = Color(1, 1, 1, 0.08)
	line_node.custom_minimum_size = Vector2(2, 28)
	line_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line_node)

static func thumbnail(id: String) -> Texture2D:
	var path := "res://assets/ui/thumbnails/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null

static func glass_style(radius: int = 14, alpha: float = 0.9) -> StyleBoxFlat:
	var style := ToySkin.face(Color(ToySkin.INK, alpha), radius, 12)
	style.border_color = Color(1, 1, 1, 0.07)
	return style
