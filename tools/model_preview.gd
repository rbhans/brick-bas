extends SceneTree

# Windowed review renders for furniture and HVAC equipment models.
#
#   Parts sheet:  --parts=4079,1 [--back]                    (3 views per part)
#   Furniture:    --items=desk,sofa|all [--cols=4] [--fig] [--label] [--view=iso|explore|front|top|low|side|back]
#   Equipment:    --equip=ahu:damper+filter+cooling_coil+fan,vav:damper+heating_coil,diffuser,tee,cross,tstat
#                 [--open] [--doors] [--covers=0] [--anim=0..1]
#   Scenes:       --scene=office|school|lounge|kitchen|bath|mech|outdoor|hvac
#   Check:        --check   (headless OK) builds everything, validates, prints MODEL_CHECK PASS/FAIL
#   Common:       --out=/abs.png --size=1600x1000 --yaw= --pitch= --dist= --zoom= --fov= --target=x,y,z --timeout=60
#
# Only depends on Bricks, PlanGrid, Stage, BrickBatch and the model scripts.

const Furniture := preload("res://scripts/build/furniture_catalog.gd")
const Equipment := preload("res://scripts/build/equipment_models.gd")

var stage: Stage
var world: Node3D
var camera: Camera3D
var focus := AABB()

func _init() -> void:
	run.call_deferred()

func arg(name: String, fallback: String = "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return fallback

func flag(name: String) -> bool:
	return ("--%s" % name) in OS.get_cmdline_user_args()

func run() -> void:
	if flag("check"):
		var holder := Node3D.new()
		root.add_child(holder)
		var ok := ModelCheck.run_all(holder)
		quit(0 if ok else 1)
		return
	# Never hang a capture session (occluded windows can stall frames).
	var watchdog := create_timer(float(arg("timeout", "60")))
	watchdog.timeout.connect(func() -> void:
		print("MODEL_PREVIEW timeout")
		quit(2))
	var size_text := arg("size", "1600x1000").split("x")
	root.size = Vector2i(int(size_text[0]), int(size_text[1]))
	stage = Stage.new()
	root.add_child(stage)
	world = Node3D.new()
	world.name = "Preview world"
	root.add_child(world)
	camera = Camera3D.new()
	camera.fov = float(arg("fov", "30"))
	camera.far = 600.0
	root.add_child(camera)
	camera.make_current()
	if not arg("parts").is_empty():
		await render_parts(arg("parts").split(",", false))
	elif not arg("items").is_empty():
		await render_items(arg("items"))
	elif not arg("equip").is_empty():
		await render_equipment(arg("equip"))
	elif not arg("scene").is_empty():
		await render_scene(arg("scene"))
	quit(0)

func clear_world() -> void:
	for child in world.get_children():
		child.free()

func aim(center: Vector3, yaw: float, pitch: float, distance: float) -> void:
	camera.position = center + Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, distance)
	camera.look_at(center)

func capture() -> Image:
	for frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

func save(image: Image, fallback: String) -> void:
	var out := arg("out", fallback)
	print("CAPTURE ", out, " ", error_string(image.save_png(out)))

# Frames the focus box from the requested view, unless overridden.
func frame_view(default_view: String = "iso") -> void:
	var view := arg("view", default_view)
	var yaw := -0.55
	var pitch := -0.62
	match view:
		"explore":
			yaw = -0.38
			pitch = -0.36
		"front":
			yaw = 0.0
			pitch = -0.18
		"top":
			yaw = 0.0
			pitch = -1.45
		"low":
			yaw = -0.5
			pitch = 0.3
		"side":
			yaw = PI * 0.5
			pitch = -0.2
		"back":
			yaw = PI - 0.55
			pitch = -0.55
	yaw = float(arg("yaw", str(yaw)))
	pitch = float(arg("pitch", str(pitch)))
	var center := focus.get_center()
	var radius := maxf(focus.size.length() * 0.5, float(arg("minradius", "1.6")))
	var distance := radius / sin(deg_to_rad(camera.fov * 0.5)) * float(arg("zoom", "0.95"))
	distance = float(arg("dist", str(distance)))
	if arg("target") != "":
		var t := arg("target").split(",")
		center = Vector3(float(t[0]), float(t[1]), float(t[2]))
	aim(center, yaw, pitch, distance)
	stage.focus_shadows(distance)

func grow_focus(box: AABB) -> void:
	focus = box if focus.size == Vector3.ZERO else focus.merge(box)

static func node_bounds(node: Node) -> AABB:
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

# --- Floor, walls and reference figures ---------------------------------------

func floor_pad(center: Vector3, size: Vector2, tint: Variant = "tan") -> void:
	var pad := Bricks.box(world, Vector3(size.x, PlanGrid.FLOOR_TOP, size.y), center + Vector3(0, PlanGrid.FLOOR_TOP * 0.5 - 0.001, 0), tint)
	pad.material_override = pad.material_override.duplicate()
	(pad.material_override as StandardMaterial3D).albedo_color = Bricks.color(tint).darkened(0.05)

func wall_backdrop(origin: Vector3, width: float, basis: Basis) -> void:
	var wall := Bricks.box(world, Vector3(width, PlanGrid.WALL_HEIGHT, 0.5), Vector3.ZERO, "white")
	wall.transform = Transform3D(basis, origin + basis * Vector3(0, PlanGrid.WALL_HEIGHT * 0.5, -0.25))

