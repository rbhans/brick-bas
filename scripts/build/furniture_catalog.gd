class_name FurnitureCatalog
extends RefCounted

# Minifig-scale furniture built only from official LDraw parts at native scale
# (1 LDU = 0.025 m). Every item is a small "set build": recognisable at the
# isometric camera, <= ~40 pieces, plain Bricks pieces so the architecture
# renderer can batch them. Animated bits (doors) sit under a Node3D with meta
# "dynamic" so BrickBatch.absorb leaves them live.
#
# Local frame of every item:
#   * origin = centre of the footprint on the surface it stands on (y = 0 is
#     the floor-tile top); length along +X, depth along Z;
#   * FRONT faces +Z: a chair's seat faces +Z, a desk's user side is +Z;
#   * wall items: origin is the wall-face contact point on the floor line
#     under the item, the item grows toward +Z from z = 0 and upward to its
#     mounting height (the footprint spans z = 0 .. depth).
#
# Scale reference: stud 0.5 m, plate 0.2 m, brick 0.6 m. A minifigure (the
# game's 0.9 scale) is ~2.25 m tall with its hip joint at ~0.63 m. Seated,
# its lowest point is ~0.4 m below the hip joint. Desks and tables are 1.4 m
# tall (knee room 1.2 m), chair seats 0.6-0.8 m, counters 1.4 m.
#
# build() returns:
#   collision:    [{size: Vector3, center: Vector3}]          local boxes
#   seats:        [{position, facing, forward}]  position = seat surface point
#                 where the sitter's pelvis rests; facing = rotation_y for a
#                 figure that looks down -Z at yaw 0 (Godot/minifig
#                 convention); forward = local unit vector the sitter faces.
#   interactions: [{kind, position, label}]
#   light:        {position, color, range}  (only lamps)
#   doors:        [{node, axis, open_angle}]  optional hinged dynamic parts;
#                 node.basis = Basis(axis, open_angle * t) opens it (t 0..1).

const STUD := 0.5
const PLATE := 0.2
const BRICK := 0.6
const FACE_PLUS_Z := PI   # yaw so a -Z-looking figure faces +Z
const FACE_MINUS_Z := 0.0

const ITEMS := {
	# --- Office -----------------------------------------------------------
	"desk": {"label": "Office desk", "category": "office", "footprint": Vector2i(6, 3), "height": 2.8, "mount": "floor", "colors": ["white", "medium_nougat", "dark_bluish_gray"], "variants": ["monitors", "laptop"]},
	"office_chair": {"label": "Office chair", "category": "office", "footprint": Vector2i(2, 2), "height": 1.6, "mount": "floor", "colors": ["black", "dark_bluish_gray"]},
	"filing_cabinet": {"label": "Filing cabinet", "category": "office", "footprint": Vector2i(3, 2), "height": 1.6, "mount": "floor", "colors": ["light_bluish_gray", "dark_bluish_gray", "white"]},
	"bookshelf": {"label": "Bookshelf", "category": "office", "footprint": Vector2i(4, 2), "height": 3.1, "mount": "floor", "colors": ["medium_nougat", "white", "reddish_brown"]},
	"meeting_table": {"label": "Meeting table", "category": "office", "footprint": Vector2i(8, 8), "height": 2.4, "mount": "floor", "colors": ["medium_nougat", "white", "black"]},
	"reception_desk": {"label": "Reception desk", "category": "office", "footprint": Vector2i(6, 4), "height": 2.3, "mount": "floor", "colors": ["white", "medium_nougat", "medium_azure"]},
	"printer": {"label": "Copier", "category": "office", "footprint": Vector2i(3, 2), "height": 1.8, "mount": "floor", "colors": ["light_bluish_gray", "white", "dark_bluish_gray"]},
	"water_cooler": {"label": "Water cooler", "category": "office", "footprint": Vector2i(2, 2), "height": 2.3, "mount": "floor", "colors": ["white", "light_bluish_gray"]},
	"whiteboard": {"label": "Whiteboard", "category": "office", "footprint": Vector2i(6, 1), "height": 3.6, "mount": "wall", "colors": ["white", "flat_silver"]},
	"tv": {"label": "Wall display", "category": "office", "footprint": Vector2i(4, 1), "height": 3.1, "mount": "wall", "colors": ["black", "dark_bluish_gray"]},
	# --- School -----------------------------------------------------------
	"student_desk": {"label": "Student desk", "category": "school", "footprint": Vector2i(4, 4), "height": 2.0, "mount": "floor", "colors": ["medium_nougat", "red", "medium_blue", "yellow", "lime"]},
	"teacher_desk": {"label": "Teacher's desk", "category": "school", "footprint": Vector2i(6, 3), "height": 2.5, "mount": "floor", "colors": ["reddish_brown", "medium_nougat", "white"]},
	"chalkboard": {"label": "Chalkboard", "category": "school", "footprint": Vector2i(8, 1), "height": 3.6, "mount": "wall", "colors": ["dark_green", "black"]},
	"lockers": {"label": "Lockers", "category": "school", "footprint": Vector2i(8, 2), "height": 2.8, "mount": "floor", "colors": ["medium_blue", "dark_azure", "sand_blue", "red", "sand_green"]},
	"cubby_shelf": {"label": "Cubby shelf", "category": "school", "footprint": Vector2i(6, 2), "height": 2.1, "mount": "floor", "colors": ["white", "medium_nougat"]},
	"globe": {"label": "Globe", "category": "school", "footprint": Vector2i(2, 2), "height": 1.9, "mount": "floor", "colors": ["blue", "dark_azure", "medium_blue"]},
	"reading_rug": {"label": "Reading rug", "category": "school", "footprint": Vector2i(6, 6), "height": 0.2, "mount": "floor", "colors": ["medium_blue", "red", "yellow", "lime"]},
	# --- Lounge -----------------------------------------------------------
	"sofa": {"label": "Sofa", "category": "lounge", "footprint": Vector2i(8, 3), "height": 1.4, "mount": "floor", "colors": ["sand_blue", "dark_red", "sand_green", "dark_bluish_gray", "tan"]},
	"armchair": {"label": "Armchair", "category": "lounge", "footprint": Vector2i(4, 3), "height": 1.4, "mount": "floor", "colors": ["dark_red", "sand_blue", "sand_green", "tan"]},
	"coffee_table": {"label": "Coffee table", "category": "lounge", "footprint": Vector2i(4, 2), "height": 1.4, "mount": "floor", "colors": ["reddish_brown", "white", "black"]},
	"rug": {"label": "Rug", "category": "lounge", "footprint": Vector2i(6, 4), "height": 0.2, "mount": "floor", "colors": ["sand_blue", "dark_red", "sand_green", "tan"]},
	"floor_lamp": {"label": "Floor lamp", "category": "lounge", "footprint": Vector2i(2, 2), "height": 2.4, "mount": "floor", "colors": ["tan", "white", "black"]},
	"tall_plant": {"label": "Tall plant", "category": "decor", "footprint": Vector2i(2, 2), "height": 2.7, "mount": "floor", "colors": ["dark_bluish_gray", "white", "nougat"], "variants": ["fig", "bamboo"], "overhang": 1.0},
	"small_plant": {"label": "Small plant", "category": "decor", "footprint": Vector2i(2, 2), "height": 1.2, "mount": "floor", "colors": ["nougat", "white", "dark_bluish_gray"], "overhang": 0.9},
	# --- Kitchen / break --------------------------------------------------
	"kitchen_counter": {"label": "Counter with sink", "category": "kitchen", "footprint": Vector2i(6, 3), "height": 2.0, "mount": "floor", "colors": ["white", "medium_nougat", "sand_blue"]},
	"fridge": {"label": "Fridge", "category": "kitchen", "footprint": Vector2i(3, 2), "height": 2.6, "mount": "floor", "colors": ["white", "flat_silver"]},
	"dining_table": {"label": "Table for four", "category": "kitchen", "footprint": Vector2i(8, 8), "height": 2.6, "mount": "floor", "colors": ["medium_nougat", "white", "reddish_brown"]},
	"vending_machine": {"label": "Vending machine", "category": "kitchen", "footprint": Vector2i(4, 2), "height": 3.4, "mount": "floor", "colors": ["red", "dark_blue", "black"]},
	"coffee_station": {"label": "Coffee station", "category": "kitchen", "footprint": Vector2i(6, 2), "height": 2.9, "mount": "floor", "colors": ["white", "medium_nougat", "sand_blue"]},
	# --- Bath -------------------------------------------------------------
	"toilet_stall": {"label": "Toilet stall", "category": "bath", "footprint": Vector2i(6, 5), "height": 2.6, "mount": "floor", "colors": ["sand_blue", "light_bluish_gray", "sand_green"]},
	"sink_vanity": {"label": "Sink vanity", "category": "bath", "footprint": Vector2i(3, 3), "height": 3.1, "mount": "floor", "colors": ["white", "medium_nougat", "sand_blue"]},
	# --- Mechanical -------------------------------------------------------
	"storage_shelving": {"label": "Storage shelving", "category": "mechanical", "footprint": Vector2i(6, 2), "height": 3.2, "mount": "floor", "colors": ["flat_silver", "dark_bluish_gray"]},
	"workbench": {"label": "Workbench", "category": "mechanical", "footprint": Vector2i(6, 3), "height": 3.1, "mount": "floor", "colors": ["reddish_brown", "medium_nougat"]},
	"water_heater": {"label": "Water heater", "category": "mechanical", "footprint": Vector2i(2, 2), "height": 3.8, "mount": "floor", "colors": ["white", "light_bluish_gray", "sand_blue"]},
	"electrical_panel": {"label": "Electrical panel", "category": "mechanical", "footprint": Vector2i(2, 1), "height": 3.7, "mount": "wall", "colors": ["light_bluish_gray", "dark_bluish_gray"]},
	# --- Outdoor ----------------------------------------------------------
	"park_bench": {"label": "Park bench", "category": "outdoor", "footprint": Vector2i(6, 2), "height": 2.1, "mount": "floor", "colors": ["reddish_brown", "medium_nougat", "dark_green"]},
	"lamp_post": {"label": "Lamp post", "category": "outdoor", "footprint": Vector2i(2, 2), "height": 5.8, "mount": "floor", "colors": ["black", "dark_green", "dark_bluish_gray"]},
	"bike_rack": {"label": "Bike rack", "category": "outdoor", "footprint": Vector2i(6, 6), "height": 2.0, "mount": "floor", "colors": ["flat_silver", "black", "yellow"], "variants": ["one_bike", "two_bikes", "empty"]},
	"picket_fence": {"label": "Picket fence", "category": "outdoor", "footprint": Vector2i(4, 1), "height": 1.4, "mount": "floor", "colors": ["white", "reddish_brown", "medium_nougat"], "variants": ["picket", "spindled"]},
	"flower_bed": {"label": "Flower bed", "category": "outdoor", "footprint": Vector2i(6, 2), "height": 1.5, "mount": "floor", "colors": ["dark_tan", "reddish_brown", "dark_bluish_gray"], "overhang": 0.6},
	"trash_bin": {"label": "Trash bin", "category": "outdoor", "footprint": Vector2i(2, 2), "height": 1.4, "mount": "floor", "colors": ["dark_green", "dark_bluish_gray", "black"]},
	"outdoor_table": {"label": "Picnic table", "category": "outdoor", "footprint": Vector2i(6, 6), "height": 3.6, "mount": "floor", "colors": ["reddish_brown", "medium_nougat"], "variants": ["umbrella", "plain"]},
}

