extends SceneTree

# Bakes catalogue thumbnails for architecture pieces (256 x 224, transparent)
# into res://assets/ui/thumbnails/. Run windowed:
#   Godot --path . --script res://tools/bake_arch_thumbnails.gd

const SIZE := Vector2i(256, 224)

var viewport: SubViewport
var studio: Node3D
var camera: Camera3D

func _init() -> void:
	bake.call_deferred()

func entry(kind: String, props: Dictionary, position: Vector3 = Vector3.ZERO, rotation: float = 0.0) -> Dictionary:
	return {"id": "thumb-%d" % randi(), "kind": kind, "floor_id": "floor-1", "transform": {"position": [position.x, position.y, position.z], "rotation_y": rotation}, "properties": props}

func wall(edge: String, style: String = "tan") -> Dictionary:
	return entry("wall", {"edge": edge, "style": style}, PlanGrid.edge_center(edge), PlanGrid.edge_rotation(edge))

func floor_tile(cell: Vector2i, finish: String) -> Dictionary:
	return entry("floor", {"cell": [cell.x, cell.y], "finish": finish}, PlanGrid.cell_center(cell))

func setup_studio() -> void:
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
	environment.environment.ambient_light_energy = 0.42
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment.tonemap_exposure = 0.95
	studio.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -32, 0)
	key.light_energy = 1.05
	studio.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 140, 0)
	fill.light_energy = 0.3
	studio.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	studio.add_child(camera)
	camera.make_current()

func shoot(id: String, objects: Array, view: Vector3 = Vector3(1.6, 1.35, 2.4), zoom: float = 1.0) -> void:
	var holder := Node3D.new()
	studio.add_child(holder)
	var index := BuildingIndex.new()
	index.rebuild(objects)
	var renderer := ArchitectureRenderer.new()
	renderer.preview_mode = true
	renderer.rebuild(holder, objects, index)
	var box := AABB()
	var first := true
	for owner in renderer.batch.owners:
		var part := renderer.batch.owner_bounds(owner)
		box = part if first else box.merge(part)
		first = false
	var center := box.get_center()
	var direction := view.normalized()
	camera.position = center + direction * 40.0
	camera.look_at(center)
	# Fit the projected bounds on both screen axes.
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var half := Vector2.ZERO
	for i in range(8):
		var offset := box.get_endpoint(i) - center
		half = half.max(Vector2(absf(offset.dot(right)), absf(offset.dot(up))))
	var aspect := float(SIZE.x) / float(SIZE.y)
	camera.size = maxf(maxf(half.y * 2.0, half.x * 2.0 / aspect) * 1.12, 0.6) * zoom
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var error := image.save_png("res://assets/ui/thumbnails/%s.png" % id)
	print("THUMB ", id, " ", error_string(error))
	renderer.clear()
	holder.free()

func bake() -> void:
	setup_studio()
	# Tools.
	var room: Array = []
	for edge in PlanGrid.rect_perimeter(Vector2i(0, 0), Vector2i(2, 2)): room.append(wall(edge, "tan"))
	for cell in PlanGrid.rect_cells(Vector2i(0, 0), Vector2i(2, 2)): room.append(floor_tile(cell, "oak"))
	room.append(entry("door", {"edge": "x:0:2", "style": "door"}))
	room.append(entry("window", {"edge": "z:0:1", "style": "window"}))
	# Show the room open toward the camera: drop the two near walls.
	room = room.filter(func(item: Dictionary) -> bool: return item.kind != "wall" or String(item.properties.edge) not in ["x:1:2", "z:2:1"])
	room = room.filter(func(item: Dictionary) -> bool: return item.kind != "door")
	await shoot("tool_room", room)
	await shoot("tool_wall", [wall("x:0:0"), wall("z:1:0"), wall("x:1:0")], Vector3(1.4, 1.0, 2.6))
	await shoot("tool_floor", [floor_tile(Vector2i(0, 0), "oak"), floor_tile(Vector2i(1, 0), "oak")], Vector3(1.0, 2.2, 1.6))
	await shoot("tool_door", [wall("x:0:0"), entry("door", {"edge": "x:0:0", "style": "door"})], Vector3(0.9, 0.7, 2.6), 0.95)
	await shoot("tool_window", [wall("x:0:0"), entry("window", {"edge": "x:0:0", "style": "window"})], Vector3(0.9, 0.7, 2.6), 0.95)
	# Wall styles: a corner so both faces and the bond read.
	for style in ArchitectureRenderer.WALL_STYLES:
		await shoot("wall_" + style, [wall("x:0:0", style), wall("z:1:0", style)], Vector3(1.3, 0.9, 2.6))
	for finish in ArchitectureRenderer.FLOOR_FINISHES:
		await shoot("floor_" + finish, [floor_tile(Vector2i(0, 0), finish), floor_tile(Vector2i(1, 0), finish), floor_tile(Vector2i(0, 1), finish), floor_tile(Vector2i(1, 1), finish)], Vector3(1.0, 2.4, 1.6), 0.8)
	for style in ArchitectureRenderer.DOOR_STYLES:
		await shoot("door_" + style, [wall("x:0:0"), entry("door", {"edge": "x:0:0", "style": style})], Vector3(0.9, 0.7, 2.6), 0.95)
	for style in ArchitectureRenderer.WINDOW_STYLES:
		await shoot("window_" + style, [wall("x:0:0"), entry("window", {"edge": "x:0:0", "style": style})], Vector3(0.9, 0.7, 2.6), 0.95)
	for variant in ArchitectureRenderer.TREES:
		await shoot("tree_" + variant, [entry("tree", {"variant": variant})], Vector3(1.0, 0.7, 2.4), 0.9)
	await shoot("shrub", [entry("shrub", {})], Vector3(1.0, 0.9, 2.4), 0.9)
	await shoot("parking", [floor_tile(Vector2i(0, 0), "asphalt"), floor_tile(Vector2i(0, 1), "asphalt"), entry("parking", {}, Vector3(1.25, 0, 2.5))], Vector3(1.0, 2.2, 1.6), 0.85)
	quit(0)
