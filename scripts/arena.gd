extends Node2D

signal goal(scoring_side: int)
signal stalled
signal impact(speed: float, paddle_side: int)

const CONFIG = preload("res://resources/physics.tres")
const PADDLE = preload("res://scenes/paddle.tscn")
const PUCK = preload("res://scripts/puck.gd")
var puck: RigidBody2D
var paddles: Array[RigidBody2D] = [] # bottom = 0, top = 1
var running := false
var ticks := 0
var last_position := Vector2.ZERO
var quiet_ticks := 0
var contacts := [0, 0]
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	# Collision layers: rails=1, bottom=2, top=4, bottom limits=8, top limits=16.
	_wall(Vector2(-20, 500), Vector2(40, 1080), 1)
	_wall(Vector2(620, 500), Vector2(40, 1080), 1)
	for y in [0.0, 1000.0]:
		_wall(Vector2(85, y - 20 if y == 0 else y + 20), Vector2(210, 40), 1)
		_wall(Vector2(515, y - 20 if y == 0 else y + 20), Vector2(210, 40), 1)
		for x in [190.0, 410.0]:
			_post(Vector2(x, y), 18.0)
		for x in [0.0, 600.0]:
			_post(Vector2(x, y), 32.0)
	_wall(Vector2(300, 500), Vector2(680, 4), 8 | 16)
	_wall(Vector2(300, 1020), Vector2(680, 40), 8)
	_wall(Vector2(300, -20), Vector2(680, 40), 16)
	for side in range(2):
		var paddle: RigidBody2D = PADDLE.instantiate()
		paddle.collision_layer = 2 if side == 0 else 4
		paddle.collision_mask = 1 | (8 if side == 0 else 16) | 32
		paddle.position = Vector2(300, 830 if side == 0 else 170)
		add_child(paddle)
		paddles.append(paddle)
	puck = RigidBody2D.new()
	puck.set_script(PUCK)
	puck.collision_layer = 32
	puck.collision_mask = 1 | 2 | 4
	puck.position = Vector2(300, 500)
	add_child(puck)
	puck.body_entered.connect(_contact)
	set_running(false)

func _wall(point: Vector2, size: Vector2, layer: int) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	_collider(point, shape, layer)

func _post(point: Vector2, radius: float) -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	_collider(point, shape, 1)

func _collider(point: Vector2, shape: Shape2D, layer: int) -> void:
	var body := StaticBody2D.new()
	body.position = point
	body.collision_layer = layer
	body.collision_mask = 0
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 0.0
	body.physics_material_override.bounce = 0.15
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

func set_running(value: bool) -> void:
	running = value
	puck.freeze = not value
	for paddle in paddles:
		paddle.freeze = not value
		if not value:
			paddle.set_command(Vector2.ZERO)

func reset_rally(serve_side: int = 0, velocity := Vector2.ZERO) -> void:
	set_running(false)
	for side in range(2):
		paddles[side].reset_at(Vector2(300, 830 if side == 0 else 170))
	puck.reset_at(Vector2(300, 600 if serve_side == 0 else 400), velocity)
	last_position = puck.position
	ticks = 0
	quiet_ticks = 0
	contacts = [0, 0]

func launch(serve_side: int) -> void:
	set_running(true)
	puck.linear_velocity = Vector2(rng.randf_range(-80, 80), 260 if serve_side == 0 else -260)
	last_position = puck.position

func _physics_process(delta: float) -> void:
	if not running:
		return
	assert(absf(delta - 1.0 / 120.0) < 0.00001, "Physics clock changed")
	ticks += 1
	var current := puck.position
	if not current.is_finite() or not puck.linear_velocity.is_finite():
		set_running(false)
		stalled.emit()
		return
	var side := crossed_goal(last_position, current)
	last_position = current
	if side >= 0:
		set_running(false)
		goal.emit(side)
		return
	quiet_ticks = quiet_ticks + 1 if puck.linear_velocity.length() < 25 else 0
	if quiet_ticks >= int(CONFIG.stall_seconds * 120):
		set_running(false)
		stalled.emit()

func crossed_goal(previous: Vector2, current: Vector2) -> int:
	for side in range(2):
		var plane: float = -CONFIG.puck_radius if side == 0 else CONFIG.height + CONFIG.puck_radius
		var crossed: bool = previous.y >= plane and current.y < plane if side == 0 else previous.y <= plane and current.y > plane
		if crossed and current.y != previous.y:
			var x := lerpf(previous.x, current.x, (plane - previous.y) / (current.y - previous.y))
			var clearance: float = CONFIG.goal_width / 2 - CONFIG.puck_radius - 18.0
			if absf(x - CONFIG.width / 2) <= clearance:
				return side # top goal scores bottom (0)
	return -1

func clamp_target(point: Vector2, side: int) -> Vector2:
	var r: float = CONFIG.paddle_radius + 2.0
	return Vector2(clampf(point.x, r, CONFIG.width - r),
		clampf(point.y, CONFIG.height / 2 + r if side == 0 else r,
			CONFIG.height - r if side == 0 else CONFIG.height / 2 - r))

func drive_to(side: int, target: Vector2) -> void:
	paddles[side].set_command((clamp_target(target, side) - paddles[side].position) * 12 / CONFIG.paddle_speed)

func baseline(side: int, style: String = "intercept") -> void:
	# Development/training only. Release main always loads a policy.
	var sign_y := 1.0 if side == 0 else -1.0
	var own_puck := Vector2(puck.position.x, puck.position.y if side == 0 else 1000 - puck.position.y)
	var target := Vector2(300, 840)
	if style == "chase" and own_puck.y > 500:
		target = own_puck + Vector2(0, 30)
	elif style == "center":
		target.x = lerpf(300, own_puck.x, 0.35)
	else:
		var vy := puck.linear_velocity.y * sign_y
		if vy > 30:
			var travel := clampf((840 - own_puck.y) / vy, 0, 2)
			var projected := fposmod(own_puck.x + puck.linear_velocity.x * travel - 18, 1128)
			target.x = 18 + (projected if projected < 564 else 1128 - projected)
		if own_puck.y > 580 and own_puck.y < 900:
			target = own_puck + Vector2(0, 35)
	if side == 1:
		target.y = 1000 - target.y
	drive_to(side, target)

func _contact(body: Node) -> void:
	quiet_ticks = 0
	var side := paddles.find(body) if body is RigidBody2D else -1
	if side >= 0:
		contacts[side] += 1
	impact.emit(puck.linear_velocity.length(), side)
