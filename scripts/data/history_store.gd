class_name HistoryStore
extends RefCounted

# Trend history for every numeric point, kept in packed arrays so a whole
# building (1000+ points) can hold a simulated day cheaply. Boundaries (reset,
# data-source change) are stored as NaN so trends break instead of joining
# unrelated data.

const SAMPLE_INTERVAL_S := 60.0
const MAX_SAMPLES_PER_POINT := 1440

var times: Dictionary = {}   # point id -> PackedFloat32Array
var values: Dictionary = {}  # point id -> PackedFloat32Array
var last_sample_time := -INF
var _latest_time := -INF
# Readings flagged like this aren't current: they trend as a gap.
const NOT_CURRENT := ["stale", "fault", "down", "disabled", "communication_failure", "unknown"]

func sample(points: Array[Dictionary], sim_time: float) -> bool:
	# The clock went back (a reset, a new game, a verify run from midnight):
	# the old samples would sit ahead of now and mix with the new ones.
	if sim_time < _latest_time:
		clear()
	if sim_time - last_sample_time < SAMPLE_INTERVAL_S:
		return false
	last_sample_time = sim_time
	for point in points:
		var id := String(point.get("point_id", ""))
		var value: Variant = point.get("value")
		if id.is_empty():
			continue
		var number := NAN
		if value is bool: number = 1.0 if value else 0.0
		elif value is int or value is float: number = float(value)
		else: continue
		for flag in point.get("quality_flags", []):
			if String(flag) in NOT_CURRENT: number = NAN
		if not times.has(id):
			times[id] = PackedFloat32Array()
			values[id] = PackedFloat32Array()
		_push(id, sim_time, number)
	return true

func _push(id: String, time: float, value: float) -> void:
	# Appending through the dictionary mutates in place (no copy-on-write).
	times[id].append(time)
	values[id].append(value)
	_latest_time = maxf(_latest_time, time)
	if times[id].size() > MAX_SAMPLES_PER_POINT + 120:
		times[id] = times[id].slice(-MAX_SAMPLES_PER_POINT)
		values[id] = values[id].slice(-MAX_SAMPLES_PER_POINT)

# Older samples from elsewhere (a station's history) ahead of what's been
# sampled live: [[time, value], ...] oldest first.
func prepend(point_id: String, samples: Array) -> void:
	var t := PackedFloat32Array()
	var v := PackedFloat32Array()
	var first: float = times[point_id][0] if times.has(point_id) and not times[point_id].is_empty() else INF
	for sample in samples:
		if float(sample[0]) >= first: break
		t.append(float(sample[0]))
		v.append(float(sample[1]))
	if t.is_empty(): return
	if times.has(point_id):
		t.append_array(times[point_id])
		v.append_array(values[point_id])
	times[point_id] = t.slice(-MAX_SAMPLES_PER_POINT)
	values[point_id] = v.slice(-MAX_SAMPLES_PER_POINT)

func mark_boundary(_reason: String, sim_time: float) -> void:
	last_sample_time = -INF
	for id in times:
		_push(String(id), sim_time, NAN)

func clear() -> void:
	times.clear()
	values.clear()
	last_sample_time = -INF
	_latest_time = -INF

# [{time, value, boundary}] oldest first; `since` limits the window.
func get_series(point_id: String, since: float = -INF) -> Array:
	var result: Array = []
	if not times.has(point_id):
		return result
	var t: PackedFloat32Array = times[point_id]
	var v: PackedFloat32Array = values[point_id]
	for index in range(t.size()):
		if t[index] < since:
			continue
		var boundary := is_nan(v[index])
		result.append({"time": t[index], "value": null if boundary else v[index], "boundary": boundary})
	return result
