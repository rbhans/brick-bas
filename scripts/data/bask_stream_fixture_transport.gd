class_name BaskStreamFixtureTransport
extends RefCounted

const Codec := preload("res://scripts/data/message_pack.gd")
var opened := false
var incoming: Array[PackedByteArray] = []
var sent_requests: Array[Dictionary] = []

func open() -> bool:
	opened = true
	return true

func state() -> String:
	return "ready" if opened else "offline"

func send_binary(frame: PackedByteArray) -> bool:
	if not opened: return false
	var decoded := Codec.decode(frame)
	if not decoded.ok or not decoded.value is Dictionary: return false
	var request: Dictionary = decoded.value
	sent_requests.append(request.duplicate(true))
	match String(request.get("op", "")):
		"ping": incoming.append(Codec.encode({"op": "pong", "id": request.get("id", "")}))
		"capabilities": incoming.append(Codec.encode({"op": "capabilities_result", "id": request.get("id", ""), "capabilities": {"apiVersion": "1.5", "operations": ["read", "replace_subscriptions", "subscribe"], "limits": {"maxMessageBytes": 1048576, "maxSubscriptionsPerClient": 500}, "subscriptions": {"pointCov": true, "viewGroups": true}}}))
		"replace_subscriptions", "subscribe": incoming.append(Codec.encode({"op": "subscriptions_replaced", "id": request.get("id", ""), "points": _snapshots(request.get("points", []))}))
	return true

func poll_frames() -> Array[PackedByteArray]:
	var result := incoming.duplicate()
	incoming.clear()
	return result

func push_cov(points: Array[Dictionary]) -> void:
	incoming.append(Codec.encode({"op": "cov", "sequence": 2, "timestamp": 1779648232328, "points": points}))

func push_malformed() -> void:
	incoming.append(PackedByteArray([0x81, 0xa2, 0x6f]))

func close() -> void:
	opened = false
	incoming.clear()

func _snapshots(points: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point in points:
		result.append({"point": String(point), "ok": true, "value": 55.0, "valueType": "baja:Double", "status": "{ok}", "timestamp": 1779648232328, "facets": {"units": "%"}})
	return result
