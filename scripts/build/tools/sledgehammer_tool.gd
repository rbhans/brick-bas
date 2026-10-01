class_name SledgehammerTool
extends BuildTool

# Click a piece to knock it out, or drag a box across the lot to clear an
# area. Everything highlighted red goes in one undoable swing.

var hovered := ""
var start_point := Vector3.INF
var doomed: Array = []

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "delete"
	label = "Sledgehammer"
	shows_grid = false

func exit() -> void:
	game.clear_marks()
	game.hide_area()
	super.exit()

func hover(mouse: Vector2) -> void:
	var hit: Dictionary = game.pick(mouse)
	var found := String(hit.get("id", ""))
	if found != hovered:
		hovered = found
		game.clear_marks()
		if not hovered.is_empty():
			game.mark([hovered], "delete")
	game.set_status("Sledgehammer · %s · drag to clear an area" % (game.describe(hovered) if not hovered.is_empty() else "click a piece"))

func press(mouse: Vector2) -> void:
	start_point = game.rig.ground_point(mouse, PlanGrid.FLOOR_TOP)
	doomed.clear()

func drag(mouse: Vector2) -> void:
	if start_point == Vector3.INF or mouse.distance_to(press_screen) < 8.0:
		return
	var point: Vector3 = game.rig.ground_point(mouse, PlanGrid.FLOOR_TOP)
	if point == Vector3.INF:
		return
	var area := Rect2(Vector2(start_point.x, start_point.z), Vector2.ZERO).expand(Vector2(point.x, point.z))
	doomed = game.objects_in_area(area)
	game.clear_marks()
	game.mark(doomed, "delete")
	game.show_area(area)
	game.set_status("Sledgehammer · %d piece%s · release to clear" % [doomed.size(), "" if doomed.size() == 1 else "s"])

func release(mouse: Vector2) -> void:
	game.hide_area()
	var targets: Array = doomed.duplicate()
	if mouse.distance_to(press_screen) < 8.0 or targets.is_empty():
		targets = [hovered] if not hovered.is_empty() else []
	# In a career job only what the job lets you change can go.
	targets = targets.filter(func(id: Variant) -> bool: return game.edit_block(game.edit_kind(String(id))).is_empty())
	doomed.clear()
	game.clear_marks()
	if targets.is_empty():
		return
	var plan: Dictionary = game.removal_plan(targets)
	var removes: Array = plan.removes
	game.apply("Demolish", plan.adds, removes)
	game.play_sound("demolish")
	game.set_status("Cleared %d piece%s" % [removes.size(), "" if removes.size() == 1 else "s"])
	hovered = ""
	hover(mouse)
