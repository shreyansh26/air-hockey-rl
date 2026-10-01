extends Node

const OBS = preload("res://scripts/observation.gd")
const POLICY = preload("res://scripts/policy.gd")
var arena: Node2D
var learner_side := 0
var history = OBS.new()
var opponent_history = OBS.new()
var delay_ticks := 10
var mode := "defense"
var opponent_style := "center"
var opponent_delay := 22
var shot_type := "serve"
var opponents: Array[String] = []
var opponent: RefCounted
var terminated := false
var truncated := false
var reward := 0.0
var episode_reward := 0.0
var episode_ticks := 0
var limit_ticks := 1440
var winner := -1
var stalls := 0
var contact_credit := false
var hit_reward := 0.05
var shaping := 0.03
var drill_bonus := 0.0
var drill_success := false
var verified_return := false
var gamma := 0.99
var potential := 0.0
var active_mode := "defense"
var last_sample_tick := 0
var opponent_mode := "mixed"
var fixed_style := "intercept"
var evaluation_match := false
var match_scores := [0, 0]
var opening_serve := 0
var next_serve := -1
var rng := RandomNumberGenerator.new()

func initialize(value: Node2D, seed_value: int) -> void:
	arena = value
	rng.seed = seed_value
	arena.rng.seed = seed_value
	arena.goal.connect(_goal)
	arena.stalled.connect(_stall)
	arena.impact.connect(_impact)
	process_physics_priority = 100

func reset_episode() -> void:
	terminated = false
	truncated = false
	reward = 0
	episode_reward = 0
	episode_ticks = 0
	winner = -1
	stalls = 0
	contact_credit = false
	drill_success = false
	verified_return = false
	active_mode = mode
	if mode == "mixed":
		active_mode = ["defense", "attack", "rally"][rng.randi_range(0, 2)]
	var serve := rng.randi_range(0, 1)
	if evaluation_match:
		if next_serve < 0:
			serve = opening_serve
			opening_serve = 1 - opening_serve
		else:
			serve = next_serve
	arena.reset_rally(serve)
	opponent_style = ["center", "chase", "intercept", "delayed_chase", "puck_chase"][rng.randi_range(0, 4)]
	if opponent_mode == "fixed":
		opponent_style = fixed_style
	opponent = null
	if not opponents.is_empty() and (opponent_mode == "fixed" or rng.randf() < 0.35):
		var candidate = POLICY.new()
		var error: String = candidate.load_actor(opponents[rng.randi_range(0, opponents.size() - 1)])
		if error:
			push_error("Frozen opponent: " + error)
			get_tree().quit(2)
			return
		opponent = candidate
	if active_mode == "defense":
		arena.paddles[0].reset_at(Vector2(rng.randf_range(200, 400), 850))
		var point := Vector2(rng.randf_range(70, 530), rng.randf_range(250, 500))
		var velocity := Vector2(rng.randf_range(-650, 650), rng.randf_range(500, 1500))
		shot_type = "direct"
		if rng.randf() < 0.3:
			var left := rng.randf() < 0.5
			point.x = 60 if left else 540
			velocity.x = rng.randf_range(700, 1300) * (-1 if left else 1)
			shot_type = "bank"
		elif rng.randf() < 0.2:
			var aim := rng.randf_range(225, 375)
			velocity = (Vector2(aim, 1000) - point).normalized() * rng.randf_range(1400, 2300)
			shot_type = "fast_goal"
		arena.puck.reset_at(point, velocity.limit_length(2300))
	elif active_mode == "attack":
		var point := Vector2(rng.randf_range(60, 540), rng.randf_range(620, 740))
		var paddle := Vector2(clampf(point.x + rng.randf_range(-100, 100), 46, 554), point.y + rng.randf_range(90, 180))
		shot_type = "attack"
		if rng.randf() < 0.25:
			point.y = rng.randf_range(850, 930)
			paddle.y = rng.randf_range(600, 720)
			shot_type = "recovery"
		arena.paddles[0].reset_at(paddle)
		arena.puck.reset_at(point, Vector2(rng.randf_range(-100, 100), rng.randf_range(-50, 150)))
	else:
		shot_type = "serve"
		if evaluation_match:
			arena.launch(serve) # Nominal held-out matches use the shipped serve primitive.
		else:
			arena.puck.linear_velocity = Vector2(rng.randf_range(-250, 250), 260 if serve == 0 else -260)
	arena.last_position = arena.puck.position
	history.reset(arena, learner_side)
	opponent_history.reset(arena, 1 - learner_side)
	last_sample_tick = 0
	potential = _potential()
	arena.set_running(true)

