extends SceneTree

# Z-fighting guard: builds every starter and scans all LDraw pieces (batched
# and loose) for pairs that share a same-facing face in one plane with real
# overlapping area. Those flicker as the camera moves. Downward faces (bottoms
# resting on a floor) can't be seen and are ignored, as are parts whose
# origin isn't on their top face (slopes), which this box test can't judge.

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _piece(part: String, transform: Transform3D, owner: String) -> Dictionary:
	if transform.basis.y.normalized().dot(Vector3.UP) < 0.999:
		return {}
	var x := transform.basis.x.normalized()
	if absf(x.x) < 0.999 and absf(x.z) < 0.999:
		return {}
	var bounds := Bricks.bounds(part)
	if bounds.position.y > -0.01:
		return {}
	var body := AABB(bounds.position, Vector3(bounds.size.x, -bounds.position.y, bounds.size.z))
	return {"part": part, "box": transform * body, "owner": owner}

func _describe(game: Node, owner: String) -> String:
	var item: Dictionary = game.model.find_object(owner)
	if item.is_empty(): return owner
	return "%s:%s" % [item.kind, String(item.properties.get("item", ""))] if item.kind == "furniture" else String(item.kind)

func _collect(game: Node) -> Array:
	var pieces: Array = []
	var batches: Array = [[game.arch.batch, Transform3D.IDENTITY]]
	for id in game.equipment.batches:
		batches.append([game.equipment.batches[id], (game.equipment.roots[id] as Node3D).global_transform])
	for entry in batches:
		var batch: BrickBatch = entry[0]
		var space: Transform3D = entry[1]
		var owner_of := {}
		for owner in batch.owners:
			for ref in batch.owners[owner]:
				owner_of[str(ref[0]) + "#" + str(ref[1])] = String(owner)
		for key in batch.groups:
			var group: Dictionary = batch.groups[key]
			for index in range(group.records.size()):
				var piece := _piece(String(group.part), space * (group.records[index][0] as Transform3D), owner_of.get(str(key) + "#" + str(index), ""))
				if not piece.is_empty(): pieces.append(piece)
	var roots: Array = [game.arch.root]
	for id in game.equipment.roots: roots.append(game.equipment.roots[id])
	for root_node in roots:
		for mesh in (root_node as Node).find_children("*", "MeshInstance3D", true, false):
			if mesh.has_meta("ldraw_part_id") and (mesh as Node3D).is_visible_in_tree():
				var piece := _piece(String(mesh.get_meta("ldraw_part_id")), (mesh as Node3D).global_transform, String((root_node as Node).get_meta("entity_id", "")))
				if not piece.is_empty(): pieces.append(piece)
	return pieces

func _flickers(pieces: Array) -> Dictionary:
	var grid := {}
	for i in range(pieces.size()):
		var box: AABB = pieces[i].box
		for cx in range(floori(box.position.x), floori(box.end.x) + 1):
			for cz in range(floori(box.position.z), floori(box.end.z) + 1):
				var cell := Vector2i(cx, cz)
				if not grid.has(cell): grid[cell] = []
				grid[cell].append(i)
	var seen := {}
	var found := {}
	for cell in grid:
		var list: Array = grid[cell]
		for ai in range(list.size()):
			for bi in range(ai + 1, list.size()):
				var pair := Vector2i(mini(list[ai], list[bi]), maxi(list[ai], list[bi]))
				if seen.has(pair): continue
				seen[pair] = true
				var a: AABB = pieces[pair.x].box
				var b: AABB = pieces[pair.y].box
				var shared := a.intersection(b)
				var faces: Array[String] = []
				for axis in 3:
					if shared.size[(axis + 1) % 3] < 0.04 or shared.size[(axis + 2) % 3] < 0.04: continue
					if axis != 1 and absf(a.position[axis] - b.position[axis]) < 0.004: faces.append("-" + "xyz"[axis])
					if absf(a.end[axis] - b.end[axis]) < 0.004: faces.append("+" + "xyz"[axis])
				if faces.is_empty(): continue
				var label := "%s[%s] / %s[%s] %s" % [pieces[pair.x].owner, pieces[pair.x].part, pieces[pair.y].owner, pieces[pair.y].part, str(faces)]
				found[label] = a.get_center()
	return found

func run() -> void:
	var game: Node = load("res://scripts/game.gd").new()
	root.add_child(game)
	await process_frame
	game.sound_enabled = false
	game.session_ui.hide()
	for template in ["studio", "office", "school"]:
		game.start_new_game(template, false)
		await process_frame
		var pieces := _collect(game)
		var found := _flickers(pieces)
		var named: Array[String] = []
		for label in found.keys().slice(0, 6):
			var parts := String(label).split(" / ")
			named.append("%s near %s" % [label.replace(parts[0].get_slice("[", 0), _describe(game, parts[0].get_slice("[", 0))), found[label]])
		expect(found.is_empty(), "%s: no coplanar overlapping pieces (%d pieces, %d found: %s)" % [template, pieces.size(), found.size(), "; ".join(named)])
	print("GEOMETRY_OVERLAPS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