func figure(parent: Node3D, position: Vector3, facing: float, seated: bool, shirt: Color = Color("#d6453d")) -> Node3D:
	var fig := Node3D.new()
	fig.name = "Reference minifig"
	parent.add_child(fig)
	fig.scale = Vector3.ONE * 0.9
	var skin := Color("#f6ce4f")
	var legs_color := Color("#294453")
	Bricks.spawn(fig, "3815b", Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)), legs_color)
	Bricks.spawn(fig, "973", Transform3D(Basis.IDENTITY, Vector3(0, 1.8, 0)), shirt)
	Bricks.spawn(fig, "3626c", Transform3D(Basis.IDENTITY, Vector3(0, 2.4, 0)), skin)
	for leg in ["3817b", "3816b"]:
		var holder := Node3D.new()
		holder.position = Vector3(0, 0.7, 0)
		fig.add_child(holder)
		Bricks.spawn(holder, leg, Transform3D.IDENTITY, legs_color)
		if seated:
			holder.rotation.x = PI * 0.5
	for arm in [["3819", 0.3888, 0.171], ["3818", -0.3888, -0.171]]:
		var holder := Node3D.new()
		holder.position = Vector3(arm[1], 1.575, 0)
		holder.rotation.z = arm[2]
		holder.rotation.x = 0.5 if seated else 0.0
		fig.add_child(holder)
		Bricks.spawn(holder, arm[0], Transform3D.IDENTITY, shirt)
		Bricks.spawn(holder, "3820", Transform3D(Basis(Vector3.RIGHT, -PI * 0.25), Vector3(0.12 * signf(arm[1]), -0.475, -0.247)), skin)
	fig.rotation.y = facing
	# Seat positions are the pelvis rest point; the seated figure's lowest
	# point (back of the thighs) is 0.45 LDU-metres below its hip joint.
	fig.position = position - (Vector3(0, 0.45 * 0.9, 0) if seated else Vector3.ZERO)
	return fig

# --- Furniture --------------------------------------------------------------

func item_ids(list: String) -> Array[String]:
	var ids: Array[String] = []
	if list == "all":
		ids = Furniture.ids()
	elif list.begins_with("cat:"):
		for id in Furniture.ids():
			if String(Furniture.spec(id).get("category", "")) in list.trim_prefix("cat:").split("+"):
				ids.append(id)
	else:
		for id in list.split(",", false):
			ids.append(id)
	return ids

# Builds one item on a floor pad (or against a wall) centred at `center`.
func stage_item(id: String, center: Vector3, cell: float) -> AABB:
	var info := Furniture.spec(id)
	var outdoor := String(info.get("category", "")) == "outdoor"
	var holder := Node3D.new()
	holder.name = id
	world.add_child(holder)
	var base_y := 0.0 if outdoor else PlanGrid.FLOOR_TOP
	if not outdoor:
		floor_pad(center, Vector2(cell - 0.3, cell - 0.3), "light_nougat")
	var anchor := center
	if String(info.get("mount", "floor")) == "wall":
		anchor = center + Vector3(0, 0, -1.0)
		wall_backdrop(anchor, cell - 0.3, Basis.IDENTITY)
	holder.position = anchor + Vector3(0, base_y, 0)
	holder.rotation.y = float(arg("rot", "0"))
	var options := {}
	if arg("variant") != "":
		options["variant"] = arg("variant")
	var result := Furniture.build(holder, id, options)
	var pieces := holder.find_children("*", "MeshInstance3D", true, false).size()
	print("ITEM %s pieces=%d seats=%d" % [id, pieces, result.get("seats", []).size()])
	var box := node_bounds(holder)
	if flag("fig"):
		var width := float(info.footprint.x) * 0.25
		figure(holder, Vector3(width + 0.7, 0, 0.6), PI - 0.5, false)
		for seat in result.get("seats", []):
			figure(holder, seat.position, seat.facing, true, Color.from_hsv(randf(), 0.6, 0.8))
		box = node_bounds(holder)
	if flag("label"):
		var label := Label3D.new()
		label.text = "%s  %dx%d  %d pcs" % [id, info.footprint.x, info.footprint.y, pieces]
		label.font_size = 64
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color("#fff6c8")
		label.outline_size = 12
		label.position = center + Vector3(0, 0.3, cell * 0.42)
		world.add_child(label)
	return box

func render_items(list: String) -> void:
	var ids := item_ids(list)
	var cols := int(arg("cols", str(mini(ids.size(), 4))))
	var cell := float(arg("cell", "5.5"))
	if flag("sheet"):
		var tile := Vector2i(int(arg("tile", "520x400").split("x")[0]), int(arg("tile", "520x400").split("x")[1]))
		root.size = tile * 2
		var rows := ceili(float(ids.size()) / float(cols))
		var sheet := Image.create(tile.x * cols, tile.y * rows, false, Image.FORMAT_RGBA8)
		for index in range(ids.size()):
			clear_world()
			focus = stage_item(ids[index], Vector3.ZERO, cell)
			frame_view()
			var image: Image = await capture()
			image.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i((index % cols) * tile.x, (index / cols) * tile.y))
		save(sheet, "/tmp/items_sheet.png")
		return
	for index in range(ids.size()):
		grow_focus(stage_item(ids[index], Vector3(float(index % cols) * cell, 0, float(index / cols) * cell), cell))
	frame_view()
	save(await capture(), "/tmp/items.png")

# --- Equipment --------------------------------------------------------------

# "ahu:damper+filter+fan" -> kind + layout.
func parse_equipment(entry: String) -> Dictionary:
	var parts := entry.split(":")
	var layout: Array[String] = []
	if parts.size() > 1:
		for role in parts[1].split("+", false):
			layout.append(role)
	return {"kind": parts[0], "layout": layout}

