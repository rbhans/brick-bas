extends SceneTree

const Model := preload("res://scripts/model/project_model.gd")
const Templates := preload("res://scripts/model/templates.gd")
var failures: Array[String] = []
var checks := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _init() -> void:
	var original := Templates.create("office")
	var good: Dictionary = JSON.parse_string(JSON.stringify(original.to_dictionary()))
	var loaded := Model.new()
	expect(loaded.from_dictionary(good), "current starter schema accepted")
	var before: Dictionary = loaded.to_dictionary().duplicate(true)
	for mutation in ["version", "array", "object", "transform", "position", "duplicate", "paint", "binding", "camera", "checkpoint", "component", "path", "numeric", "edge", "kind", "names"]:
		var bad: Dictionary = good.duplicate(true)
		match mutation:
			"version": bad.version = 999
			"array": bad.rooms = "broken"
			"object": bad.objects[0] = null
			"transform": bad.objects[0].transform = []
			"position": bad.objects[0].transform.position = [1, 2]
			"duplicate": bad.objects.append(bad.objects[0].duplicate(true))
			"paint": bad.objects[0].properties.paint = {"wall": []}
			"binding": bad.objects[0].properties.bindings = {"fan": "bad"}
			"camera": bad.site.camera = {"target": [1]}
			"checkpoint": bad.demo_checkpoint = {"sim_seconds": "noon"}
			"edge": bad.objects[0].properties.edge = "q:1"
			"kind": bad.objects[0].kind = "spaceship"
			"names": bad.site.room_names = {"0:0": 5}
			"component": bad.objects[0].properties.component_records = ["bad"]
			"path": bad.objects[0].properties.waypoints = [[1]]
			"numeric": bad.objects[0].transform.rotation_y = INF
		expect(not loaded.from_dictionary(bad), mutation + " rejected")
		expect(loaded.to_dictionary() == before, mutation + " does not partially replace the current build")
	good.connections = [{"id": "example", "station_url": "https://example.invalid", "username": "test", "password": "never-persist-this", "cookie": "never-persist-this"}]
	expect(loaded.from_dictionary(good), "connection profile accepted")
	expect(not JSON.stringify(loaded.to_dictionary()).contains("never-persist-this"), "import strips passwords and cookies")
	var dir := "res://artifacts/web-review"
	DirAccess.make_dir_recursive_absolute(dir)
	original.project_id = "browser-restore-check"
	original.site.name = "Browser restore check"
	expect(original.save_to(dir + "/backup.json") == OK, "valid browser import fixture written")
	var file := FileAccess.open(dir + "/invalid.json", FileAccess.WRITE)
	file.store_string('{"format":"bas-sandbox-project","version":999}')
	file.close()
	print("BROWSER_SAVE_TESTS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
