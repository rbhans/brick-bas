class_name BrickBatch
extends RefCounted

# Draws every static LDraw piece of a scene with one MultiMesh per part.
#
# Pieces are recorded with an owner id (the model object they belong to) so a
# whole object can be highlighted or hidden without rebuilding: its instances
# are re-tinted or collapsed in place. Rebuilding the full batch is cheap
# because instance data is written as one packed buffer per part.

const OPAQUE_SHADER := preload("res://scripts/render/brick_batch.gdshader")
const GLASS_SHADER := preload("res://scripts/render/brick_glass.gdshader")
const GHOST_SHADER := preload("res://scripts/render/brick_ghost.gdshader")
const FLOATS := 20 # 12 transform + 4 colour + 4 custom

static var opaque_material: ShaderMaterial
static var glass_material: ShaderMaterial

var root: Node3D
var cast_shadows := true
var override_material: Material # ghost previews draw every group with this
var groups: Dictionary = {}   # group key -> {part, glass, records: Array of [Transform3D, Color, Color]}
var owners: Dictionary = {}   # owner id -> Array of [group key, index]
var instances: Dictionary = {} # group key -> MultiMeshInstance3D
var _tinted: Dictionary = {}
var _hidden: Dictionary = {}

static func materials() -> Array[ShaderMaterial]:
	if opaque_material == null:
		opaque_material = ShaderMaterial.new()
		opaque_material.shader = OPAQUE_SHADER
		glass_material = ShaderMaterial.new()
		glass_material.shader = GLASS_SHADER
		glass_material.render_priority = 1
	return [opaque_material, glass_material]

