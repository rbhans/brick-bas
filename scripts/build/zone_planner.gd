class_name ZonePlanner
extends RefCounted

# Plans the equipment that makes a room a conditioned zone: a VAV sized from
# the room's cooling load (just inside the room, inlet facing its supply), one
# or two ceiling diffusers over the room (two via a branch tee in big rooms),
# the duct runs between them and a thermostat by the room's door. When no
# free outlet is close, it taps the main: a trunk cross is spliced into the
# nearest supply duct and the room branches off it. Nothing touches the model
# here: `entries` (new pieces) and `removed` (tapped ducts) make one undo step.

const DuctPorts := preload("res://scripts/build/duct_connections.gd")
const Bindings := preload("res://scripts/data/animation_binding.gd")
const THERMOSTAT_HEIGHT := 1.55
const CEILING_FACE := 3.6
const NEAR_SOCKET := 9.0     # a free outlet this close beats tapping the main
const TAP_SEGMENT := 3.4     # straight run needed to splice in a cross (m)
const TAP_MARGIN := 1.7      # keep the cross this far from the run's ends
# Design airflow: sensible peak load over a 10 K supply-to-room difference.
const DESIGN_DT_K := 10.0
const ENVELOPE_W_M2 := 15.0   # walls, roof and leakage on a design day
const GLASS_W_M2 := 150.0     # sun through each m² of exterior glass
const VAV_MIN_M3_S := 0.15
const VAV_MAX_M3_S := 1.1

var objects: Array = []    # working copy: existing objects + planned ones
var entries: Array = []
var removed: Array = []    # existing objects the plan replaces
var unhooked: Array[String] = []   # pieces a move left without a connection
var blocked: Array[String] = []    # runs a move would cut through
var index: BuildingIndex
var library: Script
var make_id: Callable
var error := ""

# `id_source` returns a fresh unique id for a kind (ProjectModel.new_id).
func _init(existing: Array, building: BuildingIndex, id_source: Callable) -> void:
	objects = existing.duplicate()
	index = building
	library = Placement.equipment_models()
	make_id = id_source

func _add(kind: String, position: Vector3, rotation: float, properties: Dictionary) -> Dictionary:
	var item := {"id": String(make_id.call(kind)), "kind": kind, "floor_id": "floor-1", "transform": {"position": [position.x, position.y, position.z], "rotation_y": fposmod(rotation, TAU)}, "properties": properties}
	objects.append(item)
	entries.append(item)
	return item

func _drop(item: Dictionary) -> void:
	objects.erase(item)
	entries.erase(item)

func _remove(item: Dictionary) -> void:
	objects.erase(item)
	removed.append(item)

func _unremove(item: Dictionary) -> void:
	removed.erase(item)
	objects.append(item)

func _find(id: String) -> Dictionary:
	for item in objects:
		if String(item.id) == id: return item
	return {}

func port_height(kind: String, properties: Dictionary, port: String) -> float:
	if library == null:
		return {"vav": 0.8, "tee": 0.0, "cross": 0.0}.get(kind, 0.0)
	return float((library.port_local(kind, properties, port).get("face", Vector3.ZERO) as Vector3).y)

func footprint(kind: String, properties: Dictionary) -> Vector2i:
	return library.footprint(kind, properties) if library != null else Vector2i(4, 4)

func snap(point: Vector3, kind: String, properties: Dictionary, rotation: float) -> Vector3:
	var turned := PlanGrid.rotated_footprint(footprint(kind, properties), rotation)
	return Vector3(PlanGrid.snap_part_center(point.x, turned.x), point.y, PlanGrid.snap_part_center(point.z, turned.y))

func route(from_item: Dictionary, from_port: String, to_item: Dictionary, to_port: String) -> Dictionary:
	var start := DuctPorts.port(from_item, from_port)
	var finish := DuctPorts.port(to_item, to_port)
	if start.is_empty() or finish.is_empty():
		return {}
	var routed := DuctPorts.auto_route(start, finish, objects)
	if not bool(routed.ok):
		error = String(routed.message)
		return {}
	var properties: Dictionary = routed.properties
	properties.bindings = Bindings.defaults("duct")
	return _add("duct", Vector3.ZERO, 0.0, properties)

# Free supply outlets (AHU outlets, tee/cross outlets) nearest the room first.
func supply_ports(room: Dictionary) -> Array:
	var center: Vector3 = room.center
	var found: Array = []
	for item in objects:
		if String(item.kind) not in ["ahu", "tee", "cross"]:
			continue
		for name in DuctPorts.port_names(item):
			var port := DuctPorts.port(item, name)
			if port.direction != "out" or DuctPorts.occupied(port, objects):
				continue
			found.append({"item": item, "port": name, "distance": Vector2(port.position.x - center.x, port.position.z - center.z).length()})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	return found

