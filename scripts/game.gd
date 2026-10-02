extends Node

# BRICK / BAS game shell. Owns the project model and the three modes:
#   Build      Sims-style architecture, furniture and landscaping
#   Equipment  place and connect HVAC (with the AHU/VAV workbench)
#   Explore    walk the building as a minifigure and use what you built
# and the two ways to play: Creative (the sandbox, simulated or live station
# data) and Career (contract jobs with objectives, run by a JobSession).
# Everything visible is rebuilt from the model after each undoable change.

enum Mode { BUILD, EQUIPMENT, EXPLORE }
enum Walls { UP, CUTAWAY, DOWN }

const SAVE_PATH := "user://bas_sandbox_office.json"
const PointStoreScript := preload("res://scripts/data/point_store.gd")
const HistoryStoreScript := preload("res://scripts/data/history_store.gd")
const AlarmManagerScript := preload("res://scripts/sim/alarm_manager.gd")
const Bindings := preload("res://scripts/data/animation_binding.gd")
const Templates := preload("res://scripts/model/templates.gd")
const HUDScript := preload("res://scripts/ui/hud.gd")
const TourScript := preload("res://scripts/ui/tour.gd")
const SessionUI := preload("res://scripts/ui/session_ui.gd")
const BrowserFiles := preload("res://scripts/ui/browser_files.gd")
const EquipmentViewScript := preload("res://scripts/build/equipment_view.gd")
const ExplorerScript := preload("res://scripts/explore/explorer.gd")
const ALARM_CHUNK_STEPS := 10
const TURBO_BUDGET_US := 9000 # simulation time per frame while time-lapsing...
const TURBO_BUDGET_MAX_US := 50000 # ...growing with slow frames, so a slow machine still gets through the day
const EDIT_GLYPHS := ["move", "rotate", "copy", "hammer", "build", "duct", "paint", "floor", "link"]

signal mode_changed(mode: int)
signal selection_changed(id: String)
signal world_changed

var demo_only := OS.has_feature("web")
var model := ProjectModel.new()
var commands := BuildCommandStack.new(model)
var index := BuildingIndex.new()
var arch := ArchitectureRenderer.new()
var placement: Placement
var sim := DemoSimulation.new()
var points: PointStore
var history: RefCounted
var alarms: RefCounted
var data: DataSource
var equipment: Node3D
var explorer: Node3D
var stage: Stage
var world: Node3D
var ghost_root: Node3D
var marks: PlanMarks
var rig: CameraRig
var hud: Control
var session_ui: Control
var browser_files: RefCounted
var sound_player: AudioStreamPlayer
var sounds: Dictionary = {}

var mode := Mode.BUILD
var wall_mode := Walls.CUTAWAY
var equipment_wall_mode := Walls.DOWN
var tool: BuildTool
var selected_id := ""
var hover_id := ""
var overlay := false
var overlay_by_mode := {0: false, 1: true, 2: false}
var sound_enabled := true
var reduced_motion := false
var graphics := "auto"        # auto | high | low (see set_graphics)
var tour: Control
var low_graphics := false
var _slow_seconds := 0.0
var status_text := ""
var network: Dictionary = {}
var topology: Dictionary = {}
var room_labels: Node3D
var overlay_root: Node3D
var furniture_info: Dictionary = {}  # furniture id -> {seats} in world space
var _ui_timer := 0.0
var _overlay_timer := 0.0
var _last_open_signature := ""
var career: CareerState
var job: JobSession          # the career job in progress (null in Creative)
var turbo_until := -1.0      # time-lapse target in simulation seconds (< 0: off)
var _backfilled: Dictionary = {} # "connection|ORD" -> true once its station history was asked for
var _live_epoch := -1.0 # local midnight the live clock counts from (keeps trend times float32-exact)

func _ready() -> void:
	name = "Game"
	# The browser tab and desktop window show the game's name (a frame later:
	# the engine applies the project name itself once the scene is up).
	_set_title.call_deferred()
	career = CareerState.load_or_new()
	points = PointStoreScript.new()
	history = HistoryStoreScript.new()
	alarms = AlarmManagerScript.new()
	data = DataSource.new(self)
	stage = Stage.new()
	add_child(stage)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	ghost_root = Node3D.new()
	ghost_root.name = "Ghosts"
	add_child(ghost_root)
	room_labels = Node3D.new()
	room_labels.name = "Room labels"
	add_child(room_labels)
	overlay_root = Node3D.new()
	overlay_root.name = "BAS overlay"
	add_child(overlay_root)
	marks = PlanMarks.new()
	add_child(marks)
	marks.setup(self)
	placement = Placement.new(self)
	arch.furniture_builder = _build_furniture
	rig = CameraRig.new()
	add_child(rig)
	rig.make_current()
	equipment = EquipmentViewScript.new()
	add_child(equipment)
	equipment.setup(self)
	explorer = ExplorerScript.new()
	add_child(explorer)
	explorer.setup(self)
	_setup_sound()
	# Before the HUD, so its menu shows the saved settings.
	var preferences := Settings.load_all()
	reduced_motion = bool(preferences.reduced_motion)
	if DisplayServer.get_name() != "headless": sound_enabled = bool(preferences.sounds)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUDScript.new()
	layer.add_child(hud)
	hud.setup(self)
	tour = TourScript.new()
	layer.add_child(tour)
	tour.setup(self)
	session_ui = SessionUI.new()
	layer.add_child(session_ui)
	session_ui.setup(self)
	browser_files = BrowserFiles.new()
	browser_files.setup(self)
	set_graphics(String(preferences.graphics), false)
	set_tool(SelectTool.new(self))
	start_new_game("office", false)
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and args.is_empty() and not OS.get_cmdline_args().has("--script"):
		session_ui.show_home()
	for argument in args:
		if argument.begins_with("--template="):
			start_new_game(argument.trim_prefix("--template="), false)
		elif argument.begins_with("--view="):
			var view := argument.trim_prefix("--view=").split(",")
			rig.set_view(Vector3(float(view[0]), 0.5, float(view[1])), float(view[2]), float(view[3]), float(view[4]), true)
		elif argument == "--explore":
			set_mode.call_deferred(Mode.EXPLORE)
		elif argument == "--equipment":
			set_mode.call_deferred(Mode.EQUIPMENT)
		elif argument.begins_with("--select="):
			select.call_deferred(argument.trim_prefix("--select="))
		elif argument.begins_with("--speed="):
			set_speed.call_deferred(float(argument.trim_prefix("--speed=")))
		elif argument.begins_with("--graphics="):
			set_graphics(argument.trim_prefix("--graphics="), false)
		elif argument.begins_with("--walls="):
			wall_mode = int(argument.trim_prefix("--walls="))
		elif argument.begins_with("--capture="):
			_capture_and_quit.call_deferred(argument.trim_prefix("--capture="))

func _exit_tree() -> void:
	data.close()

# --- Model changes -------------------------------------------------------------

func apply(label: String, adds: Array = [], removes: Array = [], updates: Array = []) -> Dictionary:
	# The last word on career locks: a tool or workbench left open when a job
	# phase changed can't commit what the job no longer allows.
	if job != null and not _edits_allowed(adds, removes, updates):
		return {"added": [], "changed": 0}
	var result := commands.apply(label, adds, removes, updates)
	var added_ids: Array = []
	for item in result.added:
		added_ids.append(String(item.id))
	result.added = added_ids
	refresh_world()
	return result

func undo() -> void:
	if _blocked("equipment"):
		return
	# A piece being carried is put back first: its record may be about to go.
	var carried: Variant = tool.get("moving_id") if tool != null else null
	if carried != null and not String(carried).is_empty():
		finish_tool()
	var command := commands.undo()
	if command.is_empty():
		set_status("Nothing to undo")
		return
	refresh_world()
	play_sound("undo")
	set_status("Undid %s" % String(command.action).to_lower())

func redo() -> void:
	if _blocked("equipment"):
		return
	var carried: Variant = tool.get("moving_id") if tool != null else null
	if carried != null and not String(carried).is_empty():
		finish_tool()
	var command := commands.redo()
	if command.is_empty():
		set_status("Nothing to redo")
		return
	refresh_world()
	play_sound("place")
	set_status("Redid %s" % String(command.action).to_lower())

func refresh_world() -> void:
	furniture_info.clear()
	index.rebuild(model.objects, model.site)
	arch.rebuild(world, model.objects, index)
	placement.rebuild(model.objects, index)
	equipment.rebuild(model.objects)
	_reconfigure_simulation()
	_rebuild_room_labels()
	explorer.refresh()
	if not selected_id.is_empty() and not model.has_object(selected_id):
		select("")
	marks.reapply()
	_update_cutaway()
	if mode == Mode.EQUIPMENT and is_instance_valid(hud):
		hud.rebuild_shelf()   # the tray's "what's next" note follows the building
	world_changed.emit()

