class_name DuctConnections
extends RefCounted

const Ducts := preload("res://scripts/build/duct_geometry.gd")
# Equipment collars end at their port faces; ducts butt straight onto them and
# run LEAD metres along the port normal before any bend.
const SOCKET_LENGTH := 0.0
const LEAD := 0.5
const WALL_TOP := PlanGrid.WALL_HEIGHT + 0.1
const ROUTE_HEIGHT := 4.6

static func equipment_size(item: Dictionary) -> Vector3:
	var library := models()
	if library != null:
		return library.size(String(item.kind), item.properties)
	if item.kind == "vav":
		return Vector3(2.0, 1.6, 1.5)
	return Vector3(float(maxi(1, item.properties.get("layout", []).size())) * 2.0, 2.7, 1.75)

static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func equipment_transform(item: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(item.transform.get("rotation_y", 0))), vector(item.transform.position))

static func models() -> Script:
	return Placement.equipment_models()

static func port_names(item: Dictionary) -> Array[String]:
	var kind := String(item.get("kind", ""))
	var library := models()
	if library != null and kind in ["ahu", "vav", "tee", "cross", "diffuser"]:
		var names: Array[String] = []
		names.assign(library.port_names(kind))
		return names
	match kind:
		"ahu", "vav": return ["inlet", "outlet"]
		"tee": return ["inlet", "outlet_a", "outlet_b"]
		"cross": return ["inlet", "outlet", "branch_a", "branch_b"]
		"diffuser": return ["inlet"]
	return []

static func port(item: Dictionary, name: String) -> Dictionary:
	if item.is_empty() or name not in port_names(item):
		return {}
	var transform := equipment_transform(item)
	var local_face := Vector3.ZERO
	var local_normal := Vector3.ZERO
	var direction := "in" if name == "inlet" else "out"
	var library := models()
	if library != null:
		var local: Dictionary = library.port_local(String(item.kind), item.properties, name)
		local_face = local.get("face", Vector3.ZERO)
		local_normal = local.get("normal", Vector3.RIGHT)
	else:
		match String(item.kind):
			"ahu":
				var sign := -1.0 if name == "inlet" else 1.0
				var half := float(maxi(1, item.properties.get("layout", []).size()))
				local_face = Vector3(sign * half, 1.2, 0.375)
				local_normal = Vector3(sign, 0, 0)
			"vav":
				var sign := -1.0 if name == "inlet" else 1.0
				local_face = Vector3(sign, 0.8, 0.0)
				local_normal = Vector3(sign, 0, 0)
			"tee":
				local_face = {"inlet": Vector3(0, 0, -0.75), "outlet_a": Vector3(-0.75, 0, 0), "outlet_b": Vector3(0.75, 0, 0)}[name]
				local_normal = {"inlet": Vector3(0, 0, -1), "outlet_a": Vector3(-1, 0, 0), "outlet_b": Vector3(1, 0, 0)}[name]
			"cross":
				local_face = {"inlet": Vector3(-0.75, 0, 0), "outlet": Vector3(0.75, 0, 0), "branch_a": Vector3(0, 0, -0.75), "branch_b": Vector3(0, 0, 0.75)}[name]
				local_normal = {"inlet": Vector3(-1, 0, 0), "outlet": Vector3(1, 0, 0), "branch_a": Vector3(0, 0, -1), "branch_b": Vector3(0, 0, 1)}[name]
			"diffuser":
				local_face = Vector3(-0.75, 0, 0)
				local_normal = Vector3(-1, 0, 0)
	var normal := (transform.basis * local_normal).normalized()
	var face := transform * local_face
	return {"owner": item.id, "port": name, "position": face + normal * SOCKET_LENGTH, "normal": normal, "face": face, "direction": direction, "medium": "supply_air", "profile": "brick_1.0_outer_0.6_inner", "capacity_m3_s": float(item.properties.get("capacity_m3_s", 1.2))}

static func compatible(first: Dictionary, second: Dictionary) -> Dictionary:
	if first.is_empty() or second.is_empty():
		return {"ok": false, "message": "Select two existing sockets."}
	if first.owner == second.owner:
		return {"ok": false, "message": "Choose a socket on a different piece."}
	if first.direction == second.direction:
		return {"ok": false, "message": "Connect an outlet to an inlet."}
	if first.medium != second.medium:
		return {"ok": false, "message": "Those sockets carry different services."}
	if first.profile != second.profile:
		return {"ok": false, "message": "Those sockets need a transition fitting."}
	return {"ok": true, "message": ""}