static func build_equipment(parent: Node3D, kind: String, layout: Array[String], options: Dictionary) -> Dictionary:
	match kind:
		"ahu":
			return Equipment.build_ahu(parent, {"layout": layout if not layout.is_empty() else ["damper", "filter", "cooling_coil", "heating_coil", "fan"], "sensor_enabled": true}, options)
		"vav":
			return Equipment.build_vav(parent, {"layout": layout if not layout.is_empty() else ["damper", "heating_coil"], "sensor_enabled": true}, options)
		"diffuser":
			return Equipment.build_diffuser(parent, options)
		"tee":
			return Equipment.build_tee(parent, options)
		"cross":
			return Equipment.build_cross(parent, options)
		"tstat":
			return Equipment.build_thermostat(parent, options)
	return Equipment.build_component(parent, kind, options)

static func pose(result: Dictionary, amount: float) -> void:
	for entry in result.get("animated", []):
		var node: Node3D = entry.node
		match String(entry.kind):
			"rotation":
				node.basis = Basis((entry.axis as Vector3).normalized(), amount * TAU * 0.13)
			"damper":
				node.basis = Basis((entry.axis as Vector3).normalized(), lerpf(float(entry.closed), float(entry.open), amount))
			"fill":
				var material := (node as MeshInstance3D).material_override as ShaderMaterial
				var rows := maxi(1, int(entry.rows))
				var level := clampf(amount * float(rows) - float(entry.row), 0.0, 1.0)
				material.set_shader_parameter("fill_level", level)

func stage_equipment(entry: String, x: float) -> AABB:
	var parsed := parse_equipment(entry)
	var kind := String(parsed.kind)
	var options := {"open": flag("open"), "preview": flag("preview")}
	var holder := Node3D.new()
	holder.name = entry
	world.add_child(holder)
	var result := build_equipment(holder, kind, parsed.layout, options)
	var pieces := 0
	for mesh in holder.find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("ldraw_part_id"):
			pieces += 1
	print("EQUIP %s pieces=%d animated=%d doors=%d covers=%d" % [entry, pieces, result.animated.size(), result.doors.size(), result.covers.size()])
	pose(result, float(arg("anim", "0.6")))
	if flag("doors"):
		for door in result.get("doors", []):
			(door.node as Node3D).basis = Basis((door.axis as Vector3).normalized(), float(door.open_angle))
	if arg("covers") == "0":
		for cover in result.get("covers", []):
			(cover as Node3D).visible = false
	var box := node_bounds(holder)
	holder.position.x = x - box.position.x
	holder.position.y = float(arg("lift", str(PlanGrid.FLOOR_TOP)))
	if kind == "tstat":
		holder.position.y = 1.6
		wall_backdrop(Vector3(holder.position.x, 0, 0), 3.0, Basis.IDENTITY)
	elif kind == "diffuser" and not flag("nofloor"):
		holder.position.y = float(arg("lift", "0.6"))
	box = node_bounds(holder)
	if flag("fig"):
		figure(world, Vector3(box.end.x + 0.6, 0, box.end.z + 0.6), PI - 0.6, false)
	if flag("markers"):
		for port in Equipment.port_names(kind):
			var info: Dictionary = Equipment.port_local(kind, {"layout": parsed.layout if not parsed.layout.is_empty() else (["damper", "filter", "cooling_coil", "heating_coil", "fan"] if kind == "ahu" else [])}, port)
			var marker := Bricks.box(world, Vector3.ONE * 0.12, holder.transform * (info.face as Vector3), "red")
			marker.material_override = marker.material_override.duplicate()
			(marker.material_override as StandardMaterial3D).no_depth_test = true
			var tip := Bricks.box(world, Vector3.ONE * 0.08, holder.transform * ((info.face as Vector3) + (info.normal as Vector3) * 0.5), "yellow")
			tip.material_override = marker.material_override
	return box

func render_equipment(list: String) -> void:
	var entries := list.split(",", false)
	if flag("sheet"):
		var cols := int(arg("cols", "3"))
		var tile := Vector2i(int(arg("tile", "620x440").split("x")[0]), int(arg("tile", "620x440").split("x")[1]))
		root.size = tile * 2
		var rows := ceili(float(entries.size()) / float(cols))
		var sheet := Image.create(tile.x * cols, tile.y * rows, false, Image.FORMAT_RGBA8)
		for index in range(entries.size()):
			clear_world()
			focus = stage_equipment(entries[index], 0.0)
			if not flag("nofloor"):
				floor_pad(focus.get_center() * Vector3(1, 0, 1), Vector2(focus.size.x + 3, focus.size.z + 3), "dark_bluish_gray")
			frame_view()
			var image: Image = await capture()
			image.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i((index % cols) * tile.x, (index / cols) * tile.y))
		save(sheet, "/tmp/equipment_sheet.png")
		return
	var cursor := 0.0
	for entry in entries:
		var box := stage_equipment(entry, cursor)
		cursor = box.end.x + float(arg("spacing", "3.0"))
		grow_focus(box)
	if not flag("nofloor"):
		floor_pad(focus.get_center() * Vector3(1, 0, 1), Vector2(focus.size.x + 4, focus.size.z + 4), "dark_bluish_gray")
	frame_view()
	save(await capture(), "/tmp/equipment.png")

# --- Composite scenes -------------------------------------------------------

func place_item(id: String, position: Vector3, yaw: float = 0.0, options: Dictionary = {}, fig: bool = true) -> Dictionary:
	var holder := Node3D.new()
	holder.name = id
	world.add_child(holder)
	holder.position = position
	holder.rotation.y = yaw
	var result := Furniture.build(holder, id, options)
	if fig and flag("fig"):
		for seat in result.get("seats", []):
			figure(holder, seat.position, seat.facing, true, Color.from_hsv(randf(), 0.55, 0.85))
	return result