# Zone `room`: from a free outlet close by, else by tapping the nearest
# supply duct, else from any free outlet. Returns the new VAV or {}.
func zone(room: Dictionary, label: String, layout: Array = ["damper", "heating_coil"]) -> Dictionary:
	var center: Vector3 = room.center
	var candidates := supply_ports(room)
	var mains := supply_ducts()
	if candidates.is_empty() and mains.is_empty():
		error = "No air to connect to yet. Place an air handler first."
		return {}
	for candidate in candidates.slice(0, 4):
		if float(candidate.distance) > NEAR_SOCKET: break
		var vav := zone_from(room, candidate.item, String(candidate.port), label, layout)
		if not vav.is_empty():
			return vav
	var excluded: Array = []
	for attempt in range(3):
		var tapped := tap(mains, center, excluded)
		if tapped.is_empty(): break
		var cross: Dictionary = tapped.cross
		for branch in _branches_toward(cross, center):
			var vav := zone_from(room, cross, branch, label, layout)
			if not vav.is_empty():
				return vav
		excluded.append(cross.transform.position)
		untap(tapped)
	for candidate in candidates.slice(0, 4):
		if float(candidate.distance) <= NEAR_SOCKET: continue
		var vav := zone_from(room, candidate.item, String(candidate.port), label, layout)
		if not vav.is_empty():
			return vav
	if error.is_empty():
		error = "Couldn't reach %s from the ductwork. Try moving the air handler closer." % String(room.label)
	return {}

# Connects a newly placed piece's inlet to the supply: a free outlet within
# reach, else a tap on the right duct (the main for VAVs and fittings, the
# serving VAV's discharge for diffusers). Returns true when connected.
func connect_inlet(item: Dictionary) -> bool:
	var inlet := DuctPorts.port(item, "inlet")
	if inlet.is_empty() or DuctPorts.occupied(inlet, objects):
		return false
	var point: Vector3 = inlet.position
	var diffuser := String(item.kind) == "diffuser"
	var feeders := ["vav", "tee", "cross"] if diffuser else ["ahu", "tee", "cross"]
	var serving := _serving_vav(point) if diffuser else ""
	var sockets: Array = []
	for other in objects:
		if String(other.kind) not in feeders or other.id == item.id:
			continue
		if diffuser and String(other.kind) != "vav" and not _downstream_of(String(other.id), serving):
			continue
		if not diffuser and _is_discharge(String(other.id)):
			continue
		for name in DuctPorts.port_names(other):
			var port := DuctPorts.port(other, name)
			if port.direction != "out" or DuctPorts.occupied(port, objects):
				continue
			sockets.append({"item": other, "port": name, "distance": (port.position as Vector3).distance_to(point)})
	sockets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	# Of the nearby free outlets, use the one giving the tidiest run.
	var best: Dictionary = {}
	var best_cost := INF
	for socket in sockets.slice(0, 4):
		if float(socket.distance) > NEAR_SOCKET * 1.5: break
		var run := route(socket.item, String(socket.port), item, "inlet")
		if run.is_empty(): continue
		var cost := _run_cost(run)
		_drop(run)
		if cost < best_cost:
			best_cost = cost
			best = socket
	if not best.is_empty() and not route(best.item, String(best.port), item, "inlet").is_empty():
		return true
	var ducts := supply_ducts(serving) if diffuser else supply_ducts()
	var excluded: Array = []
	for attempt in range(3):
		var tapped := tap(ducts, point, excluded)
		if tapped.is_empty(): break
		for branch in _branches_toward(tapped.cross, point):
			if not route(tapped.cross, branch, item, "inlet").is_empty():
				return true
		excluded.append(tapped.cross.transform.position)
		untap(tapped)
	# A diffuser that can't tap in joins its VAV's layout: the VAV's
	# discharge is re-planned to feed every diffuser it serves.
	if diffuser and not serving.is_empty():
		var fed: Array = []
		for duct in supply_ducts(serving):
			var end := _find(String(duct.properties.end_port.owner))
			if String(end.get("kind", "")) == "diffuser": fed.append(end)
		fed.append(item)
		return feed_diffusers(_find(serving), fed)
	return false

# Lays a VAV's discharge ductwork from scratch: straight to one diffuser, or
# through a branch tee (two) or cross (three) near its outlet. Diffusers
# may turn to take their duct from the handiest side (a real round-neck
# diffuser can). The old discharge is replaced; on failure nothing changes.
func feed_diffusers(vav: Dictionary, diffusers: Array, fixed_id: String = "") -> bool:
	if vav.is_empty() or diffusers.is_empty() or diffusers.size() > 3:
		return false
	var mark := _mark()
	var ids: Array = diffusers.map(func(item: Dictionary) -> String: return String(item.id))
	for duct in supply_ducts(String(vav.id)):
		var end := _find(String(duct.properties.end_port.owner))
		_remove(duct)
		if String(end.get("kind", "")) in ["tee", "cross"]: _remove(end)
	if ids.size() == 1:
		if not route(vav, "outlet", _find(ids[0]), "inlet").is_empty():
			return true
		var turned := _turn_toward(_find(ids[0]), DuctPorts.port(vav, "outlet").position)
		if not route(vav, "outlet", turned, "inlet").is_empty():
			return true
	if _feed_through_fitting(vav, ids):
		return true
	# Last resort: keep the player's diffuser where it is and slide the
	# others to the tee's free outlets.
	if ids.size() >= 2:
		var keep := fixed_id if not fixed_id.is_empty() else String(ids[-1])
		if _feed_rearranged(vav, keep, ids.filter(func(id: String) -> bool: return id != keep)):
			return true
	_rollback(mark)
	return false