static func ids() -> Array[String]:
	var result: Array[String] = []
	for key in ITEMS:
		result.append(String(key))
	return result

static func spec(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})

# options: "color" (main colour override, palette name or html), "variant",
# "colors" (optional array overriding the item's colour list by index).
static func build(parent: Node3D, item_id: String, options: Dictionary = {}) -> Dictionary:
	var info: Dictionary = ITEMS.get(item_id, {})
	var out := {"collision": [], "seats": [], "interactions": []}
	if info.is_empty():
		push_warning("Unknown furniture item %s" % item_id)
		return out
	var colors: Array = (info.get("colors", ["light_bluish_gray"]) as Array).duplicate()
	var custom: Array = options.get("colors", [])
	for index in range(mini(custom.size(), colors.size())):
		colors[index] = custom[index]
	if options.has("color"):
		colors[0] = options.color
	var variants: Array = info.get("variants", [])
	var variant := String(options.get("variant", variants[0] if not variants.is_empty() else ""))
	var kit := Kit.new(parent, out)
	match item_id:
		"desk": _desk(kit, colors, variant)
		"office_chair": _office_chair_item(kit, colors)
		"filing_cabinet": _filing_cabinet(kit, colors)
		"bookshelf": _bookshelf(kit, colors)
		"meeting_table": _meeting_table(kit, colors)
		"reception_desk": _reception_desk(kit, colors)
		"printer": _printer(kit, colors)
		"water_cooler": _water_cooler(kit, colors)
		"whiteboard": _whiteboard(kit, colors)
		"tv": _tv(kit, colors)
		"student_desk": _student_desk(kit, colors)
		"teacher_desk": _teacher_desk(kit, colors)
		"chalkboard": _chalkboard(kit, colors)
		"lockers": _lockers(kit, colors)
		"cubby_shelf": _cubby_shelf(kit, colors)
		"globe": _globe(kit, colors)
		"reading_rug": _reading_rug(kit, colors)
		"sofa": _sofa(kit, colors, 3)
		"armchair": _sofa(kit, colors, 1)
		"coffee_table": _coffee_table(kit, colors)
		"rug": _rug(kit, colors)
		"floor_lamp": _floor_lamp(kit, colors)
		"tall_plant": _tall_plant(kit, colors, variant)
		"small_plant": _small_plant(kit, colors)
		"kitchen_counter": _kitchen_counter(kit, colors)
		"fridge": _fridge(kit, colors)
		"dining_table": _dining_table(kit, colors)
		"vending_machine": _vending_machine(kit, colors)
		"coffee_station": _coffee_station(kit, colors)
		"toilet_stall": _toilet_stall(kit, colors)
		"sink_vanity": _sink_vanity(kit, colors)
		"storage_shelving": _storage_shelving(kit, colors)
		"workbench": _workbench(kit, colors)
		"water_heater": _water_heater(kit, colors)
		"electrical_panel": _electrical_panel(kit, colors)
		"park_bench": _park_bench(kit, colors)
		"lamp_post": _lamp_post(kit, colors)
		"bike_rack": _bike_rack(kit, colors, variant)
		"picket_fence": _picket_fence(kit, colors, variant)
		"flower_bed": _flower_bed(kit, colors)
		"trash_bin": _trash_bin(kit, colors)
		"outdoor_table": _outdoor_table(kit, colors, variant)
	return out

# --- Placement kit -----------------------------------------------------------

# Thin helper that owns the parent node, an optional sub-frame (for rotated
# sub-assemblies such as chairs) and the result dictionary.
class Kit:
	var parent: Node3D
	var out: Dictionary
	var frame := Transform3D.IDENTITY

	func _init(target: Node3D, result: Dictionary) -> void:
		parent = target
		out = result

	# Part whose bottom-centre sits on `bottom`, optionally re-oriented.
	func put(part: String, bottom: Vector3, tint: Variant, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
		return Bricks.spawn(parent, part, frame * Bricks.bottom_transform(part, bottom, basis), tint)

	# Part turned about Y (the everyday case).
	func at(part: String, bottom: Vector3, tint: Variant, yaw: float = 0.0) -> MeshInstance3D:
		return put(part, bottom, tint, Basis(Vector3.UP, yaw))

	# Part whose bounding-box centre sits on `center`.
	func mid(part: String, center: Vector3, tint: Variant, basis: Basis = Basis.IDENTITY) -> MeshInstance3D:
		return Bricks.spawn(parent, part, frame * Bricks.centered_transform(part, center, basis), tint)

	func box(size: Vector3, center: Vector3) -> void:
		out.collision.append({"size": size, "center": frame * center})

	func seat(position: Vector3, facing: float) -> void:
		var world_facing := facing + frame.basis.get_euler().y
		out.seats.append({"position": frame * position, "facing": wrapf(world_facing, -PI, PI), "forward": Basis(Vector3.UP, world_facing) * Vector3(0, 0, -1)})

	func interact(kind: String, position: Vector3, label: String) -> void:
		out.interactions.append({"kind": kind, "position": frame * position, "label": label})

	# Temporarily build in a rotated/offset local frame.
	func with_frame(origin: Vector3, yaw: float) -> Transform3D:
		var previous := frame
		frame = frame * Transform3D(Basis(Vector3.UP, yaw), origin)
		return previous

# Orientation helpers. A tile/plate "facing" a direction has its top (studs or
# smooth face) pointing that way; its length stays horizontal.
static func face(yaw: float) -> Basis:
	# Top toward Basis(UP, yaw) * +Z, length along Basis(UP, yaw) * +X.
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)

