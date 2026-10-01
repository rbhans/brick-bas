extends Control

# Small drawn marks: star ratings and objective checks. Drawn rather than typed
# because the browser build's bundled font has no ★ ☆ ✓ ✗ ○ glyphs.

var kind := "star"            # star | check | cross | ring
var color := Color.WHITE
var dim := Color(1, 1, 1, 0.25) # unlit stars
var count := 1                # stars in a row
var lit := 1                  # how many of them are filled
var size_px := 14.0

static func make(parent: Node, mark_kind: String, mark_color: Color, pixels: float = 14.0, stars: int = 1, filled: int = 1) -> Control:
	var mark: Control = load("res://scripts/ui/mark.gd").new()
	mark.kind = mark_kind
	mark.color = mark_color
	mark.size_px = pixels
	mark.count = stars
	mark.lit = filled
	mark.custom_minimum_size = Vector2(pixels * (stars if mark_kind == "star" else 1) + (pixels * 0.25 * (stars - 1) if mark_kind == "star" else 0.0), pixels)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(mark)
	return mark

func set_stars(filled: int, mark_color: Color) -> void:
	lit = filled
	color = mark_color
	queue_redraw()

func _draw() -> void:
	var s := size_px
	match kind:
		"star":
			for index in range(count):
				var center := Vector2(s * 0.5 + index * s * 1.25, size.y * 0.5)
				_star(center, s * 0.5, color if index < lit else dim, index < lit)
		"check":
			var c := Vector2(s * 0.5, size.y * 0.5)
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.32, 0), c + Vector2(-s * 0.08, s * 0.26), c + Vector2(s * 0.36, -s * 0.28)]), color, maxf(2.0, s * 0.16), true)
		"cross":
			var c := Vector2(s * 0.5, size.y * 0.5)
			var r := s * 0.28
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), color, maxf(2.0, s * 0.15), true)
			draw_line(c + Vector2(-r, r), c + Vector2(r, -r), color, maxf(2.0, s * 0.15), true)
		"ring":
			draw_arc(Vector2(s * 0.5, size.y * 0.5), s * 0.3, 0.0, TAU, 24, color, maxf(1.5, s * 0.1), true)

func _star(center: Vector2, radius: float, fill: Color, solid: bool) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI * 0.5 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	if solid:
		draw_colored_polygon(points, fill)
	else:
		points.append(points[0])
		draw_polyline(points, fill, maxf(1.2, radius * 0.14), true)