func _reconfigure_simulation() -> void:
	network = RouteNetwork.evaluate(model.objects)
	topology = ZoneTopology.build(index, model.objects, network)
	sim.configure(topology)
	_last_open_signature = ""
	sync_openings()
	if data.is_demo():
		points.replace_snapshot(data.provider.snapshot())

# Doors and windows the player has opened change infiltration and mixing.
func sync_openings() -> void:
	var connections: Array = []
	for door_id in explorer.open_doors:
		if not bool(explorer.open_doors[door_id]): continue
		var item: Dictionary = model.find_object(String(door_id))
		if item.is_empty(): continue
		var sides := index.edge_rooms(String(item.properties.get("edge", "")))
		if sides.size() == 2 and (not sides[0].is_empty() or not sides[1].is_empty()):
			connections.append({"a": sides[0] if not sides[0].is_empty() else "outside", "b": sides[1] if not sides[1].is_empty() else "outside", "kind": "door"})
	var signature := str(connections)
	if signature != _last_open_signature:
		_last_open_signature = signature
		sim.set_open_connections(connections)

# --- Entries ---------------------------------------------------------------------

func entry(kind: String, position: Vector3, rotation_y: float, properties: Dictionary) -> Dictionary:
	return {"kind": kind, "transform": {"position": [position.x, position.y, position.z], "rotation_y": rotation_y}, "properties": properties}

func wall_entry(edge: String, style: String) -> Dictionary:
	return entry("wall", PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge), {"edge": edge, "style": style})

func floor_entry(cell: Vector2i, finish: String) -> Dictionary:
	return entry("floor", PlanGrid.cell_center(cell), 0.0, {"cell": [cell.x, cell.y], "finish": finish})

func opening_entry(kind: String, edge: String, style: String, swing: float = 1.0) -> Dictionary:
	var props := {"edge": edge, "style": style}
	if kind == "door": props.swing = swing
	return entry(kind, PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge), props)

# Walls on these edges plus everything that hangs on them.
func walls_and_dependents(edges: Array) -> Array:
	var ids: Array = []
	for edge in edges:
		if index.walls.has(edge):
			ids.append(String(index.walls[edge].id))
	return with_dependents(ids)

func with_dependents(ids: Array) -> Array:
	var result: Dictionary = {}
	var edges: Dictionary = {}
	for id in ids:
		result[String(id)] = true
		var item: Dictionary = model.find_object(String(id))
		if item.get("kind", "") == "wall":
			edges[String(item.properties.edge)] = true
	for item in model.objects:
		var edge := String(item.properties.get("edge", ""))
		if not edge.is_empty() and edges.has(edge) and item.kind != "wall":
			result[String(item.id)] = true
	return result.keys()

# Removing pieces: their dependents, the ducts attached to any equipment,
# and a bridging duct wherever a fitting is pulled out of a main.
func removal_plan(ids: Array) -> Dictionary:
	var planner := ZonePlanner.new(model.objects, index, model.new_id)
	planner.plan_removal(with_dependents(ids))
	return {"adds": planner.entries, "removes": planner.removed_ids()}

func objects_in_area(area: Rect2) -> Array:
	var found: Array = []
	for item in model.objects:
		var point := _anchor(item)
		if point != Vector3.INF and area.has_point(Vector2(point.x, point.z)):
			found.append(String(item.id))
	return found

func _anchor(item: Dictionary) -> Vector3:
	match String(item.kind):
		"wall", "door", "window":
			return PlanGrid.edge_center(String(item.properties.get("edge", "x:0:0")))
		"floor":
			return PlanGrid.cell_center(BuildingIndex.cell_of(item))
		"duct":
			return Vector3.INF
	return vector(item.transform.position)

# --- Tools ---------------------------------------------------------------------------

func set_tool(next: BuildTool) -> void:
	if tool != null:
		tool.exit()
	marks.hide_guides()
	marks.clear()
	stage.set_grid(false)
	tool = next
	if tool.id != "select":
		select("")
	tool.enter()
	if tool.shows_grid:
		stage.set_grid(true, rig.target)
	if is_instance_valid(hud):
		hud.tool_changed()

func finish_tool() -> void:
	set_tool(SelectTool.new(self))

func start_tool(tool_id: String, params: Dictionary = {}) -> void:
	var touches := "equipment" if tool_id in ["equipment", "duct", "zone", "delete"] or (tool_id == "place" and String(params.get("kind", "")) == "tstat") else "architecture"
	if _blocked(touches):
		return
	if mode == Mode.EXPLORE:
		set_mode(Mode.BUILD)
	match tool_id:
		"room": set_tool(RoomTool.new(self, params))
		"wall": set_tool(WallTool.new(self, params))
		"floor": set_tool(FloorTool.new(self, params))
		"door", "window":
			params.kind = tool_id
			set_tool(OpeningTool.new(self, params))
		"place": set_tool(PlaceTool.new(self, params))
		"delete": set_tool(SledgehammerTool.new(self, params))
		"paint": set_tool(PaintTool.new(self, params))
		_:
			if equipment.has_tool(tool_id):
				set_tool(equipment.make_tool(tool_id, params))
			else:
				finish_tool()

# --- Selection & highlighting ---------------------------------------------------------

func select(id: String, _hit: Dictionary = {}) -> void:
	if id == selected_id:
		return
	selected_id = id
	marks.set_selected(id)
	selection_changed.emit(id)
	if not id.is_empty():
		play_sound("select")

func set_hover(id: String) -> void:
	hover_id = id
	marks.set_hover(id)

func mark(ids: Array, kind: String) -> void:
	marks.mark(ids, kind)

func clear_marks() -> void:
	marks.clear()

func flash(ids: Array) -> void:
	marks.flash(ids)

func tint_object(id: String, tint: Color) -> void:
	arch.batch.tint_owner(id, tint)
	equipment.tint(id, tint)

func hide_object(id: String, hidden: bool) -> void:
	arch.batch.set_owner_hidden(id, hidden)
	equipment.set_hidden(id, hidden)
	for body in arch.bodies.get(id, []):
		if is_instance_valid(body):
			body.collision_layer = 0 if hidden else 1

func show_vertex_cursor(vertex: Vector2i, danger: bool) -> void:
	marks.show_vertex(vertex, danger)

func show_cell_cursor(cell: Vector2i, danger: bool) -> void:
	marks.show_cell(cell, danger)

func show_measure(a: Vector3, b: Vector3, c: Vector3 = Vector3.INF) -> void:
	marks.show_measure(a, b, c)

func hide_measure() -> void:
	marks.hide_measure()

func show_area(area: Rect2) -> void:
	marks.show_area(area)

func hide_area() -> void:
	marks.hide_area()

func show_footprint(transform: Transform3D, studs: Vector2i, valid: bool, wall: bool) -> void:
	marks.show_footprint(transform, studs, valid, wall)

# --- Picking -----------------------------------------------------------------------------

func active_camera() -> Camera3D:
	return explorer.camera if mode == Mode.EXPLORE else rig.camera

# First placed object under the pointer. Wall parts that are currently cut
# away are looked through, so you can click furniture behind a lowered wall.
func pick(mouse: Vector2, max_distance: float = 4000.0, include_cut: bool = false) -> Dictionary:
	var camera := active_camera()
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * max_distance
	var excluded: Array[RID] = []
	if mode == Mode.EXPLORE:
		excluded.append(explorer.player.get_rid())
	var space := world.get_world_3d().direct_space_state
	for attempt in range(16):
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = excluded
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var id := _entity_of(hit.collider)
		if id.is_empty():
			return {"id": "", "position": hit.position, "ground": true}
		var item: Dictionary = model.find_object(id)
		if item.is_empty():
			excluded.append(hit.collider.get_rid())
			continue
		if not include_cut and item.kind in ["wall", "door", "window"] and _is_cut(String(item.properties.get("edge", "")), hit.position.y):
			excluded.append(hit.collider.get_rid())
			continue
		return {"id": id, "item": item, "position": hit.position, "normal": hit.normal}
	return {}

func _entity_of(collider: Object) -> String:
	var node := collider as Node
	while node != null:
		if node.has_meta("entity_id"):
			return String(node.get_meta("entity_id"))
		node = node.get_parent()
	return ""