func room(origin: Vector3, size: Vector2, tint: String, walls: Array) -> void:
	floor_pad(origin + Vector3(size.x * 0.5, 0, size.y * 0.5), size, tint)
	for wall in walls:
		# wall = [x0, z0, x1, z1]; the wall's inner face sits on that line.
		var a := Vector3(wall[0], 0, wall[1]) + origin
		var b := Vector3(wall[2], 0, wall[3]) + origin
		var length := a.distance_to(b)
		var along := (b - a).normalized()
		var inward := Vector3(along.z, 0, -along.x) * -1.0
		var node := Bricks.box(world, Vector3(length + 0.5, PlanGrid.WALL_HEIGHT, 0.5), (a + b) * 0.5 - inward * 0.25 + Vector3(0, PlanGrid.WALL_HEIGHT * 0.5, 0), "white")
		node.rotation.y = -atan2(b.z - a.z, b.x - a.x)

func render_scene(name: String) -> void:
	var f := PlanGrid.FLOOR_TOP
	match name:
		"office":
			room(Vector3.ZERO, Vector2(15, 10), "sand_blue", [[0, 0, 15, 0], [0, 10, 0, 0]])
			place_item("desk", Vector3(3, f, 1.5))
			place_item("office_chair", Vector3(2.75, f, 3.0), PI)
			place_item("desk", Vector3(7, f, 1.5), 0.0, {"variant": "laptop"})
			place_item("office_chair", Vector3(6.75, f, 3.0), PI)
			place_item("bookshelf", Vector3(11, f, 0.5))
			place_item("filing_cabinet", Vector3(13.25, f, 0.5))
			place_item("meeting_table", Vector3(10.5, f, 6.5))
			place_item("water_cooler", Vector3(0.5, f, 8.5), PI * 0.5)
			place_item("printer", Vector3(0.5, f, 6.25), PI * 0.5)
			place_item("whiteboard", Vector3(0.0, f, 3.5), PI * 0.5)
			place_item("tall_plant", Vector3(14, f, 9))
			place_item("tv", Vector3(5, f, 0.0))
			focus = AABB(Vector3(0, 0, 0), Vector3(15, 3.6, 10))
		"school":
			room(Vector3.ZERO, Vector2(15, 12.5), "medium_nougat", [[0, 0, 15, 0], [0, 12.5, 0, 0]])
			place_item("chalkboard", Vector3(7.5, f, 0.0))
			place_item("teacher_desk", Vector3(7.5, f, 2.5), PI)
			var tints := ["red", "medium_blue", "yellow", "lime", "orange", "medium_azure"]
			for i in range(3):
				for j in range(2):
					place_item("student_desk", Vector3(3.5 + i * 4.0, f, 6.0 + j * 3.5), 0.0, {"colors": ["medium_nougat", tints[i + j * 3]]})
			place_item("lockers", Vector3(0.5, f, 7.0), PI * 0.5)
			place_item("cubby_shelf", Vector3(12.5, f, 12.0), PI)
			place_item("globe", Vector3(13.5, f, 2.0))
			place_item("reading_rug", Vector3(12.0, f, 8.0))
			focus = AABB(Vector3(0, 0, 0), Vector3(15, 3.6, 12.5))
		"lounge":
			room(Vector3.ZERO, Vector2(12.5, 10), "medium_nougat", [[0, 0, 12.5, 0], [0, 10, 0, 0]])
			place_item("rug", Vector3(5.0, f, 4.25))
			place_item("sofa", Vector3(5.0, f, 1.25))
			place_item("coffee_table", Vector3(5.0, f, 4.0))
			place_item("armchair", Vector3(1.5, f, 4.5), PI * 0.5)
			place_item("floor_lamp", Vector3(1.0, f, 1.0))
			place_item("tall_plant", Vector3(9.0, f, 1.0))
			place_item("small_plant", Vector3(11.5, f, 1.0))
			place_item("tall_plant", Vector3(11.5, f, 3.0), 0.0, {"variant": "bamboo"})
			focus = AABB(Vector3(0, 0, 0), Vector3(12.5, 3.6, 10))
		"kitchen":
			room(Vector3.ZERO, Vector2(15, 10), "white", [[0, 0, 15, 0], [0, 10, 0, 0]])
			place_item("kitchen_counter", Vector3(2.0, f, 0.75))
			place_item("coffee_station", Vector3(5.0, f, 0.5))
			place_item("fridge", Vector3(7.5, f, 0.5))
			place_item("vending_machine", Vector3(10.0, f, 0.5))
			place_item("dining_table", Vector3(5.0, f, 6.0))
			place_item("dining_table", Vector3(10.5, f, 6.0))
			place_item("trash_bin", Vector3(13.5, f, 1.0))
			focus = AABB(Vector3(0, 0, 0), Vector3(15, 3.6, 10))
		"bath":
			room(Vector3.ZERO, Vector2(10, 7.5), "white", [[0, 0, 10, 0], [0, 7.5, 0, 0]])
			place_item("toilet_stall", Vector3(1.5, f, 1.25))
			place_item("toilet_stall", Vector3(4.5, f, 1.25))
			place_item("sink_vanity", Vector3(7.25, f, 0.75))
			place_item("sink_vanity", Vector3(8.75, f, 0.75))
			focus = AABB(Vector3(0, 0, 0), Vector3(10, 3.6, 7.5))
		"mech":
			room(Vector3.ZERO, Vector2(12.5, 10), "dark_bluish_gray", [[0, 0, 12.5, 0], [0, 10, 0, 0]])
			place_item("storage_shelving", Vector3(2.0, f, 0.5))
			place_item("workbench", Vector3(6.0, f, 0.75))
			place_item("water_heater", Vector3(9.5, f, 1.0))
			place_item("electrical_panel", Vector3(11.5, f, 0.0))
			place_item("electrical_panel", Vector3(0.0, f, 4.0), PI * 0.5)
			focus = AABB(Vector3(0, 0, 0), Vector3(12.5, 3.6, 10))
		"outdoor":
			place_item("park_bench", Vector3(2, 0, 2))
			place_item("lamp_post", Vector3(5, 0, 1.5))
			place_item("bike_rack", Vector3(8.5, 0, 2.5), 0.0, {"variant": "two_bikes"})
			for i in range(3):
				place_item("picket_fence", Vector3(1 + i * 2.0, 0, 6.5))
			place_item("flower_bed", Vector3(9.5, 0, 6.5))
			place_item("trash_bin", Vector3(12.5, 0, 2.0))
			place_item("outdoor_table", Vector3(4.5, 0, 9.5))
			place_item("outdoor_table", Vector3(10.5, 0, 10.0), 0.0, {"variant": "plain"})
			focus = AABB(Vector3(0, 0, 0), Vector3(14, 4.0, 12))
		"hvac":
			await render_hvac_scene()
			return
	frame_view()
	save(await capture(), "/tmp/scene.png")

