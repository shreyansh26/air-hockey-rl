extends Node

# Present only in QA export presets. Commands/telemetry never ship in release.
var main: Control
var browser := false
var elapsed := 0.0
var autoplay := false
var soak_started := 0
var soak_matches := 0
var soak_active_seconds := 0.0
var soak_complete := false
var soak_stalls := 0
var soak_invalid_states := 0
var soak_out_of_bounds := 0
var soak_physics_ticks := 0
var previous_tick := -1
var physics_report := {}
var parity_report := {}
var memory_samples := []
var frame_bins := PackedInt32Array()
var frame_count := 0
var last_memory := 0
var js_callbacks := []
var telemetry_enabled := true
var silence_until := 0
var boot_id := str(Time.get_unix_time_from_system())
var last_goal := {}

func initialize(value: Control) -> void:
	main = value
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 300
	browser = OS.has_feature("web")
	main.arena.goal.connect(func(side):
		last_goal = {"side": side, "scores": main.scores.duplicate(), "puck": [main.arena.puck.position.x, main.arena.puck.position.y]})
	main.arena.stalled.connect(func():
		if soak_started > 0:
			soak_stalls += 1
			if main.arena.last_stall_reason == "out_of_bounds":
				soak_out_of_bounds += 1
			if not main.arena.puck.position.is_finite() or not main.arena.puck.linear_velocity.is_finite():
				soak_invalid_states += 1)
	if browser:
		JavaScriptBridge.eval("""(() => { let p=document.createElement('details');p.id='qa-panel';p.open=true;p.style='position:fixed;bottom:0;left:0;z-index:9999;background:#071621;color:white;font:12px monospace;max-width:100vw';p.innerHTML='<summary>QA</summary><input aria-label="QA command" id="qa-command" style="width:min(400px,95vw)"><pre id="qa-state" style="max-height:100px;overflow:auto"></pre>';document.body.append(p) })()""")

func _physics_process(_delta: float) -> void:
	if autoplay and main.state == "rally":
		main.arena.baseline(0, "intercept")
		var tick: int = main.arena.puck.integration_ticks
		soak_physics_ticks += tick if previous_tick < 0 or tick < previous_tick else tick - previous_tick
		previous_tick = tick

