class_name DuctGeometry
extends RefCounted

const OUTER := 0.5
const INNER := 0.3
const PLATE := preload("res://assets/third_party/ldraw/meshes/3022.obj")
# Smooth 2 x 2 tiles read as galvanized sheet metal; they are the removable lid.
const LID := preload("res://assets/third_party/ldraw/meshes/3068b.obj")
# Transverse flanged joints (TDC-style) every JOINT_SPACING metres.
const JOINT_SPACING := 2

# Local axis is +X. Four walls leave both ends and the inner air passage open.
# The upper wall is removable; arbitrary endpoints define the orientation.
static func frame(start: Vector3, finish: Vector3) -> Transform3D:
	var axis := (finish - start).normalized()
	var reference := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var side := axis.cross(reference).normalized()
	var up := side.cross(axis).normalized()
	return Transform3D(Basis(axis, up, side), (start + finish) * 0.5)

static func valid_segment(start: Vector3, finish: Vector3) -> bool:
	return start.is_finite() and finish.is_finite() and start.distance_to(finish) >= 0.25

static func path_shell(parent: Node3D, points: Array[Vector3], color: Color, start_connected: bool = false, end_connected: bool = false) -> Node3D:
	var cover := Node3D.new()
	cover.name = "Duct cutaway cover"
	parent.add_child(cover)
	if points.size() < 2:
		return cover
	var outer := path_rings(points, OUTER)
	var inner := path_rings(points, INNER)
	var plate_intervals: Array = []
	for segment in range(points.size() - 1):
		var length := points[segment].distance_to(points[segment + 1])
		var axis := (points[segment + 1] - points[segment]).normalized()
		# The transported frame matches the miter shell, including vertical runs.
		var side: Vector3 = (outer[segment][1] - outer[segment][0]).normalized()
		var up := side.cross(axis).normalized()
		var basis := Basis(axis, up, axis.cross(up).normalized())
		var first := 0.6 if segment > 0 else 0.0
		var last := length - (0.6 if segment < points.size() - 2 else 0.0)
		var intervals: Array[Vector2] = []
		for index in range(maxi(0, int(floor(last - first)))):
			var start := first + index
			intervals.append(Vector2(start / length, (start + 1.0) / length))
			var plate := MeshInstance3D.new()
			plate.name = "LDraw 3068b removable lid"
			plate.mesh = LID
			plate.transform = Transform3D(basis, points[segment] + axis * (start + 0.5) + up * (INNER - LID.get_aabb().position.y))
			plate.material_override = plastic(color)
			plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plate.set_meta("ldraw_part_id", "3068b")
			plate.set_meta("paint_role", "housing")
			cover.add_child(plate)
			if absf(axis.y) > 0.7:
				# Upright duct modules have an opposing studded access plate too.
				# It replaces the wall rather than being pushed through a slab.
				var opposite := plate.duplicate() as MeshInstance3D
				opposite.transform = Transform3D(Basis(axis, -up, -basis.z), points[segment] + axis * (start + 0.5) - up * (INNER - LID.get_aabb().position.y))
				parent.add_child(opposite)
		plate_intervals.append(intervals)
		# Flanged transverse joints on lid seams every JOINT_SPACING metres: a
		# slim collar standing proud of the sheet; the top bar leaves with the
		# cutaway lid.
		for index in range(1, int(floor(length))):
			if index % JOINT_SPACING != 0:
				continue
			var joint := first + float(index)
			if joint > last - 0.2:
				continue
			var anchor := points[segment] + axis * joint
			var rim := color.darkened(0.1)
			for sign in [-1.0, 1.0]:
				var side_joint := box(parent, Vector3(0.07, OUTER * 2.0 + 0.1, 0.05), Vector3.ZERO, rim)
				side_joint.transform = Transform3D(basis, anchor + basis.z * sign * (OUTER + 0.025))
				side_joint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var cap_joint := box(cover if sign > 0 else parent, Vector3(0.07, 0.05, OUTER * 2.0), Vector3.ZERO, rim)
				cap_joint.transform = Transform3D(basis, anchor + up * sign * (OUTER + 0.025))
				cap_joint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for face in range(4):
		var next := (face + 1) % 4
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_smooth_group(-1)
		for segment in range(points.size() - 1):
			var spans: Array[Vector2] = [Vector2(0, 1)]
			if face == 2 or (face == 0 and absf((points[segment + 1] - points[segment]).normalized().y) > 0.7):
				spans.clear()
				var previous := 0.0
				for interval in plate_intervals[segment]:
					if interval.x > previous:
						spans.append(Vector2(previous, interval.x))
					previous = interval.y
				if previous < 1.0:
					spans.append(Vector2(previous, 1.0))
			for span in spans:
				quad(surface, outer[segment][face].lerp(outer[segment + 1][face], span.x), outer[segment][face].lerp(outer[segment + 1][face], span.y), outer[segment][next].lerp(outer[segment + 1][next], span.y), outer[segment][next].lerp(outer[segment + 1][next], span.x))
				quad(surface, inner[segment][next].lerp(inner[segment + 1][next], span.x), inner[segment][next].lerp(inner[segment + 1][next], span.y), inner[segment][face].lerp(inner[segment + 1][face], span.y), inner[segment][face].lerp(inner[segment + 1][face], span.x))
		for end in [0, points.size() - 1]:
			# The mating socket already owns this annular face. Two coplanar
			# caps here produce the flickering triangles at equipment joints.
			if (end == 0 and start_connected) or (end > 0 and end_connected):
				continue
			if face == 2:
				var intervals: Array = plate_intervals[0 if end == 0 else -1]
				if not intervals.is_empty() and ((end == 0 and is_zero_approx(intervals[0].x)) or (end > 0 and is_equal_approx(intervals[-1].y, 1.0))):
					continue
			quad(surface, inner[end][face], outer[end][face], outer[end][next], inner[end][next])
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = surface.commit()
		mesh.material_override = plastic(color)
		mesh.set_meta("paint_role", "housing")
		(cover if face == 2 else parent).add_child(mesh)
	return cover