func spawn_equipment(kind: String, position: Vector3, yaw: float, config: Dictionary = {}) -> Dictionary:
	var holder := Node3D.new()
	holder.name = kind
	world.add_child(holder)
	holder.position = position
	holder.rotation.y = yaw
	var result: Dictionary
	match kind:
		"ahu": result = Equipment.build_ahu(holder, config, {"open": flag("open")})
		"vav": result = Equipment.build_vav(holder, config, {"open": flag("open"), "hangers": flag("hangers")})
		"diffuser": result = Equipment.build_diffuser(holder, {"open": flag("open")})
		"tee": result = Equipment.build_tee(holder, {"open": flag("open")})
		"cross": result = Equipment.build_cross(holder, {"open": flag("open")})
		"tstat": result = Equipment.build_thermostat(holder, {})
	pose(result, 0.6)
	return {"node": holder, "result": result}

func port_world(kind: String, node: Node3D, config: Dictionary, port: String) -> Dictionary:
	var info := Equipment.port_local(kind, config, port)
	return {"face": node.transform * (info.face as Vector3), "normal": node.transform.basis * (info.normal as Vector3)}

func duct(points: Array[Vector3]) -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	var cover := DuctGeometry.path_shell(holder, points, Bricks.color("flat_silver"), true, true)
	if arg("covers") == "0":
		cover.visible = false

# Places `kind` so its `port` face sits `gap` beyond a feeding port and faces
# it, draws the connecting duct, and returns the new node/result/config.
func attach(kind: String, config: Dictionary, feed: Dictionary, gap: float, port: String = "inlet") -> Dictionary:
	var local := Equipment.port_local(kind, config, port)
	var want: Vector3 = -(feed.normal as Vector3)
	var have: Vector3 = local.normal
	var yaw := atan2(want.x, want.z) - atan2(have.x, have.z)
	var target: Vector3 = (feed.face as Vector3) + (feed.normal as Vector3) * gap
	var origin := target - Basis(Vector3.UP, yaw) * (local.face as Vector3)
	var placed := spawn_equipment(kind, origin, yaw, config)
	if gap > 0.01:
		duct([feed.face, target])
	placed["config"] = config
	placed["kind"] = kind
	return placed

func port_of(placed: Dictionary, port: String) -> Dictionary:
	return port_world(String(placed.kind), placed.node, placed.config, port)

func render_hvac_scene() -> void:
	var f := PlanGrid.FLOOR_TOP
	room(Vector3.ZERO, Vector2(27.5, 12.5), "dark_bluish_gray", [[0, 0, 27.5, 0], [0, 12.5, 0, 0], [12.5, 0, 12.5, 12.5]])
	floor_pad(Vector3(20.0, 0.002, 6.25), Vector2(15.0, 12.5), "sand_blue")
	var ahu_config := {"layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"], "sensor_enabled": true}
	var ahu := spawn_equipment("ahu", Vector3(5.5, f, 2.5), 0.0, ahu_config)
	ahu["config"] = ahu_config
	ahu["kind"] = "ahu"
	var o: Vector3 = port_of(ahu, "outlet").face
	var main_end := Vector3(14.0, 4.6, 6.25)
	duct([o, o + Vector3(0.65, 0, 0), Vector3(o.x + 0.65, 4.6, o.z), Vector3(o.x + 0.65, 4.6, main_end.z), main_end])
	var cross := attach("cross", {}, {"face": main_end, "normal": Vector3(1, 0, 0)}, 0.0)
	var vav := attach("vav", {"layout": ["damper", "heating_coil"], "sensor_enabled": true}, port_of(cross, "outlet"), 1.0)
	attach("diffuser", {}, port_of(vav, "outlet"), 0.75)
	attach("diffuser", {}, port_of(cross, "branch_b"), 1.5)
	attach("diffuser", {}, port_of(cross, "branch_a"), 0.75)
	spawn_equipment("tstat", Vector3(20.0, 1.9, 0.0), 0.0)
	place_item("water_heater", Vector3(1.25, f, 8.0))
	place_item("electrical_panel", Vector3(0.0, f, 10.5), PI * 0.5)
	place_item("storage_shelving", Vector3(6.0, f, 11.75), PI)
	place_item("workbench", Vector3(9.5, f, 11.5), PI)
	place_item("desk", Vector3(17.0, f, 9.5), PI)
	place_item("office_chair", Vector3(17.25, f, 8.0))
	place_item("desk", Vector3(23.0, f, 9.5), PI)
	place_item("office_chair", Vector3(23.25, f, 8.0))
	place_item("tall_plant", Vector3(26.5, f, 1.0))
	focus = AABB(Vector3(0, 0, 0), Vector3(27.5, 5.5, 12.5))
	frame_view()
	save(await capture(), "/tmp/hvac.png")