static func resolve(reference: Dictionary, objects: Array) -> Dictionary:
	for item in objects:
		if item.id == reference.get("owner", ""):
			return port(item, String(reference.get("port", "")))
	return {}

# Anchored endpoint + straight lead are derived, so movement, rotation, bay edits,
# mount changes and undo cannot leave a duct embedded in its former casing.
static func path(properties: Dictionary, objects: Array, lookup: Dictionary = {}) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for value in properties.get("waypoints", []):
		points.append(vector(value))
	if points.size() < 2:
		return points
	for endpoint in ["start_port", "end_port"]:
		var reference: Dictionary = properties.get(endpoint, {})
		var connection := {}
		if lookup.is_empty():
			connection = resolve(reference, objects)
		elif lookup.has(String(reference.get("owner", ""))):
			connection = port(lookup[String(reference.owner)], String(reference.get("port", "")))
		if connection.is_empty():
			continue
		var position: Vector3 = connection.position
		var normal: Vector3 = connection.normal
		var lead: Vector3 = position + normal * LEAD
		# A run that already leaves straight along the socket axis needs no
		# extra lead (and a short straight stub would fold back over one).
		var neighbour: Vector3 = points[1] if endpoint == "start_port" else points[-2]
		var away := neighbour - position
		var straight := away.length() > 0.01 and away.normalized().dot(normal) > 0.9999
		if endpoint == "start_port":
			points[0] = position
			if not straight: points.insert(1, lead)
		else:
			points[-1] = position
			if not straight: points.insert(points.size() - 1, lead)
	# Do not leave zero-length vertices when a user lands on a lead point.
	var clean: Array[Vector3] = []
	for point in points:
		if clean.is_empty() or clean[-1].distance_to(point) > 0.01:
			if clean.size() >= 2:
				var before := (clean[-1] - clean[-2]).normalized()
				var after := (point - clean[-1]).normalized()
				if before.dot(after) > 0.9999:
					clean.remove_at(clean.size() - 1)
			clean.append(point)
	return clean

static func clearance_error(points: Array[Vector3], objects: Array, exclude_id: String = "", endpoint_owners: Dictionary = {}) -> String:
	if points.size() < 2:
		return "Duct needs two endpoints."
	for point in points:
		if not point.is_finite():
			return "Duct endpoints must be finite."
	# Gather obstacles once; the per-segment loops below only test them.
	var equipment: Array = []
	var walls: Array = []
	var others: Array = []
	var lookup: Dictionary = {}
	for item in objects:
		lookup[String(item.id)] = item
	for item in objects:
		match String(item.kind):
			"ahu", "vav", "diffuser", "tee", "cross":
				equipment.append(item)
			"wall":
				if not String(item.properties.get("edge", "")).is_empty():
					walls.append(item)
			"duct":
				if item.id != exclude_id and bool(item.properties.get("enabled", true)):
					others.append(path(item.properties, objects, lookup))
	var owners := [String(endpoint_owners.get("start", "")), String(endpoint_owners.get("end", ""))]
	# Include miter overhang and the native plate studs in the swept envelope.
	var rings := Ducts.path_rings(points, Ducts.OUTER + 0.1)
	var wall_reach := Ducts.OUTER + 0.05
	for i in range(points.size() - 1):
		if not Ducts.valid_segment(points[i], points[i + 1]):
			return "Duct sections need at least 0.25 m."
		if i > 0 and (points[i] - points[i - 1]).normalized().dot((points[i + 1] - points[i]).normalized()) < -0.7:
			return "That bend folds back through the duct. Add a wider turn."
		for item in equipment:
			var id := String(item.id)
			if (i == 0 and id == owners[0]) or (i == points.size() - 2 and id == owners[1]):
				continue
			var transform := equipment_transform(item)
			var inverse := transform.affine_inverse()
			var extent := Vector3.ZERO
			for end in [i, i + 1]:
				for corner in rings[end]:
					var offset: Vector3 = (inverse.basis * (corner - points[end])).abs()
					extent = extent.max(offset)
			# Conservative oriented sweep, including square-profile rotation and
			# bend overhang; a scalar half-width misses those corner collisions.
			var body := equipment_size(item)
			# A duct's own unit is only its casing: the collars are where it docks
			# (fittings take ducts on every side, diffusers on one).
			if id in owners:
				body.x = maxf(0.5, body.x - 1.0)
				if String(item.kind) in ["tee", "cross"]: body.z = maxf(0.5, body.z - 1.0)
			var bounds := AABB(Vector3(-body.x * 0.5, 0, -body.z * 0.5) - extent, body + extent * 2)
			if bounds.intersects_segment(inverse * points[i], inverse * points[i + 1]) != null:
				return "Duct overlaps %s. Route outside the casing or snap to its socket." % item.properties.get("label", item.id)
		# Only segments that dip toward the wall tops can hit walls.
		if minf(points[i].y, points[i + 1].y) < WALL_TOP + wall_reach + 0.01:
			for item in walls:
				var edge := String(item.properties.edge)
				var center := PlanGrid.edge_center(edge) + Vector3(0, WALL_TOP * 0.5, 0)
				var inverse := Transform3D(Basis(Vector3.UP, PlanGrid.edge_rotation(edge)), center).affine_inverse()
				# Centre-line test against the wall inflated by the duct half-size, so
				# a duct clears when its underside is above the wall's studs.
				var bounds := AABB(Vector3(-PlanGrid.TILE * 0.5 - 0.25 - wall_reach, -WALL_TOP * 0.5, -0.25 - wall_reach), Vector3(PlanGrid.TILE + 0.5 + wall_reach * 2.0, WALL_TOP + wall_reach, 0.5 + wall_reach * 2.0))
				if bounds.intersects_segment(inverse * points[i], inverse * points[i + 1]) != null:
					return "Duct crosses a wall. Raise it into the ceiling space above the walls."
		for other in others:
			for other_index in range(other.size() - 1):
				var closest := Geometry3D.get_closest_points_between_segments(points[i], points[i + 1], other[other_index], other[other_index + 1])
				if closest.size() == 2 and closest[0].distance_to(closest[1]) < Ducts.OUTER * 2.0 + 0.08:
					return "Duct overlaps another run. Add a new elevation or a tee."
	return ""

