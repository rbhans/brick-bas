extends Node3D

# HVAC equipment and ductwork: builds each unit from EquipmentModels, paints
# it, animates it from BAS points (fans, damper vanes, coil valves, airflow),
# opens casings and access doors, and fades overhead HVAC out of the way while
# exploring. Also supplies the Equipment-mode tray, tools and context card.

const Ducts := preload("res://scripts/build/duct_geometry.gd")
const DuctPorts := preload("res://scripts/build/duct_connections.gd")
const Bindings := preload("res://scripts/data/animation_binding.gd")
const Coplanar := preload("res://scripts/render/coplanar.gd")
const EquipmentToolScript := preload("res://scripts/build/tools/equipment_tool.gd")
const DuctToolScript := preload("res://scripts/build/tools/duct_tool.gd")
const WorkbenchScript := preload("res://scripts/ui/workbench.gd")

const KINDS := ["ahu", "vav", "diffuser", "tee", "cross", "tstat", "duct"]
# Ceiling pieces that fade out of the camera's way to the minifigure.
# Diffusers sit flush with the ceiling and stay put.
const OVERHEAD := ["vav", "tee", "cross", "duct"]
# A unit gives way once it comes within SIGHT_IN of the camera's line to the
# minifigure (head or feet), and only comes back after being further than
# SIGHT_OUT for RETURN_DELAY seconds, so walking along its edge doesn't make it
# blink.
const SIGHT_IN := 1.1
const SIGHT_OUT := 2.0
const RETURN_DELAY := 0.6
const THERMOSTAT_HEIGHT := 1.55
const CEILING_FACE := 3.6

var game: Node
var roots: Dictionary = {}
var results: Dictionary = {}
var air: Array = []
var screens: Dictionary = {}
var open_casings: Dictionary = {}
var access: Dictionary = {}       # "id:door index" -> bool
var door_angles: Dictionary = {}
var airflow_view := false
var workbench: Control
var workbench_config: Dictionary = {
	"ahu": {"layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"], "sensor_enabled": true},
	"vav": {"layout": ["damper", "heating_coil"], "sensor_enabled": true},
}
var ceiling_studs: Dictionary = {} # stud -> id of ceiling-hung equipment
var batches: Dictionary = {}       # id -> BrickBatch of the unit's static pieces
var can_fade := RenderingServer.get_current_rendering_method() != "gl_compatibility"
# The web renderer pays per draw call, so there every unit's static bricks
# share one batch (hidden per unit through instance transforms). Desktop keeps
# a batch per unit so each can fade on its own.
var shared: BrickBatch
var _unit_hidden: Dictionary = {}
var _held: Dictionary = {}        # id -> true while a move tool carries it (stays hidden)
var _signature := 0
var _screen_timer := 0.0
var _mode := 0
var _samples: Dictionary = {}
var _overlays: Dictionary = {}
var _fade: Dictionary = {}
var _giving_way: Dictionary = {}  # id -> true while faded (desktop) or hidden (web)
var _clear_for: Dictionary = {}   # id -> seconds it's been clear of the sight line
var _bounds: Dictionary = {}      # id -> world AABB of an overhead unit
var duct_paths: Dictionary = {}   # duct id -> Array[Vector3], cached per rebuild
var _unbatched: Array[String] = [] # units built this rebuild, batched once all are settled

func setup(owner: Node) -> void:
	game = owner
	name = "Equipment"

func models() -> Script:
	return Placement.equipment_models()

# --- Build --------------------------------------------------------------------------

func rebuild(objects: Array) -> void:
	var relevant: Array = []
	var walls := 0
	for item in objects:
		if item.kind in KINDS: relevant.append([item.id, item.kind, item.transform, item.properties])
		elif item.kind == "wall": walls += 1
	var signature := hash([relevant, walls, airflow_view])
	if signature == _signature:
		return
	_signature = signature
	for child in get_children():
		child.free()
	roots.clear()
	results.clear()
	shared = null if can_fade else BrickBatch.new()
	_unit_hidden.clear()
	air.clear()
	screens.clear()
	_fade.clear()
	_giving_way.clear()
	_clear_for.clear()
	_bounds.clear()
	duct_paths.clear()
	ceiling_studs.clear()
	batches.clear()
	var library := models()
	var pending: Array[String] = []
	_unbatched = pending
	for item in objects:
		if item.kind not in KINDS:
			continue
		if item.kind in ["ahu", "vav", "duct"]:
			Bindings.refresh_automatic(item)
		var id := String(item.id)
		var root := Node3D.new()
		root.name = id
		root.set_meta("entity_id", id)
		add_child(root)
		roots[id] = root
		if item.kind == "duct":
			_build_duct(root, item)
			continue
		root.transform = _transform(item)
		if library == null:
			continue
		var result: Dictionary = _build_model(root, String(item.kind), item.properties, false)
		results[id] = result
		_apply_paint(root, item.properties.get("paint", {}))
		if item.kind in ["tee", "cross"]:
			_cap_open_ports(root, item)
		# Fitting and diffuser lids never open in play, so they batch with
		# the rest of the unit instead of costing a draw call each.
		if item.kind in ["tee", "cross", "diffuser"]:
			for cover in result.get("covers", []):
				if is_instance_valid(cover):
					for node in [cover] + (cover as Node).find_children("*", "", true, false):
						node.remove_meta("dynamic")
			result.covers = []
		# Static casing pieces draw as a handful of MultiMeshes per unit (once
		# every unit is built: see below).
		pending.append(id)
		if item.kind in ["vav", "diffuser", "tee", "cross"]:
			for stud in Placement.footprint_studs(root.position, library.footprint(String(item.kind), item.properties), float(item.transform.get("rotation_y", 0.0))):
				ceiling_studs[stud] = id
		for box in result.get("collision", []):
			_body(root, id, box.size, box.center)
		if item.kind == "tstat":
			_screen(id, result)
		elif item.kind in ["ahu", "vav"]:
			_label(root, item, result)
			_screen(id, result, 30)
	# Settle flush faces between each unit's pieces, procedural ones included,
	# before anything is batched (coplanar.gd).
	for id in pending:
		_bounds[id] = _unit_bounds(roots[id])
	var furniture := {}
	for item in objects:
		if item.kind == "furniture": furniture[String(item.id)] = true
	for id in pending:
		Coplanar.settle(roots[id], _neighbours(id, pending, furniture))
	for id in pending:
		_batch_unit(id, roots[id])
	_unbatched = []
	if shared != null:
		shared.build(self, "Equipment pieces")
	_apply_mode_look()
	# A piece still being carried stays hidden in the rebuilt scene.
	for id in _held.keys():
		if roots.has(id): set_hidden(String(id), true)
		else: _held.erase(id)

