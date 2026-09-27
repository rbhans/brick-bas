class_name DataSource
extends RefCounted

# Owns which PointProvider feeds the point store: the offline demo simulation
# (default, and the only option in the web build) or the desktop-only,
# read-only Niagara/baskStream bridge. Live integration is kept but parked
# until the baskStream SDK is final; nothing here writes to a station.

const DemoProviderScript := preload("res://scripts/data/demo_provider.gd")
const BaskStreamProviderScript := preload("res://scripts/data/bask_stream_provider.gd")
const BaskFixtureScript := preload("res://scripts/data/bask_stream_fixture_transport.gd")
const BaskBridgeTransportScript := preload("res://scripts/data/bask_stream_bridge_transport.gd")

signal changed

var game: Node
var demo_only := OS.has_feature("web")
var provider: PointProvider
var live_transport: RefCounted
var bridge_process_id := -1
var busy := false
var status := "Demo simulation"
var detail := "Offline building model and simulated BAS points are active."

func _init(owner: Node) -> void:
	game = owner
	provider = DemoProviderScript.new(owner.sim)

func is_demo() -> bool:
	return provider.provider_id() == "demo"

func authority() -> String:
	return "demo" if is_demo() else "niagara"

func close() -> void:
	if live_transport != null:
		live_transport.close()
		if live_transport.has_method("clear_secret"): live_transport.clear_secret()
		live_transport = null
	if bridge_process_id > 0 and OS.is_process_running(bridge_process_id):
		OS.kill(bridge_process_id)
	bridge_process_id = -1

func use_demo() -> void:
	if live_transport != null:
		live_transport.close()
		if live_transport.has_method("clear_secret"): live_transport.clear_secret()
		live_transport = null
	provider = DemoProviderScript.new(game.sim)
	game.points.apply_updates(provider.snapshot())
	game.history.mark_boundary("source:demo", game.sim.sim_seconds)
	_announce("Demo simulation", "Offline building data is active. Saved Niagara references stay isolated and never borrow demo values.")

func poll() -> void:
	if not is_demo() and live_transport != null and provider.connection_state() not in ["ready", "handshaking", "connecting", "station_connecting", "bridge_connecting"] and status.begins_with("Connected"):
		_announce("Connection lost", String(provider.protocol_error) if not String(provider.protocol_error).is_empty() else "The station stream closed. Reconnect or use the demo simulation.")

func saved_profile() -> Dictionary:
	if not game.model.connections.is_empty():
		return game.model.connections[0].duplicate(true)
	return {"id": "local-station", "name": "Local Niagara station", "station_url": "", "username": "", "tls_mode": "strict"}

func niagara_point_ids() -> Array[String]:
	var ids: Array[String] = []
	for item in game.model.objects:
		for binding in item.properties.get("bindings", {}).values():
			if String(binding.get("source", "")) != "niagara": continue
			var point_id := String(binding.get("point_id", ""))
			if not point_id.is_empty() and point_id not in ids: ids.append(point_id)
	ids.sort()
	return ids

func refresh_subscriptions() -> void:
	if is_demo() or provider.connection_state() != "ready":
		return
	var ids := niagara_point_ids()
	if ids.is_empty(): provider.unsubscribe([])
	else: provider.subscribe(ids)

func toggle_fixture() -> void:
	if demo_only: return
	if not is_demo():
		use_demo()
		return
	var live := BaskStreamProviderScript.new()
	var fixture := BaskFixtureScript.new()
	if not live.attach_transport(fixture):
		_announce("Fixture failed", "Niagara protocol fixture handshake failed.")
		return
	var ids := niagara_point_ids()
	if ids.is_empty(): ids.append("station:|slot:/AHU/FanSpeed")
	live.subscribe(ids)
	live.snapshot()
	provider = live
	live_transport = fixture
	game.history.mark_boundary("source:niagara-fixture", game.sim.sim_seconds)
	_announce("Niagara protocol fixture", "Binary MessagePack and COV are active without contacting a station.")

