extends Button

# A molded toy tile: the clickable piece used for tools, parts, modes and card
# actions. Draws its own plastic: a darker base under a face that lifts on
# hover and presses down when clicked, an optional pair of studs, and a
# vector pictogram, part thumbnail or caption.
#   layout_kind: "icon" (pictogram) · "part" (thumbnail + caption, the tray)
#                "mode" (pictogram + label, the mode tabs) · "line" (caption)
#                "action" (pictogram over a short caption)
#                "chip" (small pictogram then a caption, left aligned; card actions)
#   toggle_look: "fill" (selected = solid yellow) · "ring" (selected = yellow
#                rim and pictogram; for view toggles, so only the active tool
#                is solid yellow)

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Symbols := preload("res://scripts/ui/toy_symbols.gd")
const LIFT := 4.0

var caption := ""
var glyph := ""
var thumbnail: Texture2D
var layout_kind := "icon"
var face_color := ToySkin.INK_RAISED
var marked := false
var studs := false
var toggle_look := "fill"
var caption_size := 0 # 0 = by layout
var ink_color := Color(0, 0, 0, 0) # pictogram colour override (e.g. red for Delete)
var ui_font := ToySkin.font(ToySkin.WEIGHT_STRONG)

func _ready() -> void:
	text = ""
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up", "toggled", "focus_entered", "focus_exited"]:
		if signal_name == "toggled": toggled.connect(func(_pressed: bool) -> void: queue_redraw())
		else: connect(signal_name, queue_redraw)

func _selected() -> bool:
	return marked or (toggle_mode and button_pressed)

func _draw() -> void:
	var selected := _selected()
	var solid := selected and toggle_look == "fill"
	var color := ToySkin.YELLOW if solid else face_color
	if disabled: color = color.darkened(0.25).lerp(ToySkin.INK, 0.35)
	elif is_hovered() and not is_pressed(): color = color.lightened(0.07)
	var down := LIFT - 1.0 if is_pressed() else (0.0 if is_hovered() and not disabled else 1.0)
	# Base (the darker plastic underneath) and the face.
	var base_rect := Rect2(Vector2(0, LIFT), size - Vector2(0, LIFT))
	var base := ToySkin.fill(color.darkened(0.28), ToySkin.RADIUS_CONTROL + 1, 0)
	base.shadow_color = ToySkin.SHADOW
	base.shadow_size = 3 if not is_pressed() else 1
	base.shadow_offset = Vector2(0, 2)
	draw_style_box(base, base_rect)
	var face_rect := Rect2(Vector2(0, down), size - Vector2(0, LIFT))
	var surface := ToySkin.fill(color, ToySkin.RADIUS_CONTROL, 0)
	surface.border_color = color.lightened(0.16)
	surface.border_width_top = 1
	draw_style_box(surface, face_rect)
	if selected and toggle_look == "ring":
		var ring := ToySkin.fill(Color.TRANSPARENT, ToySkin.RADIUS_CONTROL, 0)
		ring.draw_center = false
		ring.border_color = ToySkin.YELLOW
		ring.set_border_width_all(2)
		draw_style_box(ring, face_rect)
	if has_focus() and focus_mode != FOCUS_NONE:
		var focus := ToySkin.fill(Color.TRANSPARENT, ToySkin.RADIUS_CONTROL + 2, 0)
		focus.draw_center = false
		focus.border_color = ToySkin.YELLOW if not solid else Color.WHITE
		focus.set_border_width_all(2)
		draw_style_box(focus, face_rect.grow(2))
	if studs:
		for x in [size.x * 0.34, size.x * 0.66]: Symbols.stud(self, Vector2(x, -3 + down), 7.5, color)
	var ink := ToySkin.CREAM_TEXT if color.get_luminance() > 0.45 else ToySkin.TEXT
	if selected and toggle_look == "ring": ink = ToySkin.YELLOW
	if disabled: ink = Color(ink, 0.45)
	var area := Rect2(face_rect.position, face_rect.size)
	match layout_kind:
		"brand":
			for x in [size.x * 0.31, size.x * 0.69]:
				draw_circle(Vector2(x, area.get_center().y + 2), 7.5, color.darkened(0.18), true, -1, true)
				draw_circle(Vector2(x, area.get_center().y), 6.5, color.lightened(0.07), true, -1, true)
		"part":
			var pad := 7.0
			var label_h := 22.0
			if thumbnail:
				var room := Rect2(area.position + Vector2(pad, pad - 1), Vector2(area.size.x - pad * 2, area.size.y - label_h - pad))
				var scale := minf(room.size.x / thumbnail.get_width(), room.size.y / thumbnail.get_height())
				var shown := Vector2(thumbnail.get_width(), thumbnail.get_height()) * scale
				draw_texture_rect(thumbnail, Rect2(room.get_center() - shown * 0.5, shown), false, Color(1, 1, 1, 0.5) if disabled else Color.WHITE)
			elif not glyph.is_empty():
				Symbols.draw_icon(self, glyph, Rect2(area.get_center() - Vector2(16, 26), Vector2(32, 32)), ink)
			draw_caption(caption, Vector2(area.get_center().x, area.end.y - 8), caption_size if caption_size > 0 else ToySkin.SIZE_SMALL, ink, area.size.x - 10)
		"mode":
			Symbols.draw_icon(self, glyph, Rect2(Vector2(16, area.get_center().y - 12), Vector2(24, 24)), ink)
			draw_string(ui_font, Vector2(50, area.get_center().y + 6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)
		"line":
			draw_caption(caption, Vector2(area.get_center().x, area.get_center().y + 5), caption_size if caption_size > 0 else ToySkin.SIZE_BODY, ink, area.size.x - 12)
		"chip":
			var tint := ink_color if ink_color.a > 0.0 and not disabled else ink
			Symbols.draw_icon(self, glyph, Rect2(Vector2(10, area.get_center().y - 8), Vector2(16, 16)), tint)
			var text_size := caption_size if caption_size > 0 else ToySkin.SIZE_SMALL
			var room := area.size.x - 44
			var shrink := text_size
			while ui_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, shrink).x > room and shrink > 10: shrink -= 1
			draw_string(ui_font, Vector2(34, area.get_center().y + shrink * 0.36), caption, HORIZONTAL_ALIGNMENT_LEFT, room, shrink, ink)
		"action":
			Symbols.draw_icon(self, glyph, Rect2(Vector2(area.get_center().x - 11, area.position.y + 8), Vector2(22, 22)), ink)
			draw_caption(caption, Vector2(area.get_center().x, area.end.y - 8), ToySkin.SIZE_CAPTION, ink, area.size.x - 6)
		_:
			var icon := minf(26.0, minf(area.size.x, area.size.y) - 16.0)
			Symbols.draw_icon(self, glyph, Rect2(area.get_center() - Vector2(icon, icon) * 0.5, Vector2(icon, icon)), ink)

# Centered caption that shrinks (down to 9 px) rather than spilling out.
func draw_caption(value: String, baseline_center: Vector2, font_size: int, color: Color, max_width: float = INF) -> void:
	var size_now := font_size
	var width := ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x
	while width > max_width and size_now > 9:
		size_now -= 1
		width = ui_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x
	draw_string(ui_font, baseline_center - Vector2(minf(width, max_width) * 0.5, 0), value, HORIZONTAL_ALIGNMENT_LEFT, max_width, size_now, color)