# --- Parts sheet ------------------------------------------------------------

# One tile per part and view; views are front (+Z), side (+X) and iso.
func render_parts(parts: PackedStringArray) -> void:
	var views := [[0.0, -0.25], [PI * 0.5, -0.25], [-0.6, -0.7]]
	if flag("back"):
		views = [[PI, -0.25], [PI * 0.75, -0.35], [PI + 0.6, -0.7]]
	var tile := Vector2i(360, 260)
	var sheet := Image.create(tile.x * views.size(), tile.y * parts.size(), false, Image.FORMAT_RGBA8)
	for row in range(parts.size()):
		clear_world()
		var id := parts[row]
		var node := Bricks.place(world, id, Vector3.ZERO, arg("color", "light_bluish_gray"))
		var box := node.transform * node.mesh.get_aabb()
		var label := Label3D.new()
		label.text = "%s  %.2f x %.2f x %.2f" % [id, box.size.x, box.size.y, box.size.z]
		label.font_size = 40
		label.pixel_size = box.size.length() * 0.0012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color("#ffe066")
		label.outline_size = 10
		world.add_child(label)
		for axis in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
			var stub := MeshInstance3D.new()
			var stub_box := BoxMesh.new()
			stub_box.size = Vector3.ONE * 0.02 + (axis[0] as Vector3).abs() * 0.3
			stub.mesh = stub_box
			var material := StandardMaterial3D.new()
			material.albedo_color = axis[1]
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.no_depth_test = true
			stub.material_override = material
			stub.position = node.position + (axis[0] as Vector3) * 0.15
			world.add_child(stub)
		for column in range(views.size()):
			var center := box.get_center()
			aim(center, views[column][0], views[column][1], box.size.length() * 1.9 + 0.8)
			label.position = center + camera.global_basis.y * box.size.length() * 0.55
			var image: Image = await capture()
			image.resize(tile.x, tile.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, tile), Vector2i(column * tile.x, row * tile.y))
	save(sheet, "/tmp/model_parts.png")

# --- Validation -------------------------------------------------------------