func connect_station(profile: Dictionary, password: String, test_only: bool = false) -> void:
	if demo_only:
		_announce("Demo simulation", "This edition uses local demo data only.")
		return
	if busy:
		return
	var safe := {
		"id": String(profile.get("id", "local-station")).strip_edges(),
		"name": String(profile.get("name", "Niagara station")).strip_edges(),
		"station_url": String(profile.get("station_url", "")).strip_edges(),
		"username": String(profile.get("username", "")).strip_edges(),
		"tls_mode": "insecure" if String(profile.get("tls_mode", "strict")) == "insecure" else "strict",
	}
	if safe.id.is_empty(): safe.id = "local-station"
	if safe.station_url.is_empty() or safe.username.is_empty() or password.is_empty():
		_announce("Connection details required", "Station URL, username and password are required. The current data source remains active.")
		return
	game.model.connections.assign([safe])
	busy = true
	_announce("Starting secure connection", "Launching the local read-only bridge. The password stays in memory only.")
	if not await _ensure_bridge():
		busy = false
		_announce("Bridge unavailable", "Node.js could not start the local bridge. The current data source remains active.")
		return
	var transport := BaskBridgeTransportScript.new()
	transport.configure(safe, password)
	var live := BaskStreamProviderScript.new()
	if not live.attach_transport(transport):
		busy = false
		_announce("Connection failed", String(transport.error_message) + " The current data source remains active.")
		return
	_announce("Authenticating", "Niagara SCRAM login and /stream/health verification are in progress.")
	var deadline := Time.get_ticks_msec() + 26000
	while Time.get_ticks_msec() < deadline:
		live.poll()
		if live.connection_state() == "ready" and not live.capabilities.is_empty(): break
		if live.connection_state() in ["connection_error", "protocol_error", "revoked", "offline"]: break
		await game.get_tree().process_frame
	var connected := live.connection_state() == "ready" and not live.capabilities.is_empty()
	if not connected:
		var message := String(transport.error_message)
		if message.is_empty(): message = live.protocol_error
		if message.is_empty(): message = "Connection timed out before capabilities were received."
		transport.close()
		transport.clear_secret()
		busy = false
		_announce("Connection failed", message + " The current data source remains active.")
		return
	var health: Dictionary = transport.health
	if health.has("service") and String(health.service) != "BASkStreamService":
		transport.close()
		transport.clear_secret()
		busy = false
		_announce("Unexpected service", "/stream/health did not identify BASkStreamService. The current data source remains active.")
		return
	var api_version := String(live.capabilities.get("apiVersion", "unknown"))
	if test_only:
		transport.close()
		transport.clear_secret()
		busy = false
		_announce("Connection test passed", "Authenticated, health checked and received baskStream API %s capabilities. The current data source remains active." % api_version)
		return
	if live_transport != null:
		live_transport.close()
		if live_transport.has_method("clear_secret"): live_transport.clear_secret()
	live_transport = transport
	provider = live
	refresh_subscriptions()
	game.points.apply_updates(provider.snapshot())
	game.history.mark_boundary("source:niagara:%s" % safe.id, game.sim.sim_seconds)
	busy = false
	_announce("Connected · %s" % safe.name, "Health verified · baskStream API %s · %d active point reference(s) · read-only" % [api_version, niagara_point_ids().size()])

func _ensure_bridge() -> bool:
	if demo_only: return false
	if bridge_process_id > 0 and OS.is_process_running(bridge_process_id):
		return true
	var script_path := ProjectSettings.globalize_path("res://scripts/baskstream-bridge.mjs")
	if not FileAccess.file_exists(script_path):
		return false
	bridge_process_id = OS.create_process("/usr/bin/env", PackedStringArray(["node", script_path]))
	if bridge_process_id <= 0:
		return false
	await game.get_tree().create_timer(0.45).timeout
	return true

func _announce(title: String, message: String) -> void:
	status = title
	detail = message if not demo_only else "Local demo simulation"
	changed.emit()
