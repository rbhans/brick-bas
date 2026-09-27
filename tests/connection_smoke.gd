extends SceneTree

# Desktop-only: drives the read-only Niagara/baskStream path end to end against
# tests/mock_baskstream_station.mjs (start it first on port 8790).

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var app: Node = load("res://scripts/game.gd").new()
	root.add_child(app)
	await process_frame
	app.session_ui.hide()
	app.sound_enabled = false
	var profile := {"id": "mock-station", "name": "Mock school station", "station_url": "http://127.0.0.1:8790", "username": "operator", "tls_mode": "strict"}
	await app.data.connect_station(profile, "demo-password", false)
	print("CONNECTION_STATE ", app.data.status, " · ", app.data.detail)
	var failures: Array[String] = []
	if app.data.provider.provider_id() != "bask_stream" or app.data.provider.connection_state() != "ready":
		failures.append("authenticated bridge did not become the active provider")
	if app.model.connections.size() != 1 or app.model.connections[0].has("password"):
		failures.append("safe connection profile did not persist without the password")
	var ahu := String(app.model.objects_of(["ahu"])[0].id)
	app.attach_binding(ahu, "fan", {"source": "niagara", "connection_id": "mock-station", "point_id": "slot:/Mock/FanSpeed", "mapping": "number", "input_min": 0.0, "input_max": 100.0, "unit": "%", "enum_levels": {}, "invert": false, "command_based": false})
	await create_timer(0.15).timeout
	var sample: Dictionary = app.animation_sample(ahu, "fan")
	if not sample.get("known", false) or not is_equal_approx(float(sample.get("level", 0.0)), 0.625):
		failures.append("live snapshot did not drive the bound fan animation")
	app.data.use_demo()
	if not app.data.is_demo() or not String(app.data.status).begins_with("Demo"):
		failures.append("disconnect did not return explicitly to demo simulation")
	print("CONNECTION_SMOKE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
