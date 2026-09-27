class_name PointProvider
extends RefCounted

func provider_id() -> String:
	return "abstract"

func connection_state() -> String:
	return "disconnected"

func discover(_query: String = "") -> Array[Dictionary]:
	return []

func snapshot() -> Array[Dictionary]:
	return []

func subscribe(_point_ids: Array[String]) -> bool:
	return false

func unsubscribe(_point_ids: Array[String]) -> void:
	pass

func write_point(_point_id: String, _value: Variant) -> bool:
	# Read-only at the provider boundary. Demo controls call the simulation directly.
	return false