func _feed_rearranged(vav: Dictionary, keep: String, movable: Array) -> bool:
	var kind := "tee" if movable.size() == 1 else "cross"
	var props := {"label": "Branch tee" if kind == "tee" else "Branch cross", "capacity_m3_s": 1.0}
	var outlet := DuctPorts.port(vav, "outlet")
	var mouth: Vector3 = outlet.position
	var along: Vector3 = outlet.normal
	var room: Dictionary = index.room_at(DuctPorts.vector(_find(keep).transform.position))
	var lifted: Dictionary = {}
	for id in movable:
		lifted[id] = _find(String(id))
		_remove(lifted[id])
	var rotation := atan2(along.x, along.z) if kind == "tee" else atan2(-along.z, along.x)
	for ahead in [1.5, 2.0, 2.5, 3.0]:
		var point: Vector3 = snap(mouth + along * ahead, kind, props, rotation)
		point.y = DuctPorts.ROUTE_HEIGHT - port_height(kind, props, "inlet")
		if _overlaps_ceiling(point, footprint(kind, props), rotation):
			continue
		var mark := _mark()
		var fitting := _add(kind, point, rotation, props.duplicate())
		if route(vav, "outlet", fitting, "inlet").is_empty() or not _feed_each(fitting, [keep]):
			_rollback(mark)
			continue
		var free: Array = DuctPorts.port_names(fitting).filter(func(name: String) -> bool: return name != "inlet" and not DuctPorts.occupied(DuctPorts.port(fitting, name), objects))
		var placed_all := true
		for id in movable:
			if not _replace_off_port(lifted[id], fitting, free, room):
				placed_all = false
				break
		if placed_all:
			return true
		_rollback(mark)
	return false

# Re-seats `diffuser` (same id) straight off one of `free` outlets of
# `fitting`, inside `room`, and ducts it.
func _replace_off_port(diffuser: Dictionary, fitting: Dictionary, free: Array, room: Dictionary) -> bool:
	for name in free:
		var port := DuctPorts.port(fitting, name)
		var normal: Vector3 = port.normal
		for distance in [1.5, 2.0, 2.5, 3.0]:
			var point: Vector3 = (port.position as Vector3) + normal * distance
			point.y = CEILING_FACE
			var rotation := atan2(-normal.z, normal.x)
			if not _fits("diffuser", diffuser.properties, point, rotation, room):
				continue
			var seat: Dictionary = diffuser.duplicate(true)
			seat.transform = {"position": [point.x, point.y, point.z], "rotation_y": fposmod(rotation, TAU)}
			include(seat)
			if not route(fitting, name, seat, "inlet").is_empty():
				free.erase(name)
				return true
			_drop(seat)
	return false

func _feed_through_fitting(vav: Dictionary, ids: Array) -> bool:
	var kind := "tee" if ids.size() <= 2 else "cross"
	var props := {"label": "Branch tee" if kind == "tee" else "Branch cross", "capacity_m3_s": 1.0}
	var outlet := DuctPorts.port(vav, "outlet")
	var mouth: Vector3 = outlet.position
	var along: Vector3 = outlet.normal
	var side := Vector3(-along.z, 0, along.x)
	for ahead in [1.5, 2.5, 3.5, 4.5]:
		for aside in [0.0, 1.5, -1.5, 3.0, -3.0]:
			var point: Vector3 = mouth + along * ahead + side * aside
			point = snap(point, kind, props, 0.0)
			point.y = DuctPorts.ROUTE_HEIGHT - port_height(kind, props, "inlet")
			# Inlet faces back toward the VAV along the dominant axis.
			var back := (mouth - point) * Vector3(1, 0, 1)
			var n := Vector3(signf(back.x), 0, 0) if absf(back.x) >= absf(back.z) else Vector3(0, 0, signf(back.z))
			var rotation := atan2(-n.x, -n.z) if kind == "tee" else atan2(n.z, -n.x)
			if _overlaps_ceiling(point, footprint(kind, props), rotation):
				continue
			var mark := _mark()
			var fitting := _add(kind, point, rotation, props.duplicate())
			if not route(vav, "outlet", fitting, "inlet").is_empty() and _feed_each(fitting, ids):
				return true
			_rollback(mark)
	return false

# Routes each diffuser from the nearest free outlet of `fitting`, turning it
# to face that outlet when it has to.
func _feed_each(fitting: Dictionary, ids: Array) -> bool:
	var free: Array = DuctPorts.port_names(fitting).filter(func(name: String) -> bool: return name != "inlet")
	for id in ids:
		var diffuser := _find(String(id))
		var inlet: Vector3 = DuctPorts.port(diffuser, "inlet").position
		free.sort_custom(func(a: String, b: String) -> bool: return (DuctPorts.port(fitting, a).position as Vector3).distance_to(inlet) < (DuctPorts.port(fitting, b).position as Vector3).distance_to(inlet))
		var done := false
		for name in free:
			if not route(fitting, name, diffuser, "inlet").is_empty():
				done = true
			else:
				var turned := _turn_toward(diffuser, DuctPorts.port(fitting, name).position)
				done = not route(fitting, name, turned, "inlet").is_empty()
				diffuser = _find(String(id))
			if done:
				free.erase(name)
				break
		if not done:
			return false
	return true

# The diffuser turned (in quarter turns) so its inlet faces `target`.
func _turn_toward(diffuser: Dictionary, target: Vector3) -> Dictionary:
	var toward := (target - DuctPorts.vector(diffuser.transform.position)) * Vector3(1, 0, 1)
	var rotation := fposmod(roundf(atan2(toward.z, -toward.x) / (PI * 0.5)) * PI * 0.5, TAU)
	if absf(angle_difference(rotation, float(diffuser.transform.get("rotation_y", 0.0)))) < 0.01:
		return diffuser
	if entries.has(diffuser):
		diffuser.transform.rotation_y = rotation   # a piece being placed right now
		return diffuser
	var turned: Dictionary = diffuser.duplicate(true)
	turned.transform.rotation_y = rotation
	_remove(diffuser)
	include(turned)
	return turned

