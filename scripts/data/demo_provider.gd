class_name DemoProvider
extends PointProvider

var simulation: DemoSimulation

func _init(value: DemoSimulation) -> void:
	simulation = value

func provider_id() -> String:
	return "demo"

func connection_state() -> String:
	return "ready"

func discover(query: String = "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for point in snapshot():
		if query.is_empty() or String(point.point_id).contains(query):
			found.append(point)
	return found

func snapshot() -> Array[Dictionary]:
	return simulation.snapshot_points()

func subscribe(_point_ids: Array[String]) -> bool:
	return true