func set_action(action: Vector2) -> void:
	var smoothness := action.distance_squared_to(history.previous_action) * 0.00005
	reward = -smoothness
	arena.paddles[learner_side].set_command(action if learner_side == 0 else -action)
	history.previous_action = Vector2(clampf(action.x, -1, 1), clampf(action.y, -1, 1))
	if opponent:
		var opponent_action: Vector2 = opponent.predict(opponent_history.encode(opponent.delay_ticks))
		opponent_history.previous_action = opponent_action
		arena.paddles[1 - learner_side].set_command(-opponent_action if learner_side == 0 else opponent_action)
	elif opponent_style in ["delayed_chase", "puck_chase"]:
		var delayed := opponent_history.encode(opponent_delay)
		var observed_puck := Vector2((delayed[36] + 1) * 300, (delayed[37] + 1) * 500)
		var observed_paddle := Vector2((delayed[40] + 1) * 300, (delayed[41] + 1) * 500)
		if opponent_style == "puck_chase":
			observed_paddle = arena.paddles[1 - learner_side].position
			if learner_side == 0:
				observed_paddle = Vector2(600, 1000) - observed_paddle
		var target := observed_puck + Vector2(0, 30) if observed_puck.y > 500 else Vector2(300, 840)
		target = arena.clamp_target(target, 0)
		var command := (target - observed_paddle) * 8 / 1050
		arena.paddles[1 - learner_side].set_command(-command if learner_side == 0 else command)
	else:
		arena.baseline(1 - learner_side, opponent_style)

func observation() -> PackedFloat32Array:
	return history.encode(delay_ticks)

func _physics_process(_delta: float) -> void:
	if terminated or truncated:
		return
	episode_ticks += 1
	capture_history()
	var puck_y: float = arena.puck.position.y if learner_side == 0 else 1000 - arena.puck.position.y
	var puck_vy: float = arena.puck.linear_velocity.y * (1 if learner_side == 0 else -1)
	if contact_credit and puck_y < 480 and puck_vy < -100:
		verified_return = true
	if drill_bonus > 0 and active_mode in ["defense", "attack"] and verified_return:
		drill_success = true
		terminated = true
		reward += drill_bonus - potential
		potential = 0
		arena.set_running(false)
		return
	if episode_ticks >= limit_ticks:
		truncated = true
		arena.set_running(false)

func finish_step() -> float:
	if not terminated:
		var next_potential := _potential()
		reward += gamma * next_potential - potential
		potential = next_potential
	var value := reward
	episode_reward += value
	reward = 0
	return value

func capture_history() -> void:
	if arena.puck.integration_ticks > last_sample_tick:
		history.record(arena, learner_side)
		opponent_history.record(arena, 1 - learner_side)
		last_sample_tick = arena.puck.integration_ticks

func _potential() -> float:
	# Training-only bounded potential: defend incoming paths, reset after outgoing shots.
	# F = gamma * Phi(next) - Phi(current); a real goal uses terminal Phi=0.
	var puck: Vector2 = arena.puck.position
	var velocity: Vector2 = arena.puck.linear_velocity
	var paddle: Vector2 = arena.paddles[learner_side].position
	if learner_side == 1:
		puck = Vector2(600, 1000) - puck
		paddle = Vector2(600, 1000) - paddle
		velocity = -velocity
	var target := Vector2(300, 850)
	if velocity.y > 40:
		var travel := clampf((810 - puck.y) / velocity.y, 0, 1.5)
		var folded := fposmod(puck.x + velocity.x * travel - 18, 1128)
		target.x = 18 + (folded if folded < 564 else 1128 - folded)
	if puck.y > 545 and puck.y < 965 and velocity.y > -450:
		target = puck + Vector2(0, 40)
	target = arena.clamp_target(target, 0)
	var alignment: float = minf(paddle.distance_to(target) / 700, 1.0)
	var progress := clampf(1 - 2 * puck.y / 1000, -1, 1)
	return shaping * (0.4 * progress - 0.6 * alignment)

func _goal(side: int) -> void:
	capture_history()
	terminated = true
	winner = 0 if side == learner_side else 1
	if evaluation_match:
		match_scores[side] += 1
		next_serve = 1 - side
		if match_scores[side] == 7:
			match_scores = [0, 0]
			next_serve = -1
	reward += (1 if side == learner_side else -1) - potential
	potential = 0

func _stall() -> void:
	capture_history()
	stalls += 1
	truncated = true
	# A stall ends a training episode; no arbitrary point is awarded.

func _impact(_speed: float, side: int) -> void:
	if side == learner_side and not contact_credit:
		reward += hit_reward
		contact_credit = true
