extends SceneTree

# Z-fighting check over everything the renderer draws: every MeshInstance3D
# and every batched brick, any orientation, LDraw or procedural. Triangles are
# grouped into flat facets per mesh; facets from different pieces that face
# the same way in (nearly) the same plane and overlap by real area flicker
# (back to back counts too when a side is drawn double-sided). Pairs that
# would look identical either way are skipped. Lists what it finds and fails
# past small leftovers (slivers where pieces barely touch).
#   Godot --headless --path . --script res://tests/zfight.gd -- [studio|office|school] [--mode=0|1|2]

const PLANE_TOLERANCE := 0.0015  # metres: closer than this flickers at a distance
const MIN_FACET_AREA := 0.002    # m²: ignores curved surfaces' tiny planes
const MIN_OVERLAP := 0.0004      # m² (2 cm × 2 cm)
const CELL := 0.5
const MAX_PAIR := 0.06           # m²: no single pair bigger than this
const MAX_TOTAL := 0.6           # m²: nor this much in all, per starter

var _facets_by_mesh: Dictionary = {}

func _init() -> void:
	run.call_deferred()

# Flat facets of a mesh in its own space: [{normal, d, area, tris: PackedVector3Array}].
func facets(mesh: Mesh) -> Array:
	var key := mesh.get_rid()
	if _facets_by_mesh.has(key):
		return _facets_by_mesh[key]
	var groups := {}
	var faces := mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var cross := (b - a).cross(c - a)
		var area := cross.length() * 0.5
		if area < 1e-7: continue
		# Godot's front faces wind clockwise: the outward normal is (c - a) × (b - a).
		var normal := -cross.normalized()
		var d := normal.dot(a)
		var group_key := Vector4i(roundi(normal.x * 200), roundi(normal.y * 200), roundi(normal.z * 200), roundi(d * 2000))
		if not groups.has(group_key):
			groups[group_key] = {"normal": normal, "d": d, "area": 0.0, "tris": PackedVector3Array()}
		var group: Dictionary = groups[group_key]
		group.area += area
		group.tris.append_array([a, b, c])
	var result: Array = []
	for group_key in groups:
		if float(groups[group_key].area) >= MIN_FACET_AREA:
			result.append(groups[group_key])
	_facets_by_mesh[key] = result
	return result

func collect(game: Node) -> Array:
	var pieces: Array = []
	var handled := {}
	# Batched bricks come from the batch's own records: headless servers keep
	# no MultiMesh instance data to read back.
	var batches: Array = [game.arch.batch]
	for id in game.equipment.batches: batches.append(game.equipment.batches[id])
	if game.equipment.shared != null: batches.append(game.equipment.shared)
	for batch in batches:
		var hidden := {}
		var owner_of := {}
		for owner in batch.owners:
			for ref in batch.owners[owner]:
				owner_of[str(ref[0]) + "#" + str(ref[1])] = String(owner)
				if bool(batch._hidden.get(owner, false)): hidden[str(ref[0]) + "#" + str(ref[1])] = true
		for key in batch.instances:
			var node: MultiMeshInstance3D = batch.instances[key]
			handled[node] = true
			if not is_instance_valid(node) or not node.is_visible_in_tree() or node.multimesh.mesh == null: continue
			var both := _double_sided(node)
			var records: Array = batch.groups[key].records
			for index in range(records.size()):
				if hidden.has(str(key) + "#" + str(index)): continue
				var label := "%s[%s]" % [_owner(game, owner_of.get(str(key) + "#" + str(index), "")), String(batch.groups[key].part) + ("|glass" if bool(batch.groups[key].glass) else "")]
				pieces.append({"mesh": node.multimesh.mesh, "xf": node.global_transform * (records[index][0] as Transform3D), "name": label, "both": both, "look": "batch|" + (records[index][1] as Color).to_html(), "inset": 0.003 if bool(batch.groups[key].glass) else 0.0})
	for node in game.find_children("*", "MeshInstance3D", true, false):
		if handled.has(node) or not (node as Node3D).is_visible_in_tree() or (node as MeshInstance3D).mesh == null: continue
		if (node as GeometryInstance3D).transparency >= 0.99: continue
		var owner := ""
		var walk: Node = node
		while walk != null and owner.is_empty():
			owner = String(walk.get_meta("entity_id", ""))
			walk = walk.get_parent()
		var part := String(node.get_meta("ldraw_part_id", node.name))
		pieces.append({"mesh": (node as MeshInstance3D).mesh, "xf": (node as Node3D).global_transform, "name": "%s[%s]" % [_owner(game, owner) if not owner.is_empty() else _name(node).get_slice("/", 0), part], "both": _double_sided(node), "look": _look(node), "inset": _inset(node)})
	return pieces

