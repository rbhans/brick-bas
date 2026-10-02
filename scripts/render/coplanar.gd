extends RefCounted

# Keeps pieces from sharing a face plane. Two pieces whose same-facing faces
# lie in one plane and overlap z-fight: the renderer can't tell which is in
# front, and the winner changes as the camera moves. Where that happens the
# smaller piece is moved back a couple of millimetres behind the larger one's
# face. Moved pieces are checked again, so a stack of flush pieces ends up at
# distinct depths. Too small to see; plenty for the depth buffer.
#
# Faces are bucketed by plane, so only faces that share a plane are compared;
# each face is judged by its bounding rectangle in that plane (a false match
# only costs an invisible nudge).

const STEP := 0.0025        # metres a face is moved back
const TOLERANCE := 0.002    # faces closer than this count as one plane
const MIN_OVERLAP := 0.008  # metres of shared face (each way) worth fixing
const MIN_FACE_AREA := 0.0004
const ROUNDS := 6

# Per mesh file: its flat faces, [normal, a point on it, corners (local AABB of the face)].
static var _faces: Dictionary = {}
# Results by content: the same model in its own frame always settles the same
# way, so rebuilding a building only pays for models it hasn't seen.
static var _results: Dictionary = {}
const MAX_RESULTS := 4000

# LDraw parts in one frame (a model's pieces). Pieces from `movable` on are
# neighbours that take part but never move. Returns fixes for the movable ones.
static func resolve(parts: Array, transforms: Array, movable: int = -1) -> Array[Transform3D]:
	var meshes: Array = []
	for part in parts: meshes.append(Bricks.mesh(String(part)))
	var fixes := _resolve(meshes, transforms, [], parts.size() if movable < 0 else movable)
	fixes.resize(parts.size() if movable < 0 else movable)
	return fixes

# Settles every static mesh under `root` together, judged in root's own frame
# (so a turned unit settles like any other), moving the nodes themselves.
# Procedural meshes count, and a material drawn from both sides makes its
# faces count facing both ways.
# `neighbours` ([Mesh, world Transform3D] pairs) take part but never move:
# other units and the architecture around this one.
static func settle(root: Node3D, neighbours: Array = []) -> void:
	var nodes: Array[MeshInstance3D] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null and (node as Node3D).is_visible_in_tree():
			nodes.append(node)
	var frame := root.global_transform.affine_inverse()
	var meshes: Array = []
	var transforms: Array = []
	var both: Array = []
	for node in nodes:
		meshes.append(node.mesh)
		transforms.append(frame * node.global_transform)
		both.append(_double_sided(node))
	for entry in neighbours:
		meshes.append(entry[0])
		transforms.append(frame * (entry[1] as Transform3D))
		both.append(entry.size() > 2 and bool(entry[2]))
	var fixes := _resolve(meshes, transforms, both, nodes.size())
	for index in range(nodes.size()):
		if fixes[index] != Transform3D.IDENTITY:
			nodes[index].transform = nodes[index].transform * fixes[index]

