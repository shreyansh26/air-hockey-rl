extends Node

const OBS = preload("res://scripts/observation.gd")
const POLICY = preload("res://scripts/policy.gd")
var arena: Node2D
var history = OBS.new()
var opponent_history = OBS.new()
var delay_ticks := 10
var mode := "defense"
var opponent_style := "center"
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
	opponent_style = ["center", "chase", "intercept"][rng.randi_range(0, 2)]
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
		arena.puck.reset_at(Vector2(rng.randf_range(70, 530), rng.randf_range(340, 500)), Vector2(rng.randf_range(-600, 600), rng.randf_range(500, 1000)))
	elif active_mode == "attack":
		var x := rng.randf_range(160, 440)
		arena.paddles[0].reset_at(Vector2(x + rng.randf_range(-60, 60), rng.randf_range(800, 930)))
		arena.puck.reset_at(Vector2(x, rng.randf_range(620, 740)), Vector2(rng.randf_range(-100, 100), rng.randf_range(-50, 150)))
	else:
		arena.puck.linear_velocity = Vector2(rng.randf_range(-250, 250), 260 if serve == 0 else -260)
	arena.last_position = arena.puck.position
	history.reset(arena, 0)
	opponent_history.reset(arena, 1)
	last_sample_tick = 0
	potential = _potential()
	arena.set_running(true)

func set_action(action: Vector2) -> void:
	var smoothness := action.distance_squared_to(history.previous_action) * 0.00005
	reward = -smoothness
	arena.paddles[0].set_command(action)
	history.previous_action = Vector2(clampf(action.x, -1, 1), clampf(action.y, -1, 1))
	if opponent:
		var opponent_action: Vector2 = opponent.predict(opponent_history.encode(opponent.delay_ticks))
		opponent_history.previous_action = opponent_action
		arena.paddles[1].set_command(-opponent_action)
	else:
		arena.baseline(1, opponent_style)

func observation() -> PackedFloat32Array:
	return history.encode(delay_ticks)

func _physics_process(_delta: float) -> void:
	if terminated or truncated:
		return
	episode_ticks += 1
	capture_history()
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
		history.record(arena, 0)
		opponent_history.record(arena, 1)
		last_sample_tick = arena.puck.integration_ticks

func _potential() -> float:
	# Bounded potential encourages approaching a reachable puck early in the curriculum.
	var distance: float = arena.paddles[0].position.distance_to(arena.puck.position)
	return -shaping * minf(distance / 1000, 1.0)

func _goal(side: int) -> void:
	capture_history()
	terminated = true
	winner = side
	if evaluation_match:
		match_scores[side] += 1
		next_serve = 1 - side
		if match_scores[side] == 7:
			match_scores = [0, 0]
			next_serve = -1
	reward += (1 if side == 0 else -1) - potential
	potential = 0

func _stall() -> void:
	capture_history()
	stalls += 1
	truncated = true
	# A stall ends a training episode; no arbitrary point is awarded.

func _impact(_speed: float, side: int) -> void:
	if side == 0 and not contact_credit:
		reward += hit_reward
		contact_credit = true