class ModelCheck:
	const Furniture := preload("res://scripts/build/furniture_catalog.gd")
	const Equipment := preload("res://scripts/build/equipment_models.gd")
	const CATEGORIES := ["office", "school", "lounge", "kitchen", "bath", "mechanical", "outdoor", "decor"]
	const PAINT_ROLES := ["housing", "damper", "filter", "cooling_coil", "heating_coil", "fan", "sensor", "door"]

	static var failures: Array[String] = []
	static var notes: Array[String] = []

	static func fail(message: String) -> void:
		failures.append(message)

	static func run_all(holder: Node3D) -> bool:
		failures.clear()
		check_furniture(holder)
		check_equipment(holder)
		for note in notes:
			print(note)
		for failure in failures:
			print("  FAIL ", failure)
		print("MODEL_CHECK %s furniture=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", Furniture.ITEMS.size(), failures.size()])
		return failures.is_empty()

	static func is_dynamic(node: Node, stop: Node) -> bool:
		var cursor := node
		while cursor != null and cursor != stop:
			if cursor.has_meta("dynamic"):
				return true
			cursor = cursor.get_parent()
		return false

	static func pieces(root: Node) -> int:
		var count := 0
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("ldraw_part_id"):
				count += 1
		return count

	static func bounds(root: Node3D) -> AABB:
		var result := AABB()
		var first := true
		var inverse := root.global_transform.affine_inverse()
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			var instance := mesh as MeshInstance3D
			if not instance.is_visible_in_tree():
				continue
			var box := (inverse * instance.global_transform) * instance.get_aabb()
			result = box if first else result.merge(box)
			first = false
		return result

	static func vec_ok(value: Variant) -> bool:
		return value is Vector3 and (value as Vector3).is_finite()

	# --- Furniture -----------------------------------------------------------

	static func check_furniture(holder: Node3D) -> void:
		var total := 0
		for id in Furniture.ids():
			var info: Dictionary = Furniture.ITEMS[id]
			for key in ["label", "category", "footprint", "height", "mount"]:
				if not info.has(key):
					fail("%s missing %s" % [id, key])
			if String(info.get("category", "")) not in CATEGORIES:
				fail("%s bad category" % id)
			if not (info.get("footprint") is Vector2i):
				fail("%s footprint not Vector2i" % id)
			if String(info.get("mount", "")) not in ["floor", "wall"]:
				fail("%s bad mount" % id)
			for tint in info.get("colors", []):
				if not Bricks.PALETTE.has(String(tint)):
					fail("%s colour %s not in palette" % [id, tint])
			var variants: Array = info.get("variants", [""])
			for variant in variants:
				var root := Node3D.new()
				holder.add_child(root)
				var result: Dictionary = Furniture.build(root, id, {"variant": variant} if String(variant) != "" else {})
				check_furniture_result(id, info, root, result)
				if variant == variants[0]:
					total += pieces(root)
					notes.append("  item %-16s %-18s %-10s %dx%d h=%.1f %s pieces=%d seats=%d" % [id, info.label, info.category, info.footprint.x, info.footprint.y, float(info.height), info.mount, pieces(root), result.seats.size()])
				root.free()
			# Recolour option must reach the build.
			var tinted := Node3D.new()
			holder.add_child(tinted)
			Furniture.build(tinted, id, {"color": "lime"})
			var found := false
			for mesh in tinted.find_children("*", "MeshInstance3D", true, false):
				var material := (mesh as MeshInstance3D).material_override as StandardMaterial3D
				if material != null and material.albedo_color.is_equal_approx(Bricks.color("lime")):
					found = true
			if not found:
				fail("%s ignores the color option" % id)
			tinted.free()
		notes.append("  furniture total pieces=%d" % total)

	static func check_furniture_result(id: String, info: Dictionary, root: Node3D, result: Dictionary) -> void:
		for key in ["collision", "seats", "interactions"]:
			if not (result.get(key) is Array):
				fail("%s result.%s not an Array" % [id, key])
		for box in result.get("collision", []):
			if not (vec_ok(box.get("size")) and vec_ok(box.get("center"))):
				fail("%s collision entry malformed" % id)
		for seat in result.get("seats", []):
			if not vec_ok(seat.get("position")) or not (seat.get("facing") is float) or not vec_ok(seat.get("forward")):
				fail("%s seat malformed" % id)
			elif float((seat.position as Vector3).y) < 0.3 or float((seat.position as Vector3).y) > 1.3:
				fail("%s seat height %.2f out of range" % [id, (seat.position as Vector3).y])
		for spot in result.get("interactions", []):
			if String(spot.get("kind", "")).is_empty() or String(spot.get("label", "")).is_empty() or not vec_ok(spot.get("position")):
				fail("%s interaction malformed" % id)
		if result.has("light"):
			var light: Dictionary = result.light
			if not vec_ok(light.get("position")) or not (light.get("color") is Color) or float(light.get("range", 0.0)) <= 0.0:
				fail("%s light malformed" % id)
		var count := pieces(root)
		if count > 45:
			fail("%s has %d pieces (> 45)" % [id, count])
		# Every mesh is a batchable LDraw piece unless it lives under "dynamic".
		for mesh in root.find_children("*", "MeshInstance3D", true, false):
			if not mesh.has_meta("ldraw_part_id") and not is_dynamic(mesh, root):
				fail("%s has a non-LDraw static mesh %s" % [id, mesh.name])
			var material := (mesh as MeshInstance3D).material_override
			if not is_dynamic(mesh, root) and not (material is StandardMaterial3D):
				fail("%s static piece without StandardMaterial3D" % id)
		var box := bounds(root)
		var half := Vector2(info.footprint.x, info.footprint.y) * 0.25
		var slack := 0.65 + float(info.get("overhang", 0.0))
		if String(info.mount) == "wall":
			if box.position.z < -0.05 or box.end.z > info.footprint.y * 0.5 + slack:
				fail("%s wall item depth %.2f..%.2f outside 0..%.2f" % [id, box.position.z, box.end.z, info.footprint.y * 0.5])
			if absf(box.position.x) > half.x + slack or absf(box.end.x) > half.x + slack:
				fail("%s wall item width outside footprint" % id)
		else:
			if box.position.x < -half.x - slack or box.end.x > half.x + slack or box.position.z < -half.y - slack or box.end.z > half.y + slack:
				fail("%s bounds %s exceed footprint %s" % [id, box, info.footprint])
		if box.position.y < -0.01:
			fail("%s dips below its floor (%.2f)" % [id, box.position.y])
		if box.end.y > float(info.height) + 0.35:
			fail("%s is %.2f tall, spec says %.2f" % [id, box.end.y, info.height])

	# --- Equipment -----------------------------------------------------------

	static func check_equipment(holder: Node3D) -> void:
		var layouts := [["fan"], ["filter", "fan"], ["damper", "filter", "cooling_coil", "fan"], ["damper", "filter", "cooling_coil", "heating_coil", "fan"], ["damper", "filter", "filter", "cooling_coil", "heating_coil", "heating_coil", "fan"]]
		for layout in layouts:
			var records: Array = []
			for index in range(layout.size()):
				records.append({"id": "c%d" % index, "role": layout[index]})
			for open in [false, true]:
				var config := {"layout": layout, "sensor_enabled": true, "component_records": records}
				run_equipment(holder, "ahu", config, {"open": open}, layout.size(), 400)
		for layout in [["damper"], ["damper", "heating_coil"], ["damper", "cooling_coil"]]:
			run_equipment(holder, "vav", {"layout": layout, "sensor_enabled": true}, {}, layout.size(), 120)
			run_equipment(holder, "vav", {"layout": layout, "sensor_enabled": false}, {"open": true, "hangers": true}, layout.size(), 120)
		for kind in ["diffuser", "tee", "cross", "tstat"]:
			run_equipment(holder, kind, {}, {}, -1, 60)
		for role in ["damper", "filter", "cooling_coil", "heating_coil", "fan", "sensor"]:
			run_equipment(holder, role, {}, {"component_id": "x"}, 1, 60)

	static func build(root: Node3D, kind: String, config: Dictionary, options: Dictionary) -> Dictionary:
		match kind:
			"ahu": return Equipment.build_ahu(root, config, options)
			"vav": return Equipment.build_vav(root, config, options)
			"diffuser": return Equipment.build_diffuser(root, options)
			"tee": return Equipment.build_tee(root, options)
			"cross": return Equipment.build_cross(root, options)
			"tstat": return Equipment.build_thermostat(root, options)
		return Equipment.build_component(root, kind, options)

	static func run_equipment(holder: Node3D, kind: String, config: Dictionary, options: Dictionary, section_count: int, budget: int) -> void:
		var root := Node3D.new()
		holder.add_child(root)
		var label := "%s%s" % [kind, config.get("layout", [])]
		var result := build(root, kind, config, options)
		for key in ["animated", "doors", "covers", "sections", "collision"]:
			if not (result.get(key) is Array):
				fail("%s result.%s missing" % [label, key])
		if not result.has("screen") or not (result.screen == null or result.screen is Node3D):
			fail("%s screen malformed" % label)
		if not vec_ok(result.get("label_anchor")):
			fail("%s label_anchor malformed" % label)
		if result.collision.is_empty():
			fail("%s has no collision" % label)
		if kind in ["ahu", "tstat", "vav"] and result.screen == null:
			fail("%s should expose a screen" % label)
		var count := pieces(root)
		if count > budget:
			fail("%s has %d pieces (> %d)" % [label, count, budget])
		for child in root.get_children():
			if not child.has_meta("paint_role") or String(child.get_meta("paint_role")) not in PAINT_ROLES:
				fail("%s child %s lacks a valid paint_role" % [label, child.name])
		var fans := 0
		for entry in result.animated:
			var node: Node3D = entry.get("node")
			if node == null or not is_instance_valid(node) or not root.is_ancestor_of(node):
				fail("%s animated node missing" % label)
				continue
			if not is_dynamic(node, root):
				fail("%s animated %s not under a dynamic node" % [label, entry.get("kind")])
			match String(entry.get("kind", "")):
				"rotation":
					fans += 1
					if not vec_ok(entry.get("axis")) or not node.basis.is_equal_approx(Basis.IDENTITY):
						fail("%s rotor malformed" % label)
				"damper":
					if not vec_ok(entry.get("axis")) or not (entry.get("closed") is float) or not (entry.get("open") is float):
						fail("%s damper entry malformed" % label)
				"fill":
					var material := (node as MeshInstance3D).material_override as ShaderMaterial if node is MeshInstance3D else null
					if material == null or material.shader == null or not material.shader.resource_path.ends_with("coil_fill.gdshader"):
						fail("%s fill without coil shader" % label)
					if int(entry.get("row", -1)) < 0 or int(entry.get("row", 0)) >= int(entry.get("rows", 0)):
						fail("%s fill row/rows malformed" % label)
				_:
					fail("%s unknown animated kind" % label)
			if String(entry.get("role", "")).is_empty():
				fail("%s animated entry without role" % label)
		for door in result.doors:
			if not is_instance_valid(door.get("node")) or not (door.node as Node).has_meta("dynamic") or not vec_ok(door.get("axis")) or not (door.get("open_angle") is float):
				fail("%s door malformed" % label)
		for cover in result.covers:
			if not (cover is Node3D) or not is_dynamic(cover, root):
				fail("%s cover not dynamic" % label)
		if section_count > 0 and kind == "ahu" and result.sections.size() != section_count:
			fail("%s sections %d != %d" % [label, result.sections.size(), section_count])
		for section in result.sections:
			if String(section.get("role", "")) == "" or not vec_ok(section.get("center")) or not section.has("component_id"):
				fail("%s section malformed" % label)
		if kind == "ahu":
			if fans != (config.layout as Array).count("fan"):
				fail("%s expected %d rotors" % [label, (config.layout as Array).count("fan")])
			if result.doors.size() != (config.layout as Array).size():
				fail("%s expected one door per section" % label)
		# Ports: each face must sit on the outside of the model along its normal.
		var box := bounds(root)
		var eq_kind := "tstat" if kind == "tstat" else kind
		for port in Equipment.port_names(eq_kind):
			var info := Equipment.port_local(eq_kind, config, port)
			if info.is_empty() or not vec_ok(info.get("face")) or not vec_ok(info.get("normal")):
				fail("%s port %s malformed" % [label, port])
				continue
			var face: Vector3 = info.face
			var normal: Vector3 = info.normal
			if not is_equal_approx(normal.length(), 1.0):
				fail("%s port %s normal not unit" % [label, port])
			var extreme := box.end.dot(normal.abs()) if normal.dot(Vector3.ONE) > 0 else -box.position.dot(normal.abs())
			var reach := face.dot(normal)
			if absf(extreme - reach) > 0.12:
				fail("%s port %s face %.2f not on the outer extent %.2f" % [label, port, reach, extreme])
		if kind in ["ahu", "vav", "diffuser", "tee", "cross", "tstat"]:
			var studs := Equipment.footprint(kind, config)
			var size := Equipment.size(kind, config)
			if absf(size.x - studs.x * 0.5) > 0.01 and kind not in ["tstat"]:
				fail("%s size.x %.2f disagrees with footprint %d" % [label, size.x, studs.x])
			if not bool(options.get("open", false)) and (box.size.x > studs.x * 0.5 + 0.3 or box.size.z > studs.y * 0.5 + 0.3):
				fail("%s bounds %s exceed footprint %s" % [label, box.size, studs])
		# The architecture batch must keep every animated/door/cover node alive.
		var batch := BrickBatch.new()
		batch.absorb("check", root)
		for entry in result.animated:
			if not is_instance_valid(entry.node) or (entry.node as Node).is_queued_for_deletion():
				fail("%s batching would free an animated node" % label)
		for door in result.doors:
			if (door.node as Node).is_queued_for_deletion():
				fail("%s batching would free a door" % label)
		notes.append("  equip %-60s pieces=%3d animated=%2d doors=%d covers=%d size=%s" % [label, count, result.animated.size(), result.doors.size(), result.covers.size(), box.size])
		root.free()
