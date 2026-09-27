extends SceneTree

# Renders a small sample plan with the architecture renderer for visual review.
# Godot --path . --script res://tools/arch_preview.gd -- --out=/abs.png [--yaw=-0.6 --pitch=-0.7 --dist=30 --walls=0]

func _init() -> void:
	run.call_deferred()

func arg(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name): return argument.trim_prefix("--%s=" % name)
	return fallback

func run() -> void:
	root.size = Vector2i(1280, 800)
	var stage := Stage.new()
	root.add_child(stage)
	var model := ProjectModel.new()
	var add := func(kind: String, props: Dictionary, position: Vector3 = Vector3.ZERO, rotation: float = 0.0) -> Dictionary:
		return model.add_object(kind, {"position": [position.x, position.y, position.z], "rotation_y": rotation}, props)
	# Two rooms side by side with a shared wall, a door between and to outside.
	var finishes := ["oak", "carpet_blue", "checker", "concrete", "tile_white", "paving"]
	for cell in PlanGrid.rect_cells(Vector2i(0, 0), Vector2i(4, 3)):
		add.call("floor", {"cell": [cell.x, cell.y], "finish": "oak"}, PlanGrid.cell_center(cell))
	for cell in PlanGrid.rect_cells(Vector2i(4, 0), Vector2i(7, 3)):
		add.call("floor", {"cell": [cell.x, cell.y], "finish": "carpet_blue"}, PlanGrid.cell_center(cell))
	for cell in PlanGrid.rect_cells(Vector2i(0, 3), Vector2i(3, 5)):
		add.call("floor", {"cell": [cell.x, cell.y], "finish": "checker"}, PlanGrid.cell_center(cell))
	for cell in PlanGrid.rect_cells(Vector2i(3, 3), Vector2i(7, 5)):
		add.call("floor", {"cell": [cell.x, cell.y], "finish": "concrete"}, PlanGrid.cell_center(cell))
	for cell in PlanGrid.rect_cells(Vector2i(2, 5), Vector2i(4, 7)):
		add.call("floor", {"cell": [cell.x, cell.y], "finish": "paving"}, PlanGrid.cell_center(cell))
	var edges := {}
	for edge in PlanGrid.rect_perimeter(Vector2i(0, 0), Vector2i(7, 5)): edges[edge] = "tan"
	for edge in PlanGrid.edges_between(Vector2i(4, 0), Vector2i(4, 3)): edges[edge] = "white"
	for edge in PlanGrid.edges_between(Vector2i(0, 3), Vector2i(7, 3)): edges[edge] = "white"
	for edge in PlanGrid.edges_between(Vector2i(3, 3), Vector2i(3, 5)): edges[edge] = "white"
	for edge in edges:
		add.call("wall", {"edge": edge, "style": edges[edge]}, PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge))
	add.call("door", {"edge": "z:4:1", "style": "door"})
	add.call("door", {"edge": "x:2:5", "style": "glass_door"})
	add.call("door", {"edge": "x:5:3", "style": "door_blue"})
	add.call("door", {"edge": "x:1:3", "style": "door"})
	add.call("window", {"edge": "x:1:0", "style": "window"})
	add.call("window", {"edge": "x:2:0", "style": "window"})
	add.call("window", {"edge": "x:5:0", "style": "window_dark"})
	add.call("window", {"edge": "z:0:1", "style": "tall_window"})
	add.call("window", {"edge": "z:7:1", "style": "window"})
	add.call("window", {"edge": "x:5:5", "style": "storefront"})
	add.call("tree", {"variant": "oak"}, Vector3(-3, 0, 4))
	add.call("tree", {"variant": "pine"}, Vector3(20, 0, 15))
	add.call("shrub", {}, Vector3(4, 0, 14))
	add.call("parking", {}, Vector3(14, 0, 18))
	var index := BuildingIndex.new()
	index.rebuild(model.objects, model.site)
	print("ROOMS ", index.rooms.size(), " ", index.rooms.map(func(r: Dictionary) -> String: return "%s %d cells ext=%d win=%d doors=%d" % [r.id, r.cells.size(), r.exterior_edges.size(), r.windows.size(), r.doors.size()]))
	var renderer := ArchitectureRenderer.new()
	var t := Time.get_ticks_usec()
	renderer.rebuild(stage, model.objects, index)
	print("BUILD_MS ", (Time.get_ticks_usec() - t) / 1000.0, " instances=", renderer.batch.instance_count(), " groups=", renderer.batch.groups.size())
	var camera := Camera3D.new()
	camera.fov = 38
	stage.add_child(camera)
	var target := Vector3(8.75, 1.0, 6.25)
	var yaw := float(arg("yaw", "-0.6"))
	var pitch := float(arg("pitch", "-0.72"))
	var distance := float(arg("dist", "34"))
	camera.position = target + Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, distance)
	camera.look_at(target)
	camera.make_current()
	var forward := -camera.global_basis.z
	BrickBatch.set_cutaway(int(arg("walls", "0")), target, forward, 60.0)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var out := arg("out", "/tmp/arch_preview.png")
	print("CAPTURE ", out, " ", error_string(root.get_texture().get_image().save_png(out)))
	quit(0)
