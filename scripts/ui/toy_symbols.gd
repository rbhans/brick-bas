extends RefCounted

static func draw_icon(canvas: CanvasItem, name: String, rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.42
	var w := 2.2
	match name:
		"play": canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.5, -r), c + Vector2(r, 0), c + Vector2(-r * 0.5, r)]), color)
		"close", "plus":
			var diagonal := name == "close"
			canvas.draw_line(c + Vector2(-r, -r if diagonal else 0), c + Vector2(r, r if diagonal else 0), color, w, true)
			canvas.draw_line(c + Vector2(-r if diagonal else 0, r), c + Vector2(r if diagonal else 0, -r), color, w, true)
		"undo", "redo":
			canvas.draw_set_transform(c, 0, Vector2(-1 if name == "redo" else 1, 1))
			canvas.draw_arc(Vector2(0, 2), r * 0.8, -PI * 0.5, PI * 0.95, 20, color, w, true)
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(-r, -r * 0.65), Vector2(0, -r * 1.1), Vector2(0, -r * 0.15)]), color)
			canvas.draw_set_transform(Vector2.ZERO)
		"build", "open", "top", "wall":
			var points := PackedVector2Array([c + Vector2(-r, -r * 0.5), c + Vector2(0, -r), c + Vector2(r, -r * 0.5), c + Vector2(r, r * 0.55), c + Vector2(0, r), c + Vector2(-r, r * 0.55), c + Vector2(-r, -r * 0.5)])
			canvas.draw_polyline(points, color, w, true)
			canvas.draw_line(points[0], c, color, w, true)
			canvas.draw_line(points[2], c, color, w, true)
			canvas.draw_line(c, points[4], color, w, true)
		"fan":
			canvas.draw_arc(c, r, 0, TAU, 32, color, 1.6, true)
			for i in range(3):
				var angle := i * TAU / 3
				canvas.draw_circle(c + Vector2.from_angle(angle) * r * 0.5, r * 0.35, color, true, -1, true)
			canvas.draw_circle(c, r * 0.18, color, true, -1, true)
		"explore":
			canvas.draw_circle(c + Vector2(0, -r * 0.75), r * 0.28, color, true, -1, true)
			canvas.draw_style_box(preload("res://scripts/ui/toy_theme.gd").face(color, 3, 0), Rect2(c + Vector2(-r * 0.5, -r * 0.3), Vector2(r, r * 0.8)))
			for x in [-0.32, 0.32]: canvas.draw_line(c + Vector2(x * r, r * 0.3), c + Vector2(x * r, r), color, w * 2, true)
		"paint":
			canvas.draw_line(c + Vector2(-r * 0.15, r * 0.15), c + Vector2(r * 0.7, -r * 0.8), color, w * 3, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.35, 0), c + Vector2(-r, r), c + Vector2(0, r * 0.65), c + Vector2(r * 0.2, r * 0.3)]), color)
		"link":
			for sign in [-1, 1]: canvas.draw_arc(c + Vector2(sign * r * 0.35, -sign * r * 0.3), r * 0.55, 0, TAU, 24, color, w, true)
			canvas.draw_line(c + Vector2(-r * 0.25, r * 0.2), c + Vector2(r * 0.25, -r * 0.2), color, w, true)
		"settings":
			canvas.draw_arc(c, r * 0.55, 0, TAU, 24, color, w * 2, true)
			for i in range(8): canvas.draw_line(c + Vector2.from_angle(i * TAU / 8) * r * 0.5, c + Vector2.from_angle(i * TAU / 8) * r, color, w * 2, true)
		"more":
			for x in [-0.6, 0, 0.6]: canvas.draw_circle(c + Vector2(x * r, 0), 2.2, color, true, -1, true)
		"left", "right":
			var sign := -1 if name == "left" else 1
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-sign * r * 0.4, -r), c + Vector2(sign * r * 0.5, 0), c + Vector2(-sign * r * 0.4, r)]), color, w, true)
		"brick":
			canvas.draw_rect(Rect2(c - Vector2(r, r * 0.5), Vector2(r * 2, r * 1.4)), color)
			for x in [-0.5, 0.5]: canvas.draw_circle(c + Vector2(x * r, -r * 0.6), r * 0.32, color.lightened(0.2), true, -1, true)
		"select":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r * 0.7, r * 0.15), c + Vector2(0.05 * r, r * 0.25), c + Vector2(-r * 0.25, r)]), color)
		"hammer":
			canvas.draw_line(c + Vector2(-r * 0.7, r * 0.9), c + Vector2(r * 0.25, -r * 0.1), color, w * 1.8, true)
			canvas.draw_set_transform(c + Vector2(r * 0.35, -r * 0.35), -PI * 0.25)
			canvas.draw_rect(Rect2(Vector2(-r * 0.75, -r * 0.3), Vector2(r * 1.5, r * 0.6)), color)
			canvas.draw_set_transform(Vector2.ZERO)
		"rotate":
			canvas.draw_arc(c, r * 0.75, PI * 0.1, PI * 1.75, 22, color, w, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.95, -r * 0.05), c + Vector2(r * 0.45, -r * 0.05), c + Vector2(r * 0.72, r * 0.42)]), color)
		"move":
			for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
				var tip := c + Vector2.from_angle(angle) * r
				canvas.draw_line(c, tip, color, w, true)
				canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2.from_angle(angle) * 2.0, tip + Vector2.from_angle(angle + 2.4) * r * 0.4, tip + Vector2.from_angle(angle - 2.4) * r * 0.4]), color)
		"copy":
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.4), Vector2(r * 1.1, r * 1.2)), color, false, w)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.3, -r * 0.9), Vector2(r * 1.1, r * 1.2)), color, false, w)
		"walls_up", "walls_cut", "walls_down":
			var heights: Array = {"walls_up": [1.0, 1.0, 1.0], "walls_cut": [0.35, 1.0, 0.35], "walls_down": [0.3, 0.3, 0.3]}[name]
			for i in range(3):
				var h: float = r * 1.7 * float(heights[i])
				canvas.draw_rect(Rect2(c + Vector2(-r + i * r * 0.72, r * 0.85 - h), Vector2(r * 0.5, h)), color)
			canvas.draw_line(c + Vector2(-r * 1.15, r * 0.85 + w * 1.2), c + Vector2(r * 1.15, r * 0.85 + w * 1.2), color, w, true)
		"pause":
			for x in [-0.4, 0.4]: canvas.draw_rect(Rect2(c + Vector2(x * r - r * 0.18, -r * 0.8), Vector2(r * 0.36, r * 1.6)), color)
		"fast", "faster":
			var count := 2 if name == "fast" else 3
			for i in range(count):
				var x := (float(i) - float(count - 1) * 0.5) * r * 0.62
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(x - r * 0.35, -r * 0.7), c + Vector2(x + r * 0.35, 0), c + Vector2(x - r * 0.35, r * 0.7)]), color)
		"save":
			canvas.draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), color, false, w)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.5, -r), Vector2(r, r * 0.7)), color)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.6, r * 0.2), Vector2(r * 1.2, r * 0.8)), color, false, w)
		"thermo":
			canvas.draw_arc(c, r * 0.85, 0, TAU, 28, color, w, true)
			canvas.draw_arc(c, r * 0.55, PI * 0.8, PI * 2.2, 20, color, w * 1.6, true)
			canvas.draw_circle(c, r * 0.14, color, true, -1, true)
		"menu":
			for y in [-0.55, 0.0, 0.55]: canvas.draw_line(c + Vector2(-r * 0.8, y * r), c + Vector2(r * 0.8, y * r), color, w * 1.2, true)
		"room":
			canvas.draw_rect(Rect2(c - Vector2(r, r * 0.85), Vector2(r * 2, r * 1.7)), color, false, w * 1.6)
			canvas.draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.1), color, w * 1.2, true)
			canvas.draw_line(c + Vector2(0, r * 0.1), c + Vector2(r, r * 0.1), color, w * 1.2, true)
		"wallpen":
			canvas.draw_line(c + Vector2(-r, r * 0.6), c + Vector2(r, r * 0.6), color, w * 2.4, true)
			canvas.draw_line(c + Vector2(-r, r * 0.6), c + Vector2(-r, -r * 0.8), color, w * 2.4, true)
			canvas.draw_circle(c + Vector2(r, r * 0.6), r * 0.22, color, true, -1, true)
		"floor":
			for i in range(3):
				for j in range(3):
					if (i + j) % 2 == 0: canvas.draw_rect(Rect2(c + Vector2(-r + i * r * 0.67, -r + j * r * 0.67), Vector2(r * 0.62, r * 0.62)), color)
		"door":
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.6, -r), Vector2(r * 1.2, r * 2)), color, false, w * 1.4)
			canvas.draw_circle(c + Vector2(r * 0.3, r * 0.1), r * 0.12, color, true, -1, true)
		"window":
			canvas.draw_rect(Rect2(c - Vector2(r * 0.85, r * 0.75), Vector2(r * 1.7, r * 1.5)), color, false, w * 1.4)
			canvas.draw_line(c + Vector2(0, -r * 0.75), c + Vector2(0, r * 0.75), color, w, true)
			canvas.draw_line(c + Vector2(-r * 0.85, 0), c + Vector2(r * 0.85, 0), color, w, true)
		"tree":
			canvas.draw_circle(c + Vector2(0, -r * 0.25), r * 0.72, color, true, -1, true)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.12, r * 0.3), Vector2(r * 0.24, r * 0.7)), color)
		"sofa":
			canvas.draw_rect(Rect2(c + Vector2(-r, -r * 0.1), Vector2(r * 2, r * 0.7)), color)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.6), Vector2(r * 1.6, r * 0.5)), color, false, w)
			for x in [-0.85, 0.85]: canvas.draw_line(c + Vector2(x * r, r * 0.6), c + Vector2(x * r, r * 0.9), color, w, true)
		"duct":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-r, r * 0.4), c + Vector2(r * 0.2, r * 0.4), c + Vector2(r * 0.2, -r * 0.7), c + Vector2(r, -r * 0.7)]), color, w * 2.6, true)
		"eye":
			canvas.draw_arc(c + Vector2(0, r * 0.5), r, PI * 1.15, PI * 1.85, 16, color, w, true)
			canvas.draw_arc(c - Vector2(0, r * 0.5), r, PI * 0.15, PI * 0.85, 16, color, w, true)
			canvas.draw_circle(c, r * 0.3, color, true, -1, true)
		"check":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, 0.0), c + Vector2(-r * 0.2, r * 0.55), c + Vector2(r * 0.75, -r * 0.55)]), color, w * 1.2, true)
		"bell":
			canvas.draw_arc(c + Vector2(0, -r * 0.1), r * 0.6, PI, TAU, 16, color, w, true)
			canvas.draw_line(c + Vector2(-r * 0.6, -r * 0.1), c + Vector2(-r * 0.75, r * 0.55), color, w, true)
			canvas.draw_line(c + Vector2(r * 0.6, -r * 0.1), c + Vector2(r * 0.75, r * 0.55), color, w, true)
			canvas.draw_line(c + Vector2(-r * 0.9, r * 0.55), c + Vector2(r * 0.9, r * 0.55), color, w, true)
			canvas.draw_circle(c + Vector2(0, r * 0.82), r * 0.16, color, true, -1, true)
		"warning":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8), c + Vector2(0, -r)]), color, w, true)
			canvas.draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.25), color, w, true)
			canvas.draw_circle(c + Vector2(0, r * 0.52), r * 0.1, color, true, -1, true)
		"dot":
			canvas.draw_circle(c, r * 0.45, color, true, -1, true)
		"airflow":
			for y in [-0.5, 0.1, 0.7]:
				canvas.draw_arc(c + Vector2(-r * 0.2, y * r - r * 0.25), r * 0.28, PI * 0.5, PI * 1.9, 10, color, w, true)
				canvas.draw_line(c + Vector2(-r * 0.2, y * r + r * 0.03), c + Vector2(r, y * r + r * 0.03), color, w, true)

static func stud(canvas: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	canvas.draw_set_transform(center, 0, Vector2(1, 0.48))
	canvas.draw_circle(Vector2(0, 5), radius + 1, color.darkened(0.35), true, -1, true)
	canvas.draw_circle(Vector2.ZERO, radius, color.lightened(0.16), true, -1, true)
	canvas.draw_arc(Vector2.ZERO, radius - 1, PI, TAU, 20, color.lightened(0.35), 1.0, true)
	canvas.draw_set_transform(Vector2.ZERO)
