extends Control

# A compact BAS-style trend: a few point histories over the recent window,
# each with its own colour, current value and unit. Breaks at history
# boundaries (reset, data source change) instead of drawing a false line.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")

var game: Node
var series: Array = []   # {point_id, label, color, quantity or unit, scale}
var window_s := 4.0 * 3600.0
var font: Font

func setup(owner: Node) -> void:
	game = owner
	custom_minimum_size = Vector2(250, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ToySkin.font(700)

func show_series(entries: Array) -> void:
	series = entries
	visible = not entries.is_empty()
	queue_redraw()

func _draw() -> void:
	if series.is_empty():
		return
	var plot := Rect2(Vector2(4, 4), size - Vector2(8, 34))
	draw_style_box(ToySkin.face(Color("142328"), 6, 0), Rect2(Vector2.ZERO, size - Vector2(0, 26)))
	var now: float = game.sim.sim_seconds
	var start := now - window_s
	var low := INF
	var high := -INF
	var data: Array = []
	for entry in series:
		var points: Array = []
		for sample in game.history.get_series(String(entry.point_id)):
			if bool(sample.get("boundary", false)):
				points.append(null)
				continue
			var time := float(sample.time)
			if time < start or sample.value == null:
				continue
			var value := _display(entry, float(sample.value))
			points.append(Vector2(time, value))
			if not bool(entry.get("own_axis", false)):
				low = minf(low, value)
				high = maxf(high, value)
		data.append(points)
	if low == INF:
		low = 0.0
		high = 1.0
	if high - low < 2.0:
		var middle := (high + low) * 0.5
		low = middle - 1.0
		high = middle + 1.0
	var pad := (high - low) * 0.1
	low -= pad
	high += pad
	# Hour grid.
	var hour := ceilf(start / 3600.0) * 3600.0
	while hour < now:
		var x := plot.position.x + (hour - start) / window_s * plot.size.x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1, 1, 1, 0.06), 1.0)
		draw_string(font, Vector2(x + 2, plot.end.y - 2), "%02d:00" % int(fposmod(hour / 3600.0, 24.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.3))
		hour += 3600.0
	for index in range(series.size()):
		var entry: Dictionary = series[index]
		var points: Array = data[index]
		var own := bool(entry.get("own_axis", false))
		var local_low := low
		var local_high := high
		if own:
			local_low = float(entry.get("min", 0.0))
			local_high = float(entry.get("max", 1.0))
		var colour: Color = entry.color
		var line := PackedVector2Array()
		for point in points:
			if point == null:
				if line.size() > 1: draw_polyline(line, colour, 1.6, true)
				line.clear()
				continue
			var p: Vector2 = point
			var y := plot.end.y - (p.y - local_low) / maxf(local_high - local_low, 0.001) * plot.size.y
			line.append(Vector2(plot.position.x + (p.x - start) / window_s * plot.size.x, clampf(y, plot.position.y, plot.end.y)))
		if line.size() > 1:
			draw_polyline(line, colour, 1.6 if not bool(entry.get("dashed", false)) else 1.0, true)
	draw_string(font, Vector2(plot.end.x - 40, plot.position.y + 10), "%.0f" % high, HORIZONTAL_ALIGNMENT_RIGHT, 38, 9, Color(1, 1, 1, 0.35))
	draw_string(font, Vector2(plot.end.x - 40, plot.end.y - 12), "%.0f" % low, HORIZONTAL_ALIGNMENT_RIGHT, 38, 9, Color(1, 1, 1, 0.35))
	# Legend with live values.
	var x := 2.0
	for entry in series:
		var point: Dictionary = game.points.get_point(String(entry.point_id))
		var value := "--"
		if point.has("value") and point.value != null and not (point.value is bool):
			var shown := _display(entry, float(point.value))
			value = ("%.0f" if absf(shown) >= 100.0 or String(entry.get("quantity", "")) == "percent" else "%.1f") % shown
		var text := "%s %s%s" % [String(entry.label), value, String(entry.get("unit", Units.suffix(String(entry.get("quantity", "")))))]
		draw_rect(Rect2(Vector2(x, size.y - 17), Vector2(8, 8)), entry.color)
		draw_string(font, Vector2(x + 11, size.y - 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d3dcdf"))
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 22

# Raw SI history in display units (°F, CFM, %…).
func _display(entry: Dictionary, raw: float) -> float:
	return Units.convert(String(entry.get("quantity", "")), raw) * float(entry.get("scale", 1.0))