# Plan checkpoints: roll entries and removals back to an earlier state.
func _mark() -> Vector2i:
	return Vector2i(entries.size(), removed.size())

func _rollback(mark: Vector2i) -> void:
	while entries.size() > mark.x:
		_drop(entries[-1])
	while removed.size() > mark.y:
		_unremove(removed[-1])

# How long and bendy a planned duct is (metres, plus 2 m per bend).
func _run_cost(duct: Dictionary) -> float:
	var path := DuctPorts.path(duct.properties, objects)
	var length := 0.0
	for i in range(path.size() - 1):
		length += path[i].distance_to(path[i + 1])
	return length + 2.0 * maxf(0.0, float(path.size() - 2))

# --- Tapping the main ---------------------------------------------------------------------

# Ducts carrying air away from `from_owner` (every air handler when empty)
# through tees and crosses, stopping at VAVs: the mains, or one VAV's discharge.
func supply_ducts(from_owner: String = "") -> Array:
	var starts: Dictionary = {}
	var lookup: Dictionary = {}
	for item in objects:
		lookup[String(item.id)] = item
		if String(item.kind) == "duct" and bool(item.properties.get("enabled", true)):
			var owner := String(item.properties.get("start_port", {}).get("owner", ""))
			if not starts.has(owner): starts[owner] = []
			starts[owner].append(item)
	var queue: Array = []
	if from_owner.is_empty():
		for item in objects:
			if String(item.kind) == "ahu": queue.append(String(item.id))
	else:
		queue.append(from_owner)
	var seen: Dictionary = {}
	var result: Array = []
	while not queue.is_empty():
		var owner: String = queue.pop_front()
		if seen.has(owner): continue
		seen[owner] = true
		for duct in starts.get(owner, []):
			result.append(duct)
			var next: Dictionary = lookup.get(String(duct.properties.get("end_port", {}).get("owner", "")), {})
			if String(next.get("kind", "")) in ["tee", "cross"]:
				queue.append(String(next.id))
	return result

# Splices a trunk cross into the straight run of `ducts` nearest `toward`.
# The duct becomes upstream → cross → downstream and the cross's two branches
# are free. Returns {cross, ducts, replaced} or {}; untap() reverses it.
func tap(ducts: Array, toward: Vector3, excluded: Array = []) -> Dictionary:
	var candidates: Array = []
	for duct in ducts:
		if not objects.has(duct): continue
		var path := DuctPorts.path(duct.properties, objects)
		for i in range(path.size() - 1):
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			if absf(a.y - b.y) > 0.01: continue
			var length := a.distance_to(b)
			var direction := (b - a) / maxf(length, 0.001)
			if length < TAP_SEGMENT or (absf(direction.x) < 0.99 and absf(direction.z) < 0.99): continue
			var along := (toward - a).dot(direction)
			for shift in [0.0, 1.0, -1.0, 2.0, -2.0, 3.0, -3.0]:
				var t := clampf(along + shift, TAP_MARGIN, length - TAP_MARGIN)
				var point := a + direction * t
				candidates.append({"duct": duct, "point": point, "direction": direction, "distance": Vector2(point.x - toward.x, point.z - toward.z).length()})
	candidates.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.distance) < float(q.distance))
	var fitting := {"label": "Trunk cross", "capacity_m3_s": 1.6}
	var tried: Dictionary = {}
	for candidate in candidates.slice(0, 16):
		var duct: Dictionary = candidate.duct
		var direction: Vector3 = candidate.direction
		var point: Vector3 = candidate.point
		var rotation := atan2(-direction.z, direction.x)
		var center := snap(point, "cross", fitting, rotation)
		# Stay exactly on the duct's line so both halves run straight.
		if absf(direction.x) > 0.5: center.z = point.z
		else: center.x = point.x
		center.y = point.y - port_height("cross", fitting, "inlet")
		var key := "%.2f,%.2f,%.2f" % [center.x, center.y, center.z]
		if tried.has(key) or excluded.any(func(at: Array) -> bool: return Vector3(float(at[0]), float(at[1]), float(at[2])).distance_to(center) < 0.5):
			continue
		tried[key] = true
		if _overlaps_ceiling(center, footprint("cross", fitting), rotation):
			continue
		var start: Dictionary = duct.properties.start_port
		var finish: Dictionary = duct.properties.end_port
		var upstream := _find(String(start.owner))
		var downstream := _find(String(finish.owner))
		if upstream.is_empty() or downstream.is_empty():
			continue
		_remove(duct)
		var cross := _add("cross", center, rotation, fitting.duplicate())
		var first := route(upstream, String(start.port), cross, "inlet")
		var second := route(cross, "outlet", downstream, String(finish.port)) if not first.is_empty() else {}
		if not second.is_empty():
			return {"cross": cross, "ducts": [first, second], "replaced": duct}
		if not first.is_empty(): _drop(first)
		_drop(cross)
		_unremove(duct)
	return {}

