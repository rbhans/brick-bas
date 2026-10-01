extends SceneTree

# Loads every script under res://scripts so parse and type errors surface
# without running the game.  Godot --headless --path . --script res://tools/compile_check.gd

func _init() -> void:
	var failed: Array[String] = []
	var count := 0
	for path in _scripts("res://scripts"):
		count += 1
		var script: Variant = load(path)
		if script == null or not (script as Script).can_instantiate():
			failed.append(path)
	print("COMPILE_CHECK %s scripts=%d failed=%s" % ["PASS" if failed.is_empty() else "FAIL", count, str(failed)])
	quit(0 if failed.is_empty() else 1)

func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"): out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	return out
