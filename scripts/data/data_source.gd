class_name DataSource
extends RefCounted

# Which PointProvider feeds the point store: the building simulation (the
# default, and the only option in the web build) or a live Niagara station
# through the local read-only bridge (desktop; needs Node.js). The bridge is
# built on the baskStream SDK and started on demand with a random port and a
# one-time token; it exits when the game does. Nothing here writes to a station.

const DemoProviderScript := preload("res://scripts/data/demo_provider.gd")
const BRIDGE_SCRIPT := "res://scripts/baskstream-bridge.mjs"
const DEMO_STATION_SCRIPT := "res://tools/demo_station.mjs"
const CONNECT_TIMEOUT_MS := 30000
const ALARM_POLL_S := 30.0

signal changed

var game: Node
var demo_only := OS.has_feature("web")
var provider: PointProvider
var live: LiveStation
var busy := false
var status := "Simulation"
var detail := "The simulated building is running."
var station_alarms: Array = []
var _bridge: Dictionary = {}        # {pid, stdio, url, token}
var _demo_station: Dictionary = {}  # {pid, stdio, url, user, password}
var _alarm_timer := 0.0
var _lost := false
var _generation := 0 # bumped when the source changes, so a slow connect can't land late

func _init(owner: Node) -> void:
	game = owner
	provider = DemoProviderScript.new(owner.sim)

func is_demo() -> bool:
	return provider.provider_id() == "demo"

func authority() -> String:
	return "demo" if is_demo() else "niagara"

func is_live() -> bool:
	return live != null and provider == live

func close() -> void:
	if live != null: live.close()
	live = null
	for process in [_bridge, _demo_station]:
		if int(process.get("pid", -1)) > 0 and OS.is_process_running(int(process.pid)): OS.kill(int(process.pid))
	_bridge = {}
	_demo_station = {}

func use_demo() -> void:
	_generation += 1
	if live != null: live.close()
	live = null
	station_alarms.clear()
	provider = DemoProviderScript.new(game.sim)
	game.points.replace_snapshot(provider.snapshot())
	game.history.mark_boundary("source:demo", game.history_time())
	_announce("Simulation", "The simulated building is running. Linked station points stay saved for when you reconnect.")

# Every 0.2 s from the game: connection health and the station's alarms.
func poll() -> void:
	if not is_live():
		return
	if live.state == "error" and not _lost:
		_lost = true
		_announce("Connection lost", live.message + " Values hold their last reading. Reconnect, or switch back to the simulation.")
	elif live.state == "reconnecting":
		_announce("Reconnecting…", live.message)
	elif live.state == "ready" and status != "Connected · %s" % String(live.info.get("name", "station")):
		_lost = false
		_announce_connected()
	_alarm_timer -= 0.2
	if _alarm_timer <= 0.0 and live.state == "ready":
		_alarm_timer = ALARM_POLL_S
		live.alarms(func(reply: Dictionary) -> void:
			if String(reply.get("op", "")) == "alarms_result": station_alarms = reply.get("alarms", []))

func saved_profile() -> Dictionary:
	if not game.model.connections.is_empty():
		return game.model.connections[0].duplicate(true)
	return {"id": "local-station", "name": "Niagara station", "station_url": "", "username": "", "tls_mode": "strict"}

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
	if live == null:
		return
	live.watch(niagara_point_ids())
	if is_live() and live.state == "ready": _announce_connected()

# Logs in through the bridge. The password goes to the bridge and is never
# saved; the profile (address, user, certificate choice) saves with the build.
func connect_station(profile: Dictionary, password: String, test_only: bool = false) -> bool:
	if demo_only:
		_announce("Simulation", "The browser edition runs on the simulated building only.")
		return false
	if busy:
		return false
	if game.job != null:
		_announce("Simulation", "Career jobs run on the simulated building. Leave the job to connect to a station.")
		return false
	var safe := {
		"id": String(profile.get("id", "local-station")).strip_edges(),
		"name": String(profile.get("name", "Niagara station")).strip_edges(),
		"station_url": String(profile.get("station_url", "")).strip_edges(),
		"username": String(profile.get("username", "")).strip_edges(),
		"tls_mode": "insecure" if String(profile.get("tls_mode", "strict")) == "insecure" else "strict",
	}
	if safe.id.is_empty(): safe.id = "local-station"
	if safe.station_url.is_empty() or safe.username.is_empty() or password.is_empty():
		_announce("Connection details required", "Station address, username and password are needed.")
		return false
	# The address is saved with the build, so it mustn't carry a login.
	var address: String = safe.station_url
	if address.contains("://"): address = address.substr(address.find("://") + 3)
	if address.get_slice("/", 0).contains("@"):
		_announce("Remove the login from the address", "Put the username and password in their own fields, not in the station address.")
		return false
	busy = true
	_announce("Starting the bridge", "Launching the local read-only bridge (Node.js).")
	if not await _ensure_bridge():
		busy = false
		_announce("Bridge unavailable", "Couldn't start the bridge. It needs Node.js 20+ and `npm install` in the project folder.")
		return false
	if not test_only: game.model.connections.assign([safe])
	var generation := _generation
	var candidate := LiveStation.new()
	candidate.open(String(_bridge.url), String(_bridge.token), safe, password)
	_announce("Logging in", "Niagara web login and baskStream capabilities…")
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and candidate.state not in ["ready", "error"]:
		candidate.poll()
		await game.get_tree().process_frame
	busy = false
	# The player moved on while we waited (back to the simulation, a career job).
	if generation != _generation or game.job != null:
		candidate.close()
		_announce("Connection cancelled", "The data source changed while connecting.")
		return false
	if candidate.state != "ready":
		var reason := candidate.message if not candidate.message.is_empty() else "The station didn't answer in time."
		candidate.close()
		_announce("Connection failed", reason)
		return false
	if test_only:
		_announce("Connection test passed", "Logged in · baskStream API %s · read-only." % String(candidate.info.get("apiVersion", "?")))
		candidate.close()
		return true
	if live != null: live.close()
	live = candidate
	provider = candidate
	_lost = false
	_alarm_timer = 0.0
	refresh_subscriptions()
	var cleared: Array[Dictionary] = []
	game.points.replace_snapshot(cleared)
	game.history.mark_boundary("source:niagara:%s" % safe.id, game.history_time())
	_announce_connected()
	return true