static func face_tall(yaw: float) -> Basis:
	# Like face() but with the part's length running vertically.
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI * 0.5)

static func upside_down(yaw: float = 0.0) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI)

# Cupboard 4532 (2 x 3 x 2) or 4534 (2 x 3 x 4) opening toward +Z in the
# kit frame, with doors, drawers or nothing. `bottom` is its floor centre.
static func _cupboard(kit: Kit, bottom: Vector3, body: Variant, fill: String, fill_colors: Array, tall: bool = false) -> void:
	var previous := kit.with_frame(bottom, PI)
	# In here the cupboard is in its native orientation: opening toward -Z.
	kit.at("4534" if tall else "4532", Vector3.ZERO, body)
	match fill:
		"door":
			var door := "4535" if tall else "4533"
			kit.put(door, Vector3(-0.65, 0.12, -0.52), fill_colors[0], Basis(Vector3.UP, PI * 0.5))
		"drawers":
			for level in range(2):
				kit.at("4536", Vector3(0, 0.1 + level * 0.55, 0.0), fill_colors[level % fill_colors.size()])
	kit.frame = previous

# --- Office -----------------------------------------------------------------

static func _desk(kit: Kit, colors: Array, variant: String) -> void:
	var top: Variant = colors[0]
	var legs: Variant = colors[2]
	# Panel leg on the left, a two-drawer pedestal on the right.
	for course in range(2):
		kit.at("3622", Vector3(-1.25, course * BRICK, 0), legs, PI * 0.5)
	_cupboard(kit, Vector3(0.75, 0, 0.25), legs, "drawers", [top])
	kit.at("3622", Vector3(0.75, 0, -0.5), legs)
	kit.at("3622", Vector3(0.75, BRICK, -0.5), legs)
	# Smooth slab top: 2 x 6 + 1 x 6 tiles.
	kit.at("69729", Vector3(0, 1.2, -0.25), top)
	kit.at("6636", Vector3(0, 1.2, 0.5), top)
	if variant == "laptop":
		kit.at("62698-f2", Vector3(-0.4, 1.4, 0.05), "dark_bluish_gray", PI)
	else:
		for screen in [[-0.8, 0.18], [0.3, -0.18]]:
			kit.at("6141", Vector3(screen[0], 1.4, -0.45), "dark_bluish_gray")
			kit.at("3024", Vector3(screen[0], 1.6, -0.45), "dark_bluish_gray")
			kit.put("3068b", Vector3(screen[0], 2.3, -0.55), "black", face(screen[1]))
			kit.put("3068b", Vector3(screen[0], 2.3, -0.55), "black", face(screen[1] + PI))
		kit.at("2412b", Vector3(-0.25, 1.4, 0.3), "dark_bluish_gray")
	kit.at("33054", Vector3(1.05, 1.4, 0.2), "white", -0.6)
	kit.box(Vector3(3.0, 1.4, 1.5), Vector3(0, 0.7, 0))
	kit.interact("computer", Vector3(-0.3, 1.4, 0.75), "Check email")

static func _office_chair(kit: Kit, center: Vector3, yaw: float, seat_color: Variant, base_color: Variant = "dark_bluish_gray") -> void:
	var previous := kit.with_frame(center, yaw)
	kit.at("4032a", Vector3.ZERO, base_color)
	kit.at("6141", Vector3(0, PLATE, 0), "flat_silver")
	kit.at("4079", Vector3(0, 2 * PLATE, 0), seat_color, PI)
	kit.seat(Vector3(0, 3 * PLATE, -0.2), FACE_PLUS_Z)
	kit.frame = previous

static func _office_chair_item(kit: Kit, colors: Array) -> void:
	_office_chair(kit, Vector3.ZERO, 0.0, colors[0])
	kit.box(Vector3(1.0, 1.6, 1.1), Vector3(0, 0.8, 0))

static func _filing_cabinet(kit: Kit, colors: Array) -> void:
	kit.at("3021", Vector3.ZERO, "dark_bluish_gray")
	_cupboard(kit, Vector3(0, PLATE, 0), colors[0], "drawers", [colors[0]])
	kit.at("26603", Vector3(0, 1.4, 0), colors[0])
	kit.at("3069b", Vector3(-0.3, 1.6, -0.1), "white", 0.2)
	kit.box(Vector3(1.5, 1.6, 1.0), Vector3(0, 0.8, 0))
	kit.interact("files", Vector3(0, 1.0, 0.6), "File paperwork")

static func _bookshelf(kit: Kit, colors: Array) -> void:
	var wood: Variant = colors[0]
	var previous := kit.with_frame(Vector3.ZERO, PI)
	kit.at("1", Vector3.ZERO, wood)
	kit.frame = previous
	var spines := ["dark_red", "dark_blue", "sand_green", "bright_light_orange", "dark_azure", "reddish_brown", "white", "dark_green"]
	# Upright "book" tiles on both shelves plus a stack of real minifig books.
	for shelf in range(2):
		var floor_y := 0.1 + shelf * 1.2
		for index in range(4):
			var x := -0.8 + index * 0.21
			kit.mid("3069b", Vector3(x, floor_y + 0.5, 0.05), spines[(index + shelf * 3) % spines.size()], Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5))
		for level in range(2 - shelf):
			kit.mid("33009-f1", Vector3(0.45, floor_y + 0.18 + level * 0.36, 0.0), spines[(level + 5) % spines.size()], Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, PI))
	# Trailing vine: over the shelf, hanging off the front.
	kit.at("30176", Vector3(0.0, 2.4, -0.2), "green", -PI * 0.5)
	kit.box(Vector3(2.0, 2.5, 1.0), Vector3(0, 1.25, 0))
	kit.interact("books", Vector3(0, 1.2, 0.6), "Browse the books")

static func _meeting_table(kit: Kit, colors: Array) -> void:
	var top: Variant = colors[0]
	for x in [-1.25, 1.25]:
		kit.at("4032a", Vector3(x, 0, 0), "dark_bluish_gray")
		kit.at("3941", Vector3(x, PLATE, 0), "dark_bluish_gray")
		kit.at("4032a", Vector3(x, 0.8, 0), "dark_bluish_gray")
	for z in [-0.5, 0.5]:
		kit.at("3034", Vector3(0, 1.0, z), top)
	for x in [-1.0, 1.0]:
		for z in [-0.5, 0.5]:
			kit.at("87079", Vector3(x, 1.2, z), top, PI * 0.5 if false else 0.0)
	for x in [-1.25, 0.0, 1.25]:
		_office_chair(kit, Vector3(x, 0, 1.5), PI, "black")
		_office_chair(kit, Vector3(x, 0, -1.5), 0.0, "black")
	kit.at("62698-f2", Vector3(-1.2, 1.4, 0.35), "dark_bluish_gray", PI)
	kit.at("33054", Vector3(0.9, 1.4, -0.4), "white", 2.2)
	kit.at("14769", Vector3(0.1, 1.4, 0), "black")
	kit.box(Vector3(4.0, 1.4, 2.0), Vector3(0, 0.7, 0))
	kit.interact("meeting", Vector3(0, 1.4, 1.0), "Start the meeting")