func _is_cut(edge: String, height: float) -> bool:
	if edge.is_empty() or height < PlanGrid.BRICK + 0.05:
		return false
	var state := cutaway_state()
	return BrickBatch.is_cut(BrickBatch.wall_custom(1, edge), int(state.mode), state.focus, state.forward, float(state.radius))

# Wall edge under the pointer: a wall hit if there is one, else the nearest
# grid edge to the ground point.
func wall_edge_at(mouse: Vector2) -> String:
	var hit := pick(mouse, 4000.0, true)
	var item: Dictionary = hit.get("item", {})
	if item.get("kind", "") in ["wall", "door", "window"]:
		return String(item.properties.edge)
	var point := rig.ground_point(mouse, PlanGrid.FLOOR_TOP)
	if point == Vector3.INF:
		return ""
	var edge := PlanGrid.nearest_edge(point)
	return edge if float(PlanGrid.edge_distance(edge, point).distance) < 0.9 and index.has_wall(edge) else ""

# --- Placeables ------------------------------------------------------------------------------

func placeable_spec(kind: String, item_id: String = "") -> Dictionary:
	return placement.spec(kind, item_id)

func snap_placeable(mouse: Vector2, kind: String, item_id: String, rotation: float, exclude_id: String = "") -> Dictionary:
	return placement.snap(mouse, kind, item_id, rotation, exclude_id)

func placement_properties(kind: String, item_id: String, transform: Transform3D) -> Dictionary:
	var props := {}
	if kind == "furniture": props.item = item_id
	if kind == "tree" and not item_id.is_empty(): props.variant = item_id
	var spec := placement.spec(kind, item_id)
	if String(spec.mount) == "wall":
		# Re-snap just off the wall line on the piece's side (it hangs half a stud
		# out), so a piece by a room corner keeps its own wall, not the next one.
		var found := placement._snap_wall(transform.origin - transform.basis.z * (PlanGrid.STUD * 0.5 - 0.05), kind, spec, "")
		props.edge = String(found.get("edge", ""))
		props.side = int(found.get("side", 1))
	return props

func build_placeable(parent: Node3D, kind: String, item_id: String, properties: Dictionary = {}) -> void:
	match kind:
		"furniture":
			var catalog := Placement.furniture_catalog()
			if catalog != null:
				catalog.build(parent, item_id, properties)
		"tree", "shrub", "parking":
			var sample := {"id": "ghost", "kind": kind, "transform": {"position": [0, 0, 0], "rotation_y": 0.0}, "properties": {"variant": item_id}}
			var preview := ArchitectureRenderer.preview(parent, [sample], true)
			preview.root.reparent(parent)
		_:
			equipment.build_preview(parent, kind, properties)

func _build_furniture(holder: Node3D, item: Dictionary) -> Dictionary:
	var catalog := Placement.furniture_catalog()
	if catalog == null:
		return {}
	var options: Dictionary = item.properties.duplicate()
	var paint: Dictionary = item.properties.get("paint", {})
	if paint.has("all"): options.color = Color(String(paint.all))
	var result: Dictionary = catalog.build(holder, String(item.properties.get("item", "")), options)
	var seats: Array = []
	for seat in result.get("seats", []):
		seats.append({"position": holder.transform * Vector3(seat.position), "facing": holder.rotation.y + float(seat.get("facing", 0.0))})
	furniture_info[String(item.id)] = {"seats": seats}
	return result

func furniture_seats() -> Array:
	var result: Array = []
	for id in furniture_info:
		if not model.has_object(String(id)):
			continue
		var info: Dictionary = furniture_info[id]
		for seat in info.seats:
			result.append({"id": String(id), "kind": "seat", "position": seat.position, "facing": seat.facing})
	return result

func equipment_ceiling() -> Dictionary:
	return equipment.ceiling_studs

func equipment_config(kind: String) -> Dictionary:
	return equipment.current_config(kind)

func can_move(id: String) -> bool:
	var item: Dictionary = model.find_object(id)
	return item.get("kind", "") in ["furniture", "tree", "shrub", "parking", "door", "window", "ahu", "vav", "diffuser", "tee", "tstat"]

func start_move(id: String) -> void:
	var item: Dictionary = model.find_object(id)
	if item.is_empty() or _blocked(edit_kind(id)):
		return
	select(id)
	match String(item.kind):
		"door", "window":
			set_tool(OpeningTool.new(self, {"kind": item.kind, "style": item.properties.get("style", item.kind), "moving_id": id, "swing": item.properties.get("swing", 1.0)}))
		"furniture", "tree", "shrub", "parking":
			set_tool(PlaceTool.new(self, {"kind": item.kind, "item": item.properties.get("item", item.properties.get("variant", "")), "moving_id": id, "rotation": item.transform.get("rotation_y", 0.0), "properties": item.properties}))
		_:
			set_tool(equipment.move_tool(id))
	play_sound("pickup")

func rotate_selected() -> void:
	var item: Dictionary = model.find_object(selected_id)
	if item.is_empty() or _blocked(edit_kind(selected_id)):
		return
	var changed := item.duplicate(true)
	match String(item.kind):
		"door":
			changed.properties.swing = -float(item.properties.get("swing", 1.0))
		"furniture", "tree", "shrub", "parking":
			var spec := placement.spec(String(item.kind), String(item.properties.get("item", "")))
			if String(spec.mount) == "wall":
				set_status("Wall pieces face out from their wall.")
				return
			changed.transform.rotation_y = fposmod(float(item.transform.get("rotation_y", 0.0)) + PI * 0.5, TAU)
			var center := vector(item.transform.position)
			var turned := PlanGrid.rotated_footprint(spec.footprint, changed.transform.rotation_y)
			center.x = PlanGrid.snap_part_center(center.x, turned.x)
			center.z = PlanGrid.snap_part_center(center.z, turned.y)
			changed.transform.position = [center.x, center.y, center.z]
			# Parking markings live on their own flat layer.
			var layer: Dictionary = placement.surfaces if bool(spec.get("surface", false)) else placement.studs
			for stud in Placement.footprint_studs(center, spec.footprint, changed.transform.rotation_y):
				var owner := String(layer.get(stud, ""))
				if not owner.is_empty() and owner != selected_id:
					set_status("No room to turn it · blocked by %s" % describe(owner))
					play_sound("error")
					return
		_:
			if equipment.rotate_object(selected_id):
				return
			set_status("That piece can't turn in place.")
			return
	apply("Rotate", [], [], [changed])
	play_sound("tick")

func delete_selected() -> void:
	if selected_id.is_empty() or _blocked(edit_kind(selected_id)):
		return
	var plan := removal_plan([selected_id])
	var label := describe(selected_id)
	apply("Delete", plan.adds, plan.removes)
	select("")
	play_sound("demolish")
	set_status("Removed %s" % label)

func duplicate_selected() -> void:
	var item: Dictionary = model.find_object(selected_id)
	if item.is_empty() or not can_move(selected_id) or item.kind in ["door", "window"] or _blocked(edit_kind(selected_id)):
		return
	match String(item.kind):
		"furniture", "tree", "shrub", "parking":
			set_tool(PlaceTool.new(self, {"kind": item.kind, "item": item.properties.get("item", item.properties.get("variant", "")), "rotation": item.transform.get("rotation_y", 0.0), "properties": item.properties, "once": true}))
		_:
			set_tool(equipment.copy_tool(selected_id))

func describe(id: String) -> String:
	var item: Dictionary = model.find_object(id)
	if item.is_empty():
		return "nothing"
	match String(item.kind):
		"wall": return "%s wall" % ArchitectureRenderer.WALL_STYLES.get(String(item.properties.get("style", "tan")), {}).get("label", "Brick")
		"floor": return ArchitectureRenderer.FLOOR_FINISHES.get(String(item.properties.get("finish", "oak")), {}).get("label", "Floor")
		"door": return ArchitectureRenderer.DOOR_STYLES.get(String(item.properties.get("style", "door")), {}).get("label", "Door")
		"window": return ArchitectureRenderer.WINDOW_STYLES.get(String(item.properties.get("style", "window")), {}).get("label", "Window")
		"furniture": return String(placement.spec("furniture", String(item.properties.get("item", ""))).label)
		"tree": return "%s tree" % String(item.properties.get("variant", "oak")).capitalize()
	return String(item.properties.get("label", String(item.kind).capitalize()))

func idle_hint() -> String:
	match mode:
		Mode.EQUIPMENT: return "Equipment · pick a unit from the tray · right-drag orbit · V wall view"
		Mode.EXPLORE: return "Explore · WASD walk · E use · drag to look around"
	return "Build · pick a tool below · right-drag orbit · wheel zoom · Q/E rotate · V wall view"

