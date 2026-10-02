extends PanelContainer

# The equipment workbench: assemble an air handler or VAV section by section
# with a live, slowly turning 3D preview. Air flows left to right: the intake
# damper stays first and an AHU's fan stays last; everything between can be
# added, removed and dragged into a different order.

const ToySkin := preload("res://scripts/ui/toy_theme.gd")
const ROLES := ["damper", "filter", "cooling_coil", "heating_coil", "fan"]
const LABELS := {"damper": "Damper", "filter": "Filter", "cooling_coil": "Cooling coil", "heating_coil": "Heating coil", "fan": "Fan"}
const CHIP_COLORS := {"damper": Color("bf893c"), "filter": Color("c6a345"), "cooling_coil": Color("278ac6"), "heating_coil": Color("be5442"), "fan": Color("617981")}
const PRESETS := {
	"ahu": [["Heat + cool", ["damper", "filter", "cooling_coil", "heating_coil", "fan"]], ["Cooling only", ["damper", "filter", "cooling_coil", "fan"]], ["Ventilation", ["damper", "filter", "fan"]], ["Preheat + cool", ["damper", "heating_coil", "filter", "cooling_coil", "fan"]]],
	"vav": [["With reheat", ["damper", "heating_coil"]], ["Cooling only", ["damper"]], ["Chilled-water trim", ["damper", "cooling_coil"]]],
}

var game: Node
var view: Node
var kind := "ahu"
var editing_id := ""
var layout: Array[String] = []
var records: Array[Dictionary] = []
var sensor := true
var serial := 1
var selected := -1
var dragging := -1
var viewport: SubViewport
var preview_root: Node3D
var preview_camera: Camera3D
var title: Label
var hint: Label
var lineup: HBoxContainer
var parts: HBoxContainer
var place_button: Button
var presets: OptionButton
var size_row: VBoxContainer
var size_pick: OptionButton
var price_label: Label
var capacity := HvacCosts.DEFAULT_AHU_SIZE
var sensor_tile: Button
var part_tiles: Dictionary = {}