static func plastic(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	# Satin galvanized finish: a little metal and sheen, still readable as
	# painted plastic next to the bricks.
	material.roughness = 0.58
	material.metallic = 0.1
	material.metallic_specular = 0.35
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Thin cutaway rims otherwise self-shadow into a checker pattern. Keep
	# their directional lighting and cast shadows, but no received shadow acne.
	material.disable_receive_shadows = true
	return material

# Custom hollow plastic adapter, not represented as an official LDraw part.
static func socket(parent: Node3D, start: Vector3, finish: Vector3, start_outer: float, end_outer: float, start_inner: float, end_inner: float, color: Color) -> void:
	var basis := frame(start, finish).basis
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var rings: Array = []
	for spec in [[start, start_outer], [finish, end_outer], [start, start_inner], [finish, end_inner]]:
		var ring: Array[Vector3] = []
		for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
			ring.append(spec[0] + (basis.y * corner.x + basis.z * corner.y) * float(spec[1]))
		rings.append(ring)
	for face in range(4):
		var next := (face + 1) % 4
		quad(surface, rings[0][face], rings[1][face], rings[1][next], rings[0][next])
		quad(surface, rings[2][next], rings[3][next], rings[3][face], rings[2][face])
		# The equipment end frame owns the mating face at the small end.
		quad(surface, rings[1][face], rings[3][face], rings[3][next], rings[1][next])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Hollow plastic socket"
	mesh.mesh = surface.commit()
	mesh.material_override = plastic(color)
	mesh.set_meta("paint_role", "housing")
	parent.add_child(mesh)

static func path_rings(points: Array[Vector3], radius: float) -> Array:
	var rings: Array = []
	var previous_axis := (points[1] - points[0]).normalized()
	var basis := frame(points[0], points[1]).basis
	for index in range(points.size()):
		var incoming := previous_axis if index == 0 else (points[index] - points[index - 1]).normalized()
		var outgoing := incoming if index == points.size() - 1 else (points[index + 1] - points[index]).normalized()
		if index > 1:
			basis = Basis(Quaternion(previous_axis, incoming)) * basis
		var plane_normal := (incoming + outgoing).normalized()
		if plane_normal.is_zero_approx():
			plane_normal = incoming
		var denominator := maxf(0.25, plane_normal.dot(incoming))
		var ring: Array[Vector3] = []
		for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
			var offset: Vector3 = (basis.y * corner.x + basis.z * corner.y) * radius
			offset -= incoming * (plane_normal.dot(offset) / denominator)
			ring.append(points[index] + offset)
		rings.append(ring)
		previous_axis = incoming
	return rings

static func quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		surface.add_vertex(point)

static func shell(parent: Node3D, length: float, color: Color) -> Node3D:
	var points: Array[Vector3] = [Vector3(-length * 0.5, 0, 0), Vector3(length * 0.5, 0, 0)]
	return path_shell(parent, points, color)

static func box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	material.metallic_specular = 0.12
	node.material_override = material
	node.set_meta("paint_role", "housing")
	parent.add_child(node)
	return node

# --- Fittings and collars (added for EquipmentModels) -------------------------

const LID_TILE := preload("res://assets/third_party/ldraw/meshes/3068b.obj")
const COLLAR_TILE := preload("res://assets/third_party/ldraw/meshes/3069b.obj")

# Solid axis-aligned box appended to a SurfaceTool (six outward quads).
static func add_box(surface: SurfaceTool, low: Vector3, high: Vector3) -> void:
	var c := [
		Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z), Vector3(high.x, high.y, low.z), Vector3(low.x, high.y, low.z),
		Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z),
	]
	quad(surface, c[0], c[3], c[2], c[1])
	quad(surface, c[4], c[5], c[6], c[7])
	quad(surface, c[0], c[1], c[5], c[4])
	quad(surface, c[3], c[7], c[6], c[2])
	quad(surface, c[0], c[4], c[7], c[3])
	quad(surface, c[1], c[2], c[6], c[5])