# --- Modes ---------------------------------------------------------------------------------

func set_mode(value: int) -> void:
	if value == Mode.EXPLORE and index.floors.is_empty() and model.objects_of(["floor"]).is_empty():
		set_status("Lay some floor or build a room before exploring.")
		play_sound("error")
		hud.refresh_mode() # the clicked tab lit itself
		return
	var previous := mode
	mode = value
	# A drag that was under way when the mode changed never sees its release.
	rig.orbiting = false
	rig.panning = false
	explorer.drag_button = MOUSE_BUTTON_NONE
	if tool != null:
		finish_tool()
	if mode == Mode.EXPLORE:
		explorer.activate(true)
	elif previous == Mode.EXPLORE:
		explorer.activate(false)
		rig.make_current()
	overlay = bool(overlay_by_mode.get(mode, false))
	_refresh_overlay(true)
	equipment.set_mode_view(mode)
	rig.input_enabled = mode != Mode.EXPLORE
	_update_cutaway()
	_rebuild_room_labels()
	mode_changed.emit(mode)
	set_status(idle_hint())
	play_sound("mode")

func cycle_wall_mode() -> void:
	if mode == Mode.EQUIPMENT:
		equipment_wall_mode = (equipment_wall_mode + 1) % 3
	else:
		wall_mode = (wall_mode + 1) % 3
	_update_cutaway()
	hud.tool_changed()
	set_status("Walls %s" % ["up", "cutaway", "down"][effective_wall_mode()])

func set_wall_mode(value: int) -> void:
	if mode == Mode.EQUIPMENT: equipment_wall_mode = value
	else: wall_mode = value
	_update_cutaway()

func effective_wall_mode() -> int:
	match mode:
		Mode.EQUIPMENT: return equipment_wall_mode
		Mode.EXPLORE: return Walls.CUTAWAY
	return wall_mode

func cutaway_state() -> Dictionary:
	if mode == Mode.EXPLORE:
		return {"mode": Walls.CUTAWAY, "focus": explorer.focus_point(), "forward": -explorer.camera.global_basis.z, "radius": explorer.cut_radius()}
	return {"mode": effective_wall_mode(), "focus": rig.target, "forward": -rig.camera.global_basis.z, "radius": clampf(rig.distance * 0.75, 12.0, 90.0)}

func _update_cutaway() -> void:
	var state := cutaway_state()
	BrickBatch.set_cutaway(int(state.mode), state.focus, state.forward, float(state.radius))
	for door_id in arch.doors:
		var door: Dictionary = arch.doors[door_id]
		var hinge: Node3D = door.hinge
		if is_instance_valid(hinge):
			# A swung-open door stays visible: it no longer blocks the view.
			var swung: bool = absf(float(explorer.door_angles.get(door_id, 0.0))) > 0.25
			hinge.visible = swung or not BrickBatch.is_cut(door.custom, int(state.mode), state.focus, state.forward, float(state.radius))
	equipment.update_cutaway(state)

# --- Frame loop -------------------------------------------------------------------------------

func _set_title() -> void:
	await get_tree().process_frame
	DisplayServer.window_set_title("BRICK / BAS")

# The quick tour runs once, after the first starter is picked.
func maybe_start_tour() -> void:
	if not bool(Settings.load_all().tour_done):
		show_tour()

func show_tour() -> void:
	tour.start()

# --- Graphics quality ------------------------------------------------------------------------

# "high" keeps shadows and anti-aliasing; "low" drops both and renders 3D at
# 75 % resolution; "auto" starts high and steps down once if the frame rate
# stays poor (slow laptops in the browser).
func set_graphics(value: String, remember: bool = true) -> void:
	graphics = value if value in ["auto", "high", "low"] else "auto"
	_apply_graphics(graphics == "low")
	_slow_seconds = 0.0
	if remember: Settings.store("graphics", graphics)

func _apply_graphics(low: bool) -> void:
	low_graphics = low
	stage.sun.shadow_enabled = not low
	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if low else int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 2)) as Viewport.MSAA
	viewport.scaling_3d_scale = 0.75 if low else 1.0

func _watch_frame_rate(delta: float) -> void:
	if graphics != "auto" or low_graphics or session_ui.visible or delta > 0.25:
		return   # (long single frames are loading hitches, not a slow machine)
	_slow_seconds = maxf(0.0, _slow_seconds + (delta if delta > 1.0 / 38.0 else -delta * 0.5))
	if _slow_seconds > 4.0:
		_apply_graphics(true)
		set_status("Things were running slowly, so graphics switched to Low · change it in Menu, Graphics")

func _process(delta: float) -> void:
	var steps := _advance_simulation(delta)
	if not data.is_demo():
		data.provider.poll()
	var updates := data.provider.snapshot()
	points.apply_updates(updates)
	history.sample(updates, history_time())
	if job != null:
		job.process(steps)
	equipment.animate(delta)
	_watch_frame_rate(delta)
	# Keys typed into a field (a room name, a number box) mustn't pan the camera.
	rig.pan_keys_enabled = not hud.typing() and not session_ui.visible
	if tool != null and mode != Mode.EXPLORE:
		tool.process(delta)
	marks.process(delta)
	_update_cutaway()
	_ui_timer += delta
	if _ui_timer >= 0.2:
		_ui_timer = 0.0
		data.poll()
		hud.refresh()
		if session_ui.visible: session_ui.refresh_readout()
	if overlay:
		_overlay_timer += delta
		if _overlay_timer > 0.5:
			_overlay_timer = 0.0
			_refresh_overlay()

# Normal play advances at the chosen speed. A time-lapse (job runs, travel,
# work in progress) steps as fast as a per-frame time budget allows until it
# reaches its target, ignoring pause, so the building visibly runs the day.
func _advance_simulation(delta: float) -> int:
	if not data.is_demo():
		return 0
	if turbo_until <= sim.sim_seconds:
		var due := sim.due_steps(delta)
		var done := 0
		while done < due:
			var count := mini(ALARM_CHUNK_STEPS, due - done)
			_run_steps(count)
			done += count
		return due
	var started := Time.get_ticks_usec()
	var budget := clampi(int(delta * 500000.0), TURBO_BUDGET_US, TURBO_BUDGET_MAX_US)
	var remaining := int(ceil(turbo_until - sim.sim_seconds))
	var steps := 0
	while steps < remaining:
		var chunk := mini(ALARM_CHUNK_STEPS, remaining - steps)
		_run_steps(chunk)
		steps += chunk
		if Time.get_ticks_usec() - started > budget:
			break
	return steps

# Alarms judge their delays at this resolution: judged once per frame, a
# time-lapse frame of hundreds of steps would credit its whole span to
# whatever held at its end.
func _run_steps(count: int) -> void:
	sim.run_steps(count)
	alarms.evaluate(sim, float(count) * DemoSimulation.STEP_SECONDS)

# The clock trends run on: simulated seconds, or local wall-clock seconds
# (so the hour grid reads true) when the data is live from a station.
func history_time() -> float:
	if data == null or data.is_demo():
		return sim.sim_seconds
	# Local seconds since the midnight the session went live: small enough for
	# the trend store's float32 times, and the hour grid still reads true.
	var zone: Dictionary = Time.get_time_zone_from_system()
	var local := Time.get_unix_time_from_system() + float(zone.get("bias", 0)) * 60.0
	if _live_epoch < 0.0:
		_live_epoch = floor(local / 86400.0) * 86400.0
	return local - _live_epoch

func set_turbo(until: float) -> void:
	turbo_until = until
	sim.accumulator = 0.0
	if is_instance_valid(hud):
		hud.refresh_simulation_controls()

func _unhandled_input(event: InputEvent) -> void:
	if session_ui.visible:
		if event.is_action_pressed("cancel_action") and not session_ui.welcome:
			session_ui.hide()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var command := key.ctrl_pressed or key.meta_pressed
		if command and key.physical_keycode == KEY_Z:
			if key.shift_pressed: redo()
			else: undo()
			get_viewport().set_input_as_handled()
			return
		if command and key.physical_keycode == KEY_Y:
			redo()
			get_viewport().set_input_as_handled()
			return
		if command and key.physical_keycode == KEY_S:
			save_project()
			get_viewport().set_input_as_handled()
			return
		match key.physical_keycode:
			KEY_TAB:
				set_mode(Mode.BUILD if mode == Mode.EXPLORE else Mode.EXPLORE)
				get_viewport().set_input_as_handled()
				return
			KEY_ESCAPE:
				_escape()
				get_viewport().set_input_as_handled()
				return
			KEY_V:
				if mode != Mode.EXPLORE:
					cycle_wall_mode()
					get_viewport().set_input_as_handled()
					return
			KEY_B:
				toggle_overlay()
				get_viewport().set_input_as_handled()
				return
			KEY_HOME:
				if mode != Mode.EXPLORE:
					frame_lot()
					get_viewport().set_input_as_handled()
					return
			KEY_F:
				if mode != Mode.EXPLORE and not selected_id.is_empty():
					frame_selection()
					get_viewport().set_input_as_handled()
					return
	if mode == Mode.EXPLORE:
		explorer.handle_input(event)
		return
	if rig.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if tool != null and tool.handle(event):
		get_viewport().set_input_as_handled()

