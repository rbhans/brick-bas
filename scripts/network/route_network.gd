class_name RouteNetwork
extends RefCounted

# Directed supply-air graph built from the actual connected duct sockets.
# Air travels AHU outlet -> ducts/tees -> VAV inlet -> VAV outlet -> diffusers.
# Output is keyed by VAV id (terminal) so the simulation can serve each zone.

const Ports := preload("res://scripts/build/duct_connections.gd")

static func evaluate(objects: Array) -> Dictionary:
	var adjacency: Dictionary = {}
	var edge_routes: Dictionary = {}
	var routes: Dictionary = {}
	var units: Dictionary = {}
	for item in objects:
		if item.kind == "ahu":
			units[String(item.id)] = {"label": String(item.properties.get("label", item.id)), "capacity_m3_s": maxf(0.0, float(item.properties.get("capacity_m3_s", 1.2))), "layout": layout(item.properties)}
		if item.kind == "duct":
			routes[String(item.id)] = {"weights": {}, "capacity_m3_s": maxf(0.0, float(item.properties.get("capacity_m3_s", 1.2)))}
		for port_name in Ports.port_names(item):
			adjacency[_key(String(item.id), port_name)] = []
	for item in objects:
		match String(item.kind):
			"ahu", "vav": _edge(adjacency, _key(item.id, "inlet"), _key(item.id, "outlet"))
			"tee":
				_edge(adjacency, _key(item.id, "inlet"), _key(item.id, "outlet_a"))
				_edge(adjacency, _key(item.id, "inlet"), _key(item.id, "outlet_b"))
			"cross":
				for outlet in ["outlet", "branch_a", "branch_b"]:
					_edge(adjacency, _key(item.id, "inlet"), _key(item.id, outlet))
	for item in objects:
		if item.kind != "duct" or not bool(item.properties.get("enabled", true)):
			continue
		if not item.properties.has("start_port") or not item.properties.has("end_port"):
			continue
		if Ports.route_error(item.properties, objects, String(item.id)) != "":
			continue
		var first := Ports.resolve(item.properties.start_port, objects)
		var second := Ports.resolve(item.properties.end_port, objects)
		if first.is_empty() or second.is_empty():
			continue
		var from := _key(first.owner, first.port) if first.direction == "out" else _key(second.owner, second.port)
		var to := _key(second.owner, second.port) if first.direction == "out" else _key(first.owner, first.port)
		_edge(adjacency, from, to)
		edge_routes[from + ">" + to] = String(item.id)
	var reachable := {}
	var by_source := {}
	for item in objects:
		if item.kind == "ahu":
			by_source[String(item.id)] = _walk(adjacency, _key(item.id, "outlet"))
			reachable.merge(by_source[String(item.id)])
	var terminals: Dictionary = {}
	var limits: Dictionary = routes.duplicate(true)
	for item in objects:
		if item.kind in ["ahu", "vav", "tee", "cross", "diffuser"]:
			limits[String(item.id)] = {"weights": {}, "capacity_m3_s": maxf(0.0, float(item.properties.get("capacity_m3_s", 0.45 if item.kind in ["vav", "diffuser"] else 1.2)))}
	for item in objects:
		if item.kind != "vav":
			continue
		var vav_id := String(item.id)
		var sources: Array[String] = []
		for id in by_source:
			if by_source[id].has(_key(vav_id, "inlet")): sources.append(String(id))
		var diffusers: Array[String] = []
		var downstream := _walk(adjacency, _key(vav_id, "outlet"))
		for diffuser in objects:
			if diffuser.kind == "diffuser" and downstream.has(_key(diffuser.id, "inlet")): diffusers.append(String(diffuser.id))
		var connected := sources.size() == 1 and not diffusers.is_empty()
		terminals[vav_id] = {"label": String(item.properties.get("label", vav_id)), "connected": connected, "capacity_m3_s": float(limits[vav_id].capacity_m3_s), "upstream": not sources.is_empty(), "terminal": not diffusers.is_empty(), "source_id": sources[0] if sources.size() == 1 else "", "layout": layout(item.properties), "diffusers": diffusers}
		if not connected: continue
		# Equal diffuser splits along deterministic shortest paths: a bounded
		# gameplay flow network, not a duct pressure solver.
		var upstream := _path(adjacency, _key(sources[0], "outlet"), _key(vav_id, "inlet"))
		for terminal in diffusers:
			var path: Array[String] = upstream.duplicate()
			path.append_array(_path(adjacency, _key(vav_id, "outlet"), _key(terminal, "inlet")))
			var resources := {}
			for index in range(path.size()):
				resources[path[index].left(path[index].rfind("."))] = true
				if index > 0:
					var edge := path[index - 1] + ">" + path[index]
					if edge_routes.has(edge): resources[edge_routes[edge]] = true
			for resource in resources:
				if limits.has(resource): limits[resource].weights[vav_id] = float(limits[resource].weights.get(vav_id, 0.0)) + 1.0 / diffusers.size()
	for id in routes: routes[id] = limits[id].duplicate(true)
	return {"terminals": terminals, "units": units, "limits": limits, "routes": routes, "reachable_ports": reachable, "route_count": routes.size()}

static func layout(properties: Dictionary) -> Array:
	if properties.has("component_records") and not properties.component_records.is_empty():
		return properties.component_records.map(func(record: Dictionary) -> String: return String(record.role))
	if properties.has("layout"): return properties.layout.duplicate()
	return properties.get("components", {}).keys().filter(func(role: String) -> bool: return bool(properties.components[role]))

static func _path(adjacency: Dictionary, origin: String, target: String) -> Array[String]:
	var parents := {origin: ""}
	var frontier: Array[String] = [origin]
	while not frontier.is_empty():
		var current := frontier.pop_front() as String
		if current == target:
			var result: Array[String] = []
			while not current.is_empty():
				result.push_front(current)
				current = parents[current]
			return result
		for next in adjacency.get(current, []):
			if not parents.has(next):
				parents[next] = current
				frontier.append(String(next))
	return []

static func _key(owner: String, port: String) -> String:
	return owner + "." + port

static func _edge(adjacency: Dictionary, from: String, to: String) -> void:
	if adjacency.has(from) and adjacency.has(to):
		adjacency[from].append(to)

static func _walk(adjacency: Dictionary, origin: String) -> Dictionary:
	var result: Dictionary = {}
	var frontier: Array[String] = [origin]
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		if result.has(current): continue
		result[current] = true
		for next in adjacency.get(current, []): frontier.append(String(next))
	return result
