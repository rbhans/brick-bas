class_name EquipmentModels
extends RefCounted

# Brick-built HVAC equipment from official LDraw parts at native scale, styled
# after real units: a sectional air handler (Trane/Daikin-style casing with
# hinged access doors), a single-duct VAV terminal, a 4-way ceiling diffuser,
# sheet-metal tee/cross fittings and a smart thermostat.
#
# Frames: every builder works from its local origin = BOTTOM centre of its
# footprint (y = 0 on the surface it stands on / its underside when ceiling
# hung), airflow along +X (air enters at -X). Exceptions: the diffuser origin
# is the centre of its face (ceiling plane, the body rises above it) and the
# thermostat origin is its wall-contact centre (face toward +Z).
#
# Every builder returns
#   animated:  [{kind: "rotation", role, node, axis}                (fan wheel)
#               {kind: "damper", role, node, axis, closed, open}    (blades, radians)
#               {kind: "fill", role, node: MeshInstance3D (coil_fill shader), row, rows}]
#              Animated nodes rest at identity: set node.basis = Basis(axis, angle).
#              Fill: material_override.set_shader_parameter("fill_level", 0..1).
#   doors:     [{node, axis, open_angle, section, role}]  hinge pivots (dynamic);
#              node.basis = Basis(axis, open_angle * t) swings the door out.
#   covers:    [Node3D]  removable panels (dynamic): hide them for the cutaway.
#              AHU covers are the roof AND the access doors (doors are also
#              listed under "doors" so Explore can swing them individually).
#   sections:  [{role, index, center, component_id}]
#   screen:    Node3D anchor (its +Z faces the viewer) or null
#   label_anchor: Vector3, collision: [{size, center}]
#
# Paint: each sub-tree root carries meta "paint_role" (housing, damper,
# filter, cooling_coil, heating_coil, fan, sensor). Pieces that must keep their
# own colour (copper pipes, black latches, glass, the orange actuator...) carry
# meta "paint_fixed" = true so a recolour walk can skip them; coil fin meshes
# use the coil_fill ShaderMaterial and carry meta "paint_shader_param" =
# "active_color" (recolour them through that uniform). Options:
#   {"open": bool (doors swung open + covers hidden), "preview": bool (no
#    hanger rods), "paint": {role: colour}, "component_id": String}

const Ducts := preload("res://scripts/build/duct_geometry.gd")
const COIL_SHADER := preload("res://scripts/build/coil_fill.gdshader")

const STUD := 0.5
const PLATE := 0.2
const BRICK := 0.6
const ROLES := ["damper", "filter", "cooling_coil", "heating_coil", "fan"]
const DEFAULT_COLORS := {
	"housing": "#aeb4b5",
	"vav": "#c3c7c5",
	"duct": "#8d949c",
	"base": "dark_bluish_gray",
	"damper": "#d78b2c",
	"filter": "#d3b04e",
	"cooling_coil": "#318cc7",
	"heating_coil": "#c5573f",
	"fan": "#343b40",
	"sensor": "#f0eee4",
	"diffuser": "white",
}
const FIN_IDLE := Color("#8f989d")

# --- Air handler dimensions ----------------------------------------------------
# A bay is 4 studs along X: a 1-stud door post + a 3-stud access door. The
# casing adds one closing post, so it is 4n + 1 studs long, 4 studs deep and
# 2.8 m tall (base rail 0.2, walls to 2.6, roof tiles to 2.8). 1.0 m square
# collars (1 stud long) sit on both end faces, centred at y = 1.3, z = 0.
const AHU_BAY := 2.0
const AHU_DEPTH := 2.0
const AHU_HEIGHT := 2.8
const AHU_PORT_Y := 1.3
const COLLAR := 0.5

# --- VAV --------------------------------------------------------------------
# 6 x 4 stud box, 1.4 m tall, round inlet at -X, rectangular discharge at +X
# (collars 1 stud long each, so the footprint is 8 x 6 studs including the
# control side). Both port centres sit VAV_PORT_Y above the origin (the
# underside): hang the box with its origin 3.9 m up and ducts meet at 4.6 m.
const VAV_HALF := 1.5
const VAV_HEIGHT := 1.4
const VAV_PORT_Y := 0.7

# --- Diffuser ---------------------------------------------------------------
# 4 x 4 stud face on the ceiling plane (y = 0) with a 2 x 2 boot rising to
# 1.8 m; its side inlet collar (on -X, ending at x = -1.0) is centred
# DIFFUSER_PORT_Y above the face: hang the face at 3.6 m and ducts meet 4.6 m.
const DIFFUSER_PORT_Y := 1.0
const DIFFUSER_HEIGHT := 1.8

# --- Fittings ---------------------------------------------------------------
# Tee/cross bodies are 1.0 m cubes (bottom on y = 0) with collars reaching
# 1.0 m from the centre; duct centre line at FITTING_PORT_Y.
const FITTING_PORT_Y := 0.5
const FITTING_REACH := 1.0