# Deleting equipment takes its ducts along, and a tee or cross pulled out of
# a main is bridged (upstream straight to downstream) so the rest keeps air.
func plan_removal(ids: Array) -> void:
	var going: Dictionary = {}
	for id in ids: going[String(id)] = true
	var fittings: Array = []
	for id in ids:
		var item := _find(String(id))
		if item.is_empty(): continue
		_remove(item)
		if String(item.kind) in ["tee", "cross"]: fittings.append(item)
	var cut: Array = []
	for duct in objects.duplicate():
		if String(duct.kind) != "duct": continue
		var start := String(duct.properties.get("start_port", {}).get("owner", ""))
		var finish := String(duct.properties.get("end_port", {}).get("owner", ""))
		if going.has(start) or going.has(finish):
			_remove(duct)
			cut.append(duct)
	for fitting in fittings:
		var id := String(fitting.id)
		var incoming := cut.filter(func(duct: Dictionary) -> bool: return String(duct.properties.end_port.owner) == id)
		var outgoing := cut.filter(func(duct: Dictionary) -> bool: return String(duct.properties.start_port.owner) == id)
		var through := outgoing.filter(func(duct: Dictionary) -> bool: return String(duct.properties.start_port.port) == "outlet")
		if through.is_empty() and outgoing.size() == 1: through = outgoing
		if incoming.size() != 1 or through.size() != 1: continue
		var up := _find(String(incoming[0].properties.start_port.owner))
		var down := _find(String(through[0].properties.end_port.owner))
		if up.is_empty() or down.is_empty(): continue
		route(up, String(incoming[0].properties.start_port.port), down, String(through[0].properties.end_port.port))

# After a unit moves, its auto-routed ducts are laid again from scratch
# (hand-drawn runs keep their bends). `moved` is the unit's new record.
func reroute_attached(moved: Dictionary) -> void:
	var old := _find(String(moved.id))
	if old.is_empty(): return
	var sound := _ducts_ok()
	# A VAV's whole discharge (its tees and diffuser ducts) moves with it.
	var diffusers: Array = []
	if String(moved.kind) == "vav":
		for duct in supply_ducts(String(moved.id)):
			var end := _find(String(duct.properties.end_port.owner))
			if String(end.get("kind", "")) == "diffuser": diffusers.append(String(end.id))
			if bool(duct.properties.get("auto_routed", false)):
				_remove(duct)
				if String(end.get("kind", "")) in ["tee", "cross"]: _remove(end)
	objects.erase(old)
	objects.append(moved)
	# Lift the rest of its runs first so the new ones don't trip over them.
	var attached: Array = []
	for duct in objects.duplicate():
		if String(duct.kind) != "duct" or not bool(duct.properties.get("auto_routed", false)):
			continue
		var start: Dictionary = duct.properties.get("start_port", {})
		var finish: Dictionary = duct.properties.get("end_port", {})
		if String(start.get("owner", "")) == String(moved.id) or String(finish.get("owner", "")) == String(moved.id):
			_remove(duct)
			attached.append(duct)
	var stranded: Array = []
	for duct in attached:
		var start: Dictionary = duct.properties.start_port
		var finish: Dictionary = duct.properties.end_port
		var upstream := _find(String(start.get("owner", "")))
		var downstream := _find(String(finish.get("owner", "")))
		if upstream.is_empty() or downstream.is_empty() or route(upstream, String(start.port), downstream, String(finish.port)).is_empty():
			stranded.append(downstream if String(start.get("owner", "")) == String(moved.id) else moved)
	if not diffusers.is_empty():
		var served: Array = diffusers.map(func(id: String) -> Dictionary: return _find(id)).filter(func(item: Dictionary) -> bool: return not item.is_empty())
		if not feed_diffusers(moved, served):
			unhooked.append("its diffusers")
	# Whatever couldn't follow reconnects its inlet, or is left cleanly
	# unhooked: never a duct stuck in its old place.
	for piece in stranded:
		if piece.is_empty() or DuctPorts.occupied(DuctPorts.port(piece, "inlet"), objects):
			continue
		if connect_inlet(piece): continue
		unhooked.append(String(piece.get("properties", {}).get("label", piece.kind)))
	# Ducts the unit now sits on are rerouted; any that can't be are blocked.
	for duct in objects.duplicate():
		if String(duct.kind) != "duct" or not sound.has(String(duct.id)) or DuctPorts.route_error(duct.properties, objects, String(duct.id)).is_empty():
			continue
		var start: Dictionary = duct.properties.start_port
		var finish: Dictionary = duct.properties.end_port
		_remove(duct)
		if route(_find(String(start.owner)), String(start.port), _find(String(finish.owner)), String(finish.port)).is_empty():
			_unremove(duct)
			blocked.append(String(_find(String(finish.owner)).get("properties", {}).get("label", "a duct")))

# Ids of ducts that are currently fine (to tell a move's damage from old damage).
func _ducts_ok() -> Dictionary:
	var result: Dictionary = {}
	for item in objects:
		if String(item.kind) == "duct" and DuctPorts.route_error(item.properties, objects, String(item.id)).is_empty():
			result[String(item.id)] = true
	return result

# Adds an already-built entry (a piece being placed) to the plan.
func include(entry: Dictionary) -> void:
	objects.append(entry)
	entries.append(entry)

func removed_ids() -> Array:
	return removed.map(func(item: Dictionary) -> String: return String(item.id))

func untap(tapped: Dictionary) -> void:
	for duct in tapped.ducts: _drop(duct)
	_drop(tapped.cross)
	_unremove(tapped.replaced)