func _escape() -> void:
	if hud.close_panels():
		return
	if mode == Mode.EXPLORE:
		if not explorer.escape():
			set_mode(Mode.BUILD)
		return
	if tool != null and tool.cancel():
		return
	if tool != null and tool.id != "select":
		finish_tool()
		set_status(idle_hint())
		return
	if not selected_id.is_empty():
		select("")
		return
	hud.toggle_menu()

func frame_lot() -> void:
	var box := _content_bounds()
	rig.frame_box(box)

# Jump to an alarm's source: a placed object, or a room by id.
func focus_on(target: String) -> void:
	if mode == Mode.EXPLORE:
		set_mode(Mode.EQUIPMENT)
	var item: Dictionary = model.find_object(target)
	if not item.is_empty():
		select(target)
		frame_selection()
		return
	var room := index.room_by_id(target)
	if not room.is_empty():
		rig.set_view(room.center, rig.goal_yaw, rig.goal_pitch, clampf(sqrt(float(room.area_m2)) * 2.4 + 8.0, 12.0, 40.0))
		for vav_id in sim.zone_state(target).get("terminals", []):
			select(String(vav_id))
			break

func frame_selection() -> void:
	var item: Dictionary = model.find_object(selected_id)
	if item.is_empty():
		return
	var point := _anchor(item)
	if point == Vector3.INF:
		return
	rig.set_view(point, rig.goal_yaw, rig.goal_pitch, clampf(rig.goal_distance, 10.0, 26.0))

func _content_bounds() -> AABB:
	var box := AABB()
	var first := true
	for item in model.objects:
		var point := _anchor(item)
		if point == Vector3.INF:
			continue
		if first: box = AABB(point, Vector3.ZERO)
		else: box = box.expand(point)
		first = false
	if first:
		return AABB(Vector3(-10, 0, -10), Vector3(20, 1, 20))
	return box

# --- Room labels and BAS overlay ------------------------------------------------------------

func _rebuild_room_labels() -> void:
	for child in room_labels.get_children():
		child.free()
	room_labels.visible = mode != Mode.EXPLORE
	for room in index.rooms:
		var label := Label3D.new()
		label.text = String(room.label).to_upper()
		label.font_size = 64 if float(room.area_m2) >= 40.0 else 44
		label.pixel_size = 0.0085
		label.rotation_degrees = Vector3(-90, 0, 0)
		label.position = Vector3(room.center.x, PlanGrid.FLOOR_TOP + 0.08, room.center.z)
		label.modulate = Color(0.13, 0.17, 0.2, 0.62)
		label.outline_size = 0
		label.double_sided = false
		label.no_depth_test = false
		label.set_meta("room_id", String(room.id))
		room_labels.add_child(label)
	if overlay:
		_refresh_overlay(true)

func toggle_overlay() -> void:
	overlay = not overlay
	overlay_by_mode[mode] = overlay
	equipment.set_mode_view(mode)
	_refresh_overlay(true)
	set_status("BAS view %s · rooms tinted by temperature vs setpoint" % ("on" if overlay else "off"))
	hud.tool_changed()

func _refresh_overlay(rebuild: bool = false) -> void:
	if not overlay:
		for child in overlay_root.get_children(): child.free()
		for label in room_labels.get_children():
			label.text = String(index.room_by_id(String(label.get_meta("room_id"))).get("label", "")).to_upper()
		return
	if rebuild:
		for child in overlay_root.get_children(): child.free()
		for room in index.rooms:
			for cell in room.cells:
				var tile := MeshInstance3D.new()
				var plane := PlaneMesh.new()
				plane.size = Vector2(PlanGrid.TILE, PlanGrid.TILE)
				tile.mesh = plane
				tile.position = PlanGrid.cell_center(cell) + Vector3(0, PlanGrid.FLOOR_TOP + 0.03, 0)
				tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tile.set_meta("room_id", String(room.id))
				overlay_root.add_child(tile)
	var materials: Dictionary = {}
	for tile in overlay_root.get_children():
		var room_id := String(tile.get_meta("room_id"))
		if not materials.has(room_id):
			materials[room_id] = _overlay_material(_room_state(room_id))
		tile.material_override = materials[room_id]
	for label in room_labels.get_children():
		var state: Dictionary = _room_state(String(label.get_meta("room_id")))
		var base := String(index.room_by_id(String(label.get_meta("room_id"))).get("label", "")).to_upper()
		label.text = base if state.is_empty() else "%s\n%s · %s" % [base, Units.temp(float(state.get("temp_c", 0.0)), 1), String(state.get("mode", "")) if bool(state.get("served", false)) else "no air"]

# A room's temperature for the overlay: the simulation's, or on a live station
# the linked room-temperature point of a VAV or thermostat in that room
# (judged against the comfort range, since station setpoints aren't linked).
func _room_state(room_id: String) -> Dictionary:
	if data.is_demo():
		return sim.zone_state(room_id)
	var temp := live_room_temp_c(room_id)
	if is_nan(temp):
		return {}
	return {"temp_c": temp, "active_cool_setpoint_c": DemoSimulation.COMFORT_MAX_C, "active_heat_setpoint_c": DemoSimulation.COMFORT_MIN_C, "served": true, "mode": "live"}

# The piece whose linked points include `ord`, or share its controller folder.
func owner_of_point(ord: String) -> String:
	var folder := ord.get_base_dir()
	var fallback := ""
	for item in model.objects:
		for binding in item.get("properties", {}).get("bindings", {}).values():
			var point := String(binding.get("point_id", ""))
			if point.is_empty() or String(binding.get("source", "")) != "niagara": continue
			if point == ord: return String(item.id)
			if fallback.is_empty() and point.get_base_dir() == folder: fallback = String(item.id)
	return fallback

# A trend on a live station starts with the station's own history for the
# chart's window (read through the SDK's history rollup), then samples live.
func _backfill_history(point_id: String) -> void:
	if not data.is_live():
		return
	var key := "%d|%s" % [data.live.get_instance_id(), point_id]
	if _backfilled.has(key):
		return
	_backfilled[key] = true
	var bias := history_time() - Time.get_unix_time_from_system()
	data.live.history(point_id, 4.0, func(reply: Dictionary) -> void:
		var samples: Array = []
		for bucket in reply.get("buckets", []):
			if bucket.get("avg") is float or bucket.get("avg") is int:
				samples.append([float(bucket.t) / 1000.0 + bias, float(bucket.avg)])
		if not samples.is_empty():
			history.prepend(point_id, samples)
			if is_instance_valid(hud): hud.card_trend.queue_redraw())

func live_room_temp_c(room_id: String) -> float:
	var owners: Array = []
	for vav_id in topology.get("terminals", {}):
		if String(topology.terminals[vav_id].get("zone_id", "")) == room_id: owners.append(String(vav_id))
	for item in model.objects_of(["tstat"]):
		if String(thermostat_room(String(item.id)).get("id", "")) == room_id: owners.append(String(item.id))
	for owner in owners:
		var binding: Dictionary = binding_for(String(owner), "space_temp")
		if String(binding.get("source", "")) != "niagara": continue
		var point: Dictionary = points.get_point(String(binding.get("point_id", "")))
		if not (point.get("value") is float) or not (point.get("quality_flags", []) as Array).has("good"): continue
		var unit := String(point.get("unit", "")).to_lower()
		var value := float(point.value)
		# Stations in the US mostly report °F; a value that only makes sense as °C is taken as °C.
		if unit.contains("c") and not unit.contains("f"): return value
		if unit.contains("f") or value > 45.0: return (value - 32.0) / 1.8
		return value
	return NAN