func _announce_connected() -> void:
	var linked := niagara_point_ids().size()
	_announce("Connected · %s" % String(live.info.get("name", "station")), "baskStream API %s · %d linked point%s · read-only%s" % [String(live.info.get("apiVersion", "?")), linked, "" if linked == 1 else "s", " · writes are off on the station too" if not bool(live.info.get("writesEnabled", false)) else ""])

# A stand-in station on this computer (tools/demo_station.mjs) so Live mode
# can be tried without a Niagara box. Returns {url, user, password} or {}.
func start_demo_station() -> Dictionary:
	if demo_only:
		return {}
	if int(_demo_station.get("pid", -1)) > 0 and OS.is_process_running(int(_demo_station.pid)):
		return _demo_station
	var started := await _spawn(DEMO_STATION_SCRIPT, ["--port=0", "--owned"])
	if started.is_empty():
		return {}
	_demo_station = started
	_demo_station.user = String(started.reply.get("user", ""))
	_demo_station.password = String(started.reply.get("password", ""))
	_demo_station.url = String(started.reply.get("url", ""))
	return _demo_station

func _ensure_bridge() -> bool:
	if int(_bridge.get("pid", -1)) > 0 and OS.is_process_running(int(_bridge.pid)):
		return true
	var token := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(18)).replace("/", "_").replace("+", "-")
	# Through the environment, not the command line (which other users can list).
	OS.set_environment("BRICK_BAS_BRIDGE_TOKEN", token)
	var started := await _spawn(BRIDGE_SCRIPT, ["--port=0", "--owned"])
	OS.unset_environment("BRICK_BAS_BRIDGE_TOKEN")
	if started.is_empty():
		return false
	_bridge = started
	_bridge.token = token
	_bridge.url = String(started.reply.get("url", ""))
	return not String(_bridge.url).is_empty()

# Starts a Node script with pipes and waits for its first stdout line (JSON).
# The script exits when our end of its stdin closes (the game quits).
func _spawn(script: String, arguments: Array) -> Dictionary:
	var node := _node_path()
	var script_path := ProjectSettings.globalize_path(script)
	if node.is_empty() or not FileAccess.file_exists(script_path):
		return {}
	var args := PackedStringArray([script_path])
	args.append_array(PackedStringArray(arguments))
	var process := OS.execute_with_pipe(node, args, false)
	if process.is_empty() or int(process.get("pid", -1)) <= 0:
		return {}
	var stdio: FileAccess = process.stdio
	var text := ""
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		var chunk := stdio.get_buffer(4096)
		if not chunk.is_empty():
			text += chunk.get_string_from_utf8()
			var newline := text.find("\n")
			if newline >= 0:
				var parsed: Variant = JSON.parse_string(text.left(newline))
				if parsed is Dictionary and bool(parsed.get("ready", false)):
					return {"pid": int(process.pid), "stdio": stdio, "stderr": process.get("stderr"), "reply": parsed}
				break
		if not OS.is_process_running(int(process.pid)):
			break
		await game.get_tree().process_frame
	if OS.is_process_running(int(process.pid)): OS.kill(int(process.pid))
	return {}

static func _node_path() -> String:
	var configured := OS.get_environment("BRICK_BAS_NODE")
	for candidate in [configured, "/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]:
		if not String(candidate).is_empty() and FileAccess.file_exists(String(candidate)):
			return String(candidate)
	var output: Array = []
	if OS.execute("/usr/bin/env", PackedStringArray(["which", "node"]), output) == 0 and not output.is_empty():
		var found := String(output[0]).strip_edges()
		if not found.is_empty(): return found
	return ""

func _announce(title: String, message: String) -> void:
	status = title
	detail = message
	changed.emit()