# Glass pulls its surfaces in (brick_glass.gdshader, Bricks.material's grow).
func _inset(node: MeshInstance3D) -> float:
	var material := node.get_active_material(0)
	if material is BaseMaterial3D and (material as BaseMaterial3D).grow: return -(material as BaseMaterial3D).grow_amount
	return 0.0

# What a surface looks like: two faces with the same look fight invisibly.
func _look(node: MeshInstance3D) -> String:
	var material := node.get_active_material(0)
	if material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		return "std|%s|%.2f|%.2f|%.2f" % [standard.albedo_color.to_html(), standard.roughness, standard.metallic, standard.metallic_specular]
	return str(material.get_rid()) if material != null else "none"

func _owner(game: Node, id: String) -> String:
	var item: Dictionary = game.model.find_object(id)
	if item.is_empty(): return "?" if id.is_empty() else id
	var extra := String(item.properties.get("item", item.properties.get("style", "")))
	return String(item.kind) + (":" + extra if not extra.is_empty() else "")

func _name(node: Node) -> String:
	var path := String(node.get_path())
	var parts := path.split("/")
	return "/".join(parts.slice(maxi(0, parts.size() - 3)))

# Materials drawn from both sides make back-to-back coplanar faces fight too.
func _double_sided(node: GeometryInstance3D) -> bool:
	var materials: Array = [node.material_override]
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		for surface in range((node as MeshInstance3D).mesh.get_surface_count()):
			materials.append((node as MeshInstance3D).get_active_material(surface))
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh.mesh != null:
		var mesh := (node as MultiMeshInstance3D).multimesh.mesh
		for surface in range(mesh.get_surface_count()): materials.append(mesh.surface_get_material(surface))
	for material in materials:
		if material is BaseMaterial3D and (material as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED: return true
		if material is ShaderMaterial and (material as ShaderMaterial).shader != null and (material as ShaderMaterial).shader.code.contains("cull_disabled"): return true
	return false

func scan(pieces: Array) -> Array:
	# World facets bucketed by plane.
	var buckets := {}
	for index in range(pieces.size()):
		var piece: Dictionary = pieces[index]
		var xf: Transform3D = piece.xf
		var normal_basis := xf.basis.inverse().transposed()
		for facet in facets(piece.mesh):
			var normal: Vector3 = (normal_basis * (facet.normal as Vector3)).normalized()
			var tris: PackedVector3Array = xf * (facet.tris as PackedVector3Array)
			var d := normal.dot(tris[0])
			var flip := normal.x < -0.5 or (absf(normal.x) <= 0.5 and (normal.y < -0.5 or (absf(normal.y) <= 0.5 and normal.z < 0.0)))
			var canonical := -normal if flip else normal
			var nkey := Vector3i(roundi(canonical.x * 100), roundi(canonical.y * 100), roundi(canonical.z * 100))
			var dkey := roundi((-d if flip else d) / PLANE_TOLERANCE)
			var key := [nkey, dkey]
			if not buckets.has(key): buckets[key] = []
			buckets[key].append({"piece": index, "normal": normal, "d": d, "plane": -d if flip else d, "tris": tris, "both": bool(piece.both), "inset": float(piece.get("inset", 0.0))})
	var found := {}
	for key in buckets:
		var list: Array = buckets[key]
		# Neighbouring plane bins too, so a pair straddling a bin edge is still seen.
		var neighbour: Array = buckets.get([key[0], key[1] + 1], [])
		if list.size() + neighbour.size() < 2: continue
		_pairs(list + neighbour, list.size(), pieces, found)
	var rows: Array = []
	for pair in found:
		rows.append(found[pair])
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.area) > float(b.area))
	return rows

