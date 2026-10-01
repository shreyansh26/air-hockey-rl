extends SceneTree

var main: Control
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func ticks(count: int) -> void:
	for _i in range(count):
		await physics_frame

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main._start_match()
	await ticks(260)
	for side in range(2):
		main.arena.set_running(false)
		main.arena.paddles[0].reset_at(Vector2(80, 920))
		main.arena.paddles[1].reset_at(Vector2(80, 80))
		main.arena.puck.reset_at(Vector2(365, 30 if side == 0 else 970), Vector2(800, -2200 if side == 0 else 2200))
		main.arena.last_position = main.arena.puck.position
		main.arena.set_running(true)
		await ticks(12)
		check(main.state == "goal" and main.scores[side] == 1, "angled physics goal %d" % side)
		var frozen: Vector2 = main.arena.puck.position
		var animation_timer: float = main.timer
		main._pause()
		await ticks(20)
		check(main.state == "paused" and main.timer == animation_timer, "goal animation pauses")
		main._resume()
		await ticks(40)
		check(main.arena.puck.position == frozen, "goal animation never moves the body")
		check(main.arena.puck.modulate.a == 0 and main.arena.puck.visual_offset.y * (-1 if side == 0 else 1) > 0, "puck enters pocket and vanishes")
		await ticks(100)
		check(main.state == "countdown" and main.arena.puck.modulate.a == 1 and main.arena.puck.visual_offset == Vector2.ZERO, "next serve restores puck")
		await ticks(160)
	main.scores[0] = 6
	main.arena.set_running(false)
	main.arena.paddles[1].reset_at(Vector2(80, 80))
	main.arena.puck.reset_at(Vector2(300, 30), Vector2(0, -2200))
	main.arena.last_position = main.arena.puck.position
	main.arena.set_running(true)
	await ticks(45)
	check(main.state == "goal" and main.scores[0] == 7 and main.arena.puck.modulate.a == 0, "winning puck vanishes before results")
	await ticks(100)
	check(main.state == "results", "first to seven ends after goal presentation")
	main._start_match()
	check(main.state == "countdown" and main.scores == [0, 0] and main.arena.puck.modulate.a == 1, "rematch restores puck")
	main._menu()
	check(main.arena.puck.visual_offset == Vector2.ZERO and main.arena.puck.modulate.a == 1, "menu restores puck")
	print(JSON.stringify({"check": "goal_flow", "failures": failures}))
	quit(0 if failures.is_empty() else 1)
