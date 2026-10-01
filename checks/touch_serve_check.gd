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

func tracking_trial(legacy: bool) -> Dictionary:
	main._begin_serve(10.0)
	main.set_physics_process(false)
	main.arena.paddles[0].reset_at(Vector2(120, 850))
	await ticks(2)
	touch(Vector2(120, 850), 9)
	var lag := 0.0
	var peak_speed := 0.0
	for step in range(1, 73):
		var target := Vector2(120 + step * 5, 850) # 600 units/s, below the shared cap.
		drag(target, 9)
		if legacy:
			main.arena.drive_to(0, target)
		await physics_frame
		if step > 32:
			lag += target.distance_to(main.arena.paddles[0].position) / 40
		peak_speed = maxf(peak_speed, main.arena.paddles[0].linear_velocity.length())
	for _step in range(60):
		drag(Vector2(480, 850), 9)
		if legacy:
			main.arena.drive_to(0, Vector2(480, 850))
		await physics_frame
	var settling_error: float = main.arena.paddles[0].position.distance_to(Vector2(480, 850))
	touch(Vector2(480, 850), 9, false)
	main.set_physics_process(true)
	return {"mean_lag_units": lag, "peak_speed": peak_speed, "settling_error": settling_error}

func zigzag_trial(diagonal: bool) -> Dictionary:
	main._begin_serve(20.0)
	main.set_physics_process(false)
	var paddle = main.arena.paddles[0]
	paddle.reset_at(Vector2(240, 820))
	await ticks(2)
	touch(Vector2(240, 820), 10)
	var lag := 0.0
	var peak_error := 0.0
	var peak_speed := 0.0
	var peak_acceleration := 0.0
	var target := Vector2.ZERO
	for step in range(240):
		# One held finger, 60 Hz samples, reversing every 200 ms at 600 units/s.
		var phase := (step - step % 2) % 48
		var travel := float(mini(phase, 48 - phase)) * 5
		target = Vector2(240 + travel, 820 - travel * 0.5 if diagonal else 820)
		if step % 2 == 0:
			drag(target, 10)
		main._drive_player()
		var velocity: Vector2 = paddle.linear_velocity
		await physics_frame
		peak_acceleration = maxf(peak_acceleration, paddle.linear_velocity.distance_to(velocity) * 120)
		peak_speed = maxf(peak_speed, paddle.linear_velocity.length())
		if step >= 48:
			var error: float = target.distance_to(paddle.position)
			lag += error / 192
			peak_error = maxf(peak_error, error)
	var settled_tick := 0
	for step in range(60):
		# No drag events once the finger stops: the normal physics path must settle.
		main._drive_player()
		await physics_frame
		if settled_tick == 0 and target.distance_to(paddle.position) < 1 and paddle.linear_velocity.length() < 5:
			settled_tick = step + 1
	var result := {"mean_error": lag, "peak_error": peak_error, "peak_speed": peak_speed,
		"peak_acceleration": peak_acceleration, "settled_tick": settled_tick, "settling_error": target.distance_to(paddle.position)}
	touch(target, 10, false)
	main.set_physics_process(true)
	return result

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
	check(main.arena.paddles[0].command != Vector2.ZERO, "drag updates the motor command before the next physics tick")
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
	main.settings.offset = 60.0
	touch(Vector2(300, 1010), 5)
	check(main.touch_id == 5 and main.drag_target.is_equal_approx(Vector2(300, 950)), "offset permits a grab below the court to reach the back rail")
	touch(Vector2(300, 1010), 5, false)
	main.settings.offset = 0.0
	touch(Vector2(300, 1010), 5)
	check(main.touch_id == -1, "without offset, touches outside the court do not grab")
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
	check(Input.use_accumulated_input, "menus restore normal UI event batching")
	main.arena.reset_rally(0)
	check(main.arena.puck.position == Vector2(300, 600), "training bottom reset is unchanged")
	main.arena.reset_rally(1)
	check(main.arena.puck.position == Vector2(300, 400), "training top reset is unchanged")
	var legacy := await tracking_trial(true)
	var current := await tracking_trial(false)
	check(current.mean_lag_units < legacy.mean_lag_units * 0.6, "finger tracking must reduce moving-target lag by at least 40 percent")
	check(current.peak_speed <= main.arena.CONFIG.paddle_speed + 0.01, "faster response retains the shared motor speed cap")
	check(current.settling_error < 2, "paddle settles on a stationary finger without drifting")
	check(not Input.use_accumulated_input, "drag events are not held until a rendered frame")
	var zigzags := []
	for diagonal in [false, true]:
		var after := await zigzag_trial(diagonal)
		check(after.mean_error < 12, "fast zigzags keep mean error below 12 table units")
		check(after.peak_error < 30, "fast zigzags stay within one paddle radius")
		check(after.peak_speed <= main.arena.CONFIG.paddle_speed + 0.01, "zigzags retain the speed cap")
		check(after.peak_acceleration <= main.arena.CONFIG.paddle_acceleration + 1, "zigzags retain finite bounded acceleration")
		check(after.settled_tick > 0 and after.settled_tick <= 15, "stopping finger settles within 125 ms")
		check(after.settling_error < 1, "held finger settles without more input events")
		zigzags.append({"diagonal": diagonal, "after": after})
	print(JSON.stringify({"zigzags": zigzags, "check": "touch_serve", "failures": failures, "tracking": {"legacy": legacy, "current": current}}))
	quit(0 if failures.is_empty() else 1)