# A fitting's free branch outlets, the one facing `point` first.
func _branches_toward(fitting: Dictionary, point: Vector3) -> Array:
	var found: Array = []
	for name in DuctPorts.port_names(fitting):
		if name in ["inlet", "outlet"] and String(fitting.kind) == "cross":
			continue
		if name == "inlet":
			continue
		var port := DuctPorts.port(fitting, name)
		if DuctPorts.occupied(port, objects):
			continue
		var toward := (point - (port.position as Vector3)) * Vector3(1, 0, 1)
		found.append({"name": name, "score": (port.normal as Vector3).dot(toward.normalized())})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	return found.map(func(entry: Dictionary) -> String: return String(entry.name))

# The VAV feeding the room at `point` (its diffusers already there), else the
# nearest VAV.
func _serving_vav(point: Vector3) -> String:
	var room: Dictionary = index.room_at(point)
	var best := ""
	var best_distance := INF
	for item in objects:
		if String(item.kind) != "vav": continue
		var discharge := supply_ducts(String(item.id))
		var serves := false
		for duct in discharge:
			var end: Dictionary = _find(String(duct.properties.end_port.owner))
			if String(end.get("kind", "")) == "diffuser" and not room.is_empty() and String(index.room_at(DuctPorts.vector(end.transform.position)).get("id", "")) == String(room.id):
				serves = true
		var distance := DuctPorts.vector(item.transform.position).distance_to(point) - (100.0 if serves else 0.0)
		if distance < best_distance:
			best_distance = distance
			best = String(item.id)
	return best

func _downstream_of(fitting_id: String, vav_id: String) -> bool:
	if vav_id.is_empty(): return false
	for duct in supply_ducts(vav_id):
		if String(duct.properties.end_port.owner) == fitting_id: return true
	return false

# True for a tee or cross that sits after a VAV (it carries conditioned
# discharge air, not supply from the air handler).
func _is_discharge(fitting_id: String) -> bool:
	for duct in supply_ducts():
		if String(duct.properties.end_port.owner) == fitting_id: return false
	var item := _find(fitting_id)
	return String(item.get("kind", "")) in ["tee", "cross"]

# A VAV's maximum airflow for a room: its people, plug and lighting loads
# (the simulation's own room-type table), the envelope, and sun on its glass.
static func design_airflow(room: Dictionary) -> float:
	var type: Array = DemoSimulation.ZONE_TYPES.get(String(room.get("type", "room")), DemoSimulation.ZONE_TYPES.room)
	var per_m2 := float(type[0]) * float(type[1]) + float(type[2]) + float(type[3]) + ENVELOPE_W_M2
	var glass := 0.0
	for window in room.get("windows", []):
		if bool(window.get("exterior", false)):
			glass += ZoneTopology.TALL_WINDOW_AREA if String(window.get("style", "")) in ["tall_window", "storefront"] else ZoneTopology.WINDOW_AREA
	var load_w := float(room.get("area_m2", 0.0)) * per_m2 + glass * GLASS_W_M2
	return snappedf(clampf(load_w / (DemoSimulation.RHO_CP * DESIGN_DT_K), VAV_MIN_M3_S, VAV_MAX_M3_S), 0.01)

# Zone `room` from a specific supply socket.
func zone_from(room: Dictionary, supply: Dictionary, supply_port: String, label: String, layout: Array = ["damper", "heating_coil"], reach: float = 1.2) -> Dictionary:
	var branch := DuctPorts.port(supply, supply_port)
	var capacity := design_airflow(room)
	var properties := {"layout": layout.duplicate(), "sensor_enabled": true, "capacity_m3_s": capacity, "mount_level": 1}
	var size: Vector3 = library.size("vav", properties) if library != null else Vector3(3.0, 1.6, 2.0)
	var inlet_offset := absf(float((library.port_local("vav", properties, "inlet").get("face", Vector3(-2, 0, 0)) as Vector3).x)) if library != null else 2.0
	# Best case: a straight branch along the supply socket's normal into the room.
	var normal := branch.normal as Vector3
	if absf(normal.y) < 0.5:
		var straight_rotation := atan2(-normal.z, normal.x)
		# Fittings already at duct height get a short straight stub; air
		# handler outlets need room to rise into the ceiling first.
		var level := absf(float((branch.position as Vector3).y) - DuctPorts.ROUTE_HEIGHT) < 0.05
		var gap := 0.5 if level else DuctPorts.LEAD * 2.0 + 0.5
		# First with the box over the room itself; small rooms then let it
		# hang over a neighbour's ceiling (as real VAVs do over corridors)
		# as long as the diffusers land in the room.
		for over_room in [true, false]:
			for step in range(0, 14):
				var distance := inlet_offset + gap + float(step) * 0.5
				var center: Vector3 = (branch.position as Vector3) + normal * distance
				center = snap(center, "vav", properties, straight_rotation)
				# Keep the branch exactly in line with the socket.
				if absf(normal.x) > 0.5: center.z = (branch.position as Vector3).z
				else: center.x = (branch.position as Vector3).x
				center.y = DuctPorts.ROUTE_HEIGHT - port_height("vav", properties, "inlet")
				var inside := _inside_room(room, center, size, straight_rotation) if over_room else _indoors(center, size, straight_rotation)
				if not inside or _overlaps_ceiling(center, footprint("vav", properties), straight_rotation):
					continue
				var placed := _place_vav(room, supply, supply_port, center, straight_rotation, properties, label)
				if not placed.is_empty():
					return placed
	# Otherwise try VAV spots in the room nearest the supply, every way round,
	# and keep the ones whose supply run is shortest and tidiest.
	var cells: Array = room.cells.duplicate()
	var supply_point: Vector3 = branch.position
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return PlanGrid.cell_center(a).distance_to(supply_point) < PlanGrid.cell_center(b).distance_to(supply_point))
	var options: Array = []
	for cell in cells.slice(0, 6):
		var spot := PlanGrid.cell_center(cell)
		for facing in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var rotation := atan2(-facing.z, facing.x)
			var point := snap(spot, "vav", properties, rotation)
			point.y = DuctPorts.ROUTE_HEIGHT - port_height("vav", properties, "inlet")
			if not _inside_room(room, point, size, rotation) or _overlaps_ceiling(point, footprint("vav", properties), rotation):
				continue
			var probe := _add("vav", point, rotation, properties.duplicate(true))
			var run := route(supply, supply_port, probe, "inlet")
			if not run.is_empty():
				options.append({"point": point, "rotation": rotation, "cost": _run_cost(run)})
				_drop(run)
			_drop(probe)
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.cost) < float(b.cost))
	for option in options.slice(0, 4):
		var placed := _place_vav(room, supply, supply_port, option.point, float(option.rotation), properties, label)
		if not placed.is_empty():
			return placed
	if error.is_empty():
		error = "Couldn't fit a VAV and its ducts in %s." % String(room.label)
	return {}

