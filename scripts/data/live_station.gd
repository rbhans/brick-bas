class_name LiveStation
extends PointProvider

# Live points from a Niagara station, through the local read-only bridge
# (scripts/baskstream-bridge.mjs, built on the baskStream SDK). The bridge holds
# the station session (login, keepalive, reconnects, leased subscriptions);
# this side speaks small JSON frames to it over a local WebSocket, keeps the
# latest value of every watched point, and normalizes them for the game:
# point id = the point's slot ORD, source "niagara", quality from its status.
# Nothing here writes to a station.

const REQUEST_TIMEOUT_MS := 25000

var peer := WebSocketPeer.new()
var url := ""
var token := ""
var state := "offline"   # offline | bridge | hello | connecting | ready | reconnecting | error
var message := ""
var info: Dictionary = {}
var points: Dictionary = {}      # ORD -> normalized point
var watched: Array[String] = []
var _pending: Dictionary = {}    # request id -> {op, callback, sent}
var _serial := 0
var _profile: Dictionary = {}
var _password := ""

func provider_id() -> String:
	return "niagara"

func connection_state() -> String:
	return state

func is_up() -> bool:
	return state == "ready" or state == "reconnecting"

# Opens the bridge socket; the hello and the station login follow in poll().
func open(bridge_url: String, bridge_token: String, profile: Dictionary, password: String) -> bool:
	url = bridge_url
	token = bridge_token
	_profile = profile.duplicate()
	_password = password
	message = ""
	peer = WebSocketPeer.new()
	var error := peer.connect_to_url(url)
	if error != OK:
		_fail("Couldn't reach the local bridge (%s)." % error_string(error))
		return false
	state = "bridge"
	return true

func poll() -> void:
	if state == "offline":
		return
	peer.poll()
	match peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state == "bridge":
				state = "hello"
				request("hello", {"token": token}, _on_hello)
			while peer.get_available_packet_count() > 0:
				var packet := peer.get_packet()
				if peer.was_string_packet(): _handle(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if state not in ["offline", "error"]:
				var reason := peer.get_close_reason()
				_fail("The bridge closed the connection%s." % ("" if reason.is_empty() else " (%s)" % reason))
	_expire()

func _on_hello(reply: Dictionary) -> void:
	if state == "error":
		return
	if String(reply.get("op", "")) == "error":
		_fail(String(reply.get("message", "The bridge refused the game.")))
		return
	state = "connecting"
	request("connect", {"station": String(_profile.get("station_url", "")), "username": String(_profile.get("username", "")), "password": _password,
		"allowSelfSigned": String(_profile.get("tls_mode", "strict")) == "insecure", "name": String(_profile.get("name", ""))}, _on_connected)

func _on_connected(reply: Dictionary) -> void:
	_password = "" # the bridge keeps it in memory for reconnects; the game doesn't need it
	if state == "error":
		return
	if String(reply.get("op", "")) == "error":
		_fail(String(reply.get("message", "The station refused the connection.")))
		return
	info = reply.get("info", {})
	state = "ready"
	if not watched.is_empty(): watch(watched)

# Sends a request; `callback` gets the reply (or {"op": "error", ...}).
func request(op: String, fields: Dictionary = {}, callback: Callable = Callable()) -> void:
	_serial += 1
	var id := "%s-%d" % [op, _serial]
	var frame := fields.duplicate()
	frame.op = op
	frame.id = id
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN or peer.send_text(JSON.stringify(frame)) != OK:
		if callback.is_valid(): callback.call({"op": "error", "id": id, "code": "not_connected", "message": "Not connected to the bridge."})
		return
	_pending[id] = {"op": op, "callback": callback, "sent": Time.get_ticks_msec()}

func browse(ord: String, callback: Callable) -> void:
	request("browse", {"ord": ord}, callback)

func search(query: String, callback: Callable, limit: int = 120) -> void:
	request("search", {"query": query, "limit": limit}, callback)

func read(ords: Array, callback: Callable) -> void:
	request("read", {"points": ords}, callback)

func history(ord: String, hours: float, callback: Callable) -> void:
	request("history", {"ord": ord, "hours": hours}, callback)

func alarms(callback: Callable) -> void:
	request("alarms", {}, callback)

# Replaces the live set: the bridge's SDK watch follows it.
func watch(ords: Array) -> void:
	watched.assign(ords.map(func(o: Variant) -> String: return String(o)))
	for id in points.keys():
		if String(id) not in watched: points.erase(id)
	if not is_up(): return
	request("watch", {"points": watched}, func(reply: Dictionary) -> void:
		for entry in reply.get("points", []): _accept(entry)
		if bool(reply.get("truncated", false)): message = "Only the first 500 linked points are live.")

func subscribe(point_ids: Array[String]) -> bool:
	watch(point_ids)
	return true

func unsubscribe(_point_ids: Array[String]) -> void:
	watch([])

func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in points: out.append(points[id])
	return out

func discover(query: String = "") -> Array[Dictionary]:
	return snapshot().filter(func(p: Dictionary) -> bool: return query.is_empty() or String(p.point_id).contains(query))

func write_point(_point_id: String, _value: Variant) -> bool:
	return false # read-only, at the code level too

func close() -> void:
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify({"op": "disconnect", "id": "bye"}))
		peer.close(1000, "Game disconnected")
	state = "offline"
	_password = ""
	_pending.clear()

