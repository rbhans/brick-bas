class_name Stage
extends Node3D

# Sky, lights, tone mapping and the studded ground plane. Shared by the game,
# the equipment workbench, thumbnails and preview captures so they all match.

const BASEPLATE := preload("res://scripts/render/baseplate.gdshader")
const GRID := preload("res://scripts/render/grid_overlay.gdshader")

var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var ground: MeshInstance3D
var ground_material: ShaderMaterial
var grid: MeshInstance3D
var grid_material: ShaderMaterial
var ground_body: StaticBody3D

func _ready() -> void:
	name = "Stage"
	var world_environment := WorldEnvironment.new()
	environment = Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#6d93b3")
	sky_material.sky_horizon_color = Color("#d4dfe2")
	sky_material.ground_bottom_color = Color("#3c4a3a")
	sky_material.ground_horizon_color = Color("#b8c4be")
	sky_material.sun_angle_max = 20.0
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 0.9
	environment.tonemap_white = 6.0
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.04
	environment.adjustment_saturation = 1.06
	environment.ssao_enabled = not OS.has_feature("web")
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.2
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.2
	environment.ssao_light_affect = 0.15
	environment.fog_enabled = true
	environment.fog_light_color = Color("#cad7dd")
	environment.fog_density = 0.00035
	environment.fog_sky_affect = 0.0
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-54, -36, 0)
	sun.light_color = Color("#fff3dc")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
	fill = DirectionalLight3D.new()
	fill.name = "Sky fill"
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_color = Color("#c2dcf0")
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	add_child(fill)
	if OS.has_feature("web"):
		environment.ambient_light_energy = 0.7
		sun.light_energy = 0.85
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 90.0
		fill.light_energy = 0.25
	_build_ground()

func _build_ground() -> void:
	ground = MeshInstance3D.new()
	ground.name = "Baseplate ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	ground.mesh = plane
	ground_material = ShaderMaterial.new()
	ground_material.shader = BASEPLATE
	var sun_direction := -(Basis.from_euler(Vector3(deg_to_rad(-54), deg_to_rad(-36), 0)) * Vector3.FORWARD)
	ground_material.set_shader_parameter("light_dir", sun_direction)
	ground_material.set_shader_parameter("plate_color", Color("#3f7a35"))
	ground.material_override = ground_material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	ground_body = StaticBody3D.new()
	ground_body.name = "Ground"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3000, 1.0, 3000)
	shape.shape = box
	shape.position.y = -0.5
	ground_body.add_child(shape)
	add_child(ground_body)
	grid = MeshInstance3D.new()
	grid.name = "Plan grid"
	var grid_plane := PlaneMesh.new()
	grid_plane.size = Vector2(400, 400)
	grid.mesh = grid_plane
	grid.position.y = PlanGrid.FLOOR_TOP + 0.012
	grid_material = ShaderMaterial.new()
	grid_material.shader = GRID
	grid.material_override = grid_material
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.visible = false
	add_child(grid)

func set_grid(visible_value: bool, cursor: Vector3 = Vector3.ZERO) -> void:
	grid.visible = visible_value
	if visible_value:
		grid.position.x = snappedf(cursor.x, PlanGrid.TILE * 4)
		grid.position.z = snappedf(cursor.z, PlanGrid.TILE * 4)
		grid_material.set_shader_parameter("cursor", cursor)

func set_ground_color(value: Color) -> void:
	ground_material.set_shader_parameter("plate_color", value)

# Keep directional shadows focused on what the camera is looking at.
func focus_shadows(distance: float) -> void:
	sun.directional_shadow_max_distance = clampf(distance * 2.2, 40.0, 180.0 if not OS.has_feature("web") else 110.0)
