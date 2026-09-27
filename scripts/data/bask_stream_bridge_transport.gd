class_name BaskStreamBridgeTransport
extends RefCounted

const Codec := preload("res://scripts/data/message_pack.gd")
const BRIDGE_URL := "ws://127.0.0.1:8789/baskstream"

var peer := WebSocketPeer.new()
var status := "offline"
var station_url := ""
var username := ""
var password := ""
var tls_mode := "strict"
var connect_sent := false
var connection_request_id := "brick-bas-connect"
var health: Dictionary = {}
var error_message := ""
var incoming: Array[PackedByteArray] = []

func configure(profile: Dictionary, secret: String) -> void:
	station_url = String(profile.get("station_url", "")).strip_edges()
	username = String(profile.get("username", "")).strip_edges()
	password = secret
	tls_mode = "insecure" if String(profile.get("tls_mode", "strict")) == "insecure" else "strict"

func open() -> bool:
	if station_url.is_empty() or username.is_empty() or password.is_empty():
		error_message = "Station URL, username and password are required."
		status = "error"
		return false
	peer = WebSocketPeer.new()
	connect_sent = false
	health.clear()
	error_message = ""
	incoming.clear()
	status = "bridge_connecting"
	var error := peer.connect_to_url(BRIDGE_URL)
	if error != OK:
		error_message = "Local baskStream bridge could not start: " + error_string(error)
		status = "error"
		return false
	return true

func state() -> String:
	return status

func send_binary(frame: PackedByteArray) -> bool:
	if status != "ready" or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	var decoded := Codec.decode(frame)
	if not decoded.ok or not decoded.value is Dictionary:
		error_message = "Godot produced an invalid baskStream MessagePack request."
		status = "error"
		return false
	return peer.send_text(JSON.stringify(decoded.value)) == OK

func poll_frames() -> Array[PackedByteArray]:
	peer.poll()
	match peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connect_sent:
				connect_sent = true
				status = "station_connecting"
				var request := {
					"op": "connect_station",
					"id": connection_request_id,
					"stationUrl": station_url,
					"username": username,
					"password": password,
					"tlsMode": tls_mode,
				}
				if peer.send_text(JSON.stringify(request)) != OK:
					error_message = "Could not send the station authentication request."
					status = "error"
			while peer.get_available_packet_count() > 0:
				var packet := peer.get_packet()
				if not peer.was_string_packet():
					error_message = "Local bridge returned an unexpected binary frame."
					status = "error"
					continue
				_handle_bridge_message(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSING:
			if status != "error": status = "closing"
		WebSocketPeer.STATE_CLOSED:
			if status not in ["error", "offline"]:
				var reason := peer.get_close_reason()
				error_message = reason if not reason.is_empty() else "Local bridge connection closed."
				status = "offline"
	var result := incoming.duplicate()
	incoming.clear()
	return result

func close() -> void:
	if peer.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
		peer.close(1000, "Brick/BAS disconnected")
	status = "offline"
	connect_sent = false
	incoming.clear()

func clear_secret() -> void:
	password = ""

func _handle_bridge_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		error_message = "Local bridge returned invalid JSON."
		status = "error"
		return
	var message: Dictionary = parsed
	var operation := String(message.get("op", ""))
	if operation == "station_connected" and String(message.get("id", "")) == connection_request_id:
		health = message.get("health", {}).duplicate(true)
		status = "ready"
		return
	if operation == "station_closed":
		error_message = "Station WebSocket closed."
		status = "offline"
		return
	if operation == "error" and String(message.get("id", "")) == connection_request_id:
		error_message = String(message.get("message", message.get("code", "Station connection failed.")))
		status = "error"
		return
	incoming.append(Codec.encode(message))
