class_name Bricks
extends RefCounted

# Shared access to the baked official LDraw meshes, the LEGO colour palette and
# cached plastic materials. Everything that places a brick goes through here so
# meshes and materials are loaded once and shared.
#
# Conventions (LDraw, converted to Godot metres, 1 LDU = 0.025 m):
#   * A brick/plate/tile origin is the centre of its TOP face; the body hangs
#     below (a 1 x 4 brick spans y -0.6..0, studs rise to +0.1).
#   * Footprint is centred on the origin in X/Z. Length runs along local +X.
#   * place() takes the centre of the part's BOTTOM face, which is how builders
#     think about stacking: bricks every 0.6 m, plates/tiles every 0.2 m.

const MESH_PATH := "res://assets/third_party/ldraw/meshes/%s.obj"

# Approximations of the official LDraw/LEGO colours (LDConfig), named the way
# builders talk about them.
const PALETTE := {
	"white": Color("f4f4f2"),
	"light_bluish_gray": Color("a0a5a9"),
	"dark_bluish_gray": Color("6c6e68"),
	"black": Color("27313a"),
	"tan": Color("e4cd9e"),
	"dark_tan": Color("958a73"),
	"light_nougat": Color("f6d7b3"),
	"nougat": Color("d09168"),
	"medium_nougat": Color("aa7d55"),
	"reddish_brown": Color("6b3a22"),
	"dark_brown": Color("4a2a1a"),
	"red": Color("c91a09"),
	"dark_red": Color("8a2323"),
	"sand_red": Color("d67572"),
	"orange": Color("fe8a18"),
	"bright_light_orange": Color("f8bb3d"),
	"yellow": Color("f2cd37"),
	"bright_light_yellow": Color("fff03a"),
	"lime": Color("bbe90b"),
	"green": Color("237841"),
	"bright_green": Color("4b9f4a"),
	"dark_green": Color("184632"),
	"sand_green": Color("a0bcac"),
	"olive_green": Color("9b9a5a"),
	"blue": Color("0055bf"),
	"medium_blue": Color("5a93db"),
	"dark_blue": Color("0a3463"),
	"sand_blue": Color("6074a1"),
	"medium_azure": Color("36aebf"),
	"dark_azure": Color("078bc9"),
	"bright_light_blue": Color("9fc3e9"),
	"lavender": Color("e1d5ed"),
	"coral": Color("ff698f"),
	"flat_silver": Color("8d949c"),
	"pearl_gold": Color("aa7f2e"),
	"copper": Color("b0683a"),
	"trans_clear": Color(0.93, 0.97, 1.0, 0.32),
	"trans_light_blue": Color(0.68, 0.91, 0.94, 0.42),
	"trans_black": Color(0.39, 0.37, 0.38, 0.55),
	"trans_orange": Color(0.99, 0.64, 0.16, 0.7),
	"trans_red": Color(0.79, 0.1, 0.04, 0.7),
	"trans_green": Color(0.14, 0.62, 0.26, 0.7),
}

static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}

static func color(value: Variant) -> Color:
	if value is Color:
		return value
	var key := String(value)
	if PALETTE.has(key):
		return PALETTE[key]
	if Color.html_is_valid(key):
		return Color(key)
	push_warning("Unknown brick colour: %s" % key)
	return PALETTE.light_bluish_gray

static func mesh(part: String) -> Mesh:
	if not _meshes.has(part):
		var loaded := load(MESH_PATH % part) as Mesh
		if loaded == null:
			push_error("Missing baked LDraw part %s" % part)
			loaded = BoxMesh.new()
		_meshes[part] = loaded
	return _meshes[part]

static func exists(part: String) -> bool:
	return ResourceLoader.exists(MESH_PATH % part)

static func bounds(part: String) -> AABB:
	return mesh(part).get_aabb()

# Offset from a part's bottom-centre to its LDraw origin.
static func bottom_offset(part: String) -> float:
	return -bounds(part).position.y

static func is_transparent(value: Color) -> bool:
	return value.a < 0.99

# Plastic look: moderately glossy ABS. Materials are shared per colour/finish.
static func material(value: Variant, emission: float = 0.0) -> StandardMaterial3D:
	var tint := color(value)
	var key := "%s|%.2f" % [tint.to_html(true), emission]
	if _materials.has(key):
		return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = 0.42
	result.metallic_specular = 0.45
	if is_transparent(tint):
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.roughness = 0.08
		result.metallic_specular = 0.7
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
		result.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		# Drawn from both sides: pull the surfaces in a touch so the far face
		# never shares a plane with what the glass rests on (brick_glass.gdshader).
		result.grow = true
		result.grow_amount = -0.003
	if emission > 0.0:
		result.emission_enabled = true
		result.emission = tint
		result.emission_energy_multiplier = emission
	_materials[key] = result
	return result

static func basis_y(rotation_y: float) -> Basis:
	return Basis(Vector3.UP, rotation_y)

# Transform of the LDraw origin for a part whose bottom-centre sits at `bottom`.
static func bottom_transform(part: String, bottom: Vector3, rotation: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(rotation, bottom + rotation * Vector3(0, bottom_offset(part), 0))

# Transform that puts the part's bounding-box centre at `center`.
static func centered_transform(part: String, center: Vector3, rotation: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(rotation, center - rotation * bounds(part).get_center())

static func spawn(parent: Node3D, part: String, transform: Transform3D, tint: Variant) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "LDraw %s" % part
	node.mesh = mesh(part)
	node.transform = transform
	node.material_override = material(tint)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.set_meta("ldraw_part_id", part)
	parent.add_child(node)
	return node

# The everyday builder call: a part standing on `bottom`, turned about Y.
static func place(parent: Node3D, part: String, bottom: Vector3, tint: Variant, rotation_y: float = 0.0) -> MeshInstance3D:
	return spawn(parent, part, bottom_transform(part, bottom, basis_y(rotation_y)), tint)

# Arbitrary orientation (sideways tiles, rotated gears, pipes...).
static func place_centered(parent: Node3D, part: String, center: Vector3, tint: Variant, rotation: Basis = Basis.IDENTITY) -> MeshInstance3D:
	return spawn(parent, part, centered_transform(part, center, rotation), tint)

# Plain box helper for things LDraw has no part for (glass infill, shadow
# proxies). Kept deliberately rare.
static func box(parent: Node3D, size: Vector3, center: Vector3, tint: Variant) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	node.mesh = shape
	node.position = center
	node.material_override = material(tint)
	parent.add_child(node)
	return node
