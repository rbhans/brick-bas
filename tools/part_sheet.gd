extends SceneTree

# Renders a labelled contact sheet of baked LDraw meshes for art direction.
# Usage: Godot --path . --script res://tools/part_sheet.gd -- --out=/abs/file.png [--parts=3005,3622] [--cols=8]
# Each part keeps its LDraw origin at the cell centre; the red/green/blue stub
# marks +X/+Y/+Z so orientation conventions are obvious in the render.

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var out := "/tmp/part_sheet.png"
	var parts: Array[String] = []
	var cols := 8
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): out = argument.trim_prefix("--out=")
		elif argument.begins_with("--parts="): parts.assign(argument.trim_prefix("--parts=").split(",", false))
		elif argument.begins_with("--cols="): cols = int(argument.trim_prefix("--cols="))
	if parts.is_empty():
		for file in DirAccess.get_files_at("res://assets/third_party/ldraw/meshes"):
			if file.ends_with(".obj"): parts.append(file.trim_suffix(".obj"))
	root.size = Vector2i(1600, 1000)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#2b3438")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#c9d6dd")
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	world.add_child(sun)
	var spacing := 6.0
	var rows := ceili(float(parts.size()) / float(cols))
	for index in range(parts.size()):
		var id := parts[index]
		var mesh := load("res://assets/third_party/ldraw/meshes/%s.obj" % id) as Mesh
		if mesh == null: continue
		var cell := Vector3(float(index % cols) * spacing, 0, float(index / cols) * spacing)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#d9d3c0")
		material.roughness = 0.7
		instance.material_override = material
		instance.position = cell
		world.add_child(instance)
		for axis in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
			var stub := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3.ONE * 0.06 + (axis[0] as Vector3).abs() * 0.6
			stub.mesh = box
			var axis_material := StandardMaterial3D.new()
			axis_material.albedo_color = axis[1]
			axis_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			stub.material_override = axis_material
			stub.position = cell + (axis[0] as Vector3) * 0.3
			world.add_child(stub)
		var label := Label3D.new()
		var aabb := mesh.get_aabb()
		label.text = "%s\n%.2f×%.2f×%.2f" % [id, aabb.size.x, aabb.size.y, aabb.size.z]
		label.font_size = 64
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = cell + Vector3(0, aabb.end.y + 0.6, 0)
		label.modulate = Color("#ffcf45")
		label.outline_size = 8
		world.add_child(label)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var width := float(cols) * spacing
	var depth := float(rows) * spacing
	camera.size = maxf(width * 0.62, depth * 0.95) + 4.0
	world.add_child(camera)
	var center := Vector3((float(cols) - 1.0) * spacing * 0.5, 0, (float(rows) - 1.0) * spacing * 0.5)
	camera.position = center + Vector3(0, 30, 30)
	camera.look_at(center)
	camera.make_current()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(out)
	print("PART_SHEET ", out, " ", error_string(error), " parts=", parts.size())
	quit(0)