func setup(owner: Node, equipment_view: Node) -> void:
	game = owner
	view = equipment_view
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -530
	offset_right = 530
	offset_top = -440
	offset_bottom = -ToySkin.MARGIN
	# Taller content grows up the screen, never off the bottom edge.
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_theme_stylebox_override("panel", ToySkin.card(0.98, 20))
	z_index = 20
	var body := UIKit.row(self, 20)
	var stage_well := PanelContainer.new()
	stage_well.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CARD - 2, 0))
	body.add_child(stage_well)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(430, 360)
	container.stretch = true
	stage_well.add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size = Vector2i(430, 360)
	container.add_child(viewport)
	var stage := Stage.new()
	viewport.add_child(stage)
	stage.ground.visible = false
	# The panel's own glass shows behind the unit.
	stage.environment.background_mode = Environment.BG_CLEAR_COLOR
	var table := MeshInstance3D.new()
	var slab := CylinderMesh.new()
	slab.top_radius = 9.0
	slab.bottom_radius = 9.0
	slab.height = 0.2
	table.mesh = slab
	table.position.y = -0.1
	table.material_override = Bricks.material("dark_bluish_gray")
	stage.add_child(table)
	preview_root = Node3D.new()
	stage.add_child(preview_root)
	preview_camera = Camera3D.new()
	preview_camera.fov = 34
	stage.add_child(preview_camera)
	var column := UIKit.column(body, 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := UIKit.row(column, 8)
	var titles := UIKit.column(header, 2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.section(titles, "Workbench")
	title = UIKit.title(titles, "Air handler", ToySkin.SIZE_HEADING)
	UIKit.tile(header, "Close · Esc", "close", close, Vector2(32, 30)).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hint = UIKit.text(column, "", ToySkin.SIZE_BODY, ToySkin.TEXT_2)
	var choices := UIKit.row(column, 14)
	var layout_field := UIKit.column(choices, 5)
	layout_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.label(layout_field, "Starting layout", ToySkin.SIZE_SMALL, ToySkin.TEXT_3, ToySkin.WEIGHT_STRONG)
	presets = UIKit.options(layout_field, [])
	presets.item_selected.connect(_apply_preset)
	size_row = UIKit.column(choices, 5)
	size_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.label(size_row, "Size", ToySkin.SIZE_SMALL, ToySkin.TEXT_3, ToySkin.WEIGHT_STRONG)
	size_pick = UIKit.options(size_row, [])
	size_pick.tooltip_text = "Design airflow. Too small and it runs flat out and falls behind on hot days; too big costs more and wastes fan energy."
	size_pick.item_selected.connect(func(index: int) -> void: capacity = float(size_pick.get_item_metadata(index)); _changed())
	var price := UIKit.column(choices, 3)
	price.size_flags_vertical = Control.SIZE_SHRINK_END
	UIKit.label(price, "Installed price", ToySkin.SIZE_SMALL, ToySkin.TEXT_3, ToySkin.WEIGHT_STRONG)
	price_label = UIKit.label(price, "", ToySkin.SIZE_TITLE, ToySkin.YELLOW, ToySkin.WEIGHT_HEAVY)
	var flow := UIKit.row(column, 8)
	UIKit.section(flow, "Airflow · left to right").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UIKit.spacer(flow)
	UIKit.tile(flow, "Move the selected section left", "left", func() -> void: _shift(-1), Vector2(36, 30))
	UIKit.tile(flow, "Move the selected section right", "right", func() -> void: _shift(1), Vector2(36, 30))
	UIKit.tile(flow, "Remove the selected section", "close", _remove, Vector2(36, 30))
	var lineup_well := PanelContainer.new()
	lineup_well.add_theme_stylebox_override("panel", ToySkin.fill(ToySkin.INK_WELL, ToySkin.RADIUS_CONTROL, 8))
	column.add_child(lineup_well)
	lineup = UIKit.row(lineup_well, 6)
	UIKit.section(column, "Add a section")
	parts = UIKit.row(column, 6)
	for role in ROLES:
		var id := String(role)
		var tile := UIKit.tile(parts, String(LABELS[id]), "", func() -> void: _add(id), Vector2(82, 88), "part")
		tile.face_color = ToySkin.CREAM_WELL
		tile.thumbnail = UIKit.thumbnail(id)
		part_tiles[id] = tile
	sensor_tile = UIKit.tile(parts, "Sensor", "", func() -> void: sensor = not sensor; _changed(), Vector2(82, 88), "part")
	sensor_tile.thumbnail = UIKit.thumbnail("sensor")
	sensor_tile.face_color = ToySkin.CREAM_WELL
	place_button = UIKit.button(column, "Place it in the building", _commit, "PrimaryButton")
	place_button.custom_minimum_size.y = 44
	hide()

func open(equipment_kind: String, id: String = "") -> void:
	kind = equipment_kind
	editing_id = id
	var source: Dictionary = game.model.find_object(id).get("properties", {}) if not id.is_empty() else view.current_config(kind)
	layout.clear()
	records.clear()
	var existing: Array = source.get("component_records", [])
	var roles: Array = RouteNetwork.layout(source)
	for index in range(roles.size()):
		layout.append(String(roles[index]))
		records.append(existing[index].duplicate(true) if index < existing.size() and existing[index] is Dictionary else _record(String(roles[index])))
	sensor = bool(source.get("sensor_enabled", true))
	capacity = float(source.get("capacity_m3_s", HvacCosts.DEFAULT_AHU_SIZE)) if kind == "ahu" else float(source.get("capacity_m3_s", 0.45))
	_fill_sizes()
	title.text = ("Edit %s" % String(game.model.find_object(id).properties.get("label", kind.to_upper()))) if not id.is_empty() else ("Air handler" if kind == "ahu" else "VAV box")
	presets.clear()
	for preset in PRESETS[kind]:
		presets.add_item(String(preset[0]))
	place_button.text = "Apply to %s" % game.describe(id) if not id.is_empty() else "Place it in the building"
	game.hud.tray.hide()
	show()
	_changed()

func close() -> void:
	hide()
	game.hud.refresh_mode()

func _record(role: String) -> Dictionary:
	serial += 1
	return {"id": "component-%d-%04d" % [Time.get_ticks_msec() % 100000, serial], "role": role, "paint": {}, "bindings": {}}

func config() -> Dictionary:
	var result := {"layout": layout.duplicate(), "component_records": records.duplicate(true), "sensor_enabled": sensor}
	if kind == "ahu": result.capacity_m3_s = capacity
	return result

func _fill_sizes() -> void:
	size_row.visible = kind == "ahu"
	size_pick.clear()
	var sizes: Array = HvacCosts.AHU_SIZES.duplicate()
	var known := false
	for value in sizes: known = known or absf(float(value) - capacity) < 0.01
	if not known: sizes.append(capacity)
	for value in sizes:
		size_pick.add_item(HvacCosts.size_label(float(value)))
		size_pick.set_item_metadata(size_pick.item_count - 1, float(value))
		if absf(float(value) - capacity) < 0.01: size_pick.select(size_pick.item_count - 1)

func layout_error(candidate: Array) -> String:
	if candidate.is_empty() or candidate[0] != "damper" or candidate.count("damper") != 1:
		return "Air enters through one intake damper, first in line."
	if kind == "vav":
		if candidate.size() > 2: return "A VAV has a damper and at most one coil."
		for role in candidate:
			if role not in ["damper", "cooling_coil", "heating_coil"]: return "%s doesn't belong in a VAV." % String(LABELS[role])
		return ""
	if candidate[-1] != "fan" or candidate.count("fan") != 1:
		return "The supply fan sits last, blowing into the duct."
	if candidate.count("cooling_coil") > 1 or candidate.count("heating_coil") > 1:
		return "One cooling coil and one heating coil per unit."
	if candidate.size() > 7:
		return "Seven sections fit on the bench."
	return ""

func _add(role: String) -> void:
	var candidate: Array = layout.duplicate()
	var at := candidate.size()
	if kind == "ahu":
		if role == "damper": at = 0
		elif "fan" in candidate and role != "fan": at = candidate.find("fan")
		if role == "filter":
			for coil in ["cooling_coil", "heating_coil"]:
				if coil in candidate: at = mini(at, candidate.find(coil))
	elif kind == "vav" and role in ["cooling_coil", "heating_coil"]:
		for coil in ["cooling_coil", "heating_coil"]:
			var existing := candidate.find(coil)
			if existing >= 0:
				candidate.remove_at(existing)
				layout.remove_at(existing)
				records.remove_at(existing)
		at = candidate.size()
	candidate.insert(at, role)
	var error := layout_error(candidate)
	if not error.is_empty():
		game.set_status(error)
		game.play_sound("error")
		return
	layout.insert(at, role)
	records.insert(at, _record(role))
	selected = at
	game.play_sound("place")
	_changed()

func _remove() -> void:
	if selected < 0 or selected >= layout.size():
		return
	var candidate: Array = layout.duplicate()
	candidate.remove_at(selected)
	var error := layout_error(candidate)
	if not error.is_empty():
		game.set_status(error)
		game.play_sound("error")
		return
	layout.remove_at(selected)
	records.remove_at(selected)
	selected = mini(selected, layout.size() - 1)
	game.play_sound("demolish")
	_changed()

func _shift(direction: int) -> void:
	_move(selected, selected + direction)

func _move(from: int, to: int) -> void:
	if from < 0 or to < 0 or from >= layout.size() or to >= layout.size() or from == to:
		return
	var candidate: Array = layout.duplicate()
	var role: String = candidate.pop_at(from)
	candidate.insert(to, role)
	var error := layout_error(candidate)
	if not error.is_empty():
		game.set_status(error)
		game.play_sound("error")
		return
	layout.insert(to, layout.pop_at(from))
	records.insert(to, records.pop_at(from))
	selected = to
	game.play_sound("tick")
	_changed()

func _apply_preset(index: int) -> void:
	layout.clear()
	records.clear()
	for role in PRESETS[kind][index][1]:
		layout.append(String(role))
		records.append(_record(String(role)))
	_changed()

func _changed() -> void:
	UIKit.clear(lineup)
	for index in range(layout.size()):
		var i := index
		var role := layout[index]
		var chip := UIKit.tile(lineup, "%d %s" % [index + 1, String(LABELS[role]).split(" ")[0]], "", func() -> void: selected = i; _changed(), Vector2(84, 34), "line")
		chip.face_color = CHIP_COLORS.get(role, ToySkin.INK)
		chip.marked = i == selected
		chip.tooltip_text = "Section %d · %s · drag to reorder" % [i + 1, LABELS[role]]
		chip.gui_input.connect(func(event: InputEvent) -> void: _chip_input(event, i))
	for role in part_tiles:
		var tile: Button = part_tiles[role]
		var candidate: Array = layout.duplicate()
		candidate.append(role)
		tile.disabled = (kind == "vav" and role in ["filter", "fan", "damper"]) or (kind == "ahu" and role in ["damper", "fan"] and role in layout)
		tile.queue_redraw()
	sensor_tile.marked = sensor
	sensor_tile.queue_redraw()
	hint.text = "Air flows left to right. Sections: %d · Air enters at the damper%s." % [layout.size(), " and the fan pushes it into the ductwork" if kind == "ahu" else " and leaves toward the diffusers"]
	price_label.text = "%s" % Units.money(HvacCosts.item_cost({"kind": kind, "properties": config()}, []))
	var error := layout_error(layout)
	place_button.disabled = not error.is_empty()
	if not error.is_empty(): hint.text = error
	_rebuild_preview()

func _chip_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = index
			selected = index
		else:
			var pointer := get_viewport().get_mouse_position()
			for child in lineup.get_children():
				if child is Control and child.get_global_rect().has_point(pointer):
					_move(dragging, child.get_index())
					break
			dragging = -1

func _rebuild_preview() -> void:
	for child in preview_root.get_children():
		child.free()
	var holder := Node3D.new()
	preview_root.add_child(holder)
	view.build_preview(holder, kind, config())
	var box := _bounds(holder)
	holder.position = -box.get_center() * Vector3(1, 0, 1)
	# The unit turns on the bench, so frame its footprint diagonal.
	var span := Vector2(box.size.x, box.size.z).length()
	var target := Vector3(0, box.size.y * 0.4, 0)
	var distance := (span * 0.5 + 0.5) / tan(deg_to_rad(preview_camera.fov * 0.5)) * 1.05
	preview_camera.position = target + Vector3(0.0, 0.42, 0.91).normalized() * distance
	preview_camera.look_at(target)

func _process(delta: float) -> void:
	if visible and is_instance_valid(preview_root):
		preview_root.rotate_y(delta * 0.25)

func _bounds(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mesh as MeshInstance3D).global_transform * (mesh as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result if not first else AABB(Vector3(-2, 0, -1), Vector3(4, 2, 2))

func _commit() -> void:
	if not layout_error(layout).is_empty():
		return
	view.workbench_config[kind] = config()
	if not editing_id.is_empty():
		var item: Dictionary = game.model.find_object(editing_id).duplicate(true)
		if item.is_empty():
			# Deleted or undone while the workbench was open.
			game.set_status("That unit is gone, so there's nothing to rebuild.")
			close()
			return
		item.properties.merge(config(), true)
		game.apply("Edit " + String(item.properties.get("label", kind)), [], [], [item])
		game.set_status("%s rebuilt with %d sections" % [String(item.properties.get("label", kind)), layout.size()])
		close()
		return
	close()
	game.start_tool("equipment", {"kind": kind, "properties": config()})