# --- Public API -------------------------------------------------------------

static func port_names(kind: String) -> Array[String]:
	match kind:
		"ahu", "vav":
			return ["inlet", "outlet"]
		"tee":
			return ["inlet", "outlet_a", "outlet_b"]
		"cross":
			return ["inlet", "outlet", "branch_a", "branch_b"]
		"diffuser":
			return ["inlet"]
	return []

static func section_count(properties: Dictionary) -> int:
	return maxi(1, (properties.get("layout", []) as Array).size())

static func ahu_casing_length(count: int) -> float:
	return AHU_BAY * count + STUD

static func footprint(kind: String, properties: Dictionary = {}) -> Vector2i:
	match kind:
		"ahu":
			return Vector2i(4 * section_count(properties) + 3, 6)
		"vav":
			return Vector2i(8, 6)
		"diffuser":
			return Vector2i(4, 4)
		"tee", "cross":
			return Vector2i(4, 4)
		"tstat", "thermostat":
			return Vector2i(1, 1)
	if kind in ROLES or kind == "sensor":
		return Vector2i(5, 4)
	return Vector2i(2, 2)

static func size(kind: String, properties: Dictionary = {}) -> Vector3:
	var studs := footprint(kind, properties)
	match kind:
		"ahu":
			return Vector3(studs.x * STUD, AHU_HEIGHT, studs.y * STUD)
		"vav":
			return Vector3(studs.x * STUD, VAV_HEIGHT, studs.y * STUD)
		"diffuser":
			return Vector3(studs.x * STUD, DIFFUSER_HEIGHT, studs.y * STUD)
		"tee", "cross":
			return Vector3(2.0, 1.1, 2.0)
		"tstat", "thermostat":
			return Vector3(0.5, 0.5, 0.6)
	return Vector3(studs.x * STUD, AHU_HEIGHT, studs.y * STUD)

# {"face": centre of the duct-connection face (local), "normal": unit, outward}.
# Ducts butt directly onto the face: the collar is part of the equipment.
static func port_local(kind: String, properties: Dictionary, port_name: String) -> Dictionary:
	if port_name not in port_names(kind):
		return {}
	var face := Vector3.ZERO
	var normal := Vector3.ZERO
	match kind:
		"ahu":
			var sign := -1.0 if port_name == "inlet" else 1.0
			face = Vector3(sign * (ahu_casing_length(section_count(properties)) * 0.5 + COLLAR), AHU_PORT_Y, 0)
			normal = Vector3(sign, 0, 0)
		"vav":
			var sign := -1.0 if port_name == "inlet" else 1.0
			face = Vector3(sign * (VAV_HALF + COLLAR), VAV_PORT_Y, 0)
			normal = Vector3(sign, 0, 0)
		"diffuser":
			face = Vector3(-1.0, DIFFUSER_PORT_Y, 0)
			normal = Vector3(-1, 0, 0)
		"tee":
			normal = {"inlet": Vector3(0, 0, -1), "outlet_a": Vector3(-1, 0, 0), "outlet_b": Vector3(1, 0, 0)}[port_name]
			face = normal * FITTING_REACH + Vector3(0, FITTING_PORT_Y, 0)
		"cross":
			normal = {"inlet": Vector3(-1, 0, 0), "outlet": Vector3(1, 0, 0), "branch_a": Vector3(0, 0, -1), "branch_b": Vector3(0, 0, 1)}[port_name]
			face = normal * FITTING_REACH + Vector3(0, FITTING_PORT_Y, 0)
	return {"face": face, "normal": normal}

# --- Shared helpers -----------------------------------------------------------

static func _result() -> Dictionary:
	return {"animated": [], "doors": [], "covers": [], "sections": [], "screen": null, "label_anchor": Vector3.ZERO, "collision": []}

static func _palette(options: Dictionary) -> Dictionary:
	var colors := {}
	for key in DEFAULT_COLORS:
		colors[key] = Bricks.color(DEFAULT_COLORS[key])
	var paint: Dictionary = options.get("paint", {})
	for key in paint:
		colors[String(key)] = Bricks.color(paint[key])
	return colors

static func _group(parent: Node3D, node_name: String, role: String, position: Vector3 = Vector3.ZERO, dynamic: bool = false) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	node.set_meta("paint_role", role)
	if dynamic:
		node.set_meta("dynamic", true)
	parent.add_child(node)
	return node

