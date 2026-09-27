extends PanelContainer

var cream := Color("eee8d4")

func _ready() -> void:
	var skin := preload("res://scripts/ui/toy_theme.gd")
	var style := skin.face(cream, 20, 16)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 7)
	add_theme_stylebox_override("panel", style)

func _draw() -> void:
	var symbols := preload("res://scripts/ui/toy_symbols.gd")
	for x in [16.0, size.x - 16.0]:
		for y in [20.0, 45.0]: symbols.stud(self, Vector2(x, y), 7, cream)
