extends SceneTree

# Measures visible z-fighting the way a player sees it: aims the camera at a
# piece, renders while the camera creeps a millimetre a frame, and counts the
# pixels whose colour jumps between frames. Real edges barely move at that
# step; two surfaces fighting over one plane swap winners in patches.
# Needs a window (not --headless):
#   Godot --path . --script res://tools/flicker_probe.gd -- --out=/tmp/flicker

const FRAMES := 16
const JUMP := 0.12   # a channel change this large counts as a flip

var out := ""
var game: Node

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
	run.call_deferred()

func frames(count: int) -> void:
	for index in range(count): await process_frame

func run() -> void:
	game = load("res://scripts/game.gd").new()
	root.add_child(game)
	await frames(2)
	game.sound_enabled = false
	game.session_ui.hide()
	game.hud.visible = false
	game.start_new_game("school", false)
	game.set_mode(1)
	game.sim.running = false
	await frames(4)
	var targets: Array = []
	# A long duct run, seen from the side and from above a bend.
	var longest := ""
	var span := [Vector3.ZERO, Vector3.ZERO]
	for id in game.equipment.duct_paths:
		var path: Array = game.equipment.duct_paths[id]
		for index in range(path.size() - 1):
			if (path[index] as Vector3).distance_to(path[index + 1]) > (span[0] as Vector3).distance_to(span[1]) and absf((path[index] as Vector3).y - (path[index + 1] as Vector3).y) < 0.01:
				span = [path[index], path[index + 1]]
				longest = String(id)
	targets.append(["duct_run", ((span[0] as Vector3) + (span[1] as Vector3)) * 0.5, -0.55, -0.35, 7.0])
	for id in game.equipment.duct_paths:
		var path: Array = game.equipment.duct_paths[id]
		if path.size() >= 3:
			targets.append(["duct_bend", path[1], 0.7, -0.75, 6.0])
			break
	for kind in ["vav", "cross", "tee"]:
		var units: Array = game.model.objects_of([kind])
		if not units.is_empty():
			var root_node: Node3D = game.equipment.roots[String(units[0].id)]
			targets.append([kind, root_node.global_position + Vector3(0, 0.5, 0), 0.9, -0.5, 5.0])
	for item in game.model.objects_of(["furniture"]):
		if String(item.properties.get("item", "")) == "lamp_post":
			var at: Array = item.transform.position
			targets.append(["lamp_post", Vector3(float(at[0]), 4.7, float(at[2])), 0.4, -0.25, 4.5])
			break
	for target in targets:
		var result := await measure(String(target[0]), target[1], float(target[2]), float(target[3]), float(target[4]))
		print("FLICKER %-10s flipped %.3f %% of pixels per frame (peak %.3f %%)" % [target[0], result.x * 100.0, result.y * 100.0])
	quit()

func measure(name: String, focus: Vector3, yaw: float, pitch: float, distance: float) -> Vector2:
	# Settle on the view first, so the cut to it doesn't count.
	game.rig.set_view(focus, yaw, pitch, distance, true)
	await frames(12)
	var previous: Image = null
	var total := 0.0
	var peak := 0.0
	var marks: Image = null
	for index in range(FRAMES + 1):
		# Creep sideways a millimetre a frame: edges stay put, fights don't.
		game.rig.set_view(focus + Vector3(0.001 * index, 0, 0.0007 * index), yaw, pitch, distance, true)
		await frames(3)
		var image := root.get_viewport().get_texture().get_image()
		if index == 0 and not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out)
			image.save_png(out.path_join(name + ".png"))
		if marks == null:
			marks = image.duplicate()
		if previous != null:
			var flipped := 0
			var size := image.get_size()
			var counted := 0
			for y in range(0, size.y, 2):
				for x in range(0, size.x, 2):
					var a := image.get_pixel(x, y)
					var b := previous.get_pixel(x, y)
					counted += 1
					if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > JUMP:
						flipped += 1
						marks.set_pixel(x, y, Color.MAGENTA)
						if x + 1 < size.x: marks.set_pixel(x + 1, y, Color.MAGENTA)
			var fraction := float(flipped) / float(counted)
			total += fraction
			peak = maxf(peak, fraction)
		previous = image
	if not out.is_empty() and marks != null:
		marks.save_png(out.path_join(name + "_flips.png"))
	return Vector2(total / FRAMES, peak)