func _place_vav(room: Dictionary, supply: Dictionary, supply_port: String, point: Vector3, rotation: float, properties: Dictionary, label: String) -> Dictionary:
	var vav := _add("vav", point, rotation, properties.duplicate(true))
	vav.properties.label = label
	vav.properties.served_room = String(vav.id)
	vav.properties.bindings = Bindings.defaults("vav", String(vav.id))
	var run := route(supply, supply_port, vav, "inlet")
	if run.is_empty():
		_drop(vav)
		return {}
	if not _diffusers(vav, room):
		_drop(run)
		_drop(vav)
		return {}
	thermostat(vav, room)
	return vav

# The whole unit hangs over this room (corners checked), so its air and its
# label belong to it.
func _inside_room(room: Dictionary, center: Vector3, size: Vector3, rotation: float) -> bool:
	var half := Vector3(size.x, 0, size.z) * 0.5
	var turned := Basis(Vector3.UP, rotation)
	for corner in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, half.z), Vector3(half.x, 0, half.z), Vector3.ZERO]:
		var point: Vector3 = center + turned * (corner * 0.9)
		if String(index.room_at(point).get("id", "")) != String(room.id):
			return false
	return true

# Every corner is over some room (not hanging outside the building).
func _indoors(center: Vector3, size: Vector3, rotation: float) -> bool:
	var half := Vector3(size.x, 0, size.z) * 0.5
	var turned := Basis(Vector3.UP, rotation)
	for corner in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(-half.x, 0, half.z), Vector3(half.x, 0, half.z)]:
		if index.room_at(center + turned * (corner * 0.9)).is_empty():
			return false
	return true

func _overlaps_ceiling(center: Vector3, size: Vector2i, rotation: float) -> bool:
	var mine := {}
	for stud in Placement.footprint_studs(center, size, rotation): mine[stud] = true
	for item in objects:
		if String(item.kind) not in ["vav", "tee", "cross", "diffuser"]:
			continue
		var values: Array = item.transform.position
		if absf(float(values[1]) - center.y) > 1.6:
			continue
		for stud in Placement.footprint_studs(Vector3(float(values[0]), 0, float(values[2])), footprint(String(item.kind), item.properties), float(item.transform.get("rotation_y", 0.0))):
			if mine.has(stud): return true
	return false

# Diffusers hang downstream of the VAV: one straight off its outlet in small
# rooms, or a branch tee near the room's middle feeding two spread diffusers
# in big ones. Falls back to spots around the room centre.
func _diffusers(vav: Dictionary, room: Dictionary) -> bool:
	var fitting := {"label": "Diffuser", "capacity_m3_s": 0.45}
	if float(room.area_m2) >= 80.0 and _diffuser_pair(vav, room, fitting):
		return true
	return _diffuser_single(vav, room, fitting)

# Distances along `normal` from `origin`, nearest to the room centre first.
func _distances(origin: Vector3, normal: Vector3, room: Dictionary, shortest: float, longest: float) -> Array[float]:
	var ideal := ((room.center as Vector3) - origin).dot(normal)
	var result: Array[float] = []
	var d := shortest
	while d <= longest + 0.01:
		result.append(d)
		d += 0.5
	result.sort_custom(func(a: float, b: float) -> bool: return absf(a - ideal) < absf(b - ideal))
	return result

func _fits(kind: String, properties: Dictionary, point: Vector3, rotation: float, room: Dictionary) -> bool:
	var size: Vector3 = library.size(kind, properties) if library != null else Vector3(2, 1, 2)
	return _inside_room(room, point, size, rotation) and not _overlaps_ceiling(point, footprint(kind, properties), rotation)

# A diffuser whose side inlet faces back along `normal` to `port`, `distance`
# metres (centre) downstream of it.
func _diffuser_at(port: Dictionary, distance: float, fitting: Dictionary, room: Dictionary) -> Dictionary:
	var normal: Vector3 = port.normal
	var rotation := atan2(-normal.z, normal.x)
	var point: Vector3 = (port.position as Vector3) + normal * distance
	point.y = CEILING_FACE
	if not _fits("diffuser", fitting, point, rotation, room):
		return {}
	return _add("diffuser", point, rotation, fitting.duplicate())

