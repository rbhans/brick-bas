class_name BaskStreamWebSocketTransport
extends RefCounted

var peer := WebSocketPeer.new()
var status := "offline"
var configured_url := ""
var configured_cookie := ""
var configured_authorization := ""
var configured_certificate_path := ""

func open_authenticated(station_https_url: String, session_cookie: String, authorization: String = "", trusted_certificate_path: String = "") -> Error:
	if not station_https_url.begins_with("https://") or session_cookie.is_empty():
		return ERR_INVALID_PARAMETER
	configured_url = station_https_url
	configured_cookie = session_cookie
	configured_authorization = authorization
	configured_certificate_path = trusted_certificate_path
	var url := station_https_url.trim_suffix("/").replace("https://", "wss://") + "/stream"
	var headers := PackedStringArray(["Cookie: " + session_cookie])
	if not authorization.is_empty(): headers.append("Authorization: " + authorization)
	peer.handshake_headers = headers
	var tls_options := TLSOptions.client()
	if not trusted_certificate_path.is_empty():
		var certificate := X509Certificate.new()
		var error := certificate.load(trusted_certificate_path)
		if error != OK: return error
		tls_options = TLSOptions.client(certificate)
	status = "connecting"
	return peer.connect_to_url(url, tls_options)

func open() -> bool:
	if peer.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]: return true
	peer = WebSocketPeer.new()
	return open_authenticated(configured_url, configured_cookie, configured_authorization, configured_certificate_path) == OK

func state() -> String:
	return status

func send_binary(frame: PackedByteArray) -> bool:
	return peer.get_ready_state() == WebSocketPeer.STATE_OPEN and peer.put_packet(frame) == OK

func poll_frames() -> Array[PackedByteArray]:
	peer.poll()
	match peer.get_ready_state():
		WebSocketPeer.STATE_OPEN: status = "ready"
		WebSocketPeer.STATE_CONNECTING: status = "connecting"
		WebSocketPeer.STATE_CLOSING: status = "closing"
		WebSocketPeer.STATE_CLOSED: status = "offline"
	var frames: Array[PackedByteArray] = []
	while peer.get_available_packet_count() > 0:
		var packet := peer.get_packet()
		if not peer.was_string_packet(): frames.append(packet)
	return frames

func close() -> void:
	peer.close()
	status = "offline"
