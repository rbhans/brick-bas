extends SceneTree

# Live mode end to end, through the real game, bridge, SDK and the demo station
# (tools/demo_station.mjs): the game starts both Node processes itself, logs in,
# browses and searches the station, auto-maps a VAV's points, and the linked
# equipment animates and reads from live values. Needs Node.js and npm install.
#   Godot --headless --path . --script res://tests/live_station.gd

var game: Node
var failures: Array[String] = []
var checks := 0

func _init() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func until(condition: Callable, limit_ms: int = 15000) -> bool:
	var deadline := Time.get_ticks_msec() + limit_ms
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await process_frame
	return condition.call()

func reply_of(call: Callable) -> Dictionary:
	var box := {}
	call.call(func(reply: Dictionary) -> void: box.merge(reply))
	await until(func() -> bool: return not box.is_empty())
	return box

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	game.start_new_game("studio", false)
	await process_frame
	var station: Dictionary = await game.data.start_demo_station()
	expect(not station.is_empty() and String(station.url).begins_with("http://127.0.0.1:"), "the game starts the demo station (%s)" % str(station.get("url", "")))
	if station.is_empty():
		_done()
		return
	var profile := {"id": "demo", "name": "Demo station", "station_url": station.url, "username": station.user, "tls_mode": "strict"}
	expect(not await game.data.connect_station(profile, "wrong-password"), "a wrong password is refused")
	expect(game.data.status == "Connection failed" and game.data.is_demo(), "and the simulation keeps running (%s: %s)" % [game.data.status, game.data.detail])
	expect(await game.data.connect_station(profile, String(station.password), true), "connection test passes")
	expect(game.data.is_demo(), "a test doesn't switch the data source")
	expect(await game.data.connect_station(profile, String(station.password)), "connects through the bridge and SDK (%s)" % game.data.detail)
	expect(game.data.is_live() and not game.data.is_demo() and game.data.authority() == "niagara", "live data is the source")
	expect(game.model.connections.size() == 1 and not game.model.connections[0].has("password"), "the profile saves, the password doesn't")
	var live: LiveStation = game.data.live
	var root_reply := await reply_of(func(done: Callable) -> void: live.browse("slot:/", done))
	expect((root_reply.get("children", []) as Array).map(func(n: Dictionary) -> String: return String(n.name)) == ["Drivers", "Services"], "browses the station")
	var found := await reply_of(func(done: Callable) -> void: live.search("DamperPos", done))
	expect((found.get("nodes", []) as Array).size() == 3, "searches the station")
	# Auto-map the Workshop VAV from a VAV controller's folder, through the details panel.
	var vav := String(game.model.objects_of(["vav"])[0].id)
	game.select(vav)
	var details: Control = game.hud.details
	details.open(vav)
	expect(details.visible and details.tabs.current_tab == 2, "on a live station a VAV's details open on the station page")
	details._location = "slot:/Drivers/BacnetNetwork/VAV_101"
	details._auto_map()
	expect(await until(func() -> bool: return String(game.binding_for(vav, "space_temp").get("source", "")) == "niagara"), "auto-map links the VAV's points")
	var links := {}
	for role in ["damper", "airflow", "heating_coil", "space_temp"]: links[role] = String(game.binding_for(vav, role).get("point_id", ""))
	expect(String(links.damper).ends_with("/DamperPos") and String(links.airflow).ends_with("/AirflowCFM") and String(links.heating_coil).ends_with("/ReheatVlvPos") and String(links.space_temp).ends_with("/SpaceTemp"), "each role got the right point (%s)" % str(links))
	expect(await until(func() -> bool: return game.points.get_point(String(links.damper)).has("value")), "linked points stream live values")
	var point: Dictionary = game.points.get_point(String(links.damper))
	expect(String(point.source_id) == "niagara" and point.quality_flags == ["good"] and String(point.unit) == "%", "live values carry source, quality and units")
	var sample: Dictionary = game.animation_sample(vav, "damper")
	expect(bool(sample.known) and float(sample.level) > 0.0, "the VAV damper animates from the live point (%s)" % str(sample))
	expect(String(game.equipment.readout(game.model.find_object(vav))).contains("Damper"), "the card reads the live points")
	var room := String(game.topology.terminals[vav].zone_id)
	var temp: float = game.live_room_temp_c(room)
	expect(is_finite(temp) and temp > 20.0 and temp < 26.0, "the room's temperature comes from the station, °F converted (%.1f °C)" % temp)
	expect(game.inspect(vav).trends.size() >= 2, "the card trends the linked points")
	expect(await until(func() -> bool: return game.history.get_series(String(links.damper)).size() > 50), "the trend starts from the station's own history (%d samples)" % game.history.get_series(String(links.damper)).size())
	var series: Array = game.history.get_series(String(links.damper))
	var steps: Dictionary = {}
	for index in range(1, mini(series.size(), 40)): steps[roundi(float(series[index].time) - float(series[index - 1].time))] = true
	expect(steps.keys() == [120], "trend times keep their precision (bucket steps %s s)" % str(steps.keys()))
	game.data._alarm_timer = 0.0
	game.data.poll()
	expect(await until(func() -> bool: return game.data.station_alarms.size() == 2), "station alarms are read")
	expect(game.owner_of_point("slot:/Drivers/BacnetNetwork/VAV_101/points/SpaceTemp") == vav, "an alarm finds its linked equipment")
	expect(not live.write_point(String(links.damper), 0.0) and not game.adjust_thermostat(String(game.model.objects_of(["tstat"])[0].id), 1.0), "nothing writes to the station")
	# A connect the player abandons (back to the simulation) doesn't land late.
	game.data.use_demo()
	game.data.connect_station(profile, String(station.password))
	await process_frame
	game.data.use_demo()
	expect(await until(func() -> bool: return not game.data.busy), "the abandoned connect finishes")
	expect(game.data.is_demo(), "and leaves the simulation running (%s)" % game.data.status)
	expect(await game.data.connect_station(profile, String(station.password)), "reconnects")
	# The game's sim-only features step aside, and come back.
	game.data.use_demo()
	expect(game.data.is_demo() and game.data.live == null, "back to the simulation")
	expect(not bool(game.animation_sample(vav, "damper").known), "station links hold until you reconnect")
	# Career jobs never run on live data.
	game.start_job(CareerJobs.find("t1_hot_office"))
	expect(not await game.data.connect_station(profile, String(station.password)) and game.data.is_demo(), "no station during a career job")
	game.end_job()
	_done()

func _done() -> void:
	game.data.close()
	print("LIVE_STATION %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures: print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
