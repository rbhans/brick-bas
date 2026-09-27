extends SceneTree

func _init() -> void:
	var text := "GODOT ENGINE\n\n" + Engine.get_license_text() + "\n\nTHIRD-PARTY COPYRIGHTS\n\n"
	text += JSON.stringify(Engine.get_copyright_info(), "  ")
	text += "\n\nTHIRD-PARTY LICENSE TEXTS\n\n" + JSON.stringify(Engine.get_license_info(), "  ")
	var file := FileAccess.open("res://dist/web/GODOT-LICENSES.txt", FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string(text)
	file.close()
	quit()