func _batch_unit(id: String, root: Node3D) -> void:
	if shared != null:
		shared.absorb(id, root, Color(0, 0, 0, 0), null, false) # world space: the shared batch sits at the origin
		batches[id] = shared
	else:
		var batch := BrickBatch.new()
		batch.absorb(id, root, Color(0, 0, 0, 0), root, false)
		batch.build(root, "Static pieces")
		batches[id] = batch
	BrickBatch.merge_static(root)

# Shows or hides a whole unit, including its bricks in the shared batch
# (only touching the batch when the state actually changes).
func _show_unit(id: String, shown: bool) -> void:
	var root: Node3D = roots.get(id)
	if is_instance_valid(root):
		root.visible = shown
	if shared != null and bool(_unit_hidden.get(id, false)) == shown:
		_unit_hidden[id] = not shown
		shared.set_owner_hidden(id, not shown)

# Unused fitting outlets get a blank-off plate (studs out) instead of showing
# an open hole; ducting to the outlet rebuilds the fitting without it.
func _cap_open_ports(root: Node3D, item: Dictionary) -> void:
	var inverse := root.global_transform.affine_inverse()
	for name in DuctPorts.port_names(item):
		if name == "inlet":
			continue
		var port := DuctPorts.port(item, name)
		if DuctPorts.occupied(port, game.model.objects):
			continue
		var normal: Vector3 = (inverse.basis * (port.normal as Vector3)).normalized()
		var face: Vector3 = inverse * (port.face as Vector3)
		# Turn the plate's thickness axis (+Y, studs) to face out of the port.
		var basis := Basis(Vector3(0, 0, 1), -PI * 0.5 * signf(normal.x)) if absf(normal.x) > 0.5 else Basis(Vector3(1, 0, 0), PI * 0.5 * signf(normal.z))
		var cap := Bricks.spawn(root, "3022", Transform3D(basis, face + normal * PlanGrid.PLATE), Color("#8d949c"))
		cap.name = "Blank-off cap"

func _transform(item: Dictionary) -> Transform3D:
	var values: Array = item.transform.position
	return Transform3D(Basis(Vector3.UP, float(item.transform.get("rotation_y", 0.0))), Vector3(float(values[0]), float(values[1]), float(values[2])))

func _build_model(root: Node3D, kind: String, properties: Dictionary, preview: bool) -> Dictionary:
	var library := models()
	if library == null:
		return {}
	var options := {"preview": preview, "paint": properties.get("paint", {}), "open": false}
	match kind:
		"ahu": return library.build_ahu(root, properties, options)
		"vav": return library.build_vav(root, properties, options)
		"diffuser": return library.build_diffuser(root, options)
		"tee": return library.build_tee(root, options)
		"cross": return library.build_cross(root, options)
		"tstat": return library.build_thermostat(root, options)
	return {}

func build_preview(parent: Node3D, kind: String, properties: Dictionary) -> void:
	var config: Dictionary = properties if not properties.is_empty() else current_config(kind)
	_build_model(parent, kind, config, true)
	_apply_paint(parent, config.get("paint", {}))

func _body(root: Node3D, id: String, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.set_meta("entity_id", id)
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)

func _label(root: Node3D, item: Dictionary, result: Dictionary) -> void:
	var label := Label3D.new()
	label.name = "BAS tag"
	label.text = String(item.properties.get("label", String(item.kind).to_upper()))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.pixel_size = 0.01
	label.outline_size = 10
	label.modulate = Color("fff6d8")
	label.outline_modulate = Color(0.08, 0.12, 0.14, 0.9)
	label.position = result.get("label_anchor", Vector3(0, 3.2, 0)) + Vector3(0, 0.6, 0)
	label.no_depth_test = true
	label.set_meta("bas_tag", true)
	root.add_child(label)

# Live readout on a device display: room temperature on thermostats, supply
# air and fan speed on AHU controllers, damper and discharge on VAV controllers.
func _screen(id: String, result: Dictionary, size: int = 48) -> void:
	var anchor: Node3D = result.get("screen")
	if not is_instance_valid(anchor):
		return
	var label := Label3D.new()
	label.name = "Display readout"
	label.font_size = size
	label.line_spacing = -4.0
	label.pixel_size = 0.0035
	label.modulate = Color("d9fbff")
	label.outline_size = 0
	label.position = Vector3(0, 0, 0.03)
	label.text = "--"
	anchor.add_child(label)
	screens[id] = label

func _apply_paint(root: Node, paint: Dictionary, inherited: String = "housing") -> void:
	if paint.is_empty():
		return
	var role := String(root.get_meta("paint_role", inherited))
	# Copper pipes, latches, glass and actuators keep their own colours.
	if root.has_meta("paint_fixed"):
		return
	if root is MeshInstance3D and (paint.has(role) or paint.has("all")):
		var colour := Color(String(paint.get(role, paint.get("all"))))
		var mesh_node := root as MeshInstance3D
		if mesh_node.material_override is ShaderMaterial:
			var shader_material := mesh_node.material_override.duplicate() as ShaderMaterial
			shader_material.set_shader_parameter(String(mesh_node.get_meta("paint_shader_param", "active_color")), colour)
			mesh_node.material_override = shader_material
		elif mesh_node.material_override is StandardMaterial3D:
			mesh_node.material_override = Bricks.material(Color(colour, (mesh_node.material_override as StandardMaterial3D).albedo_color.a))
	for child in root.get_children():
		_apply_paint(child, paint, role)

