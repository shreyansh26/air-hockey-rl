extends Node

# Present only in QA export presets. Commands/telemetry never ship in release.
var main: Control
var browser := false
var elapsed := 0.0
var autoplay := false
var soak_started := 0
var soak_matches := 0
var physics_report := {}
var parity_report := {}
var memory_samples := []
var frame_samples: Array[float] = []
var last_memory := 0
var js_callbacks := []

func initialize(value: Control) -> void:
	main = value
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 300
	browser = OS.has_feature("web")
	if browser:
		JavaScriptBridge.eval("""(() => { let p=document.createElement('details');p.id='qa-panel';p.style='position:fixed;bottom:0;left:0;z-index:9999;background:#071621;color:white;font:12px monospace;max-width:100vw';p.innerHTML='<summary>QA</summary><input aria-label="QA command" id="qa-command" style="width:400px"><pre id="qa-state" style="max-height:100px;overflow:auto"></pre>';document.body.append(p) })()""")

func _physics_process(_delta: float) -> void:
	if autoplay and main.state == "rally":
		main.arena.baseline(0, "intercept")

func _process(delta: float) -> void:
	if soak_started > 0:
		frame_samples.append(delta * 1000)
		if Time.get_ticks_msec() - last_memory >= 30000:
			last_memory = Time.get_ticks_msec()
			memory_samples.append({"seconds": (last_memory - soak_started) / 1000.0, "bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
		if main.state == "results":
			soak_matches += 1
			main._start_match()
		if Time.get_ticks_msec() - soak_started >= 1200000:
			autoplay = false
			main._pause()
			_write_report()
			soak_started = 0
	elapsed += delta
	if elapsed < 0.2:
		return
	elapsed = 0
	var command_text := ""
	if browser:
		command_text = str(JavaScriptBridge.eval("document.getElementById('qa-command').value"))
		if command_text:
			JavaScriptBridge.eval("document.getElementById('qa-command').value=''")
	elif FileAccess.file_exists("user://qa-command.json"):
		command_text = FileAccess.get_file_as_string("user://qa-command.json")
		DirAccess.remove_absolute("user://qa-command.json")
	if command_text:
		var command = JSON.parse_string(command_text)
		if command is Dictionary:
			_command(command)
	var json := JSON.stringify(snapshot())
	if browser:
		JavaScriptBridge.eval("document.getElementById('qa-state').textContent=" + JSON.stringify(json))
	else:
		var file := FileAccess.open("user://qa-state.json", FileAccess.WRITE)
		if file:
			file.store_string(json)

func _command(command: Dictionary) -> void:
	match command.get("type", ""):
		"goal":
			if main.state != "rally":
				return
			var scoring_side := int(command.get("side", 0))
			main.arena.set_running(false)
			main.arena.paddles[0].reset_at(Vector2(80, 920))
			main.arena.paddles[1].reset_at(Vector2(80, 80))
			main.arena.puck.reset_at(Vector2(300, 35 if scoring_side == 0 else 965), Vector2(0, -2300 if scoring_side == 0 else 2300))
			main.arena.last_position = main.arena.puck.position
			main.history.reset(main.arena, 1)
			main.arena.set_running(true)
		"physics":
			_run_physics()
		"parity":
			_run_parity()
		"soak":
			autoplay = true
			soak_started = Time.get_ticks_msec()
			last_memory = soak_started
			memory_samples = []
			frame_samples.clear()
			soak_matches = 0
			main._start_match()
		"stop":
			autoplay = false
			_write_report()
			soak_started = 0
			main._pause()

func _run_physics() -> void:
	main._menu()
	physics_report = {"running": true}
	var cases = load("res://checks/physics_cases.gd").new()
	add_child(cases)
	physics_report = await cases.run()
	cases.queue_free()
	print("QA_PHYSICS " + JSON.stringify(physics_report))

func _run_parity() -> void:
	main._menu()
	parity_report = {"running": true}
	var cases = load("res://checks/parity_cases.gd").new()
	add_child(cases)
	parity_report = await cases.run()
	cases.queue_free()
	print("QA_PARITY " + JSON.stringify(parity_report))

func percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * fraction)]

func snapshot() -> Dictionary:
	return {"state": main.state, "scores": main.scores, "level": main.level, "settings": main.settings,
		"paddle": [main.arena.paddles[0].position.x, main.arena.paddles[0].position.y],
		"bot": [main.arena.paddles[1].position.x, main.arena.paddles[1].position.y], "contacts": main.arena.contacts,
		"touch_id": main.touch_id, "model_hash": main.actor.manifest.weights_sha256 if main.actor else "prototype",
		"model_error": main.model_error, "physics": physics_report, "parity": parity_report, "storage_ok": main.storage_ok,
		"origin": [main.table_origin.x, main.table_origin.y], "scale": main.table_scale,
		"viewport": [main.size.x, main.size.y], "actor_ms_p95": percentile(main.actor_times, 0.95),
		"frame_ms_p50": percentile(main.frames, 0.5), "frame_ms_p95": percentile(main.frames, 0.95),
		"frame_ms_p99": percentile(main.frames, 0.99), "soak_seconds": (Time.get_ticks_msec() - soak_started) / 1000.0 if soak_started else 0,
		"soak_matches": soak_matches}

func _write_report() -> void:
	var report := snapshot()
	report["memory"] = memory_samples
	report["all_frame_ms"] = {"p50": percentile(frame_samples, 0.5), "p95": percentile(frame_samples, 0.95), "p99": percentile(frame_samples, 0.99)}
	var file := FileAccess.open("user://qa-soak.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	print("QA_SOAK " + JSON.stringify(report))
