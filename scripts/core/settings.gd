class_name Settings
extends RefCounted

# Player preferences that outlive a session (in the browser they live in the
# site's storage next to the saves): graphics quality, motion, sound and
# whether the first-run tour has been seen.

const PATH := "user://settings.cfg"
const DEFAULTS := {"graphics": "auto", "reduced_motion": false, "sounds": true, "tour_done": false}

static func load_all() -> Dictionary:
	var values: Dictionary = DEFAULTS.duplicate()
	var file := ConfigFile.new()
	if file.load(PATH) == OK:
		for key in DEFAULTS:
			var value: Variant = file.get_value("player", key, DEFAULTS[key])
			if typeof(value) == typeof(DEFAULTS[key]): values[key] = value
	return values

static func store(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	var file := ConfigFile.new()
	file.load(PATH)
	file.set_value("player", key, value)
	file.save(PATH)
