class_name ZoneTool
extends BuildTool

# Click a room to make it a conditioned zone: a VAV sized to the room,
# diffusers, a thermostat and the ducts to the nearest free supply socket,
# all in one undoable step.

var room: Dictionary = {}

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "zone"
	label = "Zone a room"
	shows_grid = false

func exit() -> void:
	game.clear_marks()
	super.exit()

func _room_ids(target: Dictionary) -> Array:
	var ids: Array = []
	for cell in target.get("cells", []):
		var floor: Dictionary = game.index.floors.get(PlanGrid.cell_key(cell), {})
		if not floor.is_empty(): ids.append(String(floor.id))
	return ids

func hover(mouse: Vector2) -> void:
	var point: Vector3 = game.rig.ground_point(mouse, PlanGrid.FLOOR_TOP)
	var found: Dictionary = game.index.room_at(point) if point != Vector3.INF else {}
	if String(found.get("id", "")) != String(room.get("id", "")):
		game.clear_marks()
		room = found
		if not room.is_empty():
			game.mark(_room_ids(room), "paint")
	if room.is_empty():
		game.set_status("Zone a room · point at a closed room")
		return
	var state: Dictionary = game.sim.zone_state(String(room.id))
	if bool(state.get("served", false)):
		game.set_status("%s already has air · Shift-click to add another VAV" % String(room.label))
	else:
		game.set_status("Zone %s · %s · adds a VAV, diffusers and a thermostat, ducted to the nearest supply" % [String(room.label), Units.area(float(room.area_m2))])

func press(_mouse: Vector2) -> void:
	if room.is_empty():
		return
	var state: Dictionary = game.sim.zone_state(String(room.id))
	if bool(state.get("served", false)) and not Input.is_key_pressed(KEY_SHIFT):
		game.play_sound("error")
		return
	var planner := ZonePlanner.new(game.model.objects, game.index, game.model.new_id)
	var vav := planner.zone(room, "VAV · %s" % String(room.label))
	if vav.is_empty():
		game.play_sound("error")
		game.set_status(planner.error)
		return
	var result: Dictionary = game.apply("Zone %s" % String(room.label), planner.entries, planner.removed_ids())
	game.clear_marks()
	game.flash(result.added)
	game.play_sound("place")
	game.select(String(vav.id))
	game.set_status("%s is now a zone · %d pieces placed and ducted%s" % [String(room.label), planner.entries.size(), " · tapped into the main with a trunk cross" if not planner.removed.is_empty() else ""])
	room = {}