func _overlay_material(state: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var colour := Color(0.6, 0.6, 0.6, 0.25)
	if not state.is_empty():
		var temperature := float(state.get("temp_c", 21.0))
		var cool := float(state.get("active_cool_setpoint_c", state.get("cool_setpoint_c", 24.0)))
		var heat := float(state.get("active_heat_setpoint_c", state.get("heat_setpoint_c", 20.0)))
		if temperature > cool:
			colour = Color(0.95, 0.35, 0.2).lerp(Color(0.85, 0.1, 0.1), clampf((temperature - cool) / 3.0, 0.0, 1.0))
		elif temperature < heat:
			colour = Color(0.25, 0.55, 0.95).lerp(Color(0.2, 0.2, 0.85), clampf((heat - temperature) / 3.0, 0.0, 1.0))
		else:
			colour = Color(0.3, 0.8, 0.45)
		colour.a = 0.34
	material.albedo_color = colour
	return material

# --- Inspection (context card) ----------------------------------------------------------------

func action(label: String, glyph: String, callback: Callable) -> Dictionary:
	return {"label": label, "glyph": glyph, "call": callback}

func inspect(id: String) -> Dictionary:
	var info := _inspect(id)
	if not data.is_demo() and not info.is_empty():
		info.trends = live_trends(id)
	if job == null or info.is_empty():
		return info
	if not edit_block(edit_kind(id)).is_empty():
		info.actions = (info.get("actions", []) as Array).filter(func(entry: Dictionary) -> bool: return String(entry.glyph) not in EDIT_GLYPHS)
	if job.is_service_target(id):
		(info.actions as Array).push_front(action("Service · test and repair", "build", func() -> void: hud.open_service(id)))
	return info

# Trend lines for a piece on a live station: its linked points, raw station units.
func live_trends(id: String) -> Array:
	var colors := [Color("f2a65a"), Color("73d398"), Color("6fb7ff"), Color("c9a2ff")]
	var lines: Array = []
	var item: Dictionary = model.find_object(id)
	for role in PointMatcher.ROLES_BY_KIND.get(String(item.get("kind", "")), []):
		var binding: Dictionary = binding_for(id, String(role))
		if String(binding.get("source", "")) != "niagara" or lines.size() >= 3: continue
		var entry := {"point_id": String(binding.point_id), "label": String(PointMatcher.ROLE_LABELS.get(role, role)), "color": colors[lines.size()]}
		_backfill_history(String(binding.point_id))
		if role != "space_temp": entry.merge({"own_axis": true, "min": float(binding.get("input_min", 0.0)), "max": float(binding.get("input_max", 100.0))})
		lines.append(entry)
	return lines

func _inspect(id: String) -> Dictionary:
	var item: Dictionary = model.find_object(id)
	if item.is_empty():
		return {}
	var move := action("Move · M", "move", func() -> void: start_move(id))
	var turn := action("Rotate · R", "rotate", rotate_selected)
	var copy := action("Copy · Ctrl+D", "copy", duplicate_selected)
	var remove := action("Delete · Del", "hammer", delete_selected)
	match String(item.kind):
		"wall":
			var sides := index.edge_rooms(String(item.properties.edge))
			var names: Array[String] = []
			for side in sides:
				names.append(String(index.room_by_id(side).get("label", "Outside")) if not side.is_empty() else "Outside")
			return {"text": "2.5 m wall section\n%s  |  %s" % [names[0], names[1]], "actions": [action("Paint walls", "paint", func() -> void: start_tool("paint", {"style": hud.room_style})), remove]}
		"floor":
			var room := index.room_at_cell(BuildingIndex.cell_of(item))
			if room.is_empty():
				return {"text": "Outdoor surface · not part of a closed room", "actions": [remove]}
			return {"title": String(room.label), "subtitle": "Room · %s floor" % describe(id), "text": room_summary(room), "room": room, "trends": room_trends(String(room.id)), "actions": [action("Floor this room", "floor", func() -> void: start_tool("floor", {"finish": String(item.properties.get("finish", "oak"))})), remove]}
		"door":
			return {"text": "Hinged door · walk into it to open\nR flips the swing", "actions": [action("Flip swing", "rotate", rotate_selected), move, remove]}
		"window":
			return {"text": "Glazed opening · solar gain counts toward its room", "actions": [move, remove]}
		"furniture":
			var spec := placement.spec("furniture", String(item.properties.get("item", "")))
			return {"text": "%s · %s" % [String(spec.category).capitalize(), "on the wall" if String(spec.mount) == "wall" else "%d × %d studs" % [spec.footprint.x, spec.footprint.y]], "actions": [move, turn, copy, remove]}
		"tree", "shrub", "parking":
			return {"text": "Landscaping", "actions": [move, turn, copy, remove]}
		"tstat":
			var info := thermostat_info(id)
			var room := thermostat_room(id)
			return {"text": String(info.get("detail", "")), "trends": room_trends(String(room.get("id", ""))), "actions": [action("Adjust", "thermo", func() -> void: hud.show_thermostat(id)), move, remove]}
	var result: Dictionary = equipment.inspect(id)
	if result.is_empty():
		return {"text": String(item.kind).capitalize(), "actions": [remove]}
	return result

func room_summary(room: Dictionary) -> String:
	var state: Dictionary = sim.zone_state(String(room.id))
	var lines: Array[String] = ["%s · %s" % [String(room.type).replace("_", " ").capitalize(), Units.area(float(room.area_m2))]]
	if not state.is_empty():
		lines.append("%s · %s" % [Units.temp(float(state.get("temp_c", 0.0)), 1), String(state.get("mode", ""))])
		if bool(state.get("served", false)):
			lines.append("Setpoints %.0f – %.0f °F" % [Units.fahrenheit(float(state.get("heat_setpoint_c", 20.0))), Units.fahrenheit(float(state.get("cool_setpoint_c", 24.0)))])
		else:
			lines.append("No VAV serves this room yet")
	return "\n".join(lines)

func room_trends(room_id: String) -> Array:
	if room_id.is_empty():
		return []
	var lines: Array = [{"point_id": room_id + ".space_temp", "label": "Room", "color": Color("f2a65a"), "quantity": "temp"}]
	var state := sim.zone_state(room_id)
	var terminals: Array = state.get("terminals", [])
	if not terminals.is_empty():
		lines.append({"point_id": String(terminals[0]) + ".cool_setpoint", "label": "Cool", "color": Color("6fb7ff"), "quantity": "temp", "dashed": true})
	lines.append({"point_id": room_id + ".co2", "label": "CO₂", "color": Color("c9a2ff"), "quantity": "co2", "own_axis": true, "min": 400.0, "max": 1400.0})
	return lines

func rename_room(room_id: String, label: String) -> void:
	if job != null:
		return
	var room := index.room_by_id(room_id)
	var text := label.strip_edges()
	if room.is_empty() or text.is_empty() or text == String(room.label):
		return
	for cell in room.cells:
		model.site.room_names.erase(PlanGrid.cell_key(cell))
	model.site.room_names[PlanGrid.cell_key(room.cells[0])] = text
	refresh_world()
	set_status("Room renamed to %s" % text)

func set_room_type(room_id: String, type: String) -> void:
	if _blocked("architecture"):
		return
	var room := index.room_by_id(room_id)
	if room.is_empty():
		return
	for cell in room.cells:
		model.site.room_types.erase(PlanGrid.cell_key(cell))
	model.site.room_types[PlanGrid.cell_key(room.cells[0])] = type
	refresh_world()

# --- Thermostats ----------------------------------------------------------------------------

func thermostat_room(id: String) -> Dictionary:
	var item: Dictionary = model.find_object(id)
	if item.is_empty():
		return {}
	var position := vector(item.transform.position)
	var facing := Basis(Vector3.UP, float(item.transform.get("rotation_y", 0.0))) * Vector3(0, 0, 1)
	return index.room_at(position + facing * 0.8)

func thermostat_info(id: String) -> Dictionary:
	var item: Dictionary = model.find_object(id)
	var room := thermostat_room(id)
	if item.is_empty():
		return {}
	var anchor := vector(item.transform.position)
	if room.is_empty():
		return {"title": "Thermostat", "detail": "Hang it inside a closed room to control that room.", "anchor": anchor}
	if not data.is_demo():
		var reading := live_room_temp_c(String(room.id))
		var live_detail := "%s · live from the station (read-only)" % String(room.label)
		if is_nan(reading):
			return {"title": "Thermostat · %s" % String(room.label), "detail": live_detail + "\nLink a room-temperature point to this thermostat or the room's VAV.", "anchor": anchor}
		return {"title": "Thermostat · %s" % String(room.label), "temp_c": reading, "setpoint_c": NAN, "detail": live_detail, "anchor": anchor}
	var state: Dictionary = sim.zone_state(String(room.id))
	var detail := "%s · %s" % [String(room.label), String(state.get("mode", ""))]
	if not bool(state.get("served", false)):
		detail += "\nNo VAV serves this room · connect one in Equipment"
	elif state.has("airflow_m3_s"):
		detail += "\nSupply %s · %s" % [Units.temp(float(state.get("supply_c", 0.0))), Units.flow(float(state.get("airflow_m3_s", 0.0)))]
	if not data.is_demo():
		detail += "\nNiagara connected · demo setpoints paused"
	var midpoint := (float(state.get("cool_setpoint_c", 23.0)) + float(state.get("heat_setpoint_c", 21.0))) * 0.5
	return {"title": "Thermostat · %s" % String(room.label), "temp_c": float(state.get("temp_c", 0.0)), "setpoint_c": midpoint, "detail": detail, "anchor": anchor}

# `step_f` is in °F (the thermostat face); the simulation works in °C.
func adjust_thermostat(id: String, step_f: float) -> bool:
	if not data.is_demo():
		return false
	if job != null and job.phase not in ["onsite", "adjust", "design"]:
		set_status("Not now: %s" % job.phase_text().to_lower())
		return false
	var room := thermostat_room(id)
	if room.is_empty():
		return false
	var state: Dictionary = sim.zone_state(String(room.id))
	var step := Units.kelvin_from_f(step_f)
	var cool := clampf(float(state.get("cool_setpoint_c", 23.0)) + step, 17.0, 30.0)
	var heat := clampf(float(state.get("heat_setpoint_c", 21.0)) + step, 16.0, cool - 1.0)
	sim.set_zone_setpoints(String(room.id), cool, heat)
	points.apply_updates(data.provider.snapshot())
	return true

# --- Paint and bindings -----------------------------------------------------------------------

func paint_object(id: String, role: String, colour: Color, same_kind: bool) -> void:
	var target: Dictionary = model.find_object(id)
	if target.is_empty() or _blocked("architecture"):
		return
	var changes: Array = []
	for item in model.objects:
		if item.id != id and not (same_kind and item.kind == target.kind and item.properties.get("item", "") == target.properties.get("item", "")):
			continue
		var changed: Dictionary = item.duplicate(true)
		var paint: Dictionary = changed.properties.get("paint", {}).duplicate(true)
		if role.is_empty(): paint.clear()
		else: paint[role] = colour.to_html()
		changed.properties.paint = paint
		changes.append(changed)
	apply("Paint", [], [], changes)
	play_sound("paint")

func binding_for(id: String, role: String) -> Dictionary:
	var item: Dictionary = model.find_object(id)
	return item.get("properties", {}).get("bindings", {}).get(role, {}).duplicate(true)

func binding_description(id: String, role: String) -> String:
	var result := animation_sample(id, role)
	return "%s · %.0f %%" % [String(result.status), float(result.level) * 100.0] if bool(result.known) else "Unknown · " + String(result.status)

func attach_binding(id: String, role: String, binding: Dictionary) -> void:
	if demo_only and String(binding.get("source", "demo")) != "demo":
		return
	if _blocked("equipment"):
		return
	var item: Dictionary = model.find_object(id)
	if item.is_empty() or String(binding.get("point_id", "")).is_empty():
		set_status("Choose a point to link.")
		return
	if binding.mapping == "number" and float(binding.input_max) <= float(binding.input_min):
		set_status("Range maximum must be greater than minimum.")
		return
	if binding.mapping == "enum" and binding.enum_levels.is_empty():
		set_status("Add at least one state, for example Running=1.")
		return
	var changed: Dictionary = item.duplicate(true)
	var bindings: Dictionary = changed.properties.get("bindings", {}).duplicate(true)
	bindings[role] = binding.duplicate(true)
	bindings[role].automatic = false
	changed.properties.bindings = bindings
	changed.properties.binding_schema = 2
	apply("Link point", [], [], [changed])
	data.refresh_subscriptions()
	set_status("%s now follows %s" % [role.replace("_", " ").capitalize(), binding.point_id])

func reset_binding(id: String, role: String) -> void:
	var item: Dictionary = model.find_object(id)
	if item.is_empty():
		return
	var changed: Dictionary = item.duplicate(true)
	var bindings: Dictionary = changed.properties.get("bindings", {}).duplicate(true)
	bindings.erase(role)
	changed.properties.bindings = bindings
	apply("Reset link", [], [], [changed])

# --- Session ---------------------------------------------------------------------------------

func start_new_game(template: String, preserve: bool = true) -> void:
	if preserve and not model.objects.is_empty():
		model.save_to("user://before_new_game.json")
	if tool != null:
		finish_tool()
	data.use_demo()
	set_turbo(-1.0)
	sim.reset()
	sim.set_faults([])
	sim.set_controls(DemoSimulation.DEFAULT_CONTROLS)
	sim.running = true
	sim.speed = 1.0
	alarms.active.clear()
	alarms.timers.clear()
	model = Templates.create(template)
	commands = BuildCommandStack.new(model)
	selected_id = ""
	explorer.reset_state()
	refresh_world()
	if mode != Mode.BUILD:
		set_mode(Mode.BUILD)
	var camera: Dictionary = model.site.get("camera", {})
	if camera.is_empty():
		var box := _content_bounds()
		rig.set_view(box.get_center() * Vector3(1, 0, 1), -0.62, -0.86, clampf(maxf(box.size.x, box.size.z) * 1.25 + 14.0, 18.0, 150.0), true)
	else:
		rig.restore(camera)
	explorer.reset_player()
	if is_instance_valid(hud):
		hud.refresh_simulation_controls()
	set_status("%s · every piece is editable" % String(model.site.get("name", "New lot")))

func capture_save_state() -> void:
	model.site.open_doors = explorer.open_doors.duplicate()
	model.site.spawn = array(explorer.player.position)
	model.site.camera = rig.state()
	model.demo_checkpoint = sim.checkpoint()

func save_project() -> void:
	if job != null:
		set_status("Career jobs aren't saved part-way: finish the job, or leave it from the job panel.")
		play_sound("error")
		return
	capture_save_state()
	var error := model.save_to(SAVE_PATH)
	set_status("Saved · layout, equipment, paint and point bindings" if error == OK else "Save failed: " + error_string(error))
	play_sound("save" if error == OK else "error")
	if error == OK and OS.has_feature("web"): browser_files.saved()

func load_project() -> bool:
	# A job only ends once a build has actually loaded (_adopt ends it).
	var loaded := ProjectModel.new()
	if not loaded.load_from(SAVE_PATH):
		set_status("No saved build found.")
		return false
	_adopt(loaded)
	set_status("Build restored%s" % (" · converted from an earlier version" if loaded.migrated_from > 0 else ""))
	return true

func import_browser_save(raw: String) -> void:
	if raw.to_utf8_buffer().size() > 8 * 1024 * 1024:
		set_status("Import rejected: backup exceeds 8 MB.")
		return
	var parsed: Variant = JSON.parse_string(raw)
	var candidate := ProjectModel.new()
	if not parsed is Dictionary or not candidate.from_dictionary(parsed):
		set_status("Import rejected: not a valid Brick/BAS backup. Your build is unchanged.")
		if OS.has_feature("web"): browser_files.browser.warn(status_text)
		return
	capture_save_state()
	model.save_to("user://before_import.json")
	_adopt(candidate)
	if OS.has_feature("web"): browser_files.browser.warn("")
	session_ui.hide()
	session_ui.welcome = false
	set_status("Backup opened · Save to keep it in this browser")

func _adopt(loaded: ProjectModel) -> void:
	end_job()
	set_turbo(-1.0)
	if tool != null:
		finish_tool()
	if demo_only:
		_use_demo_bindings(loaded)
	model = loaded
	commands = BuildCommandStack.new(model)
	selected_id = ""
	data.use_demo()
	sim.reset()
	# Older saves carry no BAS programming: they get the defaults, not
	# whatever the last building was running.
	sim.set_controls(DemoSimulation.DEFAULT_CONTROLS)
	sim.set_faults([])
	explorer.reset_state()
	explorer.open_doors = model.site.get("open_doors", {}).duplicate()
	refresh_world()
	sim.restore_checkpoint(model.demo_checkpoint)
	if mode != Mode.BUILD:
		set_mode(Mode.BUILD)
	rig.restore(model.site.get("camera", {}))
	explorer.reset_player()
	hud.refresh_simulation_controls()

func _use_demo_bindings(project: ProjectModel) -> void:
	project.connections.clear()
	project.bindings.clear()
	for item in project.objects:
		var bindings: Dictionary = item.properties.get("bindings", {})
		for role in bindings.keys():
			if String(bindings[role].get("source", "demo")) != "demo":
				bindings.erase(role)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# --- Career jobs ------------------------------------------------------------------------------

func _edits_allowed(adds: Array, removes: Array, updates: Array) -> bool:
	var kinds: Dictionary = {}
	for entry in adds: kinds["equipment" if String(entry.get("kind", "")) in HvacCosts.HVAC_KINDS else "architecture"] = true
	for entry in updates: kinds["equipment" if String(entry.get("kind", "")) in HvacCosts.HVAC_KINDS else "architecture"] = true
	for id in removes: kinds[edit_kind(String(id))] = true
	for kind in kinds:
		if _blocked(String(kind)):
			return false
	return true

func edit_kind(id: String) -> String:
	return "equipment" if String(model.find_object(id).get("kind", "")) in HvacCosts.HVAC_KINDS else "architecture"

# Why an edit isn't allowed right now ("" when it is). In a career job the
# building is the client's; only an install job, while designing, lets you
# change the HVAC.
func edit_block(kind: String) -> String:
	if job == null:
		return ""
	if kind == "architecture":
		return "This is the client's building: walls, floors and furniture stay as they are."
	if job.can_edit_equipment():
		return ""
	match job.type:
		"service": return "On a service call you fix equipment in person: Tab to walk up to it, then E."
		"tune": return "On a tune-up you change the BAS programming (job panel), not the equipment."
	return "Stop the run to change the design."

func _blocked(kind: String) -> bool:
	var reason := edit_block(kind)
	if reason.is_empty():
		return false
	set_status(reason)
	play_sound("error")
	return true

func start_job(definition: Dictionary) -> void:
	end_job()
	start_new_game(String(definition.template), false)
	if String(definition.type) == "install":
		# The client's building, minus every piece of HVAC: that's the job.
		var kept: Array[Dictionary] = []
		for item in model.objects:
			if String(item.kind) not in HvacCosts.HVAC_KINDS: kept.append(item)
		model.objects = kept
		model.rebuild_index()
		commands = BuildCommandStack.new(model)
		refresh_world()
	job = JobSession.new(self, definition)
	job.changed.connect(_on_job_changed)
	job.begin()
	if is_instance_valid(hud):
		hud.job_started()
	explorer.refresh()

func _on_job_changed() -> void:
	if is_instance_valid(hud):
		hud.refresh_job()

# Leaves the job; the building stays as a sandbox (its BAS programming too),
# without the job's hidden faults.
func end_job() -> void:
	if job == null:
		return
	# A tampered thermostat nobody fixed goes back to normal with the faults.
	for fault in job.faults:
		if String(fault.kind) == "setpoint" and bool(fault.get("applied", false)) and not bool(fault.fixed):
			sim.set_zone_setpoints(String(fault.target), JobSession.STANDARD_COOL_C, JobSession.STANDARD_HEAT_C)
	job = null
	set_turbo(-1.0)
	sim.set_faults([])
	sim.running = true
	sim.speed = 1.0
	if is_instance_valid(hud):
		hud.job_started()
		hud.refresh_simulation_controls()
	explorer.refresh()
	_card_refresh()

func finish_job(result: Dictionary) -> void:
	set_turbo(-1.0)
	var stats: Dictionary = {}
	var outcome := career.record(String(result.job_id), int(result.stars), float(result.pay), stats)
	result.earned = float(outcome.earned)
	result.new_stars = int(outcome.new_stars)
	result.total_stars = career.total_stars()
	result.money = career.money
	play_sound("save" if int(result.stars) > 0 else "error")
	session_ui.show_results(result)

# A clean simulated day for a job: 06:30, the job's weather, default BAS
# programming, no faults, no alarms.
func reset_day(scenario: String) -> void:
	set_turbo(-1.0)
	history.mark_boundary("reset", sim.sim_seconds)
	sim.reset()
	sim.set_faults([])
	sim.set_controls(DemoSimulation.DEFAULT_CONTROLS)
	sim.set_scenario(scenario)
	sim.running = true
	sim.speed = 1.0
	alarms.active.clear()
	alarms.timers.clear()
	_last_open_signature = ""
	sync_openings()
	points.replace_snapshot(data.provider.snapshot())
	if is_instance_valid(hud):
		hud.refresh_simulation_controls()

func on_job_phase() -> void:
	# Whatever was open for editing closes when the job stops allowing it.
	if job != null and not job.can_edit_equipment():
		if tool != null and tool.id != "select":
			finish_tool()
		var bench: Control = equipment.workbench
		if is_instance_valid(bench) and bench.visible:
			bench.close()
	if is_instance_valid(hud):
		hud.refresh_job()
		hud.refresh_simulation_controls()
		hud.refresh_mode()
	explorer.refresh()
	_card_refresh()

func _card_refresh() -> void:
	if is_instance_valid(hud):
		hud._card_cache = ""
		hud.refresh_card()

func room_by_label(label: String) -> Dictionary:
	for room in index.rooms:
		if String(room.label) == label:
			return room
	return {}

func thermostat_in(room_id: String) -> String:
	for item in model.objects_of(["tstat"]):
		if String(thermostat_room(String(item.id)).get("id", "")) == room_id:
			return String(item.id)
	return ""

# --- Simulation controls ----------------------------------------------------------------------

func set_speed(value: float) -> void:
	if job != null and (job.phase != "onsite" or turbo_until > sim.sim_seconds):
		set_status("The job sets the clock right now: %s" % job.phase_text().to_lower())
		hud.refresh_simulation_controls()
		return
	sim.running = value > 0.0
	if value > 0.0: sim.speed = value
	hud.refresh_simulation_controls()

func set_scenario(value: String) -> void:
	if job != null:
		set_status("The weather is part of the job.")
		hud.refresh_simulation_controls()
		return
	sim.set_scenario(value)
	set_status("Scenario · %s" % value)

func reset_simulation() -> void:
	if job != null:
		set_status("The job sets the clock.")
		return
	history.mark_boundary("reset", sim.sim_seconds)
	var scenario := sim.scenario
	sim.reset()
	sim.configure(topology)
	sim.set_scenario(scenario)
	alarms.active.clear()
	alarms.timers.clear()
	_last_open_signature = ""
	sync_openings()
	hud.refresh_simulation_controls()

func animation_sample(id: String, role: String) -> Dictionary:
	if id == "preview":
		return {"known": true, "level": 0.65, "status": "Workbench preview"}
	var item: Dictionary = model.find_object(id)
	if item.is_empty():
		return Bindings.unknown("Object missing")
	var binding: Dictionary = item.properties.get("bindings", {}).get(role, {})
	return Bindings.evaluate(binding, points.get_point(String(binding.get("point_id", ""))), data.authority())

# --- Feedback ---------------------------------------------------------------------------------

func set_status(text: String) -> void:
	status_text = text
	if is_instance_valid(hud):
		hud.set_status(text)

func _setup_sound() -> void:
	sound_player = AudioStreamPlayer.new()
	sound_player.volume_db = -12.0
	add_child(sound_player)
	sound_enabled = DisplayServer.get_name() != "headless"
	# Kenney Interface Sounds (CC0): three clips, varied by pitch and level.
	var files := {
		"place": ["click_001", 1.0, 0.0], "tick": ["click_002", 1.6, -9.0], "select": ["click_002", 1.15, -4.0],
		"error": ["drop_001", 0.62, -2.0], "demolish": ["drop_001", 0.85, 0.0], "undo": ["click_002", 0.8, -3.0],
		"mode": ["click_001", 1.3, -5.0], "pickup": ["click_002", 1.35, -3.0], "paint": ["click_001", 1.25, -4.0],
		"save": ["click_001", 0.9, -2.0], "open": ["drop_001", 1.3, -6.0], "close": ["click_001", 0.75, -4.0],
	}
	for key in files:
		var path := "res://assets/third_party/kenney_interface/Audio/%s.ogg" % files[key][0]
		if ResourceLoader.exists(path):
			sounds[key] = {"stream": load(path), "pitch": float(files[key][1]), "db": float(files[key][2])}

func play_sound(kind: String) -> void:
	if not sound_enabled or not sounds.has(kind):
		return
	var sound: Dictionary = sounds[kind]
	sound_player.stream = sound.stream
	sound_player.pitch_scale = float(sound.pitch) * randf_range(0.96, 1.04)
	sound_player.volume_db = -12.0 + float(sound.db)
	sound_player.play()

func _capture_and_quit(path: String) -> void:
	session_ui.hide()
	for frame in range(20): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " ", error_string(error), " ", debug_stats())
	get_tree().quit(0 if error == OK else 1)

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func debug_stats() -> String:
	return "fps=%d draws=%d objects=%d prims=%d instances=%d" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), arch.batch.instance_count()]
