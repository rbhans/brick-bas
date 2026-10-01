extends Control

# A compact BAS-style trend: a few point histories over the recent window,
# each with its own colour, current value and unit. Breaks at history
# boundaries (reset, data source change) instead of drawing a false line.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")

var game: Node
var series: Array = []   # {point_id, label, color, quantity or unit, scale}
var window_s := 4.0 * 3600.0   # at most; shorter while there's less history
const MIN_WINDOW_S := 600.0
const PLOT_HEIGHT := 104.0
const LEGEND_ROW := 18.0
var font: Font
var value_font: Font
var _legend_rows := 1

func setup(owner: Node) -> void:
	game = owner
	custom_minimum_size = Vector2(250, PLOT_HEIGHT + LEGEND_ROW + 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ToySkin.font(ToySkin.WEIGHT_BODY)
	value_font = ToySkin.font(ToySkin.WEIGHT_STRONG)

func show_series(entries: Array) -> void:
	series = entries
	visible = not entries.is_empty()
	queue_redraw()

func _draw() -> void:
	if series.is_empty():
		return
	var well := Rect2(Vector2.ZERO, Vector2(size.x, PLOT_HEIGHT))
	draw_style_box(ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 0), well)
	# Room on the right for the scale.
	var plot := Rect2(Vector2(8, 10), Vector2(size.x - 40, PLOT_HEIGHT - 30))
	var now: float = game.history_time()
	var earliest := now
	for entry in series:
		for sample in game.history.get_series(String(entry.point_id)):
			if not bool(sample.get("boundary", false)) and sample.value != null:
				earliest = minf(earliest, float(sample.time))
				break
	var span := clampf(now - earliest, MIN_WINDOW_S, window_s)
	var start := now - span
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
	# Hour grid (half hours on a short window), labelled under the plot.
	var grid := ToySkin.LINE
	for fraction in [0.0, 0.5, 1.0]:
		var y: float = plot.position.y + plot.size.y * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
	var step := 3600.0 if span > 2.5 * 3600.0 else (1800.0 if span > 3000.0 else 600.0)
	var tick := ceilf(start / step) * step
	while tick < now:
		var x := plot.position.x + (tick - start) / span * plot.size.x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid, 1.0)
		var minutes := int(roundf(fposmod(tick / 60.0, 1440.0)))
		if x > plot.position.x + 14.0 and x < plot.end.x - 14.0:
			draw_string(font, Vector2(x - 16, PLOT_HEIGHT - 7), "%02d:%02d" % [minutes / 60, minutes % 60], HORIZONTAL_ALIGNMENT_CENTER, 32, ToySkin.SIZE_CAPTION - 1, ToySkin.TEXT_3)
		tick += step
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
			line.append(Vector2(plot.position.x + (p.x - start) / span * plot.size.x, clampf(y, plot.position.y, plot.end.y)))
		if line.size() > 1:
			draw_polyline(line, colour, 2.0 if not bool(entry.get("dashed", false)) else 1.2, true)
			draw_circle(line[line.size() - 1], 3.0, colour, true, -1, true)
	draw_string(font, Vector2(plot.end.x + 4, plot.position.y + 4), "%.0f" % high, HORIZONTAL_ALIGNMENT_LEFT, 30, ToySkin.SIZE_CAPTION - 1, ToySkin.TEXT_3)
	draw_string(font, Vector2(plot.end.x + 4, plot.end.y + 4), "%.0f" % low, HORIZONTAL_ALIGNMENT_LEFT, 30, ToySkin.SIZE_CAPTION - 1, ToySkin.TEXT_3)
	# Legend with live values, wrapping onto a second row when it must.
	var x := 2.0
	var row := 0
	for entry in series:
		var point: Dictionary = game.points.get_point(String(entry.point_id))
		var value := "--"
		if point.has("value") and point.value != null and not (point.value is bool):
			var shown := _display(entry, float(point.value))
			value = ("%.0f" if absf(shown) >= 100.0 or String(entry.get("quantity", "")) == "percent" else "%.1f") % shown
		var name := String(entry.label)
		var reading := "%s%s" % [value, String(entry.get("unit", Units.suffix(String(entry.get("quantity", "")))))]
		var name_w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_CAPTION).x
		var width := 12.0 + name_w + 5.0 + value_font.get_string_size(reading, HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_CAPTION).x
		if x > 2.0 and x + width > size.x:
			x = 2.0
			row += 1
		var base := PLOT_HEIGHT + 14.0 + row * LEGEND_ROW
		draw_circle(Vector2(x + 4, base - 4), 4.0, entry.color, true, -1, true)
		draw_string(font, Vector2(x + 12, base), name, HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_CAPTION, ToySkin.TEXT_3)
		draw_string(value_font, Vector2(x + 12 + name_w + 5, base), reading, HORIZONTAL_ALIGNMENT_LEFT, -1, ToySkin.SIZE_CAPTION, ToySkin.TEXT)
		x += width + 14.0
	if row + 1 != _legend_rows:
		_legend_rows = row + 1
		custom_minimum_size.y = PLOT_HEIGHT + 8 + LEGEND_ROW * _legend_rows

# Raw SI history in display units (°F, CFM, %…).
func _display(entry: Dictionary, raw: float) -> float:
	return Units.convert(String(entry.get("quantity", "")), raw) * float(entry.get("scale", 1.0))