func _pairs(list: Array, own: int, pieces: Array, found: Dictionary) -> void:
	var normal: Vector3 = list[0].normal
	var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := normal.cross(u)
	var flat: Array = [] # per facet: Array of [PackedVector2Array tri, Rect2]
	var grid := {}
	for f in range(list.size()):
		var tris: PackedVector3Array = list[f].tris
		var shapes: Array = []
		for t in range(0, tris.size(), 3):
			var polygon := PackedVector2Array([Vector2(tris[t].dot(u), tris[t].dot(v)), Vector2(tris[t + 1].dot(u), tris[t + 1].dot(v)), Vector2(tris[t + 2].dot(u), tris[t + 2].dot(v))])
			var rect := Rect2(polygon[0], Vector2.ZERO).expand(polygon[1]).expand(polygon[2])
			shapes.append([polygon, rect])
			for cx in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
				for cy in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
					var cell := Vector2i(cx, cy)
					if not grid.has(cell): grid[cell] = {}
					grid[cell][f] = true
		flat.append(shapes)
	var tested := {}
	for cell in grid:
		var members: Array = grid[cell].keys()
		for i in range(members.size()):
			for j in range(i + 1, members.size()):
				var a: int = mini(members[i], members[j])
				var b: int = maxi(members[i], members[j])
				if a >= own and b >= own: continue # both in the neighbour bin: handled there
				var pa: int = list[a].piece
				var pb: int = list[b].piece
				if pa == pb: continue
				var facing := (list[a].normal as Vector3).dot(list[b].normal)
				if absf(facing) < 0.995: continue
				# Inset glass: separated from anything not inset alike, and from
				# whatever it touches back to back.
				var inset_a := float(list[a].inset)
				var inset_b := float(list[b].inset)
				if absf(inset_a - inset_b) >= PLANE_TOLERANCE: continue
				if facing < 0.0 and inset_a + inset_b >= PLANE_TOLERANCE: continue
				# Back to back only fights when a side is drawn double-sided.
				if facing < 0.0 and not (bool(list[a].both) or bool(list[b].both)): continue
				if absf(float(list[a].plane) - float(list[b].plane)) > PLANE_TOLERANCE: continue
				var pair_key := Vector2i(a, b)
				if tested.has(pair_key): continue
				tested[pair_key] = true
				var area := _overlap(flat[a], flat[b])
				if area < MIN_OVERLAP: continue
				var piece_key := Vector2i(mini(pa, pb), maxi(pa, pb))
				if String(pieces[pa].look) == String(pieces[pb].look): continue # identical surfaces: invisible
				var centre: Vector3 = (list[a].tris as PackedVector3Array)[0]
				var row: Dictionary = found.get(piece_key, {"a": pieces[piece_key.x].name, "b": pieces[piece_key.y].name, "area": 0.0, "at": centre, "normal": normal, "gap": absf(float(list[a].plane) - float(list[b].plane)), "back": facing < 0.0})
				row.area = float(row.area) + area
				found[piece_key] = row

func _overlap(a: Array, b: Array) -> float:
	var total := 0.0
	for sa in a:
		for sb in b:
			if not (sa[1] as Rect2).grow(-1e-4).intersects((sb[1] as Rect2).grow(-1e-4)): continue
			for polygon in Geometry2D.intersect_polygons(sa[0], sb[0]):
				total += absf(_area(polygon))
	return total

static func _area(polygon: PackedVector2Array) -> float:
	var sum := 0.0
	for i in range(polygon.size()):
		sum += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return sum * 0.5

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var templates: Array = []
	var view_mode := 1
	for arg in args:
		if arg.begins_with("--mode="): view_mode = int(arg.trim_prefix("--mode="))
		elif not arg.begins_with("--"): templates.append(arg)
	if templates.is_empty(): templates = ["studio", "office", "school"]
	var failures: Array[String] = []
	var game: Node = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	for template in templates:
		game.start_new_game(String(template), false)
		game.set_mode(view_mode)
		for i in range(3): await process_frame
		var started := Time.get_ticks_msec()
		var pieces := collect(game)
		var rows := scan(pieces)
		print("ZFIGHT %s: %d pieces, %d overlapping pairs (%d ms)" % [template, pieces.size(), rows.size(), Time.get_ticks_msec() - started])
		var summary := {}
		for row in rows:
			var kind := "%s  ~  %s" % [_kind(String(row.a)), _kind(String(row.b))]
			if not summary.has(kind): summary[kind] = [0, 0.0, row]
			summary[kind][0] += 1
			summary[kind][1] += float(row.area)
		var largest := 0.0
		var total := 0.0
		for row in rows:
			largest = maxf(largest, float(row.area))
			total += float(row.area)
		if largest > MAX_PAIR or total > MAX_TOTAL:
			failures.append("%s: largest %.3f m², total %.3f m²" % [template, largest, total])
		for kind in summary:
			var example: Dictionary = summary[kind][2]
			print("  %3d × %-70s %.3f m²  at %s n=%s gap=%.4f%s" % [summary[kind][0], kind, summary[kind][1], (example.at as Vector3).snapped(Vector3.ONE * 0.01), (example.normal as Vector3).snapped(Vector3.ONE * 0.01), float(example.gap), " back-to-back" if bool(example.back) else ""])
	print("ZFIGHT ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures)
	quit(0 if failures.is_empty() else 1)

# A stable label for grouping: the node path without instance numbers or unit ids.
func _kind(name: String) -> String:
	return RegEx.create_from_string("@[A-Za-z0-9]+@[0-9]+").sub(name, "mesh", true)
