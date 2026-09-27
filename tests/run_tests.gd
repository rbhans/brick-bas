extends SceneTree

# Fast headless unit tests for the building model, renderer rules, HVAC
# topology and the data layer. Run:
#   Godot --headless --path . --script res://tests/run_tests.gd

const PointStoreScript := preload("res://scripts/data/point_store.gd")
const BaskStreamProviderScript := preload("res://scripts/data/bask_stream_provider.gd")
const HistoryStoreScript := preload("res://scripts/data/history_store.gd")
const BindingScript := preload("res://scripts/data/animation_binding.gd")
const MessagePackScript := preload("res://scripts/data/message_pack.gd")
const BaskFixtureScript := preload("res://scripts/data/bask_stream_fixture_transport.gd")
const BaskWebSocketScript := preload("res://scripts/data/bask_stream_websocket_transport.gd")
const BaskBridgeTransportScript := preload("res://scripts/data/bask_stream_bridge_transport.gd")
const Templates := preload("res://scripts/model/templates.gd")
const Migration := preload("res://scripts/model/migrate_v1.gd")

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	test_plan_grid()
	test_rooms_and_openings()
	test_transactions()
	test_save_roundtrip_and_migration()
	test_wall_rendering()
	test_floor_finishes()
	test_templates()
	test_zone_topology()
	test_animation_bindings()
	test_point_normalization()
	test_history_boundaries()
	test_bask_stream_binary_fixture()
	test_connection_profile_safety()
	test_ldraw_runtime_assets()
	print("UNIT_TESTS %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func wall(model: ProjectModel, edge: String, style: String = "tan") -> Dictionary:
	return model.add_object("wall", {"position": [0, 0, 0], "rotation_y": PlanGrid.edge_rotation(edge)}, {"edge": edge, "style": style})

func floor_at(model: ProjectModel, cell: Vector2i, finish: String = "oak") -> Dictionary:
	return model.add_object("floor", {"position": [0, 0, 0], "rotation_y": 0.0}, {"cell": [cell.x, cell.y], "finish": finish})

func test_plan_grid() -> void:
	expect(PlanGrid.TILE == 2.5 and PlanGrid.TILE_STUDS == 5, "plan tiles are five studs")
	expect(PlanGrid.edge_center("x:0:0").is_equal_approx(Vector3(1.25, 0, 0)), "x edge centre")
	expect(PlanGrid.edge_center("z:1:2").is_equal_approx(Vector3(2.5, 0, 6.25)), "z edge centre")
	expect(PlanGrid.edges_between(Vector2i(0, 0), Vector2i(3, 0)) == ["x:0:0", "x:1:0", "x:2:0"], "straight wall drag")
	expect(PlanGrid.rect_perimeter(Vector2i(0, 0), Vector2i(2, 1)).size() == 6, "rectangle perimeter edge count")
	expect(PlanGrid.edge_cells("x:3:4") == [Vector2i(3, 3), Vector2i(3, 4)], "edge separates the cells either side")
	# Stud centres are multiples of 0.5 m: even parts sit between them, odd on them.
	expect(is_equal_approx(PlanGrid.snap_part_center(1.1, 4), 1.25) and is_equal_approx(PlanGrid.snap_part_center(1.1, 3), 1.0), "odd/even stud centring")
	expect(is_equal_approx(PlanGrid.snap_part_center(1.3, 2), 1.25), "even footprint centres between studs")
	expect(PlanGrid.nearest_edge(Vector3(1.2, 0, 0.1)) == "x:0:0", "nearest edge to a ground point")

func test_rooms_and_openings() -> void:
	var model := ProjectModel.new()
	for edge in PlanGrid.rect_perimeter(Vector2i(0, 0), Vector2i(4, 2)): wall(model, edge)
	for cell in PlanGrid.rect_cells(Vector2i(0, 0), Vector2i(4, 2)): floor_at(model, cell)
	var index := BuildingIndex.new()
	index.rebuild(model.objects, model.site)
	expect(index.rooms.size() == 1 and index.rooms[0].cells.size() == 8, "a closed rectangle is one room")
	expect(is_equal_approx(float(index.rooms[0].area_m2), 50.0), "room area from cells")
	for edge in PlanGrid.edges_between(Vector2i(2, 0), Vector2i(2, 2)): wall(model, edge, "white")
	model.add_object("door", {"position": [0, 0, 0], "rotation_y": 0.0}, {"edge": "z:2:0", "style": "door"})
	model.add_object("window", {"position": [0, 0, 0], "rotation_y": 0.0}, {"edge": "x:0:0", "style": "window"})
	model.add_object("door", {"position": [0, 0, 0], "rotation_y": 0.0}, {"edge": "x:3:2", "style": "glass_door"})
	model.site.room_names[PlanGrid.cell_key(Vector2i(0, 0))] = "West"
	index.rebuild(model.objects, model.site)
	expect(index.rooms.size() == 2, "a partition splits the room; doors do not merge rooms")
	var west := index.room_at(PlanGrid.cell_center(Vector2i(0, 1)))
	expect(String(west.label) == "West", "room names follow their cells")
	expect(west.windows.size() == 1 and String(west.windows[0].edge) == "x:0:0" and ZoneTopology.facing(west.windows[0].outward) == "N", "north window recorded with its orientation")
	expect(west.doors.size() == 1 and west.neighbours.size() == 1, "interior door and neighbour recorded")
	var east := index.room_at(PlanGrid.cell_center(Vector2i(3, 1)))
	expect(east.doors.any(func(door: Dictionary) -> bool: return door.to == "outside"), "exterior door recorded")
	var axes := index.vertex_axes(Vector2i(2, 0))
	expect(bool(axes.x) and bool(axes.z), "T junction vertex sees both wall axes")
	var open := ProjectModel.new()
	for edge in PlanGrid.edges_between(Vector2i(0, 0), Vector2i(3, 0)): wall(open, edge)
	index.rebuild(open.objects)
	expect(index.rooms.is_empty(), "an open wall line encloses nothing")

func test_transactions() -> void:
	var model := ProjectModel.new()
	var stack := BuildCommandStack.new(model)
	var adds: Array = []
	for edge in PlanGrid.rect_perimeter(Vector2i(0, 0), Vector2i(2, 2)):
		adds.append({"kind": "wall", "transform": {"position": [0, 0, 0], "rotation_y": 0.0}, "properties": {"edge": edge}})
	var result := stack.apply("Build room", adds)
	expect(model.objects.size() == 8 and result.added.size() == 8, "one transaction adds a whole room")
	var first := String(result.added[0].id)
	stack.undo()
	expect(model.objects.is_empty(), "one undo removes the room")
	stack.redo()
	expect(model.objects.size() == 8 and model.has_object(first), "redo restores the same stable ids")
	var changed: Dictionary = model.find_object(first).duplicate(true)
	changed.properties.style = "white"
	stack.apply("Paint", [], [String(model.objects[1].id)], [changed])
	expect(model.objects.size() == 7 and model.find_object(first).properties.style == "white", "mixed remove + update in one step")
	stack.undo()
	expect(model.objects.size() == 8 and not model.find_object(first).properties.has("style"), "undo reverses the mixed step")
	expect(model.find_object("nope").is_empty(), "missing ids resolve empty")

func test_save_roundtrip_and_migration() -> void:
	var model := Templates.create("office")
	model.demo_checkpoint = {"sim_seconds": 30000.0}
	var path := "user://unit_roundtrip.json"
	expect(model.save_to(path) == OK, "project saves")
	var loaded := ProjectModel.new()
	expect(loaded.load_from(path), "project loads (validator accepts every template kind)")
	expect(loaded.objects.size() == model.objects.size() and loaded.site.room_names.size() == model.site.room_names.size(), "objects and room names round-trip")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var legacy := {
		"format": "bas-sandbox-project", "version": 1, "project_id": "old", "next_id": 20, "complete_scene": true,
		"floors": [{"id": "floor-1"}], "rooms": [], "routes": [], "bindings": [], "connections": [], "demo_checkpoint": {}, "site": {"name": "Old save"},
		"objects": [
			{"id": "floor-0001", "kind": "floor", "floor_id": "floor-1", "transform": {"position": [1.0, 0.0, 1.0], "rotation_y": 0.0}, "properties": {}},
			{"id": "wall_run-0002", "kind": "wall_run", "floor_id": "floor-1", "transform": {"position": [1.0, 0.0, 0.25], "rotation_y": 0.0}, "properties": {"segments": [[1.0, 0.0, 0.25], [3.0, 0.0, 0.25]], "openings": {"1": "window"}}},
			{"id": "terrain-0003", "kind": "terrain", "floor_id": "floor-1", "transform": {"position": [0.0, 0.0, 0.0], "rotation_y": 0.0}, "properties": {}},
			{"id": "ahu", "kind": "ahu", "floor_id": "floor-1", "transform": {"position": [5.0, 0.2, 5.0], "rotation_y": 0.0}, "properties": {"layout": ["damper", "fan"]}},
		],
	}
	var migrated := ProjectModel.new()
	expect(migrated.from_dictionary(legacy) and migrated.migrated_from == 1, "version-1 saves migrate")
	expect(migrated.objects_of(["wall"]).size() == 2 and migrated.objects_of(["window"]).size() == 1, "wall modules become plan edges with their opening")
	expect(migrated.objects_of(["terrain"]).is_empty() and migrated.has_object("ahu"), "terrain dropped, equipment kept by id")
	var junk := ProjectModel.new()
	expect(not junk.from_dictionary({"format": "bas-sandbox-project", "version": 2, "objects": [{"id": "../x", "kind": "wall"}]}), "invalid saves are rejected")

func test_wall_rendering() -> void:
	var model := ProjectModel.new()
	for edge in PlanGrid.rect_perimeter(Vector2i(0, 0), Vector2i(2, 2)): wall(model, edge)
	var index := BuildingIndex.new()
	index.rebuild(model.objects)
	var renderer := ArchitectureRenderer.new()
	renderer.preview_mode = true
	var root := Node3D.new()
	renderer.rebuild(root, model.objects, index)
	# A 2 x 2 room is 10 studs a side: 40 perimeter studs per course, no gaps.
	var studs := 0
	for group in renderer.batch.groups.values():
		var length: int = {"3005": 1, "3004": 2, "3622": 3, "3010": 4, "3009": 6, "3008": 8}.get(String(group.part), 0)
		studs += int(length) * group.records.size()
	expect(studs == 40 * PlanGrid.WALL_COURSES, "every course is closed at the interlocked corners (%d studs)" % studs)
	renderer.clear()
	model.add_object("door", {"position": [0, 0, 0], "rotation_y": 0.0}, {"edge": "x:0:0", "style": "door"})
	index.rebuild(model.objects)
	renderer.rebuild(root, model.objects, index)
	studs = 0
	for group in renderer.batch.groups.values():
		studs += int({"3005": 1, "3004": 2, "3622": 3, "3010": 4}.get(String(group.part), 0)) * group.records.size()
	expect(studs == (40 - 4) * PlanGrid.WALL_COURSES, "a door frame replaces exactly four studs per course")
	expect(renderer.batch.groups.has("60596"), "door frame is an LDraw 60596")
	renderer.clear()
	root.free()

func test_floor_finishes() -> void:
	for finish in ArchitectureRenderer.FLOOR_FINISHES:
		var model := ProjectModel.new()
		floor_at(model, Vector2i(0, 0), String(finish))
		var index := BuildingIndex.new()
		index.rebuild(model.objects)
		var renderer := ArchitectureRenderer.new()
		renderer.preview_mode = true
		var root := Node3D.new()
		renderer.rebuild(root, model.objects, index)
		var area := 0.0
		for group in renderer.batch.groups.values():
			var box := Bricks.bounds(String(group.part))
			area += box.size.x * box.size.z * group.records.size()
		expect(is_equal_approx(area, 6.25), "%s covers the whole 2.5 m tile (%.2f m²)" % [finish, area])
		renderer.clear()
		root.free()

func test_templates() -> void:
	for spec in Templates.PRESETS:
		var model := Templates.create(String(spec.id))
		var index := BuildingIndex.new()
		index.rebuild(model.objects, model.site)
		if spec.id == "blank":
			expect(model.objects.is_empty(), "the empty lot is empty")
			continue
		var named := index.rooms.filter(func(room: Dictionary) -> bool: return not String(room.label).begins_with("Room "))
		expect(named.size() == index.rooms.size() and index.rooms.size() >= 3, "%s: every room is named (%d rooms)" % [spec.id, index.rooms.size()])
		for room in index.rooms:
			expect(int(room.floored) == room.cells.size(), "%s: %s is fully floored" % [spec.id, room.label])
			expect(not room.doors.is_empty(), "%s: %s has a door" % [spec.id, room.label])
		var ids: Dictionary = {}
		for item in model.objects: ids[item.id] = true
		expect(ids.size() == model.objects.size(), "%s: object ids are unique" % spec.id)
		expect(not model.objects_of(["ahu"]).is_empty() and not model.objects_of(["vav"]).is_empty(), "%s: ships with HVAC" % spec.id)

func test_zone_topology() -> void:
	var model := Templates.create("office")
	var index := BuildingIndex.new()
	index.rebuild(model.objects, model.site)
	var network := RouteNetwork.evaluate(model.objects)
	var topology := ZoneTopology.build(index, model.objects, network)
	expect(topology.zones.size() == index.rooms.size(), "every room becomes a thermal zone")
	var glazed := 0.0
	for zone in topology.zones.values():
		for side in zone.window_m2: glazed += float(zone.window_m2[side])
	expect(glazed > 10.0, "exterior windows contribute glazing by orientation (%.1f m²)" % glazed)
	var sim := DemoSimulation.new()
	sim.configure(topology)
	sim.step_for_test(600)
	for zone_id in topology.zones:
		var state := sim.zone_state(String(zone_id))
		expect(not state.is_empty() and is_finite(float(state.temp_c)), "zone %s simulates" % zone_id)

func test_animation_bindings() -> void:
	var binding := {"source": "demo", "mapping": "number", "input_min": 0.0, "input_max": 100.0, "unit": "%"}
	var point := {"source_id": "demo", "value": 0.0, "unit": "%", "quality_flags": []}
	var result := BindingScript.evaluate(binding, point)
	expect(result.known and result.level == 0.0, "numeric zero is valid feedback")
	point.value = 0.45
	point.unit = "fraction"
	result = BindingScript.evaluate(binding, point)
	expect(result.known and is_equal_approx(result.level, 0.45), "fraction converts to percent")
	point.unit = "Pa"
	expect(not BindingScript.evaluate(binding, point).known, "incompatible units stay unknown")
	point.unit = "%"
	for bad in [null, "50", true, NAN, INF]:
		point.value = bad
		expect(not BindingScript.evaluate(binding, point).known, "bad numeric value must not animate: %s" % str(bad))
	point.value = 50.0
	point.quality_flags = ["stale"]
	expect(not BindingScript.evaluate(binding, point).known, "stale sample must not animate")
	point.quality_flags = []
	binding.source = "niagara"
	expect(not BindingScript.evaluate(binding, point).known, "offline Niagara cannot use demo feedback")
	binding = {"source": "demo", "mapping": "enum", "enum_levels": {"Running": 1.0, "Off": 0.0, "2": 0.5}}
	point.value = "Running"
	expect(BindingScript.evaluate(binding, point).level == 1, "named enum mapping")
	point.value = 2
	expect(BindingScript.evaluate(binding, point).level == 0.5, "ordinal enum mapping")

func test_point_normalization() -> void:
	var sim := DemoSimulation.new()
	var model := Templates.create("studio")
	var index := BuildingIndex.new()
	index.rebuild(model.objects, model.site)
	sim.configure(ZoneTopology.build(index, model.objects, RouteNetwork.evaluate(model.objects)))
	sim.step_for_test(60)
	var store := PointStoreScript.new()
	store.apply_updates(sim.snapshot_points())
	var vav := String(model.objects_of(["vav"])[0].id)
	var point: Dictionary = store.get_point(vav + ".damper_feedback")
	expect(point.has("source_timestamp") and point.has("quality_flags") and point.unit == "%", "normalized point fields are retained")
	var binding: Dictionary = BindingScript.defaults("vav", vav).damper
	expect(BindingScript.evaluate(binding, point, "demo").known, "automatic VAV damper binding resolves against the simulation")
	var live := BaskStreamProviderScript.new()
	expect(not live.write_point("station:|slot:/SomePoint", 1), "the live provider rejects writes")

func test_history_boundaries() -> void:
	var history := HistoryStoreScript.new()
	var points: Array[Dictionary] = [{"point_id": "room.temp", "value": 22.0}]
	expect(history.sample(points, 0.0), "first history sample must be accepted")
	expect(not history.sample(points, 10.0), "history must honor its 30-second sampling interval")
	history.mark_boundary("reset", 20.0)
	expect(bool(history.get_series("room.temp")[-1].boundary), "reset/source changes must create a history boundary")

func test_bask_stream_binary_fixture() -> void:
	var bytes := MessagePackScript.encode({"op": "ping"})
	expect(bytes.slice(0, 4) == PackedByteArray([0x81, 0xa2, 0x6f, 0x70]), "baskStream requests use MessagePack maps")
	var nested := {"op": "cov", "points": [{"point": "slot:/AHU/Fan", "value": 42.5, "ok": true}], "sequence": 1779648232328}
	var decoded := MessagePackScript.decode(MessagePackScript.encode(nested))
	expect(bool(decoded.ok) and decoded.value == nested, "MessagePack round-trips maps, arrays, booleans, 64-bit ints, floats")
	expect(not bool(MessagePackScript.decode(PackedByteArray([0x81, 0xa2, 0x6f])).ok), "malformed binary frames fail closed")
	var fixture := BaskFixtureScript.new()
	var live := BaskStreamProviderScript.new()
	expect(live.attach_transport(fixture), "fixture session completes ping and capabilities")
	var point_ids: Array[String] = ["slot:/Drivers/AHU/FanSpeed"]
	expect(live.subscribe(point_ids), "provider creates a read subscription")
	var points := live.snapshot()
	expect(points.size() == 1 and points[0].source_id == "niagara" and points[0].quality_flags == ["good"], "snapshots normalize source and quality")
	fixture.push_cov([{"point": point_ids[0], "value": 0.0, "ok": false, "status": "{stale}"}])
	points = live.snapshot()
	expect(points[0].value == 0.0 and points[0].quality_flags == ["stale"], "COV zero values and stale quality are preserved")
	fixture.close()
	live.poll()
	expect(live.connection_state() == "offline" and live.reconnect(), "provider reconnects after transport loss")
	fixture.push_malformed()
	live.poll()
	expect(live.connection_state() == "protocol_error", "invalid MessagePack changes source state")
	var websocket := BaskWebSocketScript.new()
	expect(websocket.open_authenticated("http://insecure.example", "cookie") == ERR_INVALID_PARAMETER, "non-TLS station URLs are rejected")

func test_connection_profile_safety() -> void:
	var model := ProjectModel.new()
	model.connections.assign([{"id": "school", "name": "School", "station_url": "https://station", "username": "operator", "tls_mode": "strict"}])
	var path := "user://unit_connection_profile.json"
	expect(model.save_to(path) == OK, "connection profile saves with the project")
	var loaded := ProjectModel.new()
	expect(loaded.load_from(path) and loaded.connections.size() == 1, "connection profile loads with the project")
	expect(not loaded.connections[0].has("password"), "password is never persisted")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var bridge := BaskBridgeTransportScript.new()
	bridge.configure(loaded.connections[0], "")
	expect(not bridge.open() and bridge.state() == "error", "bridge rejects a connection without an in-memory password")

func test_ldraw_runtime_assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/third_party/ldraw/selection.json"))
	for part in ["3005", "3004", "3622", "3010", "60596", "60616b", "60594", "3068b", "2431", "3070b", "30657", "3941"]:
		expect(manifest.parts.has(part) and Bricks.exists(part), "baked LDraw part %s is present" % part)