func _build_duct(root: Node3D, item: Dictionary) -> void:
	var objects: Array = game.model.objects
	var path := DuctPorts.path(item.properties, objects)
	duct_paths[String(item.id)] = path
	var error := DuctPorts.route_error(item.properties, objects, String(item.id))
	root.set_meta("connection_error", error)
	if not error.is_empty():
		var marker_position: Vector3 = path[0] if not path.is_empty() else Vector3.ZERO
		var marker := Bricks.place(root, "3941", marker_position - Vector3(0, 0.3, 0), "red")
		marker.set_meta("paint_role", "warning")
		_body(root, String(item.id), Vector3.ONE * 0.9, marker_position)
		var warning := Label3D.new()
		warning.text = "Reroute duct"
		warning.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		warning.font_size = 28
		warning.pixel_size = 0.01
		warning.outline_size = 8
		warning.position = marker_position + Vector3(0, 0.9, 0)
		root.add_child(warning)
		return
	var paint: Dictionary = item.properties.get("paint", {})
	var colour: Color = Color(String(paint.get("housing", paint.get("all", "")))) if paint.has("housing") or paint.has("all") else Bricks.color("flat_silver")
	if not bool(item.properties.get("enabled", true)):
		colour = colour.darkened(0.3)
	var cover := Ducts.path_shell(root, path, colour, item.properties.has("start_port"), item.properties.has("end_port"))
	cover.visible = not airflow_view
	var first := DuctPorts.resolve(item.properties.get("start_port", {}), objects)
	var direction_sign := -1.0 if first.get("direction", "out") == "in" else 1.0
	var particles: Array = []
	for index in range(path.size() - 1):
		var from := path[index]
		var to := path[index + 1]
		if not Ducts.valid_segment(from, to):
			continue
		var section := Node3D.new()
		section.transform = Ducts.frame(from, to)
		root.add_child(section)
		var length := from.distance_to(to)
		var body := StaticBody3D.new()
		body.set_meta("entity_id", String(item.id))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, 1.0, 1.0)
		shape.shape = box
		body.add_child(shape)
		section.add_child(body)
		var count := maxi(2, int(length * 1.4))
		for particle_index in range(count):
			particles.append({"frame": section.transform, "phase": float(particle_index) / count, "length": length, "sign": direction_sign})
	if particles.is_empty():
		return
	_unbatched.append(String(item.id))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = Bricks.mesh("3070b")
	multimesh.instance_count = particles.size()
	var instance := MultiMeshInstance3D.new()
	instance.name = "Airflow"
	instance.multimesh = multimesh
	instance.material_override = _air_material()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	root.add_child(instance)
	air.append({"node": instance, "owner": String(item.id), "particles": particles})

func _air_material() -> StandardMaterial3D:
	if not _overlays.has("air"):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.5, 0.9, 1.0, 0.85)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission = Color("62d7ff")
		material.emission_energy_multiplier = 1.4
		_overlays["air"] = material
	return _overlays.air

# --- Animation --------------------------------------------------------------------------

func _sample(id: String, role: String) -> Dictionary:
	var key := id + ":" + role
	if not _samples.has(key):
		_samples[key] = game.animation_sample(id, role)
	return _samples[key]

func animate(delta: float) -> void:
	_samples.clear()
	var demo_paused: bool = game.data.is_demo() and not game.sim.running
	for id in results:
		var result: Dictionary = results[id]
		for entry in result.get("animated", []):
			var node: Node3D = entry.get("node")
			if not is_instance_valid(node):
				continue
			var sample := _sample(String(id), String(entry.role))
			if not bool(sample.known):
				continue
			var level := float(sample.level)
			match String(entry.kind):
				"rotation":
					if not game.reduced_motion and not demo_paused:
						node.rotate_object_local(entry.get("axis", Vector3.FORWARD), delta * level * 10.0)
				"damper":
					var goal := lerpf(float(entry.get("closed", PI * 0.5)), float(entry.get("open", 0.0)), level)
					var axis: Vector3 = entry.get("axis", Vector3.RIGHT)
					var current := float(node.get_meta("angle", float(entry.get("closed", PI * 0.5))))
					current = goal if game.reduced_motion else move_toward(current, goal, delta * 2.5)
					node.set_meta("angle", current)
					if not node.has_meta("base_basis"): node.set_meta("base_basis", node.basis)
					node.basis = Basis(axis.normalized(), current) * Basis(node.get_meta("base_basis"))
				"fill":
					var rows := maxi(1, int(entry.get("rows", 3)))
					var target := clampf(level * rows - float(entry.get("row", 0)), 0.0, 1.0)
					var fill := move_toward(float(node.get_meta("fill", 0.0)), target, delta * 2.0)
					node.set_meta("fill", fill)
					var material := (node as MeshInstance3D).material_override as ShaderMaterial if node is MeshInstance3D else null
					if material != null:
						material.set_shader_parameter("fill_level", fill)
		_animate_covers(String(id), result, delta)
		_animate_doors(String(id), result, delta)
	var particle_basis := Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(0.6, 1.0, 0.6))
	for entry in air:
		var instance: MultiMeshInstance3D = entry.node
		if not is_instance_valid(instance):
			continue
		var sample := _sample(String(entry.owner), "airflow")
		var flowing: bool = bool(sample.known) and float(sample.level) > 0.02
		instance.visible = flowing and (airflow_view or _mode == 1)
		if not instance.visible:
			continue
		var moving: bool = not game.reduced_motion and not demo_paused
		var particles: Array = entry.particles
		for index in range(particles.size()):
			var particle: Dictionary = particles[index]
			if moving:
				particle.phase = fposmod(float(particle.phase) + delta * float(sample.level) * 1.6 / maxf(float(particle.length), 0.5), 1.0)
			var local := Vector3((float(particle.phase) - 0.5) * float(particle.length) * float(particle.sign), 0, 0)
			var frame: Transform3D = particle.frame
			instance.multimesh.set_instance_transform(index, frame * Transform3D(particle_basis, local))
	_screen_timer += delta
	if _screen_timer > 0.5:
		_screen_timer = 0.0
		for id in screens:
			(screens[id] as Label3D).text = _display_text(String(id))
	if _mode == 2:
		_fade_overhead(delta)

