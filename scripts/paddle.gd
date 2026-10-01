extends RigidBody2D

const CONFIG = preload("res://resources/physics.tres")
var command := Vector2.ZERO
var tint := Color("ffbd73")
var reduced_effects := false
var reset_transform := Transform2D.IDENTITY

func _ready() -> void:
	mass = CONFIG.paddle_mass
	gravity_scale = 0.0
	lock_rotation = true
	can_sleep = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.0
	physics_material_override.bounce = 0.3
	var shape := CircleShape2D.new()
	shape.radius = CONFIG.paddle_radius
	var collider := CollisionShape2D.new()
	collider.shape = shape
	add_child(collider)

func set_command(value: Vector2) -> void:
	command = Vector2(clampf(value.x, -1, 1), clampf(value.y, -1, 1)).limit_length(1)
	if not command.is_finite():
		command = Vector2.ZERO

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Stop commanding motion into a rail; collisions still resolve through the solver.
	var arena := get_parent()
	var local_point: Vector2 = arena.to_local(state.transform.origin)
	var side := 0 if collision_layer == 2 else 1
	var target: Vector2 = arena.clamp_target(local_point + command * CONFIG.paddle_speed * state.step, side)
	var desired_velocity := ((target - local_point) / state.step).limit_length(CONFIG.paddle_speed)
	state.linear_velocity = state.linear_velocity.move_toward(desired_velocity,
		CONFIG.paddle_acceleration * state.step).limit_length(CONFIG.paddle_speed)

func reset_at(point: Vector2) -> void:
	position = point
	reset_transform = global_transform
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, reset_transform)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	command = Vector2.ZERO
	reset_physics_interpolation()

func _draw() -> void:
	var r: float = CONFIG.paddle_radius
	if not reduced_effects:
		draw_circle(Vector2(5, 10), r + 3, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, r, tint.darkened(0.65))
	draw_circle(Vector2(0, -3), r - 2, tint)
	draw_arc(Vector2(0, -3), r - 5, PI, TAU, 32, tint.lightened(0.45), 3, true)
	draw_circle(Vector2(0, -5), r - 12, tint.darkened(0.25))
	draw_circle(Vector2(0, -8), r - 17, tint.lightened(0.15))
	draw_circle(Vector2(-7, -15), r - 25, tint.lightened(0.3))