static func mesh_node(parent: Node3D, surface: SurfaceTool, color: Color, node_name: String) -> MeshInstance3D:
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = surface.commit()
	node.material_override = plastic(color)
	node.set_meta("paint_role", "housing")
	parent.add_child(node)
	return node

# Thin square flange ring (outer half 0.56) at the open end of a collar.
static func flange(parent: Node3D, face: Vector3, normal: Vector3, color: Color, depth: float = 0.07) -> MeshInstance3D:
	var basis := frame(face - normal, face).basis
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var rim := OUTER + 0.07
	# Four bars in the collar's local frame (x along the normal).
	for bar in [[Vector2(-rim, OUTER), Vector2(rim, rim)], [Vector2(-rim, -rim), Vector2(rim, -OUTER)], [Vector2(-rim, -OUTER), Vector2(-OUTER, OUTER)], [Vector2(OUTER, -OUTER), Vector2(rim, OUTER)]]:
		var low := Vector3(-depth, bar[0].x, bar[0].y)
		var high := Vector3(0.0, bar[1].x, bar[1].y)
		var corners: Array[Vector3] = []
		for corner in [Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z), Vector3(high.x, high.y, low.z), Vector3(low.x, high.y, low.z), Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z)]:
			corners.append(face + basis * corner)
		quad(surface, corners[0], corners[3], corners[2], corners[1])
		quad(surface, corners[4], corners[5], corners[6], corners[7])
		quad(surface, corners[0], corners[1], corners[5], corners[4])
		quad(surface, corners[3], corners[7], corners[6], corners[2])
		quad(surface, corners[0], corners[4], corners[7], corners[3])
		quad(surface, corners[1], corners[2], corners[6], corners[5])
	return mesh_node(parent, surface, color, "Collar flange")

# Square 1.0 m duct collar from an equipment face out to the port face, with a
# flange at the mating end. Ducts butt onto `port_face` (their start cap is
# omitted when start_connected, so nothing is coplanar).
static func collar(parent: Node3D, equipment_face: Vector3, port_face: Vector3, color: Color) -> void:
	socket(parent, equipment_face, port_face, OUTER, OUTER, INNER, INNER, color)
	flange(parent, port_face, (port_face - equipment_face).normalized(), color.darkened(0.08))

