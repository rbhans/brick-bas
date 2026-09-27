class_name SelectTool
extends BuildTool

# Default tool: hover highlights, click selects, press-and-drag picks a
# movable piece up (Sims-style) and hands over to its placement tool.

var hovered := ""
var candidate := ""

func _init(owner: Node, tool_params: Dictionary = {}) -> void:
	super(owner, tool_params)
	id = "select"
	label = "Select"
	shows_grid = false

func exit() -> void:
	game.set_hover("")
	super.exit()

func hover(mouse: Vector2) -> void:
	var hit: Dictionary = game.pick(mouse)
	hovered = String(hit.get("id", ""))
	game.set_hover(hovered)
	if hovered.is_empty():
		game.set_status(game.idle_hint())
	else:
		game.set_status("%s · click to select · drag to move" % game.describe(hovered))

func press(mouse: Vector2) -> void:
	var hit: Dictionary = game.pick(mouse)
	candidate = String(hit.get("id", ""))
	game.select(candidate, hit)

func drag(mouse: Vector2) -> void:
	if candidate.is_empty() or mouse.distance_to(press_screen) < 7.0:
		return
	if game.can_move(candidate):
		var id_to_move := candidate
		candidate = ""
		pressed = false
		game.start_move(id_to_move)

func release(_mouse: Vector2) -> void:
	candidate = ""

func key(event: InputEventKey) -> bool:
	match event.physical_keycode:
		KEY_R:
			game.rotate_selected()
			return true
		KEY_M:
			if not game.selected_id.is_empty() and game.can_move(game.selected_id):
				game.start_move(game.selected_id)
			return true
		KEY_DELETE, KEY_BACKSPACE:
			game.delete_selected()
			return true
		KEY_D:
			if event.ctrl_pressed or event.meta_pressed:
				game.duplicate_selected()
				return true
	return false