static func _double_sided(node: MeshInstance3D) -> bool:
	var material := node.get_active_material(0)
	return material is BaseMaterial3D and ((material as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED or (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)

# Returns, per piece, a transform to apply in its own space (`transform * fix`);
# identity where nothing changed.
static func _resolve(meshes: Array, transforms: Array, both: Array, movable: int) -> Array[Transform3D]:
	var count := meshes.size()
	var fixes: Array[Transform3D] = []
	fixes.resize(count)
	fixes.fill(Transform3D.IDENTITY)
	if count < 2:
		return fixes
	var identity: Array = []
	for mesh in meshes:
		# A file mesh is known by its path; a procedural one by its shape.
		var known: Mesh = mesh
		identity.append(known.resource_path if known.resource_path != "" else str(known.get_aabb()) + "|" + str(known.get_faces().size()))
	var content := hash([identity, transforms, both, movable])
	if _results.has(content):
		return (_results[content] as Array[Transform3D]).duplicate()
	var volume := PackedFloat32Array()
	volume.resize(count)
	var faces: Array = [] # [piece, normal, distance, rect]
	var by_piece: Array = []
	by_piece.resize(count)
	for index in range(count):
		var mesh: Mesh = meshes[index]
		var transform: Transform3D = transforms[index]
		var local := mesh.get_aabb()
		volume[index] = local.size.x * local.size.y * local.size.z * absf(transform.basis.determinant())
		var mine: Array = []
		for face in _placed_faces(mesh, transform, index < both.size() and bool(both[index])):
			mine.append(faces.size())
			faces.append([index, face[0], face[1], face[2]])
		by_piece[index] = mine
	var shift: Array[Vector3] = []
	shift.resize(count)
	shift.fill(Vector3.ZERO)
	var buckets := {}
	for f in range(faces.size()):
		_bucket(buckets, faces, f)
	var dirty := {}
	for key in buckets: dirty[key] = true
	for round_index in range(ROUNDS):
		var pushes := {} # piece -> Array of wanted moves
		for key in dirty:
			var members: Array = buckets.get(key, [])
			var neighbour: Array = buckets.get(Vector4i(key.x, key.y, key.z, key.w + 1), [])
			var candidates: Array = members + neighbour
			for i in range(members.size()):
				var a: Array = faces[members[i]]
				for j in range(i + 1, candidates.size()):
					var b: Array = faces[candidates[j]]
					var pa: int = a[0]
					var pb: int = b[0]
					if pa == pb or (a[1] as Vector3).dot(b[1]) < 0.999: continue
					if absf(float(a[2]) - float(b[2])) >= TOLERANCE: continue
					var shared := (a[3] as Rect2).intersection(b[3] as Rect2)
					if shared.size.x < MIN_OVERLAP or shared.size.y < MIN_OVERLAP: continue
					# The smaller piece moves back behind the larger one's face;
					# neighbours (index >= movable) never move.
					if pa >= movable and pb >= movable: continue
					var mover := pb if volume[pb] < volume[pa] or (is_equal_approx(volume[pa], volume[pb]) and pb > pa) else pa
					if pa >= movable: mover = pb
					elif pb >= movable: mover = pa
					var face: Array = a if mover == pa else b
					var other: Array = b if mover == pa else a
					if not pushes.has(mover): pushes[mover] = []
					pushes[mover].append(-(face[1] as Vector3) * (absf(float(other[2]) - float(face[2])) + STEP))
		if pushes.is_empty():
			break
		dirty = {}
		for piece in pushes:
			# One move per line through the piece. Moving the whole piece along a
			# line separates every flush face across it, whichever way it goes;
			# when its faces want opposite ways, it goes the way of the largest
			# by enough to clear the rest too.
			var lines: Array = [] # [direction, distance, conflicted]
			for push in pushes[piece]:
				var direction := (push as Vector3).normalized()
				var length := (push as Vector3).length()
				var found := false
				for line in lines:
					var along := (line[0] as Vector3).dot(direction)
					if absf(along) < 0.9: continue
					found = true
					if along < 0.0: line[2] = true
					if length > float(line[1]):
						line[1] = length
						if along < 0.0: line[0] = direction
				if not found: lines.append([direction, length, false])
			var total := Vector3.ZERO
			for line in lines:
				total += (line[0] as Vector3) * (maxf(float(line[1]), STEP + TOLERANCE) if bool(line[2]) else float(line[1]))
			shift[piece] += total
			for f in by_piece[piece]:
				_unbucket(buckets, faces, f)
				var face: Array = faces[f]
				var normal: Vector3 = face[1]
				var axes := _plane_axes(normal)
				face[2] = float(face[2]) + normal.dot(total)
				face[3] = Rect2((face[3] as Rect2).position + Vector2(total.dot(axes[0]), total.dot(axes[1])), (face[3] as Rect2).size)
				var key := _bucket(buckets, faces, f)
				dirty[key] = true
				dirty[Vector4i(key.x, key.y, key.z, key.w - 1)] = true
	for index in range(count):
		if not shift[index].is_zero_approx():
			fixes[index] = Transform3D(Basis.IDENTITY, (transforms[index] as Transform3D).basis.inverse() * shift[index])
	if _results.size() >= MAX_RESULTS: _results.clear()
	_results[content] = fixes.duplicate()
	return fixes

static func _key(face: Array) -> Vector4i:
	var normal: Vector3 = face[1]
	# Plane bins are twice TOLERANCE wide and each is also compared with the
	# next, so faces within TOLERANCE always meet.
	return Vector4i(roundi(normal.x * 100), roundi(normal.y * 100), roundi(normal.z * 100), floori(float(face[2]) / (TOLERANCE * 2.0)))

static func _bucket(buckets: Dictionary, faces: Array, f: int) -> Vector4i:
	var key := _key(faces[f])
	if not buckets.has(key): buckets[key] = []
	buckets[key].append(f)
	return key

static func _unbucket(buckets: Dictionary, faces: Array, f: int) -> void:
	var key := _key(faces[f])
	if buckets.has(key): (buckets[key] as Array).erase(f)

# Two in-plane axes for a normal; the same normal always gives the same pair.
static func _plane_axes(normal: Vector3) -> Array:
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	return [u, normal.cross(u)]

# The mesh's flat faces placed in the frame: [normal, distance, rect in the
# plane]. A double-sided mesh's faces face both ways.
static func _placed_faces(mesh: Mesh, transform: Transform3D, double_sided: bool) -> Array:
	var result: Array = []
	var normals := transform.basis.inverse().transposed()
	for face in _mesh_faces(mesh):
		var normal: Vector3 = (normals * (face[0] as Vector3)).normalized()
		var corners: PackedVector3Array = transform * (face[2] as PackedVector3Array)
		var on_plane: Vector3 = transform * (face[1] as Vector3)
		for facing in ([normal, -normal] if double_sided else [normal]):
			var axes := _plane_axes(facing)
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			for corner in corners:
				var point := Vector2(corner.dot(axes[0]), corner.dot(axes[1]))
				low = low.min(point)
				high = high.max(point)
			result.append([facing, (facing as Vector3).dot(on_plane), Rect2(low, high - low)])
	return result

# A mesh's flat faces of some size, each with the corners of its bounding box
# (cached for meshes loaded from files).
static func _mesh_faces(mesh: Mesh) -> Array:
	var key := mesh.resource_path
	if key != "" and _faces.has(key):
		return _faces[key]
	var groups := {}
	var triangles := mesh.get_faces()
	for i in range(0, triangles.size(), 3):
		var a := triangles[i]
		var b := triangles[i + 1]
		var c := triangles[i + 2]
		var cross := (b - a).cross(c - a)
		var area := cross.length() * 0.5
		if area < 1e-7: continue
		var normal := -cross.normalized() # Godot's front faces wind clockwise
		var distance := normal.dot(a)
		var plane := Vector4i(roundi(normal.x * 500), roundi(normal.y * 500), roundi(normal.z * 500), roundi(distance / 0.0005))
		if not groups.has(plane): groups[plane] = [normal, AABB(a, Vector3.ZERO), 0.0, a]
		var group: Array = groups[plane]
		group[1] = (group[1] as AABB).expand(a).expand(b).expand(c)
		group[2] = float(group[2]) + area
	var result: Array = []
	for plane in groups:
		var group: Array = groups[plane]
		if float(group[2]) < MIN_FACE_AREA: continue
		var box: AABB = group[1]
		var corners := PackedVector3Array()
		for corner in 8:
			corners.append(box.get_endpoint(corner))
		result.append([group[0], group[3], corners])
	# Only meshes loaded from files (LDraw parts) are kept: a freed procedural
	# mesh's RID can come back as a different mesh.
	if key != "": _faces[key] = result
	return result
