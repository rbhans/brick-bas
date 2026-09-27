class_name PlanMarks
extends Node3D

# Visual feedback for build tools: tinted highlights on placed pieces (hover,
# selection, pending demolition, paint), grid cursors, live dimensions, area
# boxes and placement footprints. Kept separate so tools stay declarative.

const TINTS := {
	"hover": Color(1.0, 1.0, 1.0, 0.22),
	"select": Color(1.0, 0.84, 0.28, 0.42),
	"delete": Color(1.0, 0.2, 0.14, 0.6),
	"paint": Color(0.55, 0.85, 1.0, 0.45),
	"flash": Color(1.0, 1.0, 1.0, 0.65),
}
const PRIORITY := ["delete", "paint", "flash", "select", "hover"]

var game: Node
var temp: Dictionary = {}      # id -> kind (tool marks, cleared freely)
var hover_id := ""
var selected_id := ""
var flashes: Dictionary = {}   # id -> remaining seconds
var _applied: Dictionary = {}  # id -> kind currently shown
var vertex_cursor: MeshInstance3D
var cell_cursor: MeshInstance3D
var measure: Label3D
var measure_line: MeshInstance3D
var area: MeshInstance3D
var footprint: MeshInstance3D
var _unshaded: Dictionary = {}

func setup(owner: Node) -> void:
	game = owner
	name = "Plan marks"
	vertex_cursor = _mesh(_cylinder(0.32, 0.12), "ffd23f")
	cell_cursor = _mesh(_frame(PlanGrid.TILE, 0.12), "ffd23f")
	area = _mesh(BoxMesh.new(), Color(1.0, 0.3, 0.2, 0.18))
	footprint = _mesh(BoxMesh.new(), Color(0.3, 0.9, 0.55, 0.3))
	measure_line = _mesh(BoxMesh.new(), "ffd23f")
	measure = Label3D.new()
	measure.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	measure.font_size = 42
	measure.outline_size = 10
	measure.modulate = Color("ffe27a")
	measure.outline_modulate = Color(0.08, 0.1, 0.12, 0.9)
	measure.no_depth_test = true
	measure.fixed_size = true
	measure.pixel_size = 0.0009
	measure.visible = false
	add_child(measure)

func _material(tint: Variant) -> StandardMaterial3D:
	var colour := Bricks.color(tint)
	var key := colour.to_html()
	if not _unshaded.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colour
		if colour.a < 0.99:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = colour.a < 0.99
		material.render_priority = 2
		_unshaded[key] = material
	return _unshaded[key]

func _mesh(mesh: Mesh, tint: Variant) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(tint)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return node

static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	return mesh

static func _frame(size: float, thickness: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	var inner := half - thickness
	var rings := [[Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)], [Vector3(-inner, 0, -inner), Vector3(inner, 0, -inner), Vector3(inner, 0, inner), Vector3(-inner, 0, inner)]]
	for index in range(4):
		var next := (index + 1) % 4
		for point in [rings[0][index], rings[0][next], rings[1][next], rings[0][index], rings[1][next], rings[1][index]]:
			tool.add_vertex(point)
	return tool.commit()

# --- Highlights ------------------------------------------------------------

func set_hover(id: String) -> void:
	if id == hover_id:
		return
	var previous := hover_id
	hover_id = id
	_refresh(previous)
	_refresh(id)

func set_selected(id: String) -> void:
	var previous := selected_id
	selected_id = id
	_refresh(previous)
	_refresh(id)

func mark(ids: Array, kind: String) -> void:
	for id in ids:
		temp[String(id)] = kind
		_refresh(String(id))

func clear() -> void:
	var ids := temp.keys()
	temp.clear()
	for id in ids:
		_refresh(String(id))
	vertex_cursor.visible = false
	cell_cursor.visible = false

func flash(ids: Array) -> void:
	for id in ids:
		flashes[String(id)] = 0.45
		_refresh(String(id))

