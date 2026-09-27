extends PanelContainer

# The first-run tour: four short steps under the mode tabs that walk a new
# player from building rooms to watching the HVAC run and walking inside.
# Each step switches to the mode it talks about. Shown once after the first
# starter is picked; Menu → "Show the quick tour" brings it back.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const STEPS := [
	{"mode": 0, "title": "1 · Build", "text": "This building is yours to change. Pick Room in the tray and drag a rectangle: walls and floor go down together. Right-drag orbits, the wheel zooms, V lowers the walls."},
	{"mode": 1, "title": "2 · Equipment", "text": "Every room needs air. An air handler feeds VAV boxes, and each VAV feeds its room's diffusers. Pick Zone a room, then click a room: the ducts route themselves."},
	{"mode": 1, "title": "3 · Watch it run", "text": "Click any unit for its live readout and trend. B tints rooms by temperature, the clock's arrows speed up the day, and Menu → Simulation has faults to troubleshoot."},
	{"mode": 2, "title": "4 · Explore", "text": "Walk inside: WASD to move, E to adjust a thermostat, open a VAV's casing or show the airflow at a diffuser. Tab goes back to building."},
]

var game: Node
var step := 0
var heading: Label
var body: Label
var back_button: Button
var next_button: Button

func setup(owner: Node) -> void:
	game = owner
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -250
	offset_right = 250
	offset_top = 84
	add_theme_stylebox_override("panel", UIKit.glass_style(14, 0.95))
	z_index = 15
	var column := UIKit.column(self, 8)
	heading = UIKit.label(column, "", 17, Color("ffcf45"))
	heading.add_theme_font_override("font", ToySkin.font(800))
	body = UIKit.label(column, "", 13, Color("e4ebed"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 470
	var buttons := UIKit.row(column, 8)
	UIKit.button(buttons, "Skip tour", finish)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	back_button = UIKit.button(buttons, "Back", func() -> void: show_step(step - 1))
	next_button = UIKit.button(buttons, "Next", func() -> void: show_step(step + 1) if step < STEPS.size() - 1 else finish())
	hide()

func start() -> void:
	show()
	show_step(0)

func show_step(index: int) -> void:
	step = clampi(index, 0, STEPS.size() - 1)
	var entry: Dictionary = STEPS[step]
	heading.text = String(entry.title)
	body.text = String(entry.text)
	back_button.disabled = step == 0
	next_button.text = "Done" if step == STEPS.size() - 1 else "Next"
	if game.mode != int(entry.mode):
		game.set_mode(int(entry.mode))

func finish() -> void:
	hide()
	Settings.store("tour_done", true)
