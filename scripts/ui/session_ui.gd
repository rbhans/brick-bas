extends Control

# Title screen and starter picker. Starters are hand-authored, furnished and
# already running; every piece stays editable.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const Templates := preload("res://scripts/model/templates.gd")

var app: Node
var body: VBoxContainer
var welcome := false

func setup(owner_node: Node) -> void:
	app = owner_node
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = ToySkin.create()
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.075, 0.09, 0.9)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 760
	panel.add_theme_stylebox_override("panel", UIKit.glass_style(20, 0.98))
	center.add_child(panel)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	panel.add_child(body)
	hide()

func clear() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	show()

func title(text: String, size_value: int = 24, colour: Color = Color(0, 0, 0, 0)) -> Label:
	var label := UIKit.label(body, text, size_value, colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func action(text: String, callback: Callable, parent: Node = body) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func show_home() -> void:
	clear()
	welcome = true
	var brand := title("BRICK / BAS", 44, ToySkin.YELLOW)
	brand.add_theme_font_override("font", ToySkin.font(800))
	title("Build a brick building, bring its systems to life, and walk inside.", 17)
	action("New game · choose a starter", show_starters)
	var load_button := action("Continue my saved build", func() -> void: if app.load_project(): hide(); welcome = false)
	load_button.disabled = not app.has_save()
	if OS.has_feature("web"):
		action("Import a build backup", func() -> void: app.browser_files.choose())
		title("Saves stay in this browser. Download a backup before clearing site data.", 12, Color("9aa8ad"))

func show_starters() -> void:
	clear()
	title("Choose a starter", 30).add_theme_font_override("font", ToySkin.font(800))
	title("Furnished, zoned and already running. Change anything — or start from an empty lot.", 14, Color("b9c4c7"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for spec in Templates.PRESETS:
		var id: String = spec.id
		var card := Button.new()
		card.custom_minimum_size = Vector2(360, 212)
		card.pressed.connect(func() -> void: app.start_new_game(id); welcome = false; hide(); app.maybe_start_tour())
		grid.add_child(card)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		content.offset_left = 10
		content.offset_right = -10
		content.offset_top = 8
		content.offset_bottom = -8
		content.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(content)
		var picture := TextureRect.new()
		picture.texture = UIKit.thumbnail("starter_" + id)
		picture.custom_minimum_size.y = 118
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.mouse_filter = MOUSE_FILTER_IGNORE
		content.add_child(picture)
		var header := HBoxContainer.new()
		header.mouse_filter = MOUSE_FILTER_IGNORE
		content.add_child(header)
		var name_label := UIKit.label(header, String(spec.name), 17)
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.mouse_filter = MOUSE_FILTER_IGNORE
		UIKit.label(header, String(spec.size), 12, Color("9aa8ad")).mouse_filter = MOUSE_FILTER_IGNORE
		var hint := UIKit.label(content, String(spec.detail), 12, Color("b9c4c7"))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.mouse_filter = MOUSE_FILTER_IGNORE
	action("Back" if welcome else "Keep building", show_home if welcome else hide)

func refresh_readout() -> void:
	pass
