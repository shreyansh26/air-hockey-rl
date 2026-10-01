extends RigidBody2D

const CONFIG = preload("res://resources/physics.tres")
var tint := Color("eaf8ff")
var reduced_effects := false
var reset_transform := Transform2D.IDENTITY
var integration_ticks := 0

func _ready() -> void:
	gravity_scale = 0.0
	lock_rotation = true
	can_sleep = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = CONFIG.puck_damping
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	contact_monitor = true
	max_contacts_reported = 8
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	physics_material_override.bounce = 0.82
	var shape := CircleShape2D.new()
	shape.radius = CONFIG.puck_radius
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	integration_ticks += 1
	if state.linear_velocity.is_finite():
		state.linear_velocity = state.linear_velocity.limit_length(CONFIG.puck_speed)
	else:
		state.linear_velocity = Vector2.ZERO

func reset_at(point: Vector2, velocity := Vector2.ZERO) -> void:
	integration_ticks = 0
	position = point
	reset_transform = global_transform
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, reset_transform)
	linear_velocity = velocity.limit_length(CONFIG.puck_speed)
	angular_velocity = 0
	reset_physics_interpolation()

func _draw() -> void:
	var r: float = CONFIG.puck_radius
	if not reduced_effects:
		draw_circle(Vector2(3, 6), r + 2, Color(0, 0, 0, 0.4))
	draw_circle(Vector2.ZERO, r, tint.darkened(0.45))
	draw_circle(Vector2(0, -2), r - 1, tint)
	draw_arc(Vector2(0, -2), r - 3, PI, TAU, 20, tint.lightened(0.5), 2, true)
