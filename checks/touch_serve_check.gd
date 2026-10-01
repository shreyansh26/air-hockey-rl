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

func wait_for_state(expected: String, limit := 180) -> void:
	for _i in range(limit):
		if main.state == expected:
			return
		await physics_frame
	check(false, "timed out waiting for " + expected)

func touch(point: Vector2, id: int, pressed := true, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = root.get_final_transform() * main.table_to_screen(point)
	event.index = id
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func drag(point: Vector2, id: int) -> void:
	var event := InputEventScreenDrag.new()
	event.position = root.get_final_transform() * main.table_to_screen(point)
	event.index = id
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.settings.sound = false
	main.settings.haptics = false
	main.settings.offset = 0.0
	main._start_match()
	check(main.state == "countdown" and is_equal_approx(main.timer, 0.7), "new match starts with a quick serve")
	check(main.arena.puck.position == Vector2(300, 500), "opening puck is on the centerline")
	check(main.arena.puck.freeze and not main.arena.paddles[0].freeze and not main.arena.paddles[1].freeze, "only puck is held before serve")
	main._begin_serve(2.0)
	var initial: Vector2 = main.arena.paddles[0].position
	var initial_bot: Vector2 = main.arena.paddles[1].position
	touch(Vector2(175, 880), 3)
	check(main.touch_id == 3 and main.drag_target.is_equal_approx(Vector2(175, 880)), "native touch targets the finger without a grab offset")
	check(main.arena.paddles[0].position == initial, "touch never teleports the paddle")
	await ticks(24)
	check(main.arena.paddles[0].position.x < initial.x - 40, "paddle follows touch during countdown")
	check(main.arena.paddles[1].position.distance_to(initial_bot) > 1, "trained bot also moves during countdown")
	check(main.arena.puck.position == Vector2(300, 500), "moving paddles leave the held puck at center")
	drag(Vector2(550, 880), 3)
	check(main.drag_target.is_equal_approx(Vector2(550, 880)), "moving finger targets matching table coordinates")
	await ticks(65)
	check(main.arena.paddles[0].position.x > 540, "finger reaches the table edge without reaching screen edge")
	check(main.arena.paddles[0].linear_velocity.length() <= main.arena.CONFIG.paddle_speed + 0.01, "touch retains the shared speed limit")
	touch(Vector2(550, 880), 3, true, true)
	check(main.touch_id == -1 and main.arena.paddles[0].command == Vector2.ZERO, "canceled touch clears the active pointer")
	touch(Vector2(250, 880), 4, true, true)
	check(main.touch_id == -1, "a canceled new touch never grabs a paddle")
	main.settings.offset = 40.0
	touch(Vector2(350, 880), 5)
	check(main.drag_target.is_equal_approx(Vector2(350, 840)), "configured touch offset remains available")
	touch(Vector2(350, 880), 5, false)
	main.settings.offset = 0.0
	await wait_for_state("rally", 180)
	touch(Vector2(320, 820), 6)
	main.arena.set_running(false)
	main.arena.paddles[1].reset_at(Vector2(80, 80))
	main.arena.puck.reset_at(Vector2(365, 30), Vector2(800, -2200))
	main.arena.last_position = main.arena.puck.position
	main.arena.set_running(true)
	await wait_for_state("goal", 30)
	check(main.serve_side == 1 and main.touch_id == 6, "goal serves the conceding side and preserves a held finger")
	var goal_paddle: Vector2 = main.arena.paddles[0].position
	var frozen_puck: Vector2 = main.arena.puck.position
	drag(Vector2(180, 900), 6)
	await ticks(25)
	check(main.arena.paddles[0].position.distance_to(goal_paddle) > 40, "paddle follows touch during the goal pause")
	check(main.arena.puck.position == frozen_puck, "goal presentation keeps the puck body frozen")
	await wait_for_state("countdown")
	check(main.arena.puck.position == Vector2(300, 500) and main.touch_id == 6, "next centered serve preserves ongoing touch")
	check(main.arena.paddles[0].position.x < 250, "next serve preserves the paddle position")
	await wait_for_state("rally")
	check(main.arena.puck.linear_velocity.y < 0, "serve launches toward the conceding top player")
	main._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.state == "paused" and main.touch_id == -1, "focus loss pauses and clears touch")
	var paused_position: Vector2 = main.arena.paddles[0].position
	await ticks(15)
	check(main.arena.paddles[0].position == paused_position, "paddle cannot drift while paused")
	main._resume()
	check(main.touch_id == -1, "resume does not resurrect an old touch")
	touch(Vector2(250, 850), 7)
	main._notification(Control.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(main.state == "paused" and main.touch_id == -1, "Android Back pauses and clears touch")
	main._resume()
	main._goal(1)
	check(main.serve_side == 0, "bottom concession selects the bottom player")
	await wait_for_state("rally")
	check(main.arena.puck.linear_velocity.y > 0, "serve launches toward the conceding bottom player")
	var openings := [false, false]
	seed(42)
	for _i in range(12):
		main._start_match()
		openings[main.serve_side] = true
	check(openings == [true, true], "new matches randomly select either opening player")
	main._menu()
	main.arena.reset_rally(0)
	check(main.arena.puck.position == Vector2(300, 600), "training bottom reset is unchanged")
	main.arena.reset_rally(1)
	check(main.arena.puck.position == Vector2(300, 400), "training top reset is unchanged")
	print(JSON.stringify({"check": "touch_serve", "failures": failures}))
	quit(0 if failures.is_empty() else 1)