func _diffuser_single(vav: Dictionary, room: Dictionary, fitting: Dictionary) -> bool:
	var outlet := DuctPorts.port(vav, "outlet")
	for distance in _distances(outlet.position, outlet.normal, room, 1.5, 6.0):
		var diffuser := _diffuser_at(outlet, distance, fitting, room)
		if diffuser.is_empty():
			continue
		if not route(vav, "outlet", diffuser, "inlet").is_empty():
			return true
		_drop(diffuser)
	# Anywhere else in the room, nearest its centre, facing the VAV.
	var vav_point := DuctPorts.vector(vav.transform.position)
	var cells: Array = room.cells.duplicate()
	var center: Vector3 = room.center
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return PlanGrid.cell_center(a).distance_to(center) < PlanGrid.cell_center(b).distance_to(center))
	for cell in cells.slice(0, 8):
		var spot := PlanGrid.cell_center(cell)
		var toward := (vav_point - spot) * Vector3(1, 0, 1)
		var rotation := roundf(atan2(toward.z, -toward.x) / (PI * 0.5)) * PI * 0.5 if toward.length() > 0.1 else 0.0
		var point := snap(spot, "diffuser", fitting, rotation)
		point.y = CEILING_FACE
		if not _fits("diffuser", fitting, point, rotation, room):
			continue
		var diffuser := _add("diffuser", point, rotation, fitting.duplicate())
		if not route(vav, "outlet", diffuser, "inlet").is_empty():
			return true
		_drop(diffuser)
	return false

func _diffuser_pair(vav: Dictionary, room: Dictionary, fitting: Dictionary) -> bool:
	var outlet := DuctPorts.port(vav, "outlet")
	var along := outlet.normal as Vector3
	var tee_props := {"label": "Branch tee", "capacity_m3_s": 1.0}
	var tee_rotation := atan2(along.x, along.z)
	var reach := absf(float((library.port_local("tee", tee_props, "inlet").get("face", Vector3(0, 0, -1)) as Vector3).z)) if library != null else 1.0
	for distance in _distances(outlet.position, along, room, reach + 0.5, 7.0):
		var point: Vector3 = (outlet.position as Vector3) + along * distance
		point.y = DuctPorts.ROUTE_HEIGHT - port_height("tee", tee_props, "inlet")
		if not _fits("tee", tee_props, point, tee_rotation, room):
			continue
		var tee := _add("tee", point, tee_rotation, tee_props.duplicate())
		var run := route(vav, "outlet", tee, "inlet")
		if run.is_empty():
			_drop(tee)
			continue
		var placed: Array = []
		for name in ["outlet_a", "outlet_b"]:
			var port := DuctPorts.port(tee, name)
			# Spread the pair: the farthest spot that still fits the room.
			var spots := _distances(port.position, port.normal, room, 1.5, 6.0)
			spots.sort()
			spots.reverse()
			for spot in spots:
				var diffuser := _diffuser_at(port, spot, fitting, room)
				if diffuser.is_empty():
					continue
				if not route(tee, name, diffuser, "inlet").is_empty():
					placed.append(diffuser)
					break
				_drop(diffuser)
		if placed.size() == 2:
			return true
		# Undo this attempt entirely (ducts to placed diffusers included).
		for item in entries.duplicate():
			if item.kind == "duct" and (String(item.properties.start_port.get("owner", "")) == String(tee.id) or String(item.properties.end_port.get("owner", "")) == String(tee.id)):
				_drop(item)
		for diffuser in placed: _drop(diffuser)
		_drop(tee)
	return false

# Nearest cell centre of the room when a point falls outside an L-shape.
func _inside(room: Dictionary, point: Vector3) -> Vector3:
	if String(index.room_at(point).get("id", "")) == String(room.id):
		return point
	var best: Vector3 = PlanGrid.cell_center(room.cells[0])
	for cell in room.cells:
		if PlanGrid.cell_center(cell).distance_to(point) < best.distance_to(point):
			best = PlanGrid.cell_center(cell)
	return best

# The thermostat hangs on a plain wall of the room, nearest its door.
func thermostat(vav: Dictionary, room: Dictionary) -> Dictionary:
	var candidates: Array[String] = []
	var anchor: Vector3 = room.center
	if not room.doors.is_empty():
		anchor = PlanGrid.edge_center(String(room.doors[0].edge))
	for cell in room.cells:
		for edge in PlanGrid.cell_edges(cell):
			if index.has_wall(edge) and index.opening(edge).is_empty() and edge not in candidates:
				candidates.append(edge)
	for item in objects:
		if item.kind == "tstat": candidates.erase(String(item.properties.get("edge", "")))
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: String, b: String) -> bool: return PlanGrid.edge_center(a).distance_to(anchor) < PlanGrid.edge_center(b).distance_to(anchor))
	var edge := candidates[0]
	var center := PlanGrid.edge_center(edge)
	var normal := PlanGrid.edge_normal(edge)
	var inward := normal if String(index.room_at(center + normal * 0.6).get("id", "")) == String(room.id) else -normal
	var position := center + inward * (PlanGrid.STUD * 0.5) + Vector3(0, PlanGrid.FLOOR_TOP + THERMOSTAT_HEIGHT, 0)
	return _add("tstat", position, atan2(inward.x, inward.z), {"label": "Thermostat · " + String(room.label), "edge": edge, "side": 1 if inward.dot(normal) > 0 else -1, "vav_id": String(vav.id)})