func reapply() -> void:
	# After a rebuild every batch instance is fresh; re-tint what should be.
	_applied.clear()
	var ids := {hover_id: true, selected_id: true}
	for id in temp: ids[id] = true
	for id in flashes: ids[id] = true
	for id in ids:
		if not String(id).is_empty(): _refresh(String(id))

func process(delta: float) -> void:
	for id in flashes.keys():
		flashes[id] = float(flashes[id]) - delta
		if float(flashes[id]) <= 0.0:
			flashes.erase(id)
			_refresh(String(id))
		else:
			var strength := clampf(float(flashes[id]) / 0.45, 0.0, 1.0)
			var tint: Color = TINTS.flash
			game.tint_object(String(id), Color(tint.r, tint.g, tint.b, tint.a * strength))

func _kind(id: String) -> String:
	var kinds := []
	if temp.has(id): kinds.append(String(temp[id]))
	if flashes.has(id): kinds.append("flash")
	if id == selected_id: kinds.append("select")
	if id == hover_id: kinds.append("hover")
	for candidate in PRIORITY:
		if candidate in kinds:
			return candidate
	return ""

func _refresh(id: String) -> void:
	if id.is_empty():
		return
	var kind := _kind(id)
	if String(_applied.get(id, "")) == kind and kind != "flash":
		return
	_applied[id] = kind
	game.tint_object(id, TINTS.get(kind, Color(0, 0, 0, 0)))

# --- Cursors and guides ------------------------------------------------------

func show_vertex(vertex: Vector2i, danger: bool) -> void:
	vertex_cursor.visible = true
	vertex_cursor.position = PlanGrid.vertex_position(vertex) + Vector3(0, PlanGrid.FLOOR_TOP + 0.08, 0)
	vertex_cursor.material_override = _material("ef5a48" if danger else "ffd23f")

func show_cell(cell: Vector2i, danger: bool) -> void:
	cell_cursor.visible = true
	cell_cursor.position = PlanGrid.cell_center(cell) + Vector3(0, PlanGrid.FLOOR_TOP + 0.05, 0)
	cell_cursor.material_override = _material("ef5a48" if danger else "ffd23f")

func show_measure(a: Vector3, b: Vector3, c: Vector3 = Vector3.INF) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		hide_measure()
		return
	measure.visible = true
	var label := Units.length(length)
	if c != Vector3.INF:
		label = Units.size(a.distance_to(b), b.distance_to(c))
	measure.text = label
	measure.position = (a + (c if c != Vector3.INF else b)) * 0.5 + Vector3(0, PlanGrid.WALL_HEIGHT + 1.2, 0)

func hide_measure() -> void:
	measure.visible = false
	measure_line.visible = false

func show_area(rect: Rect2) -> void:
	area.visible = true
	(area.mesh as BoxMesh).size = Vector3(maxf(rect.size.x, 0.05), 0.08, maxf(rect.size.y, 0.05))
	area.position = Vector3(rect.get_center().x, PlanGrid.FLOOR_TOP + 0.05, rect.get_center().y)

func hide_area() -> void:
	area.visible = false

func show_footprint(transform: Transform3D, studs: Vector2i, valid: bool, wall: bool) -> void:
	footprint.visible = not wall
	(footprint.mesh as BoxMesh).size = Vector3(studs.x * PlanGrid.STUD, 0.04, studs.y * PlanGrid.STUD)
	footprint.transform = Transform3D(transform.basis, Vector3(transform.origin.x, transform.origin.y + 0.03, transform.origin.z))
	footprint.material_override = _material(Color(0.3, 0.9, 0.55, 0.32) if valid else Color(0.95, 0.3, 0.22, 0.4))

func hide_guides() -> void:
	vertex_cursor.visible = false
	cell_cursor.visible = false
	footprint.visible = false
	hide_measure()
	hide_area()