func _process(delta: float) -> void:
	if Time.get_ticks_msec() < silence_until:
		return
	# Preserve the brief completed fade so input/device polling cannot miss it.
	if main.state == "goal" and main.arena.puck.modulate.a == 0:
		last_goal["hidden_puck"] = [main.arena.puck.position.x, main.arena.puck.position.y]
		last_goal["visual_offset"] = [main.arena.puck.visual_offset.x, main.arena.puck.visual_offset.y]
		last_goal["alpha"] = main.arena.puck.modulate.a
	if soak_started > 0:
		if main.state in ["rally", "countdown", "goal"]:
			soak_active_seconds += delta
			frame_bins[clampi(int(delta * 10000), 0, 10000)] += 1
			frame_count += 1
		if Time.get_ticks_msec() - last_memory >= 30000:
			last_memory = Time.get_ticks_msec()
			memory_samples.append({"seconds": (last_memory - soak_started) / 1000.0, "bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
		if main.state == "results":
			soak_matches += 1
			main._start_match()
		if soak_active_seconds >= 1200:
			autoplay = false
			soak_complete = true
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
	if not telemetry_enabled and not command_text:
		return
	var json := JSON.stringify(snapshot())
	if browser:
		JavaScriptBridge.eval("document.getElementById('qa-state').textContent=" + JSON.stringify(json))
	else:
		var file := FileAccess.open("user://qa-state.tmp", FileAccess.WRITE)
		if file:
			file.store_string(json)
			file.close()
			DirAccess.rename_absolute("user://qa-state.tmp", "user://qa-state.json")

func _command(command: Dictionary) -> void:
	match command.get("type", ""):
		"snapshot":
			pass
		"silence":
			silence_until = Time.get_ticks_msec() + clampi(int(command.get("seconds", 45)), 1, 60) * 1000
			telemetry_enabled = false
		"telemetry":
			telemetry_enabled = bool(command.get("enabled", true))
		"shot":
			if main.state != "rally":
				return
			main.arena.set_running(false)
			main.arena.paddles[0].reset_at(Vector2(300, 830))
			main.arena.paddles[1].reset_at(Vector2(300, 170))
			main.arena.puck.reset_at(Vector2(450, 480), Vector2(-250, -800))
			main.arena.last_position = main.arena.puck.position
			main.history.reset(main.arena, 1)
			main.arena.set_running(true)
		"goal":
			if main.state != "rally":
				return
			var scoring_side := int(command.get("side", 0))
			main.arena.set_running(false)
			main.arena.paddles[0].reset_at(Vector2(80, 920))
			main.arena.paddles[1].reset_at(Vector2(80, 80))
			var angled: bool = command.get("angled", false)
			main.arena.puck.reset_at(Vector2(365 if angled else 300, 30 if scoring_side == 0 else 970), Vector2(800 if angled else 0, (-1 if scoring_side == 0 else 1) * (2200 if angled else 2300)))
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
			frame_bins.resize(10001)
			frame_bins.fill(0)
			frame_count = 0
			soak_matches = 0
			soak_active_seconds = 0
			soak_complete = false
			soak_stalls = 0
			soak_invalid_states = 0
			soak_out_of_bounds = 0
			soak_physics_ticks = 0
			previous_tick = -1
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
	var widgets := []
	_collect_widgets(main, widgets)
	return {"state": main.state, "scores": main.scores, "level": main.level, "settings": main.settings,
		"timer": main.timer, "serve_side": main.serve_side, "audio_playing": main.audio.playing, "last_goal": last_goal,
		"board_scores": [main.human_score_label.text, main.score_label.text],
		"physics_frame_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
		"engine_frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
		"debug_build": OS.has_feature("debug"), "telemetry_enabled": telemetry_enabled,
		"silence_until": silence_until,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT), "resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"boot_id": boot_id, "static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "texture_memory_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"panel": main.panel_mode, "widgets": widgets,
		"paddle": [main.arena.paddles[0].position.x, main.arena.paddles[0].position.y],
		"paddle_velocity": [main.arena.paddles[0].linear_velocity.x, main.arena.paddles[0].linear_velocity.y],
		"paddle_frozen": main.arena.paddles[0].freeze, "bot_frozen": main.arena.paddles[1].freeze,
		"puck_frozen": main.arena.puck.freeze,
		"bot": [main.arena.paddles[1].position.x, main.arena.paddles[1].position.y], "contacts": main.arena.contacts,
		"puck": [main.arena.puck.position.x, main.arena.puck.position.y], "puck_velocity": [main.arena.puck.linear_velocity.x, main.arena.puck.linear_velocity.y],
		"puck_alpha": main.arena.puck.modulate.a, "puck_visual_offset": [main.arena.puck.visual_offset.x, main.arena.puck.visual_offset.y],
		"touch_id": main.touch_id, "model_hash": main.actor.manifest.weights_sha256 if main.actor else "prototype",
		"model_error": main.model_error, "physics": physics_report, "parity": parity_report, "storage_ok": main.storage_ok,
		"origin": [main.table_origin.x, main.table_origin.y], "scale": main.table_scale,
		"stretch": [main.table_stretch.x, main.table_stretch.y],
		"viewport": [main.size.x, main.size.y], "actor_ms_p95": percentile(main.actor_times, 0.95),
		"frame_ms_p50": percentile(main.frames, 0.5), "frame_ms_p95": percentile(main.frames, 0.95),
		"frame_ms_p99": percentile(main.frames, 0.99), "soak_seconds": soak_active_seconds,
		"soak_wall_seconds": (Time.get_ticks_msec() - soak_started) / 1000.0 if soak_started else 0,
		"soak_complete": soak_complete, "soak_stalls": soak_stalls, "soak_invalid_states": soak_invalid_states, "soak_out_of_bounds": soak_out_of_bounds,
		"simulated_rally_seconds": soak_physics_ticks / 120.0, "soak_matches": soak_matches}

func _collect_widgets(node: Node, widgets: Array) -> void:
	if node is BaseButton and node.is_visible_in_tree():
		var rect: Rect2 = node.get_global_rect()
		widgets.append({"text": node.text, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "type": node.get_class()})
	if node is PopupMenu and node.visible:
		var entries := []
		for i in range(node.item_count):
			entries.append(node.get_item_text(i))
		widgets.append({"type": "PopupMenu", "items": entries, "rect": [node.position.x, node.position.y, node.size.x, node.size.y]})
	for child in node.get_children(true):
		_collect_widgets(child, widgets)

func _write_report() -> void:
	var report := snapshot()
	report["memory"] = memory_samples
	report["all_frame_ms"] = {"p50": _frame_percentile(0.5), "p95": _frame_percentile(0.95), "p99": _frame_percentile(0.99), "resolution_ms": 0.1, "samples": frame_count}
	var file := FileAccess.open("user://qa-soak.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	print("QA_SOAK " + JSON.stringify(report))

func _frame_percentile(fraction: float) -> float:
	var cumulative := 0
	var target := int((frame_count - 1) * fraction)
	for i in range(frame_bins.size()):
		cumulative += frame_bins[i]
		if cumulative > target:
			return i / 10.0
	return 0