func _display_text(id: String) -> String:
	match String(game.model.find_object(id).get("kind", "")):
		"tstat":
			var info: Dictionary = game.thermostat_info(id)
			return Units.degrees(float(info.temp_c)) if info.has("temp_c") else "--"
		"ahu":
			var unit: Dictionary = game.sim.unit_state(id)
			if unit.is_empty(): return "--"
			return "%s\n%d%%" % [Units.degrees(float(unit.supply_temp_c)), roundi(float(unit.fan_feedback) * 100.0)]
		"vav":
			var terminal: Dictionary = game.sim.terminal_state(id)
			if terminal.is_empty() or not bool(terminal.get("connected", true)): return "--"
			return "%d%%\n%s" % [roundi(float(terminal.damper_feedback) * 100.0), Units.degrees(float(terminal.discharge_temp_c))]
	return "--"

func _animate_covers(id: String, result: Dictionary, delta: float) -> void:
	var open := bool(open_casings.get(id, false))
	for cover in result.get("covers", []):
		if not is_instance_valid(cover):
			continue
		if not cover.has_meta("base_position"): cover.set_meta("base_position", cover.position)
		var base: Vector3 = cover.get_meta("base_position")
		var goal := base + Vector3(0, 2.6, 0) if open else base
		cover.position = goal if game.reduced_motion else cover.position.lerp(goal, minf(delta * 7.0, 1.0))
		cover.visible = not (open and cover.position.distance_to(goal) < 0.05 and _mode == 2)

func _animate_doors(id: String, result: Dictionary, delta: float) -> void:
	var doors: Array = result.get("doors", [])
	for index in range(doors.size()):
		var door: Dictionary = doors[index]
		var node: Node3D = door.get("node")
		if not is_instance_valid(node):
			continue
		var key := "%s:%d" % [id, index]
		# "Open casing" lifts the whole cover set (doors included); a door
		# swings only when someone opens that one access door.
		var goal := float(door.get("open_angle", PI * 0.55)) if bool(access.get(key, false)) and not bool(open_casings.get(id, false)) else 0.0
		var angle := float(door_angles.get(key, 0.0))
		angle = goal if game.reduced_motion else move_toward(angle, goal, delta * 3.2)
		door_angles[key] = angle
		if not node.has_meta("base_basis"): node.set_meta("base_basis", node.basis)
		node.basis = Basis((door.get("axis", Vector3.UP) as Vector3).normalized(), angle) * Basis(node.get_meta("base_basis"))

# Overhead HVAC between the camera and the minifigure fades (desktop) or
# hides (web) so the player stays in view.
func _fade_overhead(delta: float) -> void:
	var head: Vector3 = game.explorer.focus_point()
	var feet := head - Vector3(0, 1.2, 0)
	var eye: Vector3 = game.explorer.camera.global_position
	# Whatever the player is about to use stays solid.
	var targeted := String(game.explorer.target.get("id", ""))
	for id in roots:
		var item: Dictionary = game.model.find_object(String(id))
		if item.is_empty() or String(item.kind) not in OVERHEAD:
			continue
		var gap := INF if String(id) == targeted else _sight_gap(String(id), item, eye, head, feet)
		var giving := bool(_giving_way.get(id, false))
		if not giving and gap < SIGHT_IN:
			giving = true
		elif giving:
			_clear_for[id] = float(_clear_for.get(id, 0.0)) + delta if gap > SIGHT_OUT else 0.0
			if float(_clear_for[id]) >= RETURN_DELAY:
				giving = false
		if giving != bool(_giving_way.get(id, false)):
			_giving_way[id] = giving
			_clear_for[id] = 0.0
		var goal := 0.82 if giving else 0.0
		var current := float(_fade.get(id, 0.0))
		var next := move_toward(current, goal, delta * (5.0 if giving else 2.5))
		if not can_fade:
			next = goal # the web renderer can't fade: show or hide outright
		if next != current or not _fade.has(id):
			_fade[id] = next
			_set_transparency(roots[id], next)

# How far a unit's surface is from the camera's lines to the minifigure.
func _sight_gap(id: String, item: Dictionary, eye: Vector3, head: Vector3, feet: Vector3) -> float:
	var best := INF
	if String(item.kind) == "duct":
		var path: Array = duct_paths.get(id, [])
		for index in range(path.size() - 1):
			for target in [head, feet]:
				var points := Geometry3D.get_closest_points_between_segments(path[index], path[index + 1], eye, target)
				best = minf(best, points[0].distance_to(points[1]) - Ducts.OUTER)
		return best
	var box: AABB = _bounds.get(id, AABB())
	if box.size == Vector3.ZERO:
		return INF
	var radius := box.size.length() * 0.5
	for target in [head, feet]:
		best = minf(best, Geometry3D.get_closest_point_to_segment(box.get_center(), eye, target).distance_to(box.get_center()) - radius * 0.8)
	return best

