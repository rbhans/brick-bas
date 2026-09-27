class_name BaskStreamProvider
extends PointProvider

const Codec := preload("res://scripts/data/message_pack.gd")
var state := "offline"
var transport: RefCounted
var capabilities: Dictionary = {}
var points: Dictionary = {}
var request_serial := 1
var protocol_error := ""
var desired_points: Array[String] = []
var handshake_sent := false

func provider_id() -> String:
	return "bask_stream"

func connection_state() -> String:
	return state

func attach_transport(value: RefCounted) -> bool:
	transport = value
	handshake_sent = false
	if not transport.open():
		state = "offline"
		return false
	state = "connecting"
	# The fixture becomes ready synchronously; a real WebSocket completes over
	# later frames. Two polls keep the fixture deterministic without assuming a
	# production socket is already open.
	poll()
	poll()
	return state not in ["offline", "protocol_error", "revoked"]

func poll() -> void:
	if transport == null: return
	var frames: Array[PackedByteArray] = transport.poll_frames()
	var transport_state := String(transport.state())
	if not handshake_sent and transport_state == "ready":
		handshake_sent = _send("ping") and _send("capabilities")
		if handshake_sent: state = "handshaking"
		# Synchronous fixtures queue the responses immediately.
		frames.append_array(transport.poll_frames())
	for frame in frames:
		var decoded := Codec.decode(frame)
		if not decoded.ok or not decoded.value is Dictionary:
			protocol_error = String(decoded.get("error", "Invalid binary MessagePack map."))
			state = "protocol_error"
			continue
		_handle(decoded.value)
	if state not in ["protocol_error", "revoked"]:
		if transport_state == "error":
			protocol_error = String(transport.get("error_message"))
			state = "connection_error"
		elif transport_state == "offline":
			state = "offline"
		elif not handshake_sent:
			state = transport_state

func discover(query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for point in snapshot():
		if query.is_empty() or String(point.point_id).contains(query): result.append(point)
	return result

func snapshot() -> Array[Dictionary]:
	poll()
	var result: Array[Dictionary] = []
	var ids: Array = points.keys()
	ids.sort()
	for id in ids: result.append(points[id].duplicate(true))
	return result

func subscribe(point_ids: Array[String]) -> bool:
	desired_points = point_ids.duplicate()
	if state != "ready" or not capabilities.get("operations", []).has("replace_subscriptions"): return false
	return _send("replace_subscriptions", {"group": "brick-bas:active-view", "points": point_ids, "leaseSec": 300})

func unsubscribe(_point_ids: Array[String]) -> void:
	desired_points.clear()
	if state == "ready": _send("release_subscriptions", {"group": "brick-bas:active-view"})

func reconnect() -> bool:
	if transport == null: return false
	transport.close()
	capabilities.clear()
	protocol_error = ""
	handshake_sent = false
	state = "reconnecting"
	if not transport.open():
		state = "offline"
		return false
	poll()
	if state == "ready" and not desired_points.is_empty():
		_send("replace_subscriptions", {"group": "brick-bas:active-view", "points": desired_points, "leaseSec": 300})
		poll()
	return state == "ready"

func write_point(_point_id: String, _value: Variant) -> bool:
	# Initial live integration is intentionally read-only, including at code level.
	return false

func _send(operation: String, fields: Dictionary = {}) -> bool:
	if transport == null: return false
	var request := fields.duplicate(true)
	request.op = operation
	request.id = "%s-%04d" % [operation, request_serial]
	request_serial += 1
	return transport.send_binary(Codec.encode(request))

func _handle(frame: Dictionary) -> void:
	match String(frame.get("op", "")):
		"pong": state = "ready"
		"capabilities_result":
			capabilities = frame.get("capabilities", {}).duplicate(true)
			state = "ready"
		"read_result", "subscribed", "subscriptions_replaced", "cov":
			for entry in frame.get("points", []):
				var normalized := _normalize(entry, frame.get("timestamp", 0))
				if not normalized.is_empty(): points[normalized.point_id] = normalized
		"subscriptions_revoked":
			for point in frame.get("points", []): points.erase(String(point))
		"session_revoked": state = "revoked"
		"error": protocol_error = String(frame.get("message", "baskStream error"))

func _normalize(entry: Dictionary, frame_timestamp: Variant) -> Dictionary:
	var id := String(entry.get("point", ""))
	if id.is_empty() or not entry.has("value"): return {}
	var status_text := String(entry.get("status", ""))
	var quality: Array[String] = []
	quality.append("good" if bool(entry.get("ok", true)) and (status_text.is_empty() or status_text.contains("ok")) else "fault")
	if status_text.to_lower().contains("stale"):
		quality.clear()
		quality.append("stale")
	var source_ms := float(entry.get("timestamp", frame_timestamp))
	return {"point_id": id, "value": entry.value, "value_type": String(entry.get("valueType", "unknown")), "unit": String(entry.get("facets", {}).get("units", "")), "source_id": "niagara", "quality_flags": quality, "source_timestamp": source_ms / 1000.0 if source_ms > 10000000000.0 else source_ms, "received_at": Time.get_unix_time_from_system(), "original_status": status_text}
