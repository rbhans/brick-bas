class_name BuildCommandStack
extends RefCounted

# Every edit is one transaction: a list of per-object {before, after} snapshots.
# A room drag, a sledgehammer sweep or a group paint is a single undo step.

var model: RefCounted
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
const LIMIT := 200

func _init(value: RefCounted) -> void:
	model = value

# adds: Array of {kind, transform, properties[, id]}; removes: ids; updates: full items.
func apply(label: String, adds: Array = [], removes: Array = [], updates: Array = []) -> Dictionary:
	var changes: Array = []
	var added: Array[Dictionary] = []
	for id in removes:
		var removed: Dictionary = model.remove_object(String(id))
		if not removed.is_empty():
			changes.append({"before": removed.duplicate(true), "after": {}})
	for item in updates:
		var current: Dictionary = model.find_object(String(item.id))
		if current.is_empty():
			continue
		var before := current.duplicate(true)
		model.replace_object(item)
		changes.append({"before": before, "after": model.find_object(String(item.id)).duplicate(true)})
	for entry in adds:
		var item: Dictionary = model.add_object(String(entry.kind), entry.get("transform", {"position": [0, 0, 0], "rotation_y": 0.0}), entry.get("properties", {}), String(entry.get("id", "")))
		added.append(item)
		changes.append({"before": {}, "after": item.duplicate(true)})
	if not changes.is_empty():
		undo_stack.append({"action": label, "changes": changes, "item": added[-1] if not added.is_empty() else {}})
		if undo_stack.size() > LIMIT:
			undo_stack.pop_front()
		redo_stack.clear()
	return {"added": added, "changed": changes.size()}

func undo() -> Dictionary:
	if undo_stack.is_empty():
		return {}
	var command: Dictionary = undo_stack.pop_back()
	var changes: Array = command.changes
	for index in range(changes.size() - 1, -1, -1):
		_revert(changes[index].after, changes[index].before)
	redo_stack.append(command)
	return command

func redo() -> Dictionary:
	if redo_stack.is_empty():
		return {}
	var command: Dictionary = redo_stack.pop_back()
	for change in command.changes:
		_revert(change.before, change.after)
	undo_stack.append(command)
	return command

func _revert(current: Dictionary, target: Dictionary) -> void:
	if target.is_empty():
		model.remove_object(String(current.id))
	elif current.is_empty():
		model.restore_object(target)
	else:
		model.replace_object(target)

# --- Convenience wrappers --------------------------------------------------

func add_object(kind: String, transform_data: Dictionary, properties: Dictionary = {}) -> Dictionary:
	var result := apply("add " + kind, [{"kind": kind, "transform": transform_data, "properties": properties}])
	return result.added[0] if not result.added.is_empty() else {}

func add_objects(entries: Array) -> Array[Dictionary]:
	return apply("add", entries).added

func delete_object(object_id: String) -> Dictionary:
	var item: Dictionary = model.find_object(object_id).duplicate(true)
	if item.is_empty():
		return {}
	apply("delete " + String(item.kind), [], [object_id])
	return item

func delete_objects(ids: Array) -> int:
	return int(apply("delete", [], ids).changed)

func move_object(object_id: String, transform_data: Dictionary) -> bool:
	var item: Dictionary = model.find_object(object_id).duplicate(true)
	if item.is_empty():
		return false
	item.transform = transform_data.duplicate(true)
	return int(apply("move " + String(item.kind), [], [], [item]).changed) > 0

func update_properties(object_id: String, properties: Dictionary) -> bool:
	var item: Dictionary = model.find_object(object_id).duplicate(true)
	if item.is_empty():
		return false
	item.properties = properties.duplicate(true)
	return int(apply("edit " + String(item.kind), [], [], [item]).changed) > 0

func update_objects(items: Array) -> void:
	apply("edit", [], [], items)

func can_undo() -> bool:
	return not undo_stack.is_empty()

func can_redo() -> bool:
	return not redo_stack.is_empty()
