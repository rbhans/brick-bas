extends SceneTree

# Prints each baked LDraw mesh's bounds (Godot metres, LDraw origin preserved).
func _init() -> void:
	var names := []
	for file in DirAccess.get_files_at("res://assets/third_party/ldraw/meshes"):
		if file.ends_with(".obj"): names.append(file.trim_suffix(".obj"))
	names.sort()
	for id in names:
		var mesh := load("res://assets/third_party/ldraw/meshes/%s.obj" % id) as Mesh
		var a := mesh.get_aabb()
		print("%-10s min(%6.3f %6.3f %6.3f) max(%6.3f %6.3f %6.3f) size(%5.2f %5.2f %5.2f)" % [id, a.position.x, a.position.y, a.position.z, a.end.x, a.end.y, a.end.z, a.size.x, a.size.y, a.size.z])
	quit(0)
