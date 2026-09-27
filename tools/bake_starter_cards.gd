extends SceneTree

# Renders the home-screen starter cards from the real game: each template is
# built, its walls cut away so rooms, furniture and ductwork show, the HUD
# hidden, and a 16:10 crop saved to res://assets/ui/thumbnails/starter_*.png.
# Run windowed (it needs a renderer):
#   Godot --path . --script res://tools/bake_starter_cards.gd

const SIZE := Vector2i(576, 360)
const VIEWS := {
	# target x, target z, yaw, pitch, distance
	"studio": [2.0, -3.5, 0.62, -0.78, 44.0],
	"office": [0.0, 0.5, 0.55, -0.82, 56.0],
	"school": [6.5, 1.5, 0.5, -0.86, 88.0],
	"blank": [0.0, 0.0, 0.62, -0.8, 34.0],
}

func _init() -> void:
	bake.call_deferred()

func bake() -> void:
	var app: Node = load("res://scripts/game.gd").new()
	root.add_child(app)
	await process_frame
	app.session_ui.hide()
	app.sound_enabled = false
	app.hud.get_parent().visible = false
	for id in VIEWS:
		app.start_new_game(String(id), false)
		app.overlay_by_mode[1] = false
		app.set_mode(1)
		app.set_wall_mode(2)
		app.room_labels.visible = false
		app.explorer.figure.visible = false
		# Equipment name tags are too small to read on a card.
		for label in app.equipment.find_children("*", "Label3D", true, false):
			if label.has_meta("bas_tag"): label.visible = false
		var view: Array = VIEWS[id]
		app.rig.set_view(Vector3(view[0], 0.5, view[1]), view[2], view[3], view[4], true)
		for frame in range(30): await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		# Centre crop to 16:10, then scale to the card size.
		var width := image.get_width()
		var height := image.get_height()
		var crop := Vector2i(width, int(width * 10.0 / 16.0)) if width * 10 <= height * 16 else Vector2i(int(height * 16.0 / 10.0), height)
		image = image.get_region(Rect2i((Vector2i(width, height) - crop) / 2, crop))
		image.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
		image.convert(Image.FORMAT_RGB8)
		var path := "res://assets/ui/thumbnails/starter_%s.png" % id
		print("STARTER ", path, " ", error_string(image.save_png(ProjectSettings.globalize_path(path))))
	quit()
