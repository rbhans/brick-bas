extends Button

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Symbols := preload("res://scripts/ui/toy_symbols.gd")
var caption := ""
var glyph := ""
var thumbnail: Texture2D
var layout_kind := "icon"
var face_color := Color("334149")
var marked := false
var studs := false
var ui_font := ToySkin.font(700)

func _ready() -> void:
	text = ""
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up", "toggled", "focus_entered", "focus_exited"]:
		if signal_name == "toggled": toggled.connect(func(_pressed: bool) -> void: queue_redraw())
		else: connect(signal_name, queue_redraw)

func _draw() -> void:
	var selected := marked or (toggle_mode and button_pressed)
	var color := ToySkin.YELLOW if selected else face_color
	if disabled: color = color.darkened(0.34)
	elif is_hovered(): color = color.lightened(0.09)
	var down := 3.0 if is_pressed() else 0.0
	var rect := Rect2(Vector2(0, 4), size - Vector2(0, 4))
	var base := ToySkin.face(color.darkened(0.2), 11, 0)
	base.shadow_size = 3
	base.shadow_color.a = 0.2
	draw_style_box(base, rect)
	rect.position.y = down
	rect.size.y -= down
	var surface := ToySkin.face(color, 10, 0)
	surface.shadow_size = 0
	draw_style_box(surface, rect)
	if has_focus():
		var focus := ToySkin.face(Color.TRANSPARENT, 10, 0)
		focus.border_color = ToySkin.YELLOW if not selected else Color.WHITE
		focus.set_border_width_all(2)
		draw_style_box(focus, rect.grow(-2))
	if studs:
		for x in [size.x * 0.34, size.x * 0.66]: Symbols.stud(self, Vector2(x, -4 + down), 9, color)
	var ink := ToySkin.INK if color.get_luminance() > 0.42 else ToySkin.CREAM
	var content := Rect2(Vector2(10, 6 + down), size - Vector2(20, 20))
	if layout_kind == "brand":
		for x in [size.x * 0.31, size.x * 0.69]:
			draw_circle(Vector2(x, 26 + down), 7.5, color.darkened(0.16), true, -1, true)
			draw_circle(Vector2(x, 24 + down), 6.5, color.lightened(0.06), true, -1, true)
	elif layout_kind == "part":
		if thumbnail:
			var image_rect := Rect2(Vector2(8, 2 + down), Vector2(size.x - 16, size.y - 30))
			draw_texture_rect(thumbnail, image_rect, false, Color(0.65, 0.65, 0.65, 0.55) if disabled else Color.WHITE)
		elif not glyph.is_empty(): Symbols.draw_icon(self, glyph, Rect2(Vector2(size.x * 0.28, 17 + down), Vector2(size.x * 0.44, size.y * 0.42)), ink)
		draw_caption(caption, Vector2(size.x * 0.5, size.y - 12 + down), 14, ink)
	elif layout_kind == "mode":
		Symbols.draw_icon(self, glyph, Rect2(Vector2(15, 13 + down), Vector2(26, 26)), ink)
		draw_string(ui_font, Vector2(51, size.y * 0.5 + 5 + down), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
	elif layout_kind == "line":
		draw_caption(caption, Vector2(size.x * 0.5, size.y * 0.5 + 5 + down), 14, ink)
	else:
		Symbols.draw_icon(self, glyph, Rect2(content.get_center() - Vector2(14, 14), Vector2(28, 28)), ink)

func draw_caption(value: String, center: Vector2, font_size: int, color: Color) -> void:
	var width := ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(ui_font, center - Vector2(width * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