func _handle(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return
	var frame: Dictionary = parsed
	var id := String(frame.get("id", "")) if frame.get("id") != null else ""
	if not id.is_empty() and _pending.has(id):
		var entry: Dictionary = _pending[id]
		_pending.erase(id)
		var callback: Callable = entry.callback
		if callback.is_valid(): callback.call(frame)
		return
	match String(frame.get("op", "")):
		"values":
			for entry in frame.get("points", []): _accept(entry)
		"status":
			var status := String(frame.get("status", ""))
			if status == "reconnecting": state = "reconnecting"
			elif status == "connected" and state == "reconnecting": state = "ready"
			message = String(frame.get("message", "")) if frame.get("message") != null else ""

func _accept(entry: Variant) -> void:
	if not entry is Dictionary: return
	var point := normalize(entry)
	if point.is_empty() or String(point.point_id) not in watched: return
	points[String(point.point_id)] = point

func _expire() -> void:
	var now := Time.get_ticks_msec()
	for id in _pending.keys():
		var entry: Dictionary = _pending[id]
		if now - int(entry.sent) < REQUEST_TIMEOUT_MS: continue
		_pending.erase(id)
		var callback: Callable = entry.callback
		if callback.is_valid(): callback.call({"op": "error", "id": id, "code": "timeout", "message": "The bridge didn't answer in time."})
		if String(entry.op) in ["hello", "connect"]: _fail("The station didn't answer in time.")

func _fail(text: String) -> void:
	if state == "error":
		return
	message = text
	state = "error"
	_password = ""
	# Last readings stay on screen but no longer count as current.
	for id in points:
		points[id] = points[id].duplicate()
		points[id].quality_flags = ["stale"]
	# Detach the pending requests first: their callbacks may land back here.
	var pending := _pending
	_pending = {}
	for id in pending:
		var callback: Callable = pending[id].callback
		if callback.is_valid(): callback.call({"op": "error", "id": id, "code": "connection_closed", "message": text})

# A bridge value as a game point: the shape PointStore, bindings and trends use.
static func normalize(entry: Dictionary) -> Dictionary:
	var id := String(entry.get("point", ""))
	if id.is_empty(): return {}
	var value: Variant = entry.get("value")
	var kind := String(entry.get("valueType", "")).to_lower() if entry.get("valueType") != null else ""
	var value_type := "number"
	if value is bool or kind.contains("bool"): value_type = "bool"
	elif value is String or kind.contains("enum"): value_type = "enum"
	if value is int: value = float(value)
	var status := String(entry.get("status", "")) if entry.get("status") != null else ""
	var flags: Array[String] = []
	var lower := status.to_lower()
	if not bool(entry.get("ok", false)) or value == null: flags.append("unknown")
	for flag in ["fault", "down", "stale", "disabled"]:
		if lower.contains(flag): flags.append(flag)
	if flags.is_empty(): flags.append("good")
	if lower.contains("overridden") or lower.contains("@"): flags.append("overridden")
	if lower.contains("alarm"): flags.append("alarm")
	var stamp := float(entry.get("timestamp", 0.0)) if (entry.get("timestamp") is float or entry.get("timestamp") is int) else 0.0
	return {"point_id": id, "value": value, "value_type": value_type, "unit": String(entry.get("units", "")) if entry.get("units") != null else "",
		"source_id": "niagara", "quality_flags": flags, "source_timestamp": stamp / 1000.0, "received_at": Time.get_unix_time_from_system(),
		"original_status": status, "display": String(entry.get("display", "")) if entry.get("display") != null else ""}