# Cutaway uniforms are shared by every batch (walls, frames, stubs).
static func set_cutaway(mode: int, focus: Vector3, forward: Vector3, radius: float) -> void:
	var flat := Vector2(forward.x, forward.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector2(0, -1)
	for material in materials():
		material.set_shader_parameter("wall_mode", mode)
		material.set_shader_parameter("cut_focus", focus)
		material.set_shader_parameter("cut_forward", flat)
		material.set_shader_parameter("cut_radius", radius)

# CPU mirror of the shader test, for animated nodes (door leaves) that live
# outside the batch but must disappear with their wall.
static func is_cut(custom: Color, mode: int, focus: Vector3, forward: Vector3, radius: float) -> bool:
	if custom.r < 0.5 or mode == 0:
		return false
	if mode == 2:
		return true
	var flat := Vector2(forward.x, forward.z).normalized()
	var offset := Vector2(custom.b, custom.a) - Vector2(focus.x, focus.z)
	var normal := Vector2(0, 1) if custom.g < 0.5 else Vector2(1, 0)
	return absf(normal.dot(flat)) > 0.3 and offset.dot(flat) < 1.5 and offset.length() < radius

static func ghost_material(valid: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GHOST_SHADER
	material.set_shader_parameter("ghost_tint", Color("5fe28c") if valid else Color("ef5a48"))
	material.set_shader_parameter("tint_amount", 0.35 if valid else 0.6)
	return material

static func wall_custom(flag: int, edge_key: String) -> Color:
	var center := PlanGrid.edge_center(edge_key)
	return Color(float(flag), 0.0 if edge_key.begins_with("x") else 1.0, center.x, center.z)

func clear() -> void:
	if is_instance_valid(root):
		root.free()
	root = null
	groups.clear()
	owners.clear()
	instances.clear()
	_tinted.clear()
	_hidden.clear()

func add(owner: String, part: String, transform: Transform3D, tint: Variant, custom: Color = Color(0, 0, 0, 0)) -> void:
	var colour := Bricks.color(tint)
	var glass := Bricks.is_transparent(colour)
	var key := part + ("|glass" if glass else "")
	if not groups.has(key):
		groups[key] = {"part": part, "glass": glass, "records": []}
	var records: Array = groups[key].records
	if not owner.is_empty():
		if not owners.has(owner):
			owners[owner] = []
		owners[owner].append([key, records.size()])
	records.append([transform, colour, custom])

func place(owner: String, part: String, bottom: Vector3, tint: Variant, rotation_y: float = 0.0, custom: Color = Color(0, 0, 0, 0)) -> void:
	add(owner, part, Bricks.bottom_transform(part, bottom, Bricks.basis_y(rotation_y)), tint, custom)

# Moves static MeshInstance3D pieces of a node tree into the batch and frees
# them. Subtrees marked with meta "dynamic" (rotors, hinged doors, animated
# coils) stay as nodes.
# Bakes every static LDraw piece under `node` into the batch. `space` is the
# node the batch will be built under (build(space)); transforms are stored
# relative to it, so batches can live under moved/rotated unit roots.
func absorb(owner: String, node: Node, custom: Color = Color(0, 0, 0, 0), space: Node3D = null) -> void:
	for child in node.get_children():
		if child.has_meta("dynamic") or (child is Node3D and not (child as Node3D).visible):
			continue
		absorb(owner, child, custom, space)
	if node is MeshInstance3D and node.has_meta("ldraw_part_id") and node.visible:
		var mesh_node := node as MeshInstance3D
		var material := mesh_node.material_override as StandardMaterial3D
		if material == null:
			return
		var transform := mesh_node.global_transform
		if space != null:
			transform = space.global_transform.affine_inverse() * transform
		add(owner, String(node.get_meta("ldraw_part_id")), transform, material.albedo_color, custom)
		mesh_node.get_parent().remove_child(mesh_node)
		mesh_node.queue_free()

func build(parent: Node3D, name: String = "Brick batch") -> void:
	materials()
	if not is_instance_valid(root):
		root = Node3D.new()
		root.name = name
		parent.add_child(root)
	for key in groups:
		var group: Dictionary = groups[key]
		var records: Array = group.records
		if records.is_empty():
			continue
		var data := PackedFloat32Array()
		data.resize(records.size() * FLOATS)
		var o := 0
		for record in records:
			var transform: Transform3D = record[0]
			var colour: Color = record[1]
			var custom: Color = record[2]
			var basis := transform.basis
			data[o] = basis.x.x; data[o + 1] = basis.y.x; data[o + 2] = basis.z.x; data[o + 3] = transform.origin.x
			data[o + 4] = basis.x.y; data[o + 5] = basis.y.y; data[o + 6] = basis.z.y; data[o + 7] = transform.origin.y
			data[o + 8] = basis.x.z; data[o + 9] = basis.y.z; data[o + 10] = basis.z.z; data[o + 11] = transform.origin.z
			data[o + 12] = colour.r; data[o + 13] = colour.g; data[o + 14] = colour.b; data[o + 15] = colour.a
			data[o + 16] = custom.r; data[o + 17] = custom.g; data[o + 18] = custom.b; data[o + 19] = custom.a
			o += FLOATS
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = Bricks.mesh(String(group.part))
		multimesh.instance_count = records.size()
		multimesh.buffer = data
		var instance := MultiMeshInstance3D.new()
		instance.name = String(key)
		instance.multimesh = multimesh
		instance.material_override = override_material if override_material != null else (glass_material if bool(group.glass) else opaque_material)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if bool(group.glass) or not cast_shadows or override_material != null else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(instance)
		instances[key] = instance

func has_owner(owner: String) -> bool:
	return owners.has(owner)

func owner_bounds(owner: String) -> AABB:
	var result := AABB()
	var first := true
	for entry in owners.get(owner, []):
		var group: Dictionary = groups[entry[0]]
		var transform: Transform3D = group.records[int(entry[1])][0]
		var box := transform * Bricks.bounds(String(group.part))
		result = box if first else result.merge(box)
		first = false
	return result

func owner_pieces(owner: String) -> Array:
	var result: Array = []
	for entry in owners.get(owner, []):
		var group: Dictionary = groups[entry[0]]
		var record: Array = group.records[int(entry[1])]
		result.append({"part": group.part, "transform": record[0], "color": record[1]})
	return result

# Brightens (or restores with Color(0,0,0,0)) every instance of an owner.
func tint_owner(owner: String, highlight: Color) -> void:
	for entry in owners.get(owner, []):
		var instance: MultiMeshInstance3D = instances.get(entry[0])
		if instance == null:
			continue
		var base: Color = groups[entry[0]].records[int(entry[1])][1]
		var shown := base if highlight.a <= 0.0 else base.lerp(Color(highlight.r, highlight.g, highlight.b, base.a), highlight.a)
		instance.multimesh.set_instance_color(int(entry[1]), shown)

func set_owner_hidden(owner: String, hidden: bool) -> void:
	if bool(_hidden.get(owner, false)) == hidden:
		return
	_hidden[owner] = hidden
	for entry in owners.get(owner, []):
		var instance: MultiMeshInstance3D = instances.get(entry[0])
		if instance == null:
			continue
		var transform: Transform3D = groups[entry[0]].records[int(entry[1])][0]
		if hidden:
			transform = Transform3D(Basis.from_scale(Vector3.ZERO), transform.origin)
		instance.multimesh.set_instance_transform(int(entry[1]), transform)

# Folds the static project-authored meshes under `root` (duct shells, collars,
# fitting bodies) into one mesh per material, so a duct or fitting costs a
# couple of draw calls instead of a dozen. Animated or liftable parts (any
# node under a "dynamic" meta) and LDraw pieces (batched separately) are left
# alone. Call after painting and after absorb()/build().
static func merge_static(root: Node3D) -> void:
	var groups: Dictionary = {}   # material/format key -> {material, nodes}
	var inverse := root.global_transform.affine_inverse()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.has_meta("ldraw_part_id") or not mesh_node.is_visible_in_tree() or mesh_node.mesh == null or mesh_node.mesh.get_surface_count() != 1:
			continue
		if _under_dynamic(mesh_node, root):
			continue
		var material := mesh_node.material_override if mesh_node.material_override != null else mesh_node.mesh.surface_get_material(0)
		if not (material is StandardMaterial3D):
			continue
		var standard := material as StandardMaterial3D
		# Primitive meshes share one vertex layout; ArrayMeshes group by theirs.
		var layout := (mesh_node.mesh as ArrayMesh).surface_get_format(0) if mesh_node.mesh is ArrayMesh else -1
		var key := "%s|%d|%d|%d|%s|%d" % [standard.albedo_color.to_html(), standard.transparency, standard.cull_mode, standard.shading_mode, mesh_node.mesh.get_class(), layout]
		if not groups.has(key):
			groups[key] = {"material": material, "nodes": []}
		groups[key].nodes.append(mesh_node)
	for key in groups:
		var nodes: Array = groups[key].nodes
		if nodes.size() < 2:
			continue
		var tool := SurfaceTool.new()
		for mesh_node in nodes:
			tool.append_from((mesh_node as MeshInstance3D).mesh, 0, inverse * (mesh_node as MeshInstance3D).global_transform)
		var merged := MeshInstance3D.new()
		merged.name = "Merged static"
		merged.mesh = tool.commit()
		merged.material_override = groups[key].material
		root.add_child(merged)
		for mesh_node in nodes:
			(mesh_node as Node).get_parent().remove_child(mesh_node)
			(mesh_node as Node).queue_free()

static func _under_dynamic(node: Node, root: Node) -> bool:
	var cursor := node
	while cursor != null and cursor != root:
		if cursor.has_meta("dynamic"):
			return true
		cursor = cursor.get_parent()
	return false

func instance_count() -> int:
	var total := 0
	for group in groups.values():
		total += group.records.size()
	return total