static func _reception_desk(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	var wood: Variant = colors[1]
	var accent: Variant = colors[2]
	# Customer side: a tall front panel with an accent band and a raised
	# transaction ledge; staff side: a lower work surface on a pedestal.
	kit.at("3009", Vector3(0, 0, 0.25), body)
	kit.at("3009", Vector3(0, BRICK, 0.25), body)
	kit.put("6636", Vector3(0, 0.95, 0.5), accent, face(0))
	kit.at("3666", Vector3(0, 1.2, 0.25), body)
	kit.at("3795", Vector3(0, 1.4, 0.5), wood)
	kit.at("69729", Vector3(0, 1.6, 0.5), wood)
	for course in range(2):
		kit.at("3622", Vector3(-1.25, course * BRICK, -0.5), body, PI * 0.5)
	_cupboard(kit, Vector3(0.75, 0, -0.5), body, "drawers", [wood], false)
	kit.at("6636", Vector3(0, 1.2, -0.75), wood)
	kit.at("6636", Vector3(0, 1.2, -0.25), wood)
	kit.at("6141", Vector3(-0.5, 1.4, -0.7), "dark_bluish_gray")
	kit.put("3069b", Vector3(-0.5, 1.85, -0.75), "black", face(0))
	kit.put("3069b", Vector3(-0.5, 1.85, -0.75), "black", face(PI))
	kit.at("2412b", Vector3(-0.5, 1.4, -0.3), "dark_bluish_gray")
	kit.at("30176", Vector3(1.2, 1.8, 0.35), "green", PI)
	kit.at("98138", Vector3(-1.0, 1.8, 0.7), "pearl_gold")
	kit.box(Vector3(3.0, 1.8, 2.0), Vector3(0, 0.9, 0))
	kit.interact("reception", Vector3(0, 1.8, 1.0), "Ask for directions")

static func _printer(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	kit.at("3021", Vector3.ZERO, "dark_bluish_gray")
	for course in range(2):
		for z in [-0.25, 0.25]:
			kit.at("3622", Vector3(0, PLATE + course * BRICK, z), body)
	for level in range(2):
		kit.put("63864", Vector3(0, 0.5 + level * 0.52, 0.5), colors[1], face(0))
	kit.at("3021", Vector3(0, 1.4, 0), "dark_bluish_gray")
	kit.at("3068b", Vector3(-0.25, 1.6, 0), body)
	kit.at("85984", Vector3(0.5, 1.6, 0), "black", PI * 0.5)
	kit.at("3069b", Vector3(-0.3, 1.8, -0.05), "white", 0.15)
	kit.box(Vector3(1.5, 1.8, 1.0), Vector3(0, 0.9, 0))
	kit.interact("printer", Vector3(0, 1.6, 0.6), "Print documents")

static func _water_cooler(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	kit.at("3003", Vector3.ZERO, body)
	kit.at("3003", Vector3(0, BRICK, 0), body)
	kit.at("4032a", Vector3(0, 1.2, 0), body)
	kit.put("30367a", Vector3(0, 2.1, 0), "trans_light_blue", upside_down())
	kit.at("14769", Vector3(0, 2.1, 0), "trans_light_blue")
	kit.put("3069b", Vector3(0, 0.55, 0.5), "dark_bluish_gray", face(0))
	for side in [[-0.25, "medium_blue"], [0.25, "red"]]:
		kit.put("6141", Vector3(side[0], 0.95, 0.5), side[1], face(0))
	kit.box(Vector3(1.0, 2.3, 1.0), Vector3(0, 1.15, 0))
	kit.interact("water", Vector3(0, 1.0, 0.7), "Get a drink of water")

static func _whiteboard(kit: Kit, colors: Array) -> void:
	var board: Variant = colors[0]
	var trim: Variant = colors[1]
	for row in range(2):
		kit.put("69729", Vector3(0, 1.9 + row * 1.0, 0), board, face(0))
	kit.at("3666", Vector3(0, 1.2, 0.25), trim)
	kit.at("6636", Vector3(0, 3.4, 0.25), trim)
	# Two sticky notes and a few marker lines (bars laid on the board).
	kit.put("3070b", Vector3(-1.1, 3.0, 0.2), "yellow", face(0))
	kit.put("3070b", Vector3(-1.1, 2.4, 0.2), "coral", face(0))
	kit.mid("30374", Vector3(0.35, 3.0, 0.3), "dark_blue", Basis(Vector3.BACK, PI * 0.5))
	kit.mid("87994", Vector3(0.1, 2.55, 0.3), "dark_blue", Basis(Vector3.BACK, PI * 0.5))
	kit.mid("87994", Vector3(0.6, 2.1, 0.3), "red", Basis(Vector3.BACK, PI * 0.5))
	kit.at("3023b", Vector3(0.85, 1.4, 0.25), "black")
	kit.at("6141", Vector3(0.05, 1.4, 0.25), "red")
	kit.at("6141", Vector3(-0.45, 1.4, 0.25), "medium_blue")
	kit.box(Vector3(3.0, 2.2, 0.5), Vector3(0, 2.3, 0.25))
	kit.interact("whiteboard", Vector3(0, 1.6, 0.8), "Draw on the board")

static func _tv(kit: Kit, colors: Array) -> void:
	var frame: Variant = colors[0]
	kit.put("3020", Vector3(0, 2.45, 0), frame, face(0))
	kit.put("87079", Vector3(0, 2.45, 0.2), "black", face(0))
	kit.put("2431", Vector3(0, 1.7, 0), "dark_bluish_gray", face(0))
	kit.box(Vector3(2.0, 1.4, 0.5), Vector3(0, 2.3, 0.25))
	kit.interact("tv", Vector3(0, 1.6, 1.0), "Watch the news")

# --- School -----------------------------------------------------------------

static func _student_desk(kit: Kit, colors: Array) -> void:
	var top: Variant = colors[0]
	var chair: Variant = colors[1] if colors.size() > 1 else "red"
	for x in [-0.75, 0.75]:
		for course in range(2):
			kit.at("3700", Vector3(x, course * BRICK, -0.5), "flat_silver", PI * 0.5)
	kit.at("87079", Vector3(0, 1.2, -0.5), top)
	kit.at("3069b", Vector3(0.2, 1.4, -0.35), "white", 0.25)
	kit.at("3070b", Vector3(-0.55, 1.4, -0.6), chair)
	# Sled-base school chair facing the desk (-Z).
	for x in [-0.25, 0.25]:
		kit.at("3700", Vector3(x, 0, 0.5), "flat_silver", PI * 0.5)
	kit.at("4079", Vector3(0, BRICK, 0.5), chair)
	kit.seat(Vector3(0, BRICK + PLATE, 0.75), FACE_MINUS_Z)
	kit.box(Vector3(2.0, 1.4, 1.0), Vector3(0, 0.7, -0.5))
	kit.box(Vector3(1.0, 1.8, 1.0), Vector3(0, 0.9, 0.55))

static func _teacher_desk(kit: Kit, colors: Array) -> void:
	var wood: Variant = colors[0]
	for course in range(2):
		kit.at("3622", Vector3(-1.25, course * BRICK, 0), wood, PI * 0.5)
		kit.at("3004", Vector3(-0.5, course * BRICK, -0.5), wood)
	_cupboard(kit, Vector3(0.75, 0, 0.25), wood, "drawers", [colors[1]])
	kit.at("3622", Vector3(0.75, 0, -0.5), wood)
	kit.at("3622", Vector3(0.75, BRICK, -0.5), wood)
	kit.at("69729", Vector3(0, 1.2, -0.25), colors[1])
	kit.at("6636", Vector3(0, 1.2, 0.5), colors[1])
	kit.at("33051", Vector3(1.0, 1.4, -0.3), "red", 0.8)
	for level in range(2):
		kit.mid("33009-f1", Vector3(-0.8, 1.575 + level * 0.36, -0.3), ["dark_green", "dark_red"][level], Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, level * 0.25))
	kit.at("33054", Vector3(0.1, 1.4, 0.3), "sand_blue", 2.0)
	kit.box(Vector3(3.0, 1.4, 1.5), Vector3(0, 0.7, 0))
	kit.interact("teacher", Vector3(0, 1.4, 0.75), "Grade homework")

static func _chalkboard(kit: Kit, colors: Array) -> void:
	var slate: Variant = colors[0]
	for row in range(4):
		kit.put("4162", Vector3(0, 1.65 + row * 0.5, 0), slate, face(0))
	kit.at("3460", Vector3(0, 1.2, 0.25), "medium_nougat")
	kit.at("4162", Vector3(0, 3.4, 0.25), "medium_nougat")
	# Chalk "writing" and the eraser/chalk on the tray.
	kit.mid("30374", Vector3(-0.9, 3.0, 0.3), "white", Basis(Vector3.BACK, PI * 0.5))
	kit.mid("87994", Vector3(0.95, 3.0, 0.3), "white", Basis(Vector3.BACK, PI * 0.5))
	kit.mid("30374", Vector3(-0.2, 2.5, 0.3), "white", Basis(Vector3.BACK, PI * 0.5))
	kit.mid("87994", Vector3(-1.25, 2.0, 0.3), "white", Basis(Vector3.BACK, PI * 0.5))
	kit.at("3069b", Vector3(1.2, 1.4, 0.25), "tan")
	kit.at("3070b", Vector3(-0.8, 1.4, 0.25), "white")
	kit.box(Vector3(4.0, 2.2, 0.5), Vector3(0, 2.3, 0.25))
	kit.interact("chalkboard", Vector3(0, 1.6, 0.8), "Write on the board")

static func _lockers(kit: Kit, colors: Array) -> void:
	var paint: Variant = colors[0]
	kit.at("3034", Vector3.ZERO, "dark_bluish_gray")
	# Four doors; alternate a slightly deeper shade and stagger them a hair so
	# every door reads on its own, each with a vent, a number and a lock.
	var shade := Bricks.color(paint).darkened(0.12)
	for index in range(4):
		var x := -1.5 + index * 1.0
		var door: Variant = paint if index % 2 == 0 else shade
		var z := 0.25 + (0.03 if index % 2 == 0 else 0.0)
		kit.at("22886", Vector3(x, PLATE, z), door)
		kit.at("2877", Vector3(x, 2.0, z), door)
		kit.put("98138", Vector3(x + 0.28, 1.25, z + 0.25), "flat_silver", face(0))
		kit.put("3070b", Vector3(x - 0.22, 1.75, z + 0.25), "white", face(0))
	for course in range(4):
		kit.at("3008", Vector3(0, PLATE + course * BRICK, -0.25), paint)
	for z in [-0.25, 0.25]:
		kit.at("4162", Vector3(0, 2.6, z), paint)
	kit.box(Vector3(4.0, 2.8, 1.0), Vector3(0, 1.4, 0))
	kit.interact("locker", Vector3(0, 1.2, 0.8), "Open a locker")

static func _cubby_shelf(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	var bins := ["red", "yellow", "medium_blue", "lime"]
	for side in range(2):
		_cupboard(kit, Vector3(-0.75 + side * 1.5, 0, 0), body, "drawers", [bins[side * 2], bins[side * 2 + 1]])
	kit.at("69729", Vector3(0, 1.2, 0), colors[1] if colors.size() > 1 else body)
	kit.mid("33009-f1", Vector3(-0.9, 1.575, 0.0), "dark_blue", Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, 0.2))
	kit.at("30176", Vector3(0.5, 1.4, -0.2), "green", -PI * 0.5)
	kit.box(Vector3(3.0, 1.4, 1.0), Vector3(0, 0.7, 0))
	kit.interact("cubby", Vector3(0, 1.0, 0.6), "Grab supplies")

static func _globe(kit: Kit, colors: Array) -> void:
	kit.at("4032a", Vector3.ZERO, "reddish_brown")
	kit.at("3062b", Vector3(0, PLATE, 0), "reddish_brown")
	kit.at("6141", Vector3(0, 0.8, 0), "pearl_gold")
	kit.at("30106", Vector3(0, 1.0, 0), colors[0])
	kit.box(Vector3(1.0, 1.9, 1.0), Vector3(0, 0.95, 0))
	kit.interact("globe", Vector3(0, 1.3, 0.6), "Spin the globe")

static func _reading_rug(kit: Kit, colors: Array) -> void:
	var tints := ["medium_blue", "yellow", "red", "lime", "orange", "medium_azure", "coral", "bright_green", "bright_light_orange"]
	var start: Variant = colors[0]
	var offset := maxi(0, tints.find(start))
	for i in range(3):
		for j in range(3):
			kit.at("3068b", Vector3(-1.0 + i * 1.0, 0, -1.0 + j * 1.0), tints[(i + j * 3 + offset) % tints.size()])

# --- Lounge -----------------------------------------------------------------

# Sofa (seats = 3) or armchair (seats = 1): plinth, cushions, back and arms.
static func _sofa(kit: Kit, colors: Array, seats: int) -> void:
	var fabric: Variant = colors[0]
	var width := seats * 2
	var half := width * 0.25
	var plate: String = {2: "3022", 6: "3795"}[width]
	kit.at(plate, Vector3(0, 0, 0.25), "dark_brown", 0.0 if width > 2 else 0.0)
	kit.at(plate, Vector3(0, PLATE, 0.25), fabric)
	for index in range(seats):
		var x := -half + 0.5 + index * 1.0
		kit.at("15068", Vector3(x, 2 * PLATE, 0.25), fabric)
		kit.seat(Vector3(x, 0.8, 0.0), FACE_PLUS_Z)
	var back: String = {2: "3004", 6: "3009"}[width]
	var back_tile: String = {2: "3069b", 6: "6636"}[width]
	kit.at(back, Vector3(0, 0, -0.5), fabric)
	kit.at(back, Vector3(0, BRICK, -0.5), fabric)
	kit.at(back_tile, Vector3(0, 1.2, -0.5), fabric)
	for side in [-1.0, 1.0]:
		var x: float = side * (half + 0.25)
		kit.at("3622", Vector3(x, 0, 0), fabric, PI * 0.5)
		kit.at("3623", Vector3(x, BRICK, 0), fabric, PI * 0.5)
		kit.at("63864", Vector3(x, 0.8, 0), fabric, PI * 0.5)
	kit.box(Vector3(width * 0.5 + 1.0, 1.4, 1.5), Vector3(0, 0.7, 0))

static func _coffee_table(kit: Kit, colors: Array) -> void:
	var wood: Variant = colors[0]
	for x in [-0.75, 0.75]:
		for z in [-0.25, 0.25]:
			kit.at("3062b", Vector3(x, 0, z), "black")
	kit.at("87079", Vector3(0, BRICK, 0), wood)
	kit.at("3069b", Vector3(-0.45, 0.8, 0.0), "sand_red", 0.35)
	kit.at("33054", Vector3(0.55, 0.8, 0.05), "white", 0.8)
	kit.box(Vector3(2.0, 0.8, 1.0), Vector3(0, 0.4, 0))

static func _rug(kit: Kit, colors: Array) -> void:
	for row in range(4):
		kit.at("6636", Vector3(0, 0, -0.75 + row * 0.5), colors[0] if row % 3 == 0 else ("white" if row % 3 == 1 else colors[0]))

static func _floor_lamp(kit: Kit, colors: Array) -> void:
	kit.at("4032a", Vector3.ZERO, "black")
	kit.at("87994", Vector3(0, 0.15, 0), "black")
	kit.at("3941", Vector3(0, 1.65, 0), colors[0])
	kit.at("14769", Vector3(0, 2.25, 0), colors[0])
	kit.box(Vector3(1.0, 2.4, 1.0), Vector3(0, 1.2, 0))
	kit.out["light"] = {"position": Vector3(0, 1.85, 0), "color": Color(1.0, 0.84, 0.62), "range": 7.0}
	kit.interact("lamp", Vector3(0, 1.2, 0.6), "Toggle light")

static func _tall_plant(kit: Kit, colors: Array, variant: String) -> void:
	kit.at("3941", Vector3.ZERO, colors[0])
	kit.at("14769", Vector3(0, BRICK, 0), "reddish_brown")
	if variant == "bamboo":
		for level in range(3):
			kit.at("30176", Vector3(0, 0.8 + level * BRICK, 0), "green" if level % 2 == 0 else "bright_green", level * 2.1)
	else:
		kit.at("3062b", Vector3(0, 0.8, 0), "reddish_brown")
		kit.at("3062b", Vector3(0, 1.4, 0), "reddish_brown")
		kit.mid("2423", Vector3(0, 1.15, 0), "green", Basis(Vector3.UP, 0.4))
		kit.mid("2423", Vector3(0, 1.6, 0), "bright_green", Basis(Vector3.UP, 2.5))
		kit.mid("2423", Vector3(0, 2.05, 0), "green", Basis(Vector3.UP, 4.3))
		kit.mid("2417", Vector3(0, 2.3, 0), "bright_green", Basis(Vector3.UP, 1.2))
	kit.box(Vector3(1.0, 2.6, 1.0), Vector3(0, 1.3, 0))

static func _small_plant(kit: Kit, colors: Array) -> void:
	kit.at("3941", Vector3.ZERO, colors[0])
	kit.mid("2423", Vector3(0, 0.75, 0), "green", Basis(Vector3.UP, 0.3))
	kit.mid("2423", Vector3(0, 0.9, 0), "bright_green", Basis(Vector3.UP, 2.4))
	kit.at("30657", Vector3(0, BRICK, 0), "yellow")
	kit.box(Vector3(1.0, 1.2, 1.0), Vector3(0, 0.6, 0))

# --- Kitchen ----------------------------------------------------------------

static func _kitchen_counter(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	var top: Variant = "light_bluish_gray"
	for side in range(2):
		_cupboard(kit, Vector3(-0.75 + side * 1.5, 0, 0.25), body, "door", [colors[1]])
	for course in range(2):
		kit.at("3009", Vector3(0, course * BRICK, -0.5), body)
	kit.at("6636", Vector3(0, 1.2, -0.5), top)
	kit.at("87079", Vector3(-0.5, 1.2, 0.25), top)
	# Stainless basin (an upturned 2 x 2 dish) with a mixer tap behind it.
	kit.mid("4740", Vector3(1.0, 1.32, 0.25), "flat_silver", upside_down())
	kit.at("4599b", Vector3(1.0, 1.4, -0.5), "flat_silver")
	kit.put("6636", Vector3(0, 1.65, -0.75), colors[2] if colors.size() > 2 else "sand_blue", face(0))
	kit.at("33054", Vector3(0.2, 1.4, 0.3), "red", 0.5)
	kit.box(Vector3(3.0, 1.4, 1.5), Vector3(0, 0.7, 0))
	kit.interact("sink", Vector3(1.0, 1.4, 0.75), "Wash hands")

static func _fridge(kit: Kit, colors: Array) -> void:
	var shell: Variant = colors[0]
	_cupboard(kit, Vector3.ZERO, shell, "door", [shell], true)
	kit.mid("87994", Vector3(0.52, 1.3, 0.72), "flat_silver")
	kit.put("98138", Vector3(0.52, 2.06, 0.55), "flat_silver", face(0))
	kit.put("98138", Vector3(0.52, 0.54, 0.55), "flat_silver", face(0))
	kit.at("26603", Vector3(0, 2.4, 0), shell)
	kit.put("3070b", Vector3(-0.3, 1.75, 0.6), "yellow", face(0))
	kit.put("3070b", Vector3(-0.1, 1.45, 0.6), "coral", face(0.2))
	kit.box(Vector3(1.5, 2.6, 1.0), Vector3(0, 1.3, 0))
	kit.interact("fridge", Vector3(0, 1.3, 0.8), "Grab a snack")

static func _dining_chair(kit: Kit, center: Vector3, yaw: float, wood: Variant) -> void:
	var previous := kit.with_frame(center, yaw)
	for x in [-0.25, 0.25]:
		kit.at("3700", Vector3(x, 0, 0), "reddish_brown", PI * 0.5)
	kit.at("4079", Vector3(0, BRICK, 0), wood, PI)
	kit.seat(Vector3(0, BRICK + PLATE, -0.25), FACE_PLUS_Z)
	kit.frame = previous

static func _dining_table(kit: Kit, colors: Array) -> void:
	var top: Variant = colors[0]
	kit.at("4032a", Vector3.ZERO, "dark_brown")
	kit.at("3941", Vector3(0, PLATE, 0), "dark_brown")
	kit.at("4032a", Vector3(0, 0.8, 0), "dark_brown")
	kit.at("3031", Vector3(0, 1.0, 0), top)
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			kit.at("3068b", Vector3(x, 1.2, z), top)
	for index in range(4):
		var yaw := index * PI * 0.5
		_dining_chair(kit, Basis(Vector3.UP, yaw) * Vector3(0, 0, 1.5), yaw + PI, colors[2] if colors.size() > 2 else "reddish_brown")
	kit.at("6256", Vector3(0, 1.4, 0), "white")
	kit.at("33051", Vector3(0.1, 1.45, 0.05), "red", 0.4)
	kit.at("33054", Vector3(-0.65, 1.4, 0.6), "white", 1.0)
	kit.at("33054", Vector3(0.6, 1.4, -0.65), "white", -2.0)
	kit.box(Vector3(2.0, 1.4, 2.0), Vector3(0, 0.7, 0))
	kit.interact("dine", Vector3(0, 1.4, 1.0), "Have lunch")

static func _vending_machine(kit: Kit, colors: Array) -> void:
	var paint: Variant = colors[0]
	kit.at("3020", Vector3.ZERO, "black")
	kit.at("2454a", Vector3(-0.5, PLATE, -0.25), paint)
	kit.at("2454a", Vector3(0.5, PLATE, -0.25), paint)
	kit.at("2453a", Vector3(-0.75, PLATE, 0.25), paint)
	kit.at("2453a", Vector3(0.75, PLATE, 0.25), "dark_bluish_gray")
	kit.at("87079", Vector3(0, 3.2, 0), paint)
	# Snack spirals behind the glass.
	var snacks := ["yellow", "orange", "lime", "medium_azure", "coral", "bright_green"]
	for shelf in range(3):
		var y := 0.8 + shelf * 0.8
		kit.at("3023b", Vector3(0.0, y, 0.25), "light_bluish_gray")
		for slot in range(2):
			kit.at("3062b" if (shelf + slot) % 2 == 0 else "3005", Vector3(-0.25 + slot * 0.5, y + PLATE, 0.25), snacks[(shelf * 2 + slot) % snacks.size()])
	for row in range(5):
		kit.put("3069b", Vector3(0, 0.95 + row * 0.5, 0.5), "trans_clear", face(0))
	kit.put("3069b", Vector3(0, 0.45, 0.5), "black", face(0))
	kit.put("3070b", Vector3(0.75, 2.4, 0.5), "trans_light_blue", face(0))
	kit.put("3070b", Vector3(0.75, 1.9, 0.5), "flat_silver", face(0))
	kit.put("98138", Vector3(0.75, 1.45, 0.5), "black", face(0))
	kit.put("2431", Vector3(0, 3.05, 0.5), "white", face(0))
	kit.box(Vector3(2.0, 3.4, 1.0), Vector3(0, 1.7, 0))
	kit.interact("vending", Vector3(0.6, 1.6, 0.7), "Buy a snack")

static func _coffee_station(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	for side in range(2):
		_cupboard(kit, Vector3(-0.75 + side * 1.5, 0, 0), body, "door", [colors[1]])
	kit.at("69729", Vector3(0, 1.2, 0), "light_bluish_gray")
	# Microwave: a black box with a smoked window and a keypad strip.
	for z in [-0.25, 0.25]:
		kit.at("3622", Vector3(-0.75, 1.4, z), "black")
	kit.at("26603", Vector3(-0.75, 2.0, 0), "black")
	kit.put("3069b", Vector3(-0.95, 1.7, 0.5), "trans_black", face(0))
	kit.put("3070b", Vector3(-0.25, 1.7, 0.5), "dark_bluish_gray", face(0))
	# Coffee maker: tower, head and a glass carafe, plus two mugs.
	kit.at("3004", Vector3(0.75, 1.4, -0.25), "black")
	kit.at("3004", Vector3(0.75, 2.0, -0.25), "black")
	kit.at("3023b", Vector3(0.75, 2.6, 0.0), "black", PI * 0.5)
	kit.at("3062b", Vector3(0.75, 1.4, 0.25), "trans_black")
	kit.at("33054", Vector3(1.25, 1.4, 0.2), "white", -0.4)
	kit.at("33054", Vector3(0.25, 1.4, 0.25), "red", 0.9)
	kit.box(Vector3(3.0, 2.2, 1.0), Vector3(0, 1.1, 0))
	kit.interact("coffee", Vector3(0.75, 1.4, 0.7), "Make coffee")
	kit.interact("microwave", Vector3(-0.75, 1.6, 0.7), "Heat up lunch")

# --- Bath -------------------------------------------------------------------

static func _toilet_stall(kit: Kit, colors: Array) -> void:
	var panel: Variant = colors[0]
	# Thin partitions (2 x 4 tiles on edge) on stainless shoes, with the
	# classic headrail across the front.
	for side in [-1.0, 1.0]:
		var x: float = side * 1.25
		for z in [-0.9, 0.45]:
			kit.at("6141", Vector3(side * 1.15, 0, z), "flat_silver")
			kit.at("6141", Vector3(side * 1.15, PLATE, z), "flat_silver")
		for row in range(2):
			# Back-to-back tiles so both faces are smooth.
			kit.put("87079", Vector3(side * 1.15, 0.9 + row * 1.0, -0.25), panel, face(side * PI * 0.5))
			kit.put("87079", Vector3(side * 1.15, 0.9 + row * 1.0, -0.25), panel, face(-side * PI * 0.5))
	kit.mid("30374", Vector3(0, 2.5, 0.85), "flat_silver", Basis(Vector3.BACK, PI * 0.5))
	# Toilet: tank, bowl and lid against the back wall, plus a paper roll.
	kit.at("3004", Vector3(0, 0, -1.0), "white")
	kit.at("3004", Vector3(0, BRICK, -1.0), "white")
	kit.at("3069b", Vector3(0, 1.2, -1.0), "white")
	kit.at("2555", Vector3(0.35, 1.2, -1.0), "flat_silver")
	kit.at("3941", Vector3(0, 0, -0.25), "white")
	kit.at("14769", Vector3(0, BRICK, -0.25), "white")
	kit.mid("3062b", Vector3(0.8, 1.1, -0.35), "white", Basis(Vector3.BACK, PI * 0.5))
	kit.seat(Vector3(0, 0.8, -0.4), FACE_PLUS_Z)
	# Hinged stall door (dynamic), resting ajar.
	var hinge := Node3D.new()
	hinge.name = "Stall door"
	hinge.set_meta("dynamic", true)
	hinge.set_meta("paint_role", "door")
	hinge.position = Vector3(-1.05, 0, 0.7)
	kit.parent.add_child(hinge)
	for row in range(2):
		for yaw in [0.0, PI]:
			Bricks.spawn(hinge, "87079", Bricks.bottom_transform("87079", Vector3(1.0, 0.9 + row * 1.0, 0.1), face(yaw)), panel)
	Bricks.spawn(hinge, "98138", Bricks.bottom_transform("98138", Vector3(1.8, 1.45, 0.3), face(0)), "flat_silver")
	hinge.basis = Basis(Vector3.UP, -0.3)
	kit.out["doors"] = [{"node": hinge, "axis": Vector3.UP, "open_angle": -1.45, "closed_angle": 0.0}]
	for side in [-1.0, 1.0]:
		kit.box(Vector3(0.3, 2.4, 2.0), Vector3(side * 1.15, 1.2, -0.25))
	kit.box(Vector3(1.0, 1.4, 1.5), Vector3(0, 0.7, -0.5))
	kit.interact("toilet", Vector3(0, 0.8, 0.3), "Flush")

static func _sink_vanity(kit: Kit, colors: Array) -> void:
	var body: Variant = colors[0]
	_cupboard(kit, Vector3(0, 0, 0.25), body, "door", [colors[1] if colors.size() > 1 else body])
	for course in range(2):
		kit.at("3622", Vector3(0, course * BRICK, -0.5), body)
	kit.at("63864", Vector3(0, 1.2, -0.5), "white")
	kit.at("3069b", Vector3(0.5, 1.2, 0.25), "white", PI * 0.5)
	kit.mid("4740", Vector3(-0.25, 1.32, 0.25), "white", upside_down())
	kit.at("4599b", Vector3(-0.25, 1.4, -0.5), "flat_silver")
	kit.at("98138", Vector3(0.5, 1.4, 0.45), "sand_green")
	kit.put("63864", Vector3(0, 1.65, -0.75), "white", face(0))
	kit.put("26603", Vector3(0, 2.4, -0.75), "flat_silver", face(0))
	kit.box(Vector3(1.5, 1.4, 1.5), Vector3(0, 0.7, 0))
	kit.interact("sink", Vector3(-0.25, 1.4, 0.8), "Wash hands")

# --- Mechanical -------------------------------------------------------------

static func _storage_shelving(kit: Kit, colors: Array) -> void:
	var metal: Variant = colors[0]
	for x in [-1.25, 1.25]:
		for z in [-0.25, 0.25]:
			kit.at("2453a", Vector3(x, 0, z), metal)
	for level in range(3):
		kit.at("3020", Vector3(0, 0.3 + level * 1.0, 0), "dark_bluish_gray", PI * 0.5 if false else 0.0)
	kit.at("3795", Vector3(0, 3.0, 0), "dark_bluish_gray")
	# Cardboard boxes, a toolbox and paint tins.
	kit.at("3003", Vector3(-0.5, 0.5, 0), "dark_tan")
	kit.at("3004", Vector3(0.5, 0.5, 0), "tan", PI * 0.5)
	kit.at("3004", Vector3(-0.5, 1.5, 0), "red")
	kit.at("2540", Vector3(-0.5, 2.1, 0.15), "black")
	kit.at("3062b", Vector3(0.25, 1.5, -0.25), "medium_blue")
	kit.at("3062b", Vector3(0.75, 1.5, 0.25), "white")
	kit.at("3022", Vector3(0.5, 2.5, 0), "tan")
	kit.at("3022", Vector3(0.5, 2.7, 0), "tan")
	kit.at("3023b", Vector3(-0.6, 2.5, 0), "dark_tan", PI * 0.5)
	kit.at("3023b", Vector3(-0.6, 2.7, 0), "dark_tan", PI * 0.5)
	kit.box(Vector3(3.0, 3.2, 1.0), Vector3(0, 1.6, 0))
	kit.interact("storage", Vector3(0, 1.2, 0.6), "Look for supplies")

static func _workbench(kit: Kit, colors: Array) -> void:
	var wood: Variant = colors[0]
	for x in [-1.25, 1.25]:
		for course in range(2):
			kit.at("3622", Vector3(x, course * BRICK, 0), "dark_bluish_gray", PI * 0.5)
	kit.at("3020", Vector3(0, 0.4, 0), "dark_bluish_gray")
	kit.at("3795", Vector3(0, 1.2, -0.25), wood)
	kit.at("3666", Vector3(0, 1.2, 0.5), wood)
	# Pegboard with a clip lamp, a vise and a toolbox.
	kit.put("3795", Vector3(0, 1.9, -0.75), "tan", face(0))
	kit.put("4081b", Vector3(-1.0, 2.35, -0.55), "black", face(PI))
	kit.at("3004", Vector3(1.0, 1.4, 0.45), "dark_bluish_gray", PI * 0.5)
	kit.at("3024", Vector3(1.0, 2.0, 0.55), "dark_bluish_gray")
	kit.at("3004", Vector3(-0.6, 1.4, 0.1), "red")
	kit.at("2540", Vector3(-0.6, 2.0, 0.2), "black")
	kit.at("3062b", Vector3(-0.3, 0.6, -0.2), "yellow")
	kit.box(Vector3(3.0, 1.4, 1.5), Vector3(0, 0.7, 0))
	kit.interact("workbench", Vector3(0, 1.4, 0.8), "Fix something")

static func _water_heater(kit: Kit, colors: Array) -> void:
	var shell: Variant = colors[0]
	kit.at("4032a", Vector3.ZERO, "dark_bluish_gray")
	for course in range(3):
		kit.at("6143", Vector3(0, PLATE + course * BRICK, 0), shell)
	kit.at("30367a", Vector3(0, 2.0, 0), shell)
	# Cold (silver) and hot (copper) pipes rise to the ceiling.
	kit.at("87994", Vector3(-0.25, 2.3, -0.15), "flat_silver")
	kit.at("87994", Vector3(0.25, 2.3, -0.15), "copper")
	kit.mid("4599b", Vector3(0.55, 1.75, 0.0), "pearl_gold", Basis(Vector3.UP, PI * 0.5))
	kit.mid("87994", Vector3(0.62, 0.95, 0.12), "copper")
	kit.put("3005", Vector3(0, 0.55, 0.45), "black", Basis.IDENTITY)
	kit.put("98138", Vector3(0, 0.9, 0.7), "red", face(0))
	kit.put("3070b", Vector3(0, 1.45, 0.5), "yellow", face(0))
	kit.box(Vector3(1.0, 2.7, 1.0), Vector3(0, 1.35, 0))
	kit.interact("water_heater", Vector3(0, 1.0, 0.8), "Check the water temperature")

static func _electrical_panel(kit: Kit, colors: Array) -> void:
	var box: Variant = colors[0]
	for course in range(3):
		kit.at("3004", Vector3(0, 1.2 + course * BRICK, 0.25), box)
	kit.put("3068b", Vector3(0, 2.3, 0.5), box, face(0))
	kit.put("3069b", Vector3(0, 1.55, 0.5), box, face(0))
	kit.put("98138", Vector3(0.3, 2.0, 0.7), "flat_silver", face(0))
	kit.put("3070b", Vector3(-0.2, 2.6, 0.7), "yellow", face(0))
	kit.at("87994", Vector3(-0.25, 2.3, 0.25), "dark_bluish_gray")
	kit.at("87994", Vector3(0.25, 2.3, 0.25), "dark_bluish_gray")
	kit.box(Vector3(1.0, 1.8, 0.7), Vector3(0, 2.1, 0.35))
	kit.interact("breakers", Vector3(0, 1.6, 0.9), "Check the breakers")

# --- Outdoor ----------------------------------------------------------------

static func _park_bench(kit: Kit, colors: Array) -> void:
	var slats: Variant = colors[0]
	var iron := "black"
	for x in [-1.25, 1.25]:
		kit.at("3004", Vector3(x, 0, 0), iron, PI * 0.5)
		kit.at("3005", Vector3(x, BRICK, -0.25), iron)
		kit.at("3005", Vector3(x, 2 * BRICK, -0.25), iron)
	for z in [-0.25, 0.25]:
		kit.at("2431", Vector3(0, BRICK, z), slats)
	for row in range(2):
		kit.put("6636", Vector3(0, 1.1 + row * 0.55, -0.7), slats, face(0))
	for x in [-0.55, 0.55]:
		kit.seat(Vector3(x, 0.8, -0.05), FACE_PLUS_Z)
	kit.box(Vector3(3.0, 1.9, 1.0), Vector3(0, 0.95, 0))

static func _lamp_post(kit: Kit, colors: Array) -> void:
	var iron: Variant = colors[0]
	kit.at("11062", Vector3.ZERO, iron)
	kit.at("4032a", Vector3(0, 4.2, 0), iron)
	kit.at("3941", Vector3(0, 4.4, 0), "trans_clear")
	kit.at("6141", Vector3(0, 4.45, 0), "trans_yellow" if Bricks.PALETTE.has("trans_yellow") else "trans_orange")
	kit.at("4740", Vector3(0, 5.0, 0), iron)
	kit.at("4589", Vector3(0, 5.2, 0), iron)
	kit.box(Vector3(0.8, 5.8, 0.8), Vector3(0, 2.9, 0))
	kit.out["light"] = {"position": Vector3(0, 4.7, 0), "color": Color(1.0, 0.86, 0.6), "range": 14.0}
	kit.interact("lamp", Vector3(0, 1.2, 0.6), "Toggle light")

static func _bike_rack(kit: Kit, colors: Array, variant: String) -> void:
	var metal: Variant = colors[0]
	# Three inverted-U hoops of bar stock on a paved strip.
	for x in [-1.0, 0.0, 1.0]:
		for z in [-0.7, 0.7]:
			kit.at("4032a" if false else "6141", Vector3(x, 0, z), "dark_bluish_gray")
			kit.at("87994", Vector3(x, 0.1, z), metal)
		kit.mid("87994", Vector3(x, 1.6, 0), metal, Basis(Vector3.RIGHT, PI * 0.5))
	var bikes: Array = [] if variant == "empty" else ([[0.5, "red"]] if variant != "two_bikes" else [[0.9, "red"], [-0.9, "medium_azure"]])
	for bike in bikes:
		kit.at("4719c01", Vector3(bike[0], 0, 1.075), bike[1])
	kit.box(Vector3(2.5, 1.7, 1.6), Vector3(0, 0.85, 0))
	kit.interact("bike", Vector3(0.5, 1.0, 1.6), "Ride a bike")

static func _picket_fence(kit: Kit, colors: Array, variant: String) -> void:
	kit.at("3710", Vector3.ZERO, colors[0])
	kit.at("30055" if variant == "spindled" else "33303", Vector3(0, PLATE, 0), colors[0])
	kit.box(Vector3(2.0, 1.4, 0.5), Vector3(0, 0.7, 0))

static func _flower_bed(kit: Kit, colors: Array) -> void:
	kit.at("2456", Vector3.ZERO, colors[0])
	kit.at("3795", Vector3(0, BRICK, 0), "dark_brown")
	var blooms := ["red", "yellow", "coral"]
	for index in range(3):
		var x := -1.0 + index * 1.0
		kit.mid("2423", Vector3(x, 0.95, 0), "green", Basis(Vector3.UP, 0.9 + index * 2.0))
		kit.at("30657", Vector3(x, 0.8, 0), blooms[index])
	kit.box(Vector3(3.0, 1.0, 1.0), Vector3(0, 0.5, 0))

static func _trash_bin(kit: Kit, colors: Array) -> void:
	kit.at("2439", Vector3.ZERO, colors[0])
	kit.at("14769", Vector3(0, 1.2, 0), colors[0])
	kit.box(Vector3(1.0, 1.4, 1.0), Vector3(0, 0.7, 0))
	kit.interact("trash", Vector3(0, 1.2, 0.6), "Throw away trash")

static func _outdoor_table(kit: Kit, colors: Array, variant: String) -> void:
	var wood: Variant = colors[0]
	for x in [-1.25, 1.25]:
		for course in range(2):
			kit.at("3004", Vector3(x, course * BRICK, 0), "dark_brown", PI * 0.5)
	kit.at("3795", Vector3(0, 1.2, 0), wood)
	for z in [-0.25, 0.25]:
		kit.at("6636", Vector3(0, 1.4, z), wood)
	for z in [-1.25, 1.25]:
		for x in [-1.25, 1.25]:
			kit.at("3005", Vector3(x, 0, z), "dark_brown")
			kit.at("3024", Vector3(x, BRICK, z), "dark_brown")
		kit.at("6636", Vector3(0, 0.8, z), wood)
		for x in [-0.6, 0.6]:
			kit.seat(Vector3(x, 1.0, z + (0.1 if z > 0 else -0.1)), FACE_MINUS_Z if z > 0 else FACE_PLUS_Z)
	if variant != "plain":
		kit.at("30374", Vector3(0, 1.6, 0), "white")
		kit.at("44375b", Vector3(0, 3.3, 0), "red")
		kit.at("6141", Vector3(0, 3.6, 0), "white")
	kit.box(Vector3(3.0, 1.6, 1.0), Vector3(0, 0.8, 0))
	for z in [-1.25, 1.25]:
		kit.box(Vector3(3.0, 1.0, 0.5), Vector3(0, 0.5, z))
	kit.interact("picnic", Vector3(0, 1.6, 0.8), "Have a picnic")
