extends Node

const ARENA = preload("res://scenes/arena.tscn")
var arena: Node2D
var failures: Array[String] = []
var goals := 0
var cases := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func ticks(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame

func shot(point: Vector2, velocity: Vector2) -> void:
	arena.reset_rally()
	arena.paddles[0].reset_at(Vector2(80, 930))
	arena.paddles[1].reset_at(Vector2(80, 70))
	arena.puck.reset_at(point, velocity)
	arena.last_position = point
	await ticks(2)
	arena.set_running(true)
	cases += 1

func run() -> Dictionary:
	arena = ARENA.instantiate()
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(arena)
	arena.rng.seed = 123
	arena.goal.connect(func(_side): goals += 1)
	await ticks(3)
	check(Engine.physics_ticks_per_second == 120 and Engine.time_scale == 1, "clock")
	check(arena.crossed_goal(Vector2(300, 0), Vector2(300, -40)) == 0, "fast top goal")
	check(arena.crossed_goal(Vector2(300, 1000), Vector2(300, 1040)) == 1, "fast bottom goal")
	check(arena.crossed_goal(Vector2(190, 0), Vector2(190, -40)) == -1, "post crossing")
	check(arena.crossed_goal(Vector2(250, 0), Vector2(650, -40)) == -1, "swept aperture")
	await shot(Vector2(300, 500), Vector2.ZERO)
	await ticks(24)
	check(arena.puck.position.distance_to(Vector2(300, 500)) < 0.1, "zero action displacement")
	await shot(Vector2(300, 500), Vector2(120, 0))
	await ticks(13)
	check(absf(arena.puck.position.x - 312) < 2, "known velocity / actual ticks")
	await shot(Vector2(550, 500), Vector2(2300, 0))
	await ticks(15)
	check(arena.puck.linear_velocity.x < 0 and arena.puck.position.x < 582, "maximum speed rail CCD")
	await shot(Vector2(300, 25), Vector2(0, -2300))
	await ticks(10)
	check(goals == 1 and not arena.running, "legal physical goal")
	await ticks(10)
	check(goals == 1, "duplicate score prevention")
	# This clears the right post, then drifts outside the old +/-74 scoring strip.
	for side in range(2):
		for direction in [-1, 1]:
			var before := goals
			await shot(Vector2(300 + direction * 65, 30 if side == 0 else 970), Vector2(direction * 800, -2200 if side == 0 else 2200))
			await ticks(30)
			check(goals == before + 1 and not arena.running and arena.last_stall_reason.is_empty(), "angled goal must not escape %d/%d: %s" % [side, direction, arena.puck.position])
	await shot(Vector2(178, 65), Vector2(50, -2300))
	await ticks(15)
	check(goals == 5 and arena.puck.position.y > 0, "post graze must rebound")
	var before_recovery := goals
	await shot(Vector2(650, 500), Vector2(2300, 0))
	await ticks(8)
	check(not arena.running and arena.last_stall_reason == "out_of_bounds" and goals == before_recovery, "escaped rail re-serves without a point")
	await shot(Vector2(40, 40), Vector2(-1600, -1600))
	await ticks(25)
	check(arena.puck.position.x > 18 and arena.puck.position.y > 18, "corner recovery")
	await shot(Vector2(300, 740), Vector2(0, 1800))
	arena.paddles[0].reset_at(Vector2(300, 850))
	await ticks(22)
	check(arena.puck.linear_velocity.y < 0, "stationary paddle impact")
	await shot(Vector2(300, 740), Vector2.ZERO)
	arena.paddles[0].reset_at(Vector2(300, 850))
	arena.paddles[0].set_command(Vector2(0, -1))
	await ticks(26)
	check(arena.puck.linear_velocity.y < -100, "moving paddle strike")
	for side in range(2):
		arena.reset_rally(side)
		await ticks(2)
		arena.set_running(true)
		arena.paddles[side].set_command(Vector2(1, -1 if side == 0 else 1))
		await ticks(180)
		var point: Vector2 = arena.paddles[side].position
		check(point.x <= 557 and (point.y >= 542 if side == 0 else point.y <= 458), "paddle half boundary")
		check(arena.paddles[side].linear_velocity.length() <= 1051, "no diagonal advantage")
	var random := RandomNumberGenerator.new()
	random.seed = 20261001
	for i in range(100):
		await shot(Vector2(random.randf_range(60, 540), random.randf_range(220, 780)), Vector2.RIGHT.rotated(random.randf_range(0, TAU)) * 2300)
		for j in range(50):
			await ticks(1)
			var point: Vector2 = arena.puck.position
			check(point.is_finite() and arena.puck.linear_velocity.is_finite(), "finite random trajectory %d" % i)
			# Godot contacts can penetrate by <2 units for one tick; outer rail is 40 thick.
			check(point.x >= -2 and point.x <= 602, "rail tunneling %d: %s" % [i, point])
			if not arena.running:
				check(arena.last_stall_reason != "out_of_bounds", "unscored random escape %d" % i)
				break
	arena.reset_rally()
	check(arena.contacts == [0, 0] and arena.ticks == 0 and arena.quiet_ticks == 0, "reset bookkeeping")
	for body in [arena.puck, arena.paddles[0], arena.paddles[1]]:
		check(body.linear_velocity == Vector2.ZERO, "reset velocities")
	var report := {"check": "physics", "cases": cases, "random_seed": 20261001, "failures": failures}
	viewport.queue_free()
	return report