static func route_error(properties: Dictionary, objects: Array, exclude_id: String = "") -> String:
	for end in ["start_port", "end_port"]:
		if properties.has(end) and resolve(properties[end], objects).is_empty():
			return "Connected equipment was removed. Reroute this duct."
	if properties.has("start_port") and properties.has("end_port"):
		var match_result := compatible(resolve(properties.start_port, objects), resolve(properties.end_port, objects))
		if not match_result.ok:
			return String(match_result.message)
	var endpoint_owners := {"start": String(properties.get("start_port", {}).get("owner", "")), "end": String(properties.get("end_port", {}).get("owner", ""))}
	return clearance_error(path(properties, objects), objects, exclude_id, endpoint_owners)

static func auto_route(start: Dictionary, finish: Dictionary, objects: Array, exclude_id: String = "") -> Dictionary:
	var match_result := compatible(start, finish)
	if not match_result.ok:
		return {"ok": false, "message": match_result.message}
	# Normalize route direction so authored topology always reads outlet -> inlet.
	if start.direction == "in":
		var swap := start
		start = finish
		finish = swap
	var base := {"start_port": {"owner": start.owner, "port": start.port}, "end_port": {"owner": finish.owner, "port": finish.port}, "service": start.medium, "profile": start.profile, "enabled": true, "auto_routed": true}
	var check := func(points: Array) -> String:
		var props := base.duplicate(true)
		props.waypoints = points.map(func(point: Vector3) -> Array: return [point.x, point.y, point.z])
		return route_error(props, objects, exclude_id)
	var result := DuctRouter.route(start, finish, objects, exclude_id, check)
	if not bool(result.ok):
		return {"ok": false, "message": String(result.message)}
	var properties := base.duplicate(true)
	properties.waypoints = (result.points as Array).map(func(point: Vector3) -> Array: return [point.x, point.y, point.z])
	return {"ok": true, "properties": properties}

static func occupied(reference: Dictionary, objects: Array, exclude_id: String = "") -> bool:
	if reference.is_empty():
		return false
	for item in objects:
		if item.kind != "duct" or item.id == exclude_id:
			continue
		for end in ["start_port", "end_port"]:
			var other: Dictionary = item.properties.get(end, {})
			if other.get("owner", "") == reference.get("owner", "") and other.get("port", "") == reference.get("port", ""):
				return true
	return false
