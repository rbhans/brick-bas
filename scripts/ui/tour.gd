extends PanelContainer

# The first-run tour: four short steps under the mode tabs that walk a new
# player from building rooms to watching the HVAC run and walking inside.
# Each step switches to the mode it talks about. Shown once after the first
# starter is picked; Menu → "Show the quick tour" brings it back.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const STEPS := [
	{"mode": 0, "title": "Build", "text": "This building is yours to change. Pick Room in the tray and drag a rectangle: walls and floor go down together. Right-drag orbits, the wheel zooms, V lowers the walls."},
	{"mode": 1, "title": "Equipment", "text": "Every room needs air. An air handler feeds VAV boxes, and each VAV feeds its room's diffusers. Pick Zone a room, then click a room: the ducts route themselves."},
	{"mode": 1, "title": "Watch it run", "text": "Click any unit for its live readout and trend. B tints rooms by temperature, the clock's arrows speed up the day, and Menu, Simulation has faults to troubleshoot."},
	{"mode": 2, "title": "Explore", "text": "Walk inside: WASD to move, E to adjust a thermostat, open a VAV's casing or show the airflow at a diffuser. Tab goes back to building."},
]

var game: Node
var step := 0
var eyebrow: Label
var heading: Label
var body: Label
var dots: Control
var back_button: Button
var next_button: Button

func setup(owner: Node) -> void:
	game = owner
	theme = ToySkin.create()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -260
	offset_right = 260
	offset_top = 96
	add_theme_stylebox_override("panel", ToySkin.card(0.98, 20))
	z_index = 15
	var column := UIKit.column(self, 8)
	var top := UIKit.row(column, 8)
	eyebrow = UIKit.section(top, "Quick tour", ToySkin.YELLOW)
	UIKit.spacer(top)
	dots = Control.new()
	dots.custom_minimum_size = Vector2(STEPS.size() * 14, 10)
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dots.draw.connect(func() -> void:
		for index in range(STEPS.size()):
			var current := index == step
			dots.draw_circle(Vector2(5 + index * 14, 5), 4.0 if current else 3.0, ToySkin.YELLOW if current else Color(ToySkin.TEXT, 0.25), true, -1, true))
	top.add_child(dots)
	heading = UIKit.title(column, "", ToySkin.SIZE_HEADING)
	body = UIKit.text(column, "", ToySkin.SIZE_LABEL, ToySkin.TEXT_2)
	body.custom_minimum_size.x = 480
	body.add_theme_constant_override("line_spacing", 4)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	column.add_child(gap)
	var buttons := UIKit.row(column, 8)
	UIKit.button(buttons, "Skip tour", finish, "GhostButton")
	UIKit.spacer(buttons)
	back_button = UIKit.button(buttons, "Back", func() -> void: show_step(step - 1))
	next_button = UIKit.button(buttons, "Next", func() -> void: show_step(step + 1) if step < STEPS.size() - 1 else finish(), "PrimaryButton")
	next_button.custom_minimum_size.x = 96
	hide()

func start() -> void:
	if not visible: UIKit.pop_in(self, game.reduced_motion)
	show()
	show_step(0)

func show_step(index: int) -> void:
	step = clampi(index, 0, STEPS.size() - 1)
	var entry: Dictionary = STEPS[step]
	eyebrow.text = "QUICK TOUR · %d OF %d" % [step + 1, STEPS.size()]
	heading.text = String(entry.title)
	body.text = String(entry.text)
	dots.queue_redraw()
	back_button.disabled = step == 0
	next_button.text = "Done" if step == STEPS.size() - 1 else "Next"
	if game.mode != int(entry.mode):
		game.set_mode(int(entry.mode))

func finish() -> void:
	hide()
	Settings.store("tour_done", true)
