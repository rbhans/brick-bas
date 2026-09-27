extends Node3D

var left_leg: Node3D
var right_leg: Node3D
var left_arm: Node3D
var right_arm: Node3D
var stride := 0.0
var sitting := false

func _ready() -> void:
	# Native LDraw pieces, uniformly scaled as one figure. Individual pieces are
	# neither stretched nor replaced by capsules. Pivot holders drive the gait.
	scale = Vector3.ONE * 0.9
	# Offsets follow LDraw's 973c01 torso and hips/legs shortcut assembly.
	part("3815b", Vector3(0, 1.0, 0), Color("#294453"))
	part("973", Vector3(0, 1.8, 0), Color("#e99f39"))
	part("3626c", Vector3(0, 2.4, 0), Color("#f6ce4f"))
	left_leg = limb("3817b", Vector3(0.2625, 0.7, 0), Vector3(-0.2625, 0, 0), Color("#294453"))
	right_leg = limb("3816b", Vector3(-0.2625, 0.7, 0), Vector3(0.2625, 0, 0), Color("#294453"))
	left_arm = limb("3819", Vector3(0.3888, 1.575, 0), Vector3.ZERO, Color("#e99f39"))
	right_arm = limb("3818", Vector3(-0.3888, 1.575, 0), Vector3.ZERO, Color("#e99f39"))
	left_arm.rotation.z = 0.171
	right_arm.rotation.z = -0.171
	var left_hand := part("3820", Vector3(0.12, -0.475, -0.247), Color("#f6ce4f"), left_arm)
	var right_hand := part("3820", Vector3(-0.12, -0.475, -0.247), Color("#f6ce4f"), right_arm)
	left_hand.rotation.x = -PI * 0.25
	right_hand.rotation.x = -PI * 0.25
	# Small printed-style face cues on the sourced head.
	for x in [-0.09, 0.09]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.027
		sphere.height = 0.054
		eye.mesh = sphere
		eye.position = Vector3(x, 2.15, -0.316)
		var black := StandardMaterial3D.new()
		black.albedo_color = Color("#283334")
		eye.material_override = black
		add_child(eye)

func part(id: String, origin: Vector3, color: Color, parent: Node3D = self) -> Node3D:
	var holder := Node3D.new()
	var mesh := load("res://assets/third_party/ldraw/meshes/%s.obj" % id) as Mesh
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	visual.material_override = material
	holder.position = origin
	holder.add_child(visual)
	parent.add_child(holder)
	return holder

func limb(id: String, pivot: Vector3, bottom: Vector3, color: Color) -> Node3D:
	var holder := Node3D.new()
	holder.position = pivot
	add_child(holder)
	part(id, bottom, color, holder)
	return holder

func sit(value: bool) -> void:
	sitting = value
	left_leg.rotation.x = -PI * 0.5 if value else 0.0
	right_leg.rotation.x = -PI * 0.5 if value else 0.0
	left_arm.rotation.x = -0.5 if value else 0.0
	right_arm.rotation.x = -0.5 if value else 0.0
	position.y = -0.62 if value else 0.0

func animate_walk(delta: float, speed: float, reduced_motion: bool) -> void:
	if sitting:
		return
	stride += delta * speed * 3.2
	var swing := sin(stride) * minf(speed / 3.0, 1.0) * (0.18 if reduced_motion else 0.55)
	left_leg.rotation.x = swing
	right_leg.rotation.x = -swing
	left_arm.rotation.x = -swing * 0.7
	right_arm.rotation.x = swing * 0.7