# What a unit touches, for settling against: other units' pieces and the
# furniture's bricks that meet one of its own pieces. They hold still; this
# unit moves. (Walls and floors never share a face with equipment.)
func _neighbours(id: String, units: Array[String], furniture: Dictionary) -> Array:
	var box: AABB = (_bounds.get(id, AABB()) as AABB).grow(0.02)
	var result: Array = []
	if box.size == Vector3.ZERO:
		return result
	var own: Array[AABB] = []
	for node in (roots[id] as Node).find_children("*", "MeshInstance3D", true, false):
		own.append(((node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()).grow(0.02))
	var touches := func(other: AABB) -> bool:
		if not box.intersects(other): return false
		for mine in own:
			if mine.intersects(other): return true
		return false
	for other in units:
		if other == id or not box.intersects(_bounds.get(other, AABB())):
			continue
		for node in (roots[other] as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh != null and mesh_node.is_visible_in_tree() and touches.call(mesh_node.global_transform * mesh_node.get_aabb()):
				result.append([mesh_node.mesh, mesh_node.global_transform, Coplanar._double_sided(mesh_node)])
	var arch: BrickBatch = game.arch.batch
	var seen := {}
	for cell in arch._cells_of(box):
		for entry in arch._near.get(cell, []):
			if not furniture.has(String(entry[2])): continue
			var key := str(entry[0]) + "#" + str(entry[1])
			if seen.has(key): continue
			seen[key] = true
			var part := String(arch.groups[entry[0]].part)
			var transform: Transform3D = arch.groups[entry[0]].records[int(entry[1])][0]
			if touches.call(transform * Bricks.bounds(part)):
				result.append([Bricks.mesh(part), transform, bool(arch.groups[entry[0]].glass)])
	return result

func _unit_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var box := (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func _set_transparency(node: Node, value: float) -> void:
	if not can_fade and node is Node3D and node.get_parent() == self:
		# The web renderer can't fade geometry: hide instead of ghosting.
		_show_unit(String(node.get_meta("entity_id", node.name)), value < 0.5)
		return
	if node is GeometryInstance3D and not node is Label3D:
		(node as GeometryInstance3D).transparency = value
	for child in node.get_children():
		_set_transparency(child, value)

func set_mode_view(mode: int) -> void:
	_mode = mode
	_apply_mode_look()

func _apply_mode_look() -> void:
	for id in roots:
		var item: Dictionary = game.model.find_object(String(id))
		if item.is_empty(): continue
		var overhead := String(item.kind) in OVERHEAD
		# Architecture mode keeps the ceiling services in view but quiet.
		_set_transparency(roots[id], 0.55 if _mode == 0 and overhead else 0.0)
		for child in roots[id].get_children():
			if child is Label3D and child.has_meta("bas_tag"):
				child.visible = _mode == 1 or game.overlay
	_fade.clear()
	_giving_way.clear()
	_clear_for.clear()

func update_cutaway(state: Dictionary) -> void:
	for id in roots:
		var item: Dictionary = game.model.find_object(String(id))
		if item.get("kind", "") != "tstat" or _held.has(id): continue
		var edge := String(item.properties.get("edge", ""))
		if edge.is_empty(): continue
		_show_unit(String(id), not BrickBatch.is_cut(BrickBatch.wall_custom(1, edge), int(state.mode), state.focus, state.forward, float(state.radius)))

# --- Highlighting -------------------------------------------------------------------------

func tint(id: String, colour: Color) -> void:
	var root: Node3D = roots.get(id)
	if not is_instance_valid(root):
		return
	if batches.has(id):
		batches[id].tint_owner(id, colour)
	var overlay: Material = null
	if colour.a > 0.0:
		var key := colour.to_html()
		if not _overlays.has(key):
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(colour.r, colour.g, colour.b, colour.a * 0.55)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.render_priority = 1
			_overlays[key] = material
		overlay = _overlays[key]
	_overlay(root, overlay)

func _overlay(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = material
	for child in node.get_children():
		_overlay(child, material)

func set_hidden(id: String, hidden: bool) -> void:
	if hidden: _held[id] = true
	else: _held.erase(id)
	var root: Node3D = roots.get(id)
	_show_unit(id, not hidden)
	if is_instance_valid(root):
		for body in root.find_children("*", "StaticBody3D", true, false):
			(body as StaticBody3D).collision_layer = 0 if hidden else 1

# --- Tools ------------------------------------------------------------------------------------

# The design new units start from: the last one built on the workbench, or
# a sensible standard unit.
func current_config(kind: String) -> Dictionary:
	if workbench_config.has(kind):
		return workbench_config[kind].duplicate(true)
	match kind:
		"ahu": return {"layout": ["damper", "filter", "cooling_coil", "heating_coil", "fan"], "sensor_enabled": true}
		"vav": return {"layout": ["damper", "heating_coil"], "sensor_enabled": true}
	return {}

func has_tool(id: String) -> bool:
	return id in ["equipment", "duct", "zone"]

func make_tool(id: String, params: Dictionary) -> BuildTool:
	if id == "duct":
		return DuctToolScript.new(game, params)
	if id == "zone":
		return ZoneTool.new(game, params)
	return EquipmentToolScript.new(game, params)

func move_tool(id: String) -> BuildTool:
	var item: Dictionary = game.model.find_object(id)
	if item.kind == "tstat":
		return PlaceTool.new(game, {"kind": "tstat", "moving_id": id, "properties": item.properties})
	return EquipmentToolScript.new(game, {"kind": item.kind, "moving_id": id, "properties": item.properties, "rotation": item.transform.get("rotation_y", 0.0)})

func copy_tool(id: String) -> BuildTool:
	var item: Dictionary = game.model.find_object(id)
	if item.kind == "tstat":
		return PlaceTool.new(game, {"kind": "tstat", "once": true})
	var properties: Dictionary = item.properties.duplicate(true)
	properties.erase("bindings")
	properties.erase("label")
	return EquipmentToolScript.new(game, {"kind": item.kind, "properties": properties, "rotation": item.transform.get("rotation_y", 0.0), "once": true})

func rotate_object(id: String) -> bool:
	var item: Dictionary = game.model.find_object(id)
	if item.is_empty() or String(item.kind) not in ["ahu", "vav", "diffuser", "tee", "cross"]:
		return false
	var tool := move_tool(id)
	game.set_tool(tool)
	# It turns where it stands: the ghost starts on the piece, not wherever
	# the pointer happens to be (over the HUD, or nowhere yet).
	var at := DuctPorts.vector(item.transform.position)
	at.y = PlanGrid.FLOOR_TOP if String(item.kind) == "ahu" else CEILING_FACE
	var camera: Camera3D = game.rig.camera
	if not camera.is_position_behind(at):
		tool.last_mouse = camera.unproject_position(at)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	tool.key(event)
	return true

func open_workbench(kind: String, editing_id: String = "") -> void:
	if not is_instance_valid(workbench):
		workbench = WorkbenchScript.new()
		game.hud.add_child(workbench)
		workbench.setup(game, self)
	workbench.open(kind, editing_id)

func toggle_casing(id: String) -> void:
	open_casings[id] = not bool(open_casings.get(id, false))
	game.play_sound("open" if open_casings[id] else "close")

func toggle_airflow_view() -> void:
	airflow_view = not airflow_view
	_signature = 0
	rebuild(game.model.objects)
	game.hud.rebuild_shelf()
	game.set_status("Duct lids %s · airflow particles follow each branch's actual flow" % ("off" if airflow_view else "on"))

# --- Tray -------------------------------------------------------------------------------------

func tray_categories() -> Array:
	return ["Air handling", "Air distribution", "Controls"]

func tray_items(category: String) -> Array:
	var items: Array = []
	match category:
		"Air handling":
			items.append({"id": "zone", "label": "Zone a room", "glyph": "thermo", "tooltip": "Click a room: it gets a VAV sized to it, diffusers and a thermostat, ducted from the nearest supply (tapping the main when needed). One undo.", "action": func() -> void: game.start_tool("zone"), "color": Color("bfe6f0")})
			items.append({"id": "ahu", "label": "Air handler", "glyph": "fan", "tooltip": "Heats, cools and moves the air. Put it in a mechanical room or just outside · R turns it · change its sections later from its card", "action": func() -> void: game.start_tool("equipment", {"kind": "ahu", "properties": current_config("ahu")})})
			items.append({"id": "vav", "label": "VAV box", "glyph": "fan", "tooltip": "One per room: sets that room's airflow and reheat. Place it over the room and it ducts itself to the main · change coils from its card", "action": func() -> void: game.start_tool("equipment", {"kind": "vav", "properties": current_config("vav")})})
			items.append({"id": "next", "note": next_step()})
		"Air distribution":
			items.append({"id": "diffuser", "label": "Diffuser", "glyph": "airflow", "tooltip": "Where air enters a room. Put it in the room's ceiling and it hooks up to that room's VAV", "action": func() -> void: game.start_tool("equipment", {"kind": "diffuser"})})
			items.append({"id": "duct", "label": "Duct run", "glyph": "duct", "tooltip": "Connect two sockets by hand: click one, then the other · the run finds its way over the walls", "action": func() -> void: game.start_tool("duct")})
			items.append({"id": "cross", "label": "Trunk cross", "glyph": "duct", "tooltip": "A tap on a main: air goes straight through and out two side branches (Zone a room adds these for you)", "action": func() -> void: game.start_tool("equipment", {"kind": "cross"})})
			items.append({"id": "tee", "label": "Branch tee", "glyph": "duct", "tooltip": "Splits one duct in two, e.g. to feed a second diffuser", "action": func() -> void: game.start_tool("equipment", {"kind": "tee"})})
			items.append({"id": "airflow_view", "label": "Airflow view", "glyph": "airflow", "tooltip": "Lift the duct lids and watch the air move", "action": toggle_airflow_view, "color": Color("bfe6f0") if airflow_view else Color("e5dfca")})
		"Controls":
			items.append({"id": "tstat", "label": "Thermostat", "glyph": "thermo", "tooltip": "Hang it on a wall inside the room it should control", "action": func() -> void: game.start_tool("place", {"kind": "tstat"})})
	return items

static func describe_kind(kind: String) -> String:
	return {"ahu": "air handler", "vav": "VAV", "diffuser": "diffuser", "tee": "tee", "cross": "cross"}.get(kind, kind)

# What to do next, for the tray's note.
func next_step() -> String:
	if game.model.objects_of(["ahu"]).is_empty():
		return "Start here: place an Air handler in a mechanical room or just outside."
	var waiting := 0
	for room in game.index.rooms:
		if String(room.get("type", "room")) in ["corridor", "restroom", "storage", "mechanical"]:
			continue
		if not bool(game.sim.zone_state(String(room.id)).get("served", false)):
			waiting += 1
	if waiting > 0:
		return "Next: Zone a room · %d room%s still without air." % [waiting, "" if waiting == 1 else "s"]
	return "Every room has air. Try the Airflow view, or walk the building in Explore."

# --- Context card -----------------------------------------------------------------------------

func inspect(id: String) -> Dictionary:
	var item: Dictionary = game.model.find_object(id)
	if item.is_empty():
		return {}
	var actions: Array = []
	var text := ""
	var level := -1.0
	match String(item.kind):
		"ahu", "vav":
			text = readout(item)
			var role := "fan" if item.kind == "ahu" else "damper"
			var sample: Dictionary = game.animation_sample(id, role)
			if bool(sample.known): level = float(sample.level)
			actions.append(game.action("Open casing", "open", func() -> void: toggle_casing(id)))
			actions.append(game.action("Edit components", "build", func() -> void: open_workbench(String(item.kind), id)))
			actions.append(game.action("Point links", "link", func() -> void: game.hud.details.open(id); game.hud.details.tabs.current_tab = 1))
			if item.kind == "vav":
				actions.append(game.action("Connect supply", "duct", func() -> void: auto_connect(id)))
		"duct":
			var error := String(roots[id].get_meta("connection_error", "")) if roots.has(id) else ""
			var sample: Dictionary = game.animation_sample(id, "airflow")
			text = error if not error.is_empty() else "Supply duct · %s" % (Units.flow(float(game.points.get_point(id + ".airflow").get("value", 0.0))) if bool(sample.known) else String(sample.status))
			if bool(sample.known): level = float(sample.level)
			actions.append(game.action("Airflow view", "airflow", toggle_airflow_view))
		"diffuser":
			text = diffuser_readout(item) if game.data.is_demo() else "Ceiling diffuser"
		"tee", "cross":
			var free := DuctPorts.port_names(item).filter(func(name: String) -> bool: return not DuctPorts.occupied(DuctPorts.port(item, name), game.model.objects))
			text = "%s · %d of %d sockets free" % ["Trunk cross: straight through plus two branches" if item.kind == "cross" else "Branch tee: one duct in, two out", free.size(), DuctPorts.port_names(item).size()]
	if item.kind in ["diffuser", "tee", "cross"] and not DuctPorts.occupied(DuctPorts.port(item, "inlet"), game.model.objects):
		actions.append(game.action("Connect supply", "duct", func() -> void: auto_connect(id)))
	actions.append(game.action("Move · M", "move", func() -> void: game.start_move(id)))
	if item.kind != "duct":
		actions.append(game.action("Copy", "copy", game.duplicate_selected))
	actions.append(game.action("Delete", "hammer", game.delete_selected))
	var result := {"text": text, "actions": actions, "trends": trends(item)}
	if level >= 0.0: result.level = level
	return result

# One-line live summary for floating prompts.
func short_readout(id: String) -> String:
	var item: Dictionary = game.model.find_object(id)
	if not game.data.is_demo():
		return live_readout(item).replace("\n", " · ")
	match String(item.get("kind", "")):
		"ahu":
			var unit: Dictionary = game.sim.unit_state(id)
			if unit.is_empty(): return ""
			return "%s · fan %d %% · %s supply" % [String(unit.get("mode", "")), roundi(float(unit.fan_feedback) * 100.0), Units.temp(float(unit.supply_temp_c))]
		"vav":
			var terminal: Dictionary = game.sim.terminal_state(id)
			if terminal.is_empty(): return ""
			return "%s · %s · damper %d %%" % [String(terminal.mode), Units.temp(float(terminal.space_temp_c), 1), roundi(float(terminal.damper_feedback) * 100.0)]
		"diffuser":
			return diffuser_readout(item).replace("\n", " · ")
	return ""

# What a diffuser is blowing: the airflow of the duct feeding it and the
# discharge temperature of the VAV upstream.
func diffuser_readout(item: Dictionary) -> String:
	var id := String(item.id)
	var room: Dictionary = game.index.room_at(_transform(item).origin)
	var where := String(room.label) if not room.is_empty() else "not over a room"
	var vav_id := ""
	for terminal_id in game.topology.get("terminals", {}):
		if id in (game.topology.terminals[terminal_id].get("diffusers", []) as Array): vav_id = String(terminal_id)
	if vav_id.is_empty():
		return "Ceiling diffuser · %s\nNo air · connect it downstream of a VAV" % where
	var feed := ""
	for duct in game.model.objects:
		if duct.kind == "duct" and String(duct.properties.get("end_port", {}).get("owner", "")) == id: feed = String(duct.id)
	var airflow: Dictionary = game.points.get_point(feed + ".airflow") if not feed.is_empty() else {}
	var terminal: Dictionary = game.sim.terminal_state(vav_id)
	var flow_text := Units.flow(float(airflow.value)) if airflow.get("value") is float else "--"
	return "Ceiling diffuser · %s\n%s at %s · from %s" % [where, flow_text, Units.temp(float(terminal.get("discharge_temp_c", 0.0))), String(terminal.get("label", vav_id))]

# BAS trend lines for the context card.
static func trends(item: Dictionary) -> Array:
	var id := String(item.id)
	match String(item.kind):
		"ahu":
			return [
				{"point_id": id + ".supply_air_temp", "label": "SAT", "color": Color("f2a65a"), "quantity": "temp"},
				{"point_id": id + ".supply_setpoint", "label": "SP", "color": Color("8d9aa0"), "quantity": "temp", "dashed": true},
				{"point_id": id + ".fan_speed_feedback", "label": "Fan", "color": Color("73d398"), "quantity": "percent", "own_axis": true, "min": 0.0, "max": 100.0},
			]
		"vav":
			return [
				{"point_id": id + ".space_temp", "label": "Room", "color": Color("f2a65a"), "quantity": "temp"},
				{"point_id": id + ".cool_setpoint", "label": "Cool", "color": Color("6fb7ff"), "quantity": "temp", "dashed": true},
				{"point_id": id + ".damper_feedback", "label": "Damper", "color": Color("73d398"), "unit": "%", "own_axis": true, "min": 0.0, "max": 100.0},
			]
		"duct":
			return [{"point_id": id + ".airflow", "label": "Airflow", "color": Color("7fe3ff"), "quantity": "flow", "own_axis": true, "min": 0.0, "max": Units.cfm(float(item.properties.get("capacity_m3_s", 1.2)))}]
	return []

# On a live station: each linked point's reading, as the station shows it.
func live_readout(item: Dictionary) -> String:
	var lines: Array[String] = []
	var bindings: Dictionary = item.get("properties", {}).get("bindings", {})
	for role in PointMatcher.ROLES_BY_KIND.get(String(item.get("kind", "")), []):
		var binding: Dictionary = bindings.get(role, {})
		if String(binding.get("source", "")) != "niagara": continue
		var point: Dictionary = game.points.get_point(String(binding.get("point_id", "")))
		var shown := "waiting…"
		if not point.is_empty():
			shown = String(point.get("display", ""))
			if shown.is_empty(): shown = str(point.get("value", "--"))
			var flags: Array = point.get("quality_flags", [])
			if not flags.has("good"): shown += " (%s)" % ", ".join(flags)
		lines.append("%s %s" % [String(PointMatcher.ROLE_LABELS.get(role, role)), shown])
	if lines.is_empty():
		return "No station points linked · open its details (•••) to link or auto-map them"
	return "\n".join(lines)

func readout(item: Dictionary) -> String:
	var id := String(item.id)
	if not game.data.is_demo():
		return live_readout(item)
	if item.kind == "ahu":
		var unit: Dictionary = game.sim.unit_state(id)
		if unit.is_empty(): return "Air handler · waiting for the simulation"
		var lines: Array[String] = []
		lines.append("%s · fan %d %% · %s" % [String(unit.get("mode", "")), roundi(float(unit.fan_feedback) * 100.0), Units.flow(float(unit.supply_airflow_m3_s))])
		lines.append("Supply %s (set %s) · static %s" % [Units.temp(float(unit.supply_temp_c), 1), Units.temp(float(unit.supply_setpoint_c)), Units.pressure(float(unit.duct_pressure_pa))])
		lines.append("Outdoor air %d %%%s · cool %d %% · heat %d %%" % [roundi(float(unit.oa_fraction) * 100.0), " (economizer)" if bool(unit.get("economizer", false)) else "", roundi(float(unit.cooling_output) * 100.0), roundi(float(unit.heating_output) * 100.0)])
		if not String(unit.get("fault", "")).is_empty() and game.job == null:
			lines.append("Fault: %s" % String(unit.fault).replace("_", " "))
		return "\n".join(lines)
	var terminal: Dictionary = game.sim.terminal_state(id)
	if terminal.is_empty(): return "VAV · waiting for the simulation"
	var room: Dictionary = game.index.room_by_id(String(terminal.get("zone_id", "")))
	var serving := String(room.get("label", "no room yet"))
	if not bool(terminal.get("connected", false)):
		return "Serves %s\nNot connected · needs supply from an AHU and a diffuser downstream" % serving
	return "Serves %s · %s · %s\n%s of %s · damper %d %%\nReheat %d %% · discharge %s" % [serving, String(terminal.mode), Units.temp(float(terminal.space_temp_c), 1), Units.flow(float(terminal.airflow_m3_s)), Units.flow(float(terminal.airflow_target_m3_s)), roundi(float(terminal.damper_feedback) * 100.0), roundi(float(terminal.reheat_output) * 100.0), Units.temp(float(terminal.discharge_temp_c))]

# --- Explore ----------------------------------------------------------------------------------

func interactables() -> Array:
	var result: Array = []
	for id in results:
		var item: Dictionary = game.model.find_object(String(id))
		if item.is_empty() or String(item.kind) not in ["ahu", "vav", "diffuser"]:
			continue
		var root: Node3D = roots[id]
		var owner := String(id)
		var doors: Array = results[id].get("doors", [])
		if item.kind == "ahu" and not doors.is_empty():
			var sections: Array = results[id].get("sections", [])
			for index in range(doors.size()):
				var door: Dictionary = doors[index]
				var key := "%s:%d" % [id, index]
				var section := int(door.get("section", 0))
				var local: Vector3 = sections[section].center if section < sections.size() else Vector3.ZERO
				var center := root.global_transform * local
				result.append({"id": owner, "kind": "equipment", "position": Vector3(center.x, root.global_position.y + 1.0, center.z), "access_key": key, "prompt": "%s %s door" % ["Open", String(door.get("role", "")).replace("_", " ")], "action": func() -> void: _toggle_access(key, owner)})
		elif item.kind == "diffuser":
			# Real effect: lift the duct lids and watch the air move.
			result.append({"id": owner, "kind": "equipment", "position": root.global_position, "airflow": true, "action": func() -> void: toggle_airflow_view(); game.select(owner)})
		else:
			# Lift the casing to watch the damper and reheat coil work.
			result.append({"id": owner, "kind": "equipment", "position": root.global_position + Vector3(0, 0.4, 0), "casing": true, "action": func() -> void: toggle_casing(owner); game.select(owner)})
	return result

func _toggle_access(key: String, owner: String) -> void:
	access[key] = not bool(access.get(key, false))
	game.play_sound("open" if access[key] else "close")
	game.select(owner)
	game.set_status(readout(game.model.find_object(owner)).replace("\n", " · "))

func access_open(key: String) -> bool:
	return bool(access.get(key, false))

# --- Auto-connect -----------------------------------------------------------------------------

# Route a VAV's inlet from the nearest free supply outlet, then feed the
# nearest free diffuser from its outlet. One undo step.
func auto_connect(vav_id: String) -> void:
	var planner := ZonePlanner.new(game.model.objects, game.index, game.model.new_id)
	var vav: Dictionary = planner._find(vav_id)
	var messages: Array[String] = []
	if not DuctPorts.occupied(DuctPorts.port(vav, "inlet"), planner.objects) and not planner.connect_inlet(vav):
		messages.append("no supply duct in reach")
	var outlet := DuctPorts.port(vav, "outlet")
	if String(vav.kind) == "vav" and not DuctPorts.occupied(outlet, planner.objects):
		var route := best_route(outlet, ["diffuser"], planner.objects)
		if route.is_empty(): messages.append("no free diffuser nearby")
		else: planner.include(route)
	var adds := planner.entries
	if adds.is_empty():
		game.set_status("Couldn't connect: %s" % ", ".join(messages) if not messages.is_empty() else "Already connected")
		game.play_sound("error")
		return
	game.apply("Connect " + describe_kind(String(vav.kind)), adds, planner.removed_ids())
	game.play_sound("place")
	game.set_status("Connected %d duct run%s%s" % [adds.size(), "" if adds.size() == 1 else "s", "" if messages.is_empty() else " · " + ", ".join(messages)])

static func best_route(port: Dictionary, kinds: Array, objects: Array, reach: float = 40.0) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := reach
	for item in objects:
		if String(item.kind) not in kinds or item.id == port.owner:
			continue
		for name in DuctPorts.port_names(item):
			var other := DuctPorts.port(item, name)
			if other.direction == port.direction or DuctPorts.occupied(other, objects):
				continue
			var distance: float = (other.position as Vector3).distance_to(port.position)
			if distance >= best_distance:
				continue
			var routed := DuctPorts.auto_route(port, other, objects)
			if not bool(routed.ok):
				continue
			var properties: Dictionary = routed.properties
			properties.bindings = Bindings.defaults("duct")
			best = {"kind": "duct", "transform": {"position": [0, 0, 0], "rotation_y": 0.0}, "properties": properties}
			best_distance = distance
	return best
