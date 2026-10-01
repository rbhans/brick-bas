extends PanelContainer

# The cream parts tray: one molded piece with a rim, a soft drop shadow and a
# pair of round pegs at each end (seen from above, like the studs on a plate).

const ToySkin := preload("res://scripts/ui/toy_theme.gd")

func _ready() -> void:
	var style := ToySkin.fill(ToySkin.CREAM, 18, 12)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.border_color = Color(1, 1, 1, 0.55)
	style.border_width_top = 2
	style.shadow_color = ToySkin.SHADOW
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)
	add_theme_stylebox_override("panel", style)

func _draw() -> void:
	for x in [17.0, size.x - 17.0]:
		for y in [size.y * 0.5 - 13.0, size.y * 0.5 + 13.0]:
			draw_circle(Vector2(x, y + 1.5), 7.0, ToySkin.CREAM.darkened(0.16), true, -1, true)
			draw_circle(Vector2(x, y), 6.5, ToySkin.CREAM.lightened(0.04), true, -1, true)
			draw_arc(Vector2(x, y), 5.0, PI * 1.05, PI * 1.6, 8, Color(1, 1, 1, 0.8), 1.2, true)
