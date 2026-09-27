class_name PointStore
extends RefCounted

var _points: Dictionary = {}

func replace_snapshot(updates: Array[Dictionary]) -> void:
	_points.clear()
	apply_updates(updates)

func apply_updates(updates: Array[Dictionary]) -> void:
	for update in updates:
		if update.has("point_id"):
			_points[String(update.point_id)] = update.duplicate(true)

func get_point(point_id: String) -> Dictionary:
	return _points.get(point_id, {}).duplicate(true)

func all_points() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _points.keys()
	ids.sort()
	for id in ids:
		result.append(_points[id].duplicate(true))
	return result