# Hollow sheet-metal junction (tee, cross) whose bottom sits on y = 0. The
# square body is 1.0 m (OUTER) with a 0.6 m bore; `arms` are unit horizontal
# directions that get open collars reaching `reach` from the centre, every
# other side is capped. The top is left open under LDraw lid plates (the same
# removable-lid language as straight runs), returned as the cover node.
static func fitting(parent: Node3D, arms: Array, color: Color, reach: float = 1.0) -> Node3D:
	var cover := Node3D.new()
	cover.name = "Fitting cutaway lid"
	cover.set_meta("paint_role", "housing")
	cover.set_meta("dynamic", true)
	parent.add_child(cover)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var wall := OUTER - INNER
	var top := OUTER * 2.0 - wall
	# Centre floor and the four corner posts.
	add_box(surface, Vector3(-OUTER, 0, -OUTER), Vector3(OUTER, wall, OUTER))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			add_box(surface, Vector3(minf(sx * INNER, sx * OUTER), wall, minf(sz * INNER, sz * OUTER)), Vector3(maxf(sx * INNER, sx * OUTER), top, maxf(sz * INNER, sz * OUTER)))
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		var open := false
		for arm in arms:
			if (arm as Vector3).is_equal_approx(direction):
				open = true
		var side := Vector3(direction.z, 0, -direction.x).abs()
		if not open:
			# Cap wall across this side of the bore.
			var a: Vector3 = direction * INNER - side * INNER + Vector3(0, wall, 0)
			var b: Vector3 = direction * OUTER + side * INNER + Vector3(0, top, 0)
			add_box(surface, Vector3(minf(a.x, b.x), a.y, minf(a.z, b.z)), Vector3(maxf(a.x, b.x), b.y, maxf(a.z, b.z)))
			continue
		# Three-sided collar channel (floor + two cheeks) out to `reach`.
		var floor_a: Vector3 = direction * OUTER - side * OUTER
		var floor_b: Vector3 = direction * reach + side * OUTER + Vector3(0, wall, 0)
		add_box(surface, Vector3(minf(floor_a.x, floor_b.x), 0, minf(floor_a.z, floor_b.z)), Vector3(maxf(floor_a.x, floor_b.x), wall, maxf(floor_a.z, floor_b.z)))
		for s in [-1.0, 1.0]:
			var cheek_a: Vector3 = direction * OUTER + side * s * INNER + Vector3(0, wall, 0)
			var cheek_b: Vector3 = direction * reach + side * s * OUTER + Vector3(0, top, 0)
			add_box(surface, Vector3(minf(cheek_a.x, cheek_b.x), cheek_a.y, minf(cheek_a.z, cheek_b.z)), Vector3(maxf(cheek_a.x, cheek_b.x), cheek_b.y, maxf(cheek_a.z, cheek_b.z)))
		# Collar lid: a smooth 1 x 2 tile across the channel.
		var lid := MeshInstance3D.new()
		lid.name = "LDraw 3069b collar lid"
		lid.mesh = COLLAR_TILE
		var yaw := 0.0 if absf(direction.x) > 0.5 else PI * 0.5
		var lid_center: Vector3 = direction * (OUTER + (reach - OUTER) * 0.5)
		lid.transform = Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), Vector3(lid_center.x, top - COLLAR_TILE.get_aabb().position.y, lid_center.z))
		lid.material_override = plastic(color)
		lid.set_meta("ldraw_part_id", "3069b")
		lid.set_meta("paint_role", "housing")
		cover.add_child(lid)
		flange(parent, direction * reach + Vector3(0, OUTER, 0), direction, color.darkened(0.08))
	mesh_node(parent, surface, color, "Fitting body")
	var plate := MeshInstance3D.new()
	plate.name = "LDraw 3068b fitting lid"
	plate.mesh = LID_TILE
	plate.position = Vector3(0, top - LID_TILE.get_aabb().position.y, 0)
	plate.material_override = plastic(color)
	plate.set_meta("ldraw_part_id", "3068b")
	plate.set_meta("paint_role", "housing")
	cover.add_child(plate)
	return cover