static func _put(parent: Node3D, part: String, bottom: Vector3, tint: Variant, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	return Bricks.spawn(parent, part, Bricks.bottom_transform(part, bottom, basis), tint)

static func _at(parent: Node3D, part: String, bottom: Vector3, tint: Variant, yaw: float = 0.0) -> MeshInstance3D:
	return Bricks.spawn(parent, part, Bricks.bottom_transform(part, bottom, Basis(Vector3.UP, yaw)), tint)

static func _mid(parent: Node3D, part: String, center: Vector3, tint: Variant, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
	return Bricks.spawn(parent, part, Bricks.centered_transform(part, center, basis), tint)

static func _fixed(node: MeshInstance3D) -> MeshInstance3D:
	node.set_meta("paint_fixed", true)
	return node

# Top face toward Basis(UP, yaw) * +Z, length along the rotated X.
static func _face(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)

# As _face but with the part's length running vertically.
static func _face_tall(yaw: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * 0.5)

# A round part's axis (+Y) turned along +X / -X / +Z.
const AXIS_X := Basis(Vector3(0, 0, 1), -PI * 0.5)
const AXIS_NEG_X := Basis(Vector3(0, 0, 1), PI * 0.5)
const AXIS_Z := Basis(Vector3(1, 0, 0), PI * 0.5)

static func _fill_material(role: String, colors: Dictionary, mesh: Mesh) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = COIL_SHADER
	material.set_shader_parameter("active_color", (colors[role] as Color).lightened(0.12))
	material.set_shader_parameter("idle_color", FIN_IDLE)
	material.set_shader_parameter("fill_level", 0.0)
	material.set_shader_parameter("minimum_x", mesh.get_aabb().position.x)
	material.set_shader_parameter("width_x", mesh.get_aabb().size.x)
	return material

static func _screen_anchor(parent: Node3D, position: Vector3, yaw: float) -> Node3D:
	var screen := Node3D.new()
	screen.name = "Screen anchor"
	screen.position = position
	screen.basis = Basis(Vector3.UP, yaw)
	parent.add_child(screen)
	return screen

# --- Air handling unit ----------------------------------------------------------

static func _layout(config: Dictionary) -> Array[String]:
	var layout: Array[String] = []
	for role in config.get("layout", []):
		layout.append(String(role))
	return layout

static func build_ahu(parent: Node3D, config: Dictionary, options: Dictionary = {}) -> Dictionary:
	var out := _result()
	var colors := _palette(options)
	var layout := _layout(config)
	var count := maxi(1, layout.size())
	var records: Array = config.get("component_records", [])
	var length := ahu_casing_length(count)
	var half := length * 0.5
	var housing := _group(parent, "AHU casing", "housing")
	var shell: Color = colors.housing
	var trim: Color = shell.darkened(0.14)
	var base: Color = colors.base
	var roof := _group(parent, "AHU roof panels", "housing", Vector3.ZERO, true)
	out.covers.append(roof)
	# Base rail / floor, back wall and roof, bay by bay.
	for index in range(count):
		var x := _bay_x(index, half)
		for offset in [-0.75, 0.25]:
			_at(housing, "3020", Vector3(x + offset, 0, 0), base, PI * 0.5)
			_at(roof, "87079", Vector3(x + offset, AHU_HEIGHT - PLATE, 0), shell, PI * 0.5)
		for course in range(4):
			_at(housing, "3010", Vector3(x - 0.25, PLATE + course * BRICK, -0.75), shell)
		# Darker frame (sill, header, posts) around a recessed door.
		_at(housing, "3623", Vector3(x, PLATE, 0.75), trim)
		_at(housing, "3623", Vector3(x, 2.4, 0.75), trim)
		if index > 0:
			for course in range(4):
				_at(housing, "3005", Vector3(x - 1.0, PLATE + course * BRICK, 0.75), trim)
		# Continuous piano hinge on the door's left edge.
		_fixed(_at(housing, "87994", Vector3(x - 0.74, 0.65, 0.93), trim.darkened(0.25)))
	_at(housing, "3710", Vector3(half - 0.25, 0, 0), base, PI * 0.5)
	_at(roof, "2431", Vector3(half - 0.25, AHU_HEIGHT - PLATE, 0), shell, PI * 0.5)
	for course in range(4):
		_at(housing, "3005", Vector3(half - 0.25, PLATE + course * BRICK, -0.75), shell)
	# End walls with the 1.0 m duct openings (z -0.5..0.5, y 0.8..1.8).
	for side in [-1.0, 1.0]:
		var x: float = side * (half - 0.25)
		_at(housing, "3622", Vector3(x, PLATE, 0.25), shell, PI * 0.5)
		for course in [1, 2]:
			_at(housing, "3005", Vector3(x, PLATE + course * BRICK, 0.75), trim)
		_at(housing, "3023b", Vector3(x, 1.8, 0), shell, PI * 0.5)
		_at(housing, "3622", Vector3(x, 2.0, 0.25), shell, PI * 0.5)
		Ducts.collar(housing, Vector3(side * half, AHU_PORT_Y, 0), Vector3(side * (half + COLLAR), AHU_PORT_Y, 0), colors.duct)
	# Unit controller on the intake end post, facing the -X end.
	var controller := _group(parent, "Unit controller", "housing")
	_fixed(_at(controller, "3005", Vector3(-half - 0.25, 1.95, 0.75), "dark_bluish_gray"))
	_fixed(_put(controller, "3070b", Vector3(-half - 0.25, 2.25, 1.0), "trans_light_blue", _face(0)))
	out.screen = _screen_anchor(controller, Vector3(-half - 0.25, 2.25, 1.21), 0.0)
	# Sections, their access doors and the per-role outside features.
	for index in range(count):
		var role := layout[index] if index < layout.size() else ""
		var x := _bay_x(index, half)
		var component_id := ""
		if index < records.size():
			component_id = String((records[index] as Dictionary).get("id", ""))
		if role in ROLES:
			var component := _group(parent, "Section %d %s" % [index + 1, role], role, Vector3(x, 0, 0))
			component.set_meta("section_index", index)
			component.set_meta("component_id", component_id)
			_section(component, role, colors, out, index == 0 and role == "damper")
		out.sections.append({"role": role, "index": index, "center": Vector3(x, 1.4, 0), "component_id": component_id})
		var door := _ahu_door(parent, x, role, colors)
		door.set_meta("section_index", index)
		out.doors.append({"node": door, "axis": Vector3.UP, "open_angle": -1.9, "section": index, "role": role})
		out.covers.append(door)
		if bool(options.get("open", false)):
			door.basis = Basis(Vector3.UP, -1.9)
	if bool(config.get("sensor_enabled", false)):
		var sensor := _group(parent, "Discharge air sensor", "sensor", Vector3(half + 0.25, AHU_PORT_Y + 0.5, 0))
		_sensor_probe(sensor, colors)
	if bool(options.get("open", false)):
		roof.visible = false
	out.label_anchor = Vector3(0, AHU_HEIGHT + 0.9, 0)
	out.collision.append({"size": Vector3(length, AHU_HEIGHT, AHU_DEPTH), "center": Vector3(0, AHU_HEIGHT * 0.5, 0)})
	for side in [-1.0, 1.0]:
		out.collision.append({"size": Vector3(COLLAR, 1.0, 1.0), "center": Vector3(side * (half + COLLAR * 0.5), AHU_PORT_Y, 0)})
	return out

# Centre of bay `index` (its door centre).
static func _bay_x(index: int, half: float) -> float:
	return -half + 1.25 + index * AHU_BAY

# Hinged access door: two 2 x 3 tiles recessed 0.05 behind the frame, two
# flush cam latches and a small colour-coded section tag.
static func _ahu_door(parent: Node3D, bay_x: float, role: String, colors: Dictionary) -> Node3D:
	var hinge := _group(parent, "Access door", "housing", Vector3(bay_x - 0.75, 0, 0.85), true)
	for row in range(2):
		_put(hinge, "26603", Vector3(0.75, 0.9 + row * 1.0, -0.1), colors.housing, _face(0))
	for y in [0.95, 1.85]:
		_fixed(_put(hinge, "98138", Vector3(1.28, y, 0.1), "dark_bluish_gray", _face(0)))
	if role in ROLES:
		var tag := _put(hinge, "3070b", Vector3(0.3, 2.1, 0.1), colors[role], _face(0))
		tag.set_meta("paint_role", role)
	return hinge

# One AHU section's internals in bay-local coordinates: interior x -0.75..0.75,
# z -0.5..0.8, y 0.2..2.6; its door post is the column at x = -1.0 whose
# front face is z = 1.0 (outside features mount there).
static func _section(node: Node3D, role: String, colors: Dictionary, out: Dictionary, intake: bool) -> void:
	match role:
		"damper":
			_damper_section(node, colors, out, intake)
		"filter":
			_filter_section(node, colors)
		"cooling_coil", "heating_coil":
			_coil_section(node, role, colors, out)
		"fan":
			_fan_section(node, colors, out)

static func _damper_section(node: Node3D, colors: Dictionary, out: Dictionary, intake: bool) -> void:
	var metal := "flat_silver"
	# Frame: channels top and bottom, jamb bars either side.
	_fixed(_at(node, "3023b", Vector3(-0.5, PLATE, 0), metal, PI * 0.5))
	_fixed(_at(node, "3023b", Vector3(-0.5, 2.2, 0), metal, PI * 0.5))
	# (The back jamb stands clear of the casing's back wall at z = -0.5.)
	for z in [-0.4, 0.6]:
		_fixed(_at(node, "87994", Vector3(-0.5, 0.55, z), metal))
	# Opposed blades: neighbours turn in opposite directions.
	for index in range(4):
		var pivot := _group(node, "Damper blade %d" % (index + 1), "damper", Vector3(-0.5, 0.7 + index * 0.4, 0), true)
		_mid(pivot, "3069b", Vector3.ZERO, colors.damper, _face(-PI * 0.5))
		out.animated.append({"kind": "damper", "role": "damper", "node": pivot, "axis": Vector3(0, 0, 1 if index % 2 == 0 else -1), "closed": 0.0, "open": PI * 0.46})
	# Linkage bar and the orange actuator on the door post.
	_fixed(_at(node, "87994", Vector3(-0.15, 0.55, 0.6), "dark_bluish_gray"))
	_fixed(_at(node, "3005", Vector3(-1.0, 1.6, 1.25), "orange"))
	_fixed(_put(node, "98138", Vector3(-1.0, 1.9, 1.5), "dark_bluish_gray", _face(0)))
	if intake:
		# Outdoor-air louvre above the return-air collar on the intake end.
		_fixed(_put(node, "2412b", Vector3(-1.25, 2.3, -0.5), "flat_silver", _face(-PI * 0.5)))

static func _filter_section(node: Node3D, colors: Dictionary) -> void:
	# Pleated V-bank: two angled walls of grille bricks meeting downstream.
	for wall in [[-0.15, -0.25, -0.559], [-0.15, 0.25, 0.559]]:
		for course in range(4):
			_at(node, "2877", Vector3(wall[0], PLATE + course * BRICK, wall[1]), colors.filter, wall[2])
	_fixed(_at(node, "30374", Vector3(0.3, 0.4, 0), "flat_silver"))
	# Differential-pressure gauge on the door post.
	_fixed(_put(node, "6141", Vector3(-1.0, 1.7, 1.0), "black", _face(0)))
	_fixed(_put(node, "98138", Vector3(-1.0, 1.7, 1.2), "white", _face(0)))

static func _coil_section(node: Node3D, role: String, colors: Dictionary, out: Dictionary) -> void:
	var metal := "flat_silver"
	# Finned coil across the airflow at the downstream side of the bay, on a
	# drain pan, with a blank-off above: its upstream face shows from the
	# iso camera once the roof is off.
	var x := 0.35
	_fixed(_at(node, "3023b", Vector3(x, PLATE, 0), metal, PI * 0.5))
	var fill := _group(node, "Coil fins", role, Vector3.ZERO, true)
	for row in range(3):
		var brick := _at(fill, "2877", Vector3(x, 0.4 + row * BRICK, 0), FIN_IDLE, PI * 0.5)
		brick.material_override = _fill_material(role, colors, brick.mesh)
		brick.set_meta("paint_shader_param", "active_color")
		out.animated.append({"kind": "fill", "role": role, "node": brick, "row": row, "rows": 3})
	for level in range(2):
		_fixed(_at(node, "3023b", Vector3(x, 2.2 + level * PLATE, 0), metal, PI * 0.5))
	# Copper headers on the coil's front edge, runs along the floor to the
	# door post and stubs out through it; control valve on the supply.
	for pipe in [[0.2, 0.9], [0.5, 1.5]]:
		_fixed(_at(node, "87994", Vector3(pipe[0], 0.6, 0.62), "copper"))
		_fixed(_mid(node, "87994", Vector3(pipe[0] - 0.7, pipe[1], 0.62), "copper", Basis(Vector3(0, 0, 1), PI * 0.5)))
		_fixed(_mid(node, "87994", Vector3(-1.0, pipe[1], 1.0 + (0.12 if pipe[1] > 1.0 else 0.0)), "copper", AXIS_Z))
	var valve := _at(node, "4599b", Vector3(-1.0, 1.6, 1.5), colors[role])
	valve.set_meta("paint_role", role)
	if role == "cooling_coil":
		_fixed(_mid(node, "87994", Vector3(x, 0.3, 0.9), "dark_bluish_gray", AXIS_Z))

static func _fan_section(node: Node3D, colors: Dictionary, out: Dictionary) -> void:
	# Plenum fan: a bulkhead with a bell-mouth inlet cone, the wheel right
	# behind it on a direct-drive motor sitting on an isolation base.
	for row in range(2):
		_fixed(_put(node, "26603", Vector3(-0.65, 0.8 + row * 1.0, 0.15), "flat_silver", _face(-PI * 0.5)))
	_fixed(_put(node, "3623", Vector3(-0.65, 2.3, 0.15), "flat_silver", _face(-PI * 0.5)))
	_fixed(_mid(node, "4740", Vector3(-0.85, AHU_PORT_Y, 0.15), "flat_silver", AXIS_NEG_X))
	var rotor := _group(node, "Fan wheel", "fan", Vector3(-0.05, AHU_PORT_Y, 0.15), true)
	_mid(rotor, "92947", Vector3(-0.1, 0, 0), colors.fan, AXIS_X)
	_mid(rotor, "4032a", Vector3(0.3, 0, 0), colors.fan, AXIS_X)
	out.animated.append({"kind": "rotation", "role": "fan", "node": rotor, "axis": Vector3(1, 0, 0)})
	_fixed(_mid(node, "3941", Vector3(0.55, AHU_PORT_Y, 0.15), "medium_blue", AXIS_X))
	# Motor base: clear of the door sill in front and the back wall behind.
	_fixed(_at(node, "3004", Vector3(0.5, PLATE, 0.0), "dark_bluish_gray", PI * 0.5))
	_fixed(_at(node, "3023b", Vector3(0.5, 0.8, 0.0), "black", PI * 0.5))
	# Variable-frequency drive on the door post.
	for level in range(2):
		_fixed(_at(node, "3005", Vector3(-1.0, 1.1 + level * BRICK, 1.25), "dark_bluish_gray"))
	_fixed(_put(node, "3070b", Vector3(-1.0, 2.0, 1.5), "trans_light_blue", _face(0)))
	_fixed(_put(node, "3070b", Vector3(-1.0, 1.45, 1.5), "black", _face(0)))

static func _sensor_probe(node: Node3D, colors: Dictionary) -> void:
	_fixed(_at(node, "3024", Vector3.ZERO, "dark_bluish_gray"))
	_at(node, "3005", Vector3(0, PLATE, 0), colors.sensor)
	_fixed(_at(node, "3070b", Vector3(0, 0.8, 0), "trans_green"))

# One AHU section on its own (workbench tray / thumbnails): a bay's base, its
# door post and the section internals with their outside features.
static func build_component(parent: Node3D, role: String, options: Dictionary = {}) -> Dictionary:
	var out := _result()
	var colors := _palette(options)
	var housing := _group(parent, "Component base", "housing")
	if role == "sensor":
		var sensor := _group(parent, "Sensor", "sensor")
		_fixed(_at(housing, "3023b", Vector3.ZERO, colors.base))
		_sensor_probe(_group(sensor, "Probe", "sensor", Vector3(0, PLATE, 0)), colors)
		_fixed(_mid(sensor, "87994", Vector3(0.45, 0.3, 0), "flat_silver", AXIS_X))
		out.sections.append({"role": role, "index": 0, "center": Vector3(0, 0.6, 0), "component_id": String(options.get("component_id", ""))})
		out.label_anchor = Vector3(0, 1.8, 0)
		out.collision.append({"size": Vector3(1.0, 1.2, 0.5), "center": Vector3(0, 0.6, 0)})
		return out
	for offset in [-0.75, 0.25]:
		_at(housing, "3020", Vector3(offset, 0, 0), colors.base, PI * 0.5)
	for course in range(4):
		_at(housing, "3005", Vector3(-1.0, PLATE + course * BRICK, 0.75), colors.housing)
	if role in ROLES:
		var component := _group(parent, role.capitalize(), role)
		component.set_meta("component_id", String(options.get("component_id", "")))
		_section(component, role, colors, out, false)
	out.sections.append({"role": role, "index": 0, "center": Vector3(0, 1.4, 0), "component_id": String(options.get("component_id", ""))})
	out.label_anchor = Vector3(0, AHU_HEIGHT + 0.6, 0)
	out.collision.append({"size": Vector3(2.0, 2.6, 2.0), "center": Vector3(-0.25, 1.3, 0)})
	return out

# --- VAV terminal -----------------------------------------------------------

static func build_vav(parent: Node3D, config: Dictionary, options: Dictionary = {}) -> Dictionary:
	var out := _result()
	var colors := _palette(options)
	var layout := _layout(config)
	var records: Array = config.get("component_records", [])
	var shell: Color = colors.vav
	var housing := _group(parent, "VAV casing", "housing")
	var lid := _group(parent, "VAV access lid", "housing", Vector3.ZERO, true)
	out.covers.append(lid)
	# Sheet-metal box: smooth tile underside, double-skinned side walls,
	# end strips beside the collars, removable tile lid.
	var down := Basis(Vector3.RIGHT, PI)
	for z in [-0.5, 0.5]:
		_put(housing, "69729", Vector3(0, PLATE, z), shell, down)
		_at(lid, "69729", Vector3(0, VAV_HEIGHT - PLATE, z), shell)
	for side in [-1.0, 1.0]:
		_put(housing, "69729", Vector3(0, VAV_PORT_Y, side * 0.8), shell, _face(0.0 if side > 0 else PI))
		_put(housing, "69729", Vector3(0, VAV_PORT_Y, side * 0.8), shell, _face(PI if side > 0 else 0.0))
		for z in [-0.74, 0.74]:
			_put(housing, "3069b", Vector3(side * (VAV_HALF - 0.21), VAV_PORT_Y, z), shell, _face_tall(side * PI * 0.5))
	# Round inlet spigot with its flow cross (pitot tubes pierce the wall).
	_mid(housing, "3941", Vector3(-VAV_HALF - 0.15, VAV_PORT_Y, 0), colors.duct, AXIS_X)
	for basis in [AXIS_Z, Basis.IDENTITY]:
		_fixed(_mid(housing, "87994", Vector3(-VAV_HALF - 0.3, VAV_PORT_Y, 0), "dark_bluish_gray", basis))
	# Rectangular discharge collar.
	Ducts.collar(housing, Vector3(VAV_HALF, VAV_PORT_Y, 0), Vector3(VAV_HALF + COLLAR, VAV_PORT_Y, 0), colors.duct)
	# Butterfly damper just downstream of the inlet, driven by the actuator.
	var damper_index := layout.find("damper")
	var damper := _group(parent, "VAV damper", "damper")
	damper.set_meta("component_id", String((records[damper_index] as Dictionary).get("id", "")) if damper_index >= 0 and damper_index < records.size() else "")
	var pivot := _group(damper, "Damper blade", "damper", Vector3(-1.0, VAV_PORT_Y, 0), true)
	_mid(pivot, "14769", Vector3.ZERO, colors.damper, _face(-PI * 0.5))
	out.animated.append({"kind": "damper", "role": "damper", "node": pivot, "axis": Vector3(0, 0, 1), "closed": 0.0, "open": PI * 0.45})
	_fixed(_mid(damper, "87994", Vector3(-1.0, VAV_PORT_Y, 0.4), "flat_silver", AXIS_Z))
	_fixed(_at(damper, "3005", Vector3(-1.0, 0.4, 1.25), "orange"))
	_fixed(_put(damper, "98138", Vector3(-1.0, 0.7, 1.5), "dark_bluish_gray", _face(0)))
	out.sections.append({"role": "damper", "index": maxi(damper_index, 0), "center": Vector3(-1.0, VAV_PORT_Y, 0), "component_id": damper.get_meta("component_id")})
	# DDC controller enclosure with its display.
	var controller := _group(parent, "VAV controller", "housing")
	_fixed(_at(controller, "3004", Vector3(0.0, 0.3, 1.25), "dark_bluish_gray"))
	_fixed(_at(controller, "3023b", Vector3(0.0, 0.9, 1.25), "dark_bluish_gray"))
	_fixed(_put(controller, "3070b", Vector3(-0.25, 0.65, 1.5), "trans_light_blue", _face(0)))
	_fixed(_put(controller, "3070b", Vector3(0.25, 0.65, 1.5), "black", _face(0)))
	out.screen = _screen_anchor(controller, Vector3(-0.25, 0.65, 1.71), 0.0)
	# Optional hot-water reheat (or cooling) coil at the discharge.
	var coil_role := "heating_coil" if "heating_coil" in layout else ("cooling_coil" if "cooling_coil" in layout else "")
	if not coil_role.is_empty():
		var coil_index := layout.find(coil_role)
		var coil := _group(parent, "VAV %s" % coil_role, coil_role)
		coil.set_meta("component_id", String((records[coil_index] as Dictionary).get("id", "")) if coil_index < records.size() else "")
		var fins := _group(coil, "Coil fins", coil_role, Vector3.ZERO, true)
		for row in range(2):
			var tile := _put(fins, "2412b", Vector3(1.25, 0.45 + row * 0.5, 0), FIN_IDLE, _face(-PI * 0.5))
			tile.material_override = _fill_material(coil_role, colors, tile.mesh)
			tile.set_meta("paint_shader_param", "active_color")
			out.animated.append({"kind": "fill", "role": coil_role, "node": tile, "row": row, "rows": 2})
		for y in [0.45, 0.95]:
			_fixed(_mid(coil, "87994", Vector3(1.05, y, 0.85), "copper", AXIS_Z))
		var valve := _at(coil, "4599b", Vector3(1.05, 1.05, 1.35), colors[coil_role])
		valve.set_meta("paint_role", coil_role)
		out.sections.append({"role": coil_role, "index": coil_index, "center": Vector3(1.15, VAV_PORT_Y, 0), "component_id": coil.get_meta("component_id")})
	if bool(config.get("sensor_enabled", false)):
		var sensor := _group(parent, "Discharge air sensor", "sensor", Vector3(VAV_HALF + 0.25, VAV_PORT_Y + 0.5, 0))
		_at(sensor, "6141", Vector3.ZERO, colors.sensor)
		_fixed(_at(sensor, "98138", Vector3(0, PLATE, 0), "trans_green"))
	if bool(options.get("hangers", false)):
		# Threaded hanger rods up to the structure above.
		var rods := _group(parent, "Hanger rods", "housing")
		for x in [-1.25, 1.25]:
			for z in [-1.1, 1.1]:
				_fixed(_at(rods, "30374", Vector3(x, 0.4, z), "dark_bluish_gray"))
				_fixed(_at(rods, "6141", Vector3(x, 0.2, z), "dark_bluish_gray"))
	if bool(options.get("open", false)):
		lid.visible = false
	out.label_anchor = Vector3(0, VAV_HEIGHT + 1.2, 0)
	out.collision.append({"size": Vector3(VAV_HALF * 2.0, VAV_HEIGHT, 2.0), "center": Vector3(0, VAV_HEIGHT * 0.5, 0)})
	for side in [-1.0, 1.0]:
		out.collision.append({"size": Vector3(COLLAR, 1.0, 1.0), "center": Vector3(side * (VAV_HALF + COLLAR * 0.5), VAV_PORT_Y, 0)})
	return out

# --- Ceiling diffuser -------------------------------------------------------

static func build_diffuser(parent: Node3D, options: Dictionary = {}) -> Dictionary:
	var out := _result()
	var colors := _palette(options)
	var face_color: Color = colors.diffuser
	var metal: Color = colors.duct
	var face := _group(parent, "Diffuser face", "housing")
	# 4-way louvred face (seen from below): a recessed centre plaque ringed by
	# grille tiles whose slots run concentric to it, on a white frame plate.
	var down := Basis(Vector3.RIGHT, PI)
	_put(face, "3068b", Vector3(0, 0.25, 0), face_color, down)
	for x in [-0.5, 0.5]:
		for z in [-0.75, 0.75]:
			_put(face, "2412b", Vector3(x, PLATE, z), face_color, down)
	for x in [-0.75, 0.75]:
		_put(face, "2412b", Vector3(x, PLATE, 0), face_color, Basis(Vector3.UP, PI * 0.5) * down)
	for z in [-0.5, 0.5]:
		_at(face, "3020", Vector3(0, PLATE, z), face_color)
	# Compact sheet-metal boot on top with the side inlet collar.
	var plenum := _group(parent, "Diffuser boot", "housing")
	for level in range(2):
		_at(plenum, "3003", Vector3(0, 0.4 + level * BRICK, 0), metal)
	Ducts.collar(plenum, Vector3(-0.5, DIFFUSER_PORT_Y, 0), Vector3(-1.0, DIFFUSER_PORT_Y, 0), metal)
	var lid := _group(parent, "Diffuser boot lid", "housing", Vector3.ZERO, true)
	_at(lid, "3068b", Vector3(0, 1.6, 0), metal)
	out.covers.append(lid)
	if bool(options.get("open", false)):
		lid.visible = false
	out.label_anchor = Vector3(0, DIFFUSER_HEIGHT + 0.6, 0)
	out.collision.append({"size": Vector3(2.0, 0.4, 2.0), "center": Vector3(0, 0.2, 0)})
	out.collision.append({"size": Vector3(1.0, 1.4, 1.0), "center": Vector3(0, 1.1, 0)})
	out.collision.append({"size": Vector3(COLLAR, 1.0, 1.0), "center": Vector3(-0.5 - COLLAR * 0.5, DIFFUSER_PORT_Y, 0)})
	return out

# --- Duct fittings ------------------------------------------------------------

static func _fitting(parent: Node3D, arms: Array, options: Dictionary, kind: String) -> Dictionary:
	var out := _result()
	var colors := _palette(options)
	var body := _group(parent, "Duct %s" % kind, "housing")
	var lid := Ducts.fitting(body, arms, colors.duct, FITTING_REACH)
	out.covers.append(lid)
	if bool(options.get("open", false)):
		lid.visible = false
	out.label_anchor = Vector3(0, 1.8, 0)
	out.collision.append({"size": Vector3(1.0, 1.0, 1.0), "center": Vector3(0, FITTING_PORT_Y, 0)})
	for arm in arms:
		var direction: Vector3 = arm
		var along := Vector3(absf(direction.x), 0, absf(direction.z))
		out.collision.append({"size": Vector3.ONE - along * 0.5, "center": direction * 0.75 + Vector3(0, FITTING_PORT_Y, 0)})
	return out

# Supply tee: inlet on -Z, outlets on -X and +X, capped on +Z.
static func build_tee(parent: Node3D, options: Dictionary = {}) -> Dictionary:
	return _fitting(parent, [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(1, 0, 0)], options, "tee")

# Trunk cross: trunk through along X (inlet -X, outlet +X), branches on -Z/+Z.
static func build_cross(parent: Node3D, options: Dictionary = {}) -> Dictionary:
	return _fitting(parent, [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)], options, "cross")

# --- Thermostat -------------------------------------------------------------

# Round smart thermostat: a brushed ring with a black glass face, centred on
# the origin (wall contact), face toward +Z.
static func build_thermostat(parent: Node3D, options: Dictionary = {}) -> Dictionary:
	var out := _result()
	var colors := _palette(options)
	var body := _group(parent, "Thermostat", "housing")
	_put(body, "3024", Vector3(0, 0, 0), colors.get("thermostat", Bricks.color("white")), _face(0))
	_put(body, "6141", Vector3(0, 0, 0.2), "flat_silver", _face(0))
	_fixed(_put(body, "98138", Vector3(0, 0, 0.4), "black", _face(0)))
	out.screen = _screen_anchor(body, Vector3(0, 0, 0.61), 0.0)
	out.label_anchor = Vector3(0, 0.7, 0.3)
	out.collision.append({"size": Vector3(0.5, 0.5, 0.6), "center": Vector3(0, 0, 0.3)})
	return out
