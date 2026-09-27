extends SceneTree

# Bakes 256 x 224 transparent UI thumbnails for every furniture item and for the
# HVAC equipment/components into res://assets/ui/thumbnails/<id>.png.
#
#   Godot --path . --script res://tools/bake_catalog_thumbnails.gd [-- --only=desk,ahu] [--out=res://...]
#
# Windowed (it renders). Follows tools/bake_ui_thumbnails.gd: an isolated
# SubViewport with a transparent background, studio lights and an orthographic
# camera fitted to the model's projected bounds.

const Furniture := preload("res://scripts/build/furniture_catalog.gd")
const Equipment := preload("res://scripts/build/equipment_models.gd")
const SIZE := Vector2i(256, 224)
const EQUIPMENT := ["ahu", "vav", "diffuser", "tee", "cross", "tstat", "damper", "filter", "cooling_coil", "heating_coil", "fan", "sensor"]

var viewport: SubViewport
var studio: Node3D
var camera: Camera3D

func _init() -> void:
	bake.call_deferred()

func arg(name: String, fallback: String = "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return fallback

func bake() -> void:
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	studio = Node3D.new()
	viewport.add_child(studio)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c5d9eb")
	environment.environment.ambient_light_energy = 0.6
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	studio.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.35
	studio.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12, 140, 0)
	fill.light_energy = 0.55
	studio.add_child(fill)
	var under := DirectionalLight3D.new()
	under.rotation_degrees = Vector3(70, 20, 0)
	under.light_energy = 0.35
	studio.add_child(under)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 200.0
	studio.add_child(camera)
	camera.make_current()
	var only := arg("only").split(",", false)
	var folder := arg("out", "res://assets/ui/thumbnails")
	var ids: Array[String] = []
	ids.append_array(Furniture.ids())
	ids.append_array(EQUIPMENT)
	var baked := 0
	for id in ids:
		if not only.is_empty() and id not in only:
			continue
		var model := Node3D.new()
		model.name = id
		studio.add_child(model)
		var direction := stage(model, id)
		fit(model, direction)
		for frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var path := "%s/%s.png" % [folder, id]
		var error := image.save_png(path)
		print("THUMBNAIL ", id, " ", error_string(error), " ", image.get_size())
		if error == OK:
			baked += 1
		model.free()
	print("THUMBNAILS_BAKED ", baked)
	viewport.free()
	quit()

# Builds the model and returns the direction the camera looks FROM.
func stage(model: Node3D, id: String) -> Vector3:
	var iso := Vector3(-0.46, 0.5, 0.75)
	var front_right := Vector3(0.5, 0.55, 0.75)
	if Furniture.ITEMS.has(id):
		Furniture.build(model, id)
		if String(Furniture.spec(id).get("mount", "floor")) == "wall":
			return Vector3(-0.3, 0.2, 0.95)
		return iso
	var result := {}
	match id:
		"ahu":
			result = Equipment.build_ahu(model, {"layout": ["damper", "cooling_coil", "fan"], "sensor_enabled": true})
			return pose(result, iso, 0.6)
		"vav":
			result = Equipment.build_vav(model, {"layout": ["damper", "heating_coil"], "sensor_enabled": true})
			return pose(result, iso, 0.6)
		"diffuser":
			Equipment.build_diffuser(model)
			return Vector3(-0.45, -0.55, 0.7)
		"tee":
			Equipment.build_tee(model)
			return Vector3(-0.5, 0.65, 0.6)
		"cross":
			Equipment.build_cross(model)
			return Vector3(-0.5, 0.65, 0.6)
		"tstat":
			Equipment.build_thermostat(model)
			return Vector3(-0.35, 0.2, 0.92)
		_:
			result = Equipment.build_component(model, id)
			return pose(result, front_right, 0.65)

func pose(result: Dictionary, direction: Vector3, amount: float) -> Vector3:
	for entry in result.get("animated", []):
		match String(entry.kind):
			"damper":
				(entry.node as Node3D).basis = Basis(entry.axis, lerpf(entry.closed, entry.open, amount))
			"fill":
				((entry.node as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("fill_level", amount)
	return direction

# Orthographic camera looking along -direction, sized to the projected bounds.
func fit(model: Node3D, direction: Vector3) -> void:
	var box := bounds(model)
	var center := box.get_center()
	var view := direction.normalized()
	camera.position = center + view * (box.size.length() + 10.0)
	camera.look_at(center, Vector3.UP if absf(view.y) < 0.95 else Vector3.FORWARD)
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var extent := Vector2.ZERO
	for i in range(8):
		var offset := box.get_endpoint(i) - center
		extent.x = maxf(extent.x, absf(offset.dot(right)))
		extent.y = maxf(extent.y, absf(offset.dot(up)))
	var aspect := float(SIZE.x) / float(SIZE.y)
	camera.size = maxf(extent.y * 2.0, extent.x * 2.0 / aspect) * 1.08 + 0.05

func bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if not instance.is_visible_in_tree():
			continue
		var box := instance.global_transform * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result
