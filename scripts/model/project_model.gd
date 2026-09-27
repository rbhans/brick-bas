class_name ProjectModel
extends RefCounted

# Versioned, JSON-safe project document. Every placed thing is one object:
#   {id, kind, floor_id, transform: {position: [x, y, z], rotation_y}, properties}
#
# Architecture lives on the PlanGrid:
#   wall     properties.edge = "x:i:j" | "z:i:j", properties.style
#   door     properties.edge, properties.style, properties.swing (+1/-1)
#   window   properties.edge, properties.style
#   floor    properties.cell = [i, j], properties.finish
#   furniture properties.item (catalogue id), free stud-snapped transform
# Equipment and ducts keep their own property schemas (see duct_connections).

const FORMAT_VERSION := 2
const SaveValidator := preload("res://scripts/model/save_validator.gd")
const Migration := preload("res://scripts/model/migrate_v1.gd")

var project_id := "sandbox"
var next_id := 1
var floors: Array[Dictionary] = []
var rooms: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var bindings: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var demo_checkpoint: Dictionary = {}
var complete_scene := true
var site: Dictionary = {}
var migrated_from := 0
var _index: Dictionary = {}

func _init() -> void:
	floors = [{"id": "floor-1", "name": "Ground Floor", "elevation_m": 0.0}]
	site = default_site()

static func default_site() -> Dictionary:
	return {"starter": "blank", "name": "Blank canvas", "spawn": [1.25, 1.0, 1.25], "open_doors": {}, "room_names": {}, "room_types": {}, "camera": {}}

func new_id(prefix: String) -> String:
	var result := "%s-%04d" % [prefix, next_id]
	next_id += 1
	while _index.has(result):
		result = "%s-%04d" % [prefix, next_id]
		next_id += 1
	return result

func add_object(kind: String, transform_data: Dictionary, properties: Dictionary = {}, id: String = "") -> Dictionary:
	var item := {
		"id": id if not id.is_empty() and not _index.has(id) else new_id(kind), "kind": kind, "floor_id": "floor-1",
		"transform": transform_data.duplicate(true), "properties": properties.duplicate(true)
	}
	objects.append(item)
	_index[item.id] = item
	return item

func remove_object(object_id: String) -> Dictionary:
	if not _index.has(object_id):
		return {}
	for index in range(objects.size()):
		if String(objects[index].id) == object_id:
			_index.erase(object_id)
			return objects.pop_at(index)
	_index.erase(object_id)
	return {}

func restore_object(item: Dictionary) -> void:
	var copy := item.duplicate(true)
	if _index.has(String(copy.id)):
		replace_object(copy)
		return
	objects.append(copy)
	_index[copy.id] = copy

func replace_object(item: Dictionary) -> bool:
	var current: Dictionary = _index.get(String(item.id), {})
	if current.is_empty():
		return false
	current.kind = item.kind
	current.transform = item.transform.duplicate(true)
	current.properties = item.properties.duplicate(true)
	return true

func find_object(object_id: String) -> Dictionary:
	return _index.get(object_id, {})

func has_object(object_id: String) -> bool:
	return _index.has(object_id)

func objects_of(kinds: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in objects:
		if item.kind in kinds:
			result.append(item)
	return result

func set_object_transform(object_id: String, transform_data: Dictionary) -> bool:
	var item := find_object(object_id)
	if item.is_empty():
		return false
	item.transform = transform_data.duplicate(true)
	return true

func set_object_properties(object_id: String, properties: Dictionary) -> bool:
	var item := find_object(object_id)
	if item.is_empty():
		return false
	item.properties = properties.duplicate(true)
	return true

func rebuild_index() -> void:
	_index.clear()
	for item in objects:
		_index[String(item.id)] = item

func to_dictionary() -> Dictionary:
	return {
		"format": "bas-sandbox-project", "version": FORMAT_VERSION,
		"project_id": project_id, "next_id": next_id,
		"floors": floors, "rooms": rooms, "objects": objects,
		"routes": routes, "bindings": bindings, "connections": connections,
		"demo_checkpoint": demo_checkpoint,
		"complete_scene": complete_scene,
		"site": site,
	}

func from_dictionary(data: Dictionary) -> bool:
	if data.get("format") == "bas-sandbox-project" and int(data.get("version", 0)) == 1:
		if not SaveValidator.valid_v1(data):
			return false
		data = Migration.migrate(data)
		migrated_from = 1
	if not SaveValidator.valid(data):
		return false
	project_id = String(data.get("project_id", "loaded-project"))
	next_id = maxi(1, int(data.get("next_id", 1)))
	floors.assign(data.get("floors", []))
	rooms.assign(data.get("rooms", []))
	objects.assign(data.get("objects", []))
	routes.assign(data.get("routes", []))
	bindings.assign(data.get("bindings", []))
	connections.clear()
	for profile in data.get("connections", []):
		var safe := {}
		for key in ["id", "name", "station_url", "username", "tls_mode"]:
			if profile.get(key) is String: safe[key] = profile[key]
		connections.append(safe)
	demo_checkpoint = data.get("demo_checkpoint", {}).duplicate(true)
	complete_scene = true
	site = default_site()
	site.merge(data.get("site", {}).duplicate(true), true)
	rebuild_index()
	return true

func save_to(path: String) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "  "))
	file.flush()
	file.close()
	var error := DirAccess.rename_absolute(temporary, path)
	if error == OK and OS.has_feature("web"): JavaScriptBridge.force_fs_sync()
	return error

func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() > 8 * 1024 * 1024: return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed is Dictionary and from_dictionary(parsed)
