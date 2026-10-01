extends Node

# Adapted from Godot RL Agents Sync (MIT, see THIRD_PARTY.md).
# Same 4-byte little-endian JSON protocol; .NET/inference/demo paths removed.
const ARENA = preload("res://scenes/arena.tscn")
const CONTROLLER = preload("res://training/controller.gd")
var controllers: Array[Node] = []
var stream := StreamPeerTCP.new()
var buffer := PackedByteArray()
var expected := -1
var remaining := 0
var waiting := true
var step_ready := false
var deadline := 0
var timeout_msec := 120000
var options := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1000
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 1
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			var pair := arg.trim_prefix("--").split("=", true, 1)
			options[pair[0]] = pair[1]
	var count := clampi(int(options.get("arenas", "16")), 1, 64)
	var seed_value := int(options.get("seed", "1"))
	for i in range(count):
		var viewport := SubViewport.new()
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.size = Vector2i(2, 2)
		viewport.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(viewport)
		var arena: Node2D = ARENA.instantiate()
		viewport.add_child(arena)
		var controller: Node = CONTROLLER.new()
		arena.add_child(controller)
		controller.initialize(arena, seed_value + i * 1009)
		controller.delay_ticks = int(options.get("delay", "10"))
		controller.opening_serve = i % 2
		controllers.append(controller)
	get_tree().paused = true
	deadline = Time.get_ticks_msec() + timeout_msec
	var error := stream.connect_to_host("127.0.0.1", int(options.get("port", "11008")))
	if error != OK:
		fail("Cannot connect to Python: " + str(error))
	stream.set_no_delay(true)

func fail(message: String) -> void:
	push_error(message)
	stream.disconnect_from_host()
	get_tree().quit(2)

func _process(_delta: float) -> void:
	if step_ready:
		step_ready = false
		_reply_step()
	if not waiting:
		return
	stream.poll()
	if Time.get_ticks_msec() > deadline:
		fail("Training bridge timed out")
		return
	if stream.get_status() == StreamPeerTCP.STATUS_ERROR or stream.get_status() == StreamPeerTCP.STATUS_NONE:
		fail("Training bridge disconnected")
		return
	var available := stream.get_available_bytes()
	if available > 0:
		var received := stream.get_data(available)
		if received[0] != OK:
			fail("Training bridge read failure")
			return
		buffer.append_array(received[1])
	while waiting:
		if expected == -1 and buffer.size() >= 4:
			expected = buffer.decode_u32(0)
			buffer = buffer.slice(4)
			if expected <= 0 or expected > 1048576:
				fail("Training packet exceeds 1 MiB")
				return
		if expected == -1 or buffer.size() < expected:
			break
		var message = JSON.parse_string(buffer.slice(0, expected).get_string_from_utf8())
		buffer = buffer.slice(expected)
		expected = -1
		deadline = Time.get_ticks_msec() + timeout_msec
		if not message is Dictionary:
			fail("Invalid JSON packet")
			return
		_handle(message)
	if waiting:
		OS.delay_usec(100)

func _physics_process(_delta: float) -> void:
	if waiting:
		return
	if remaining == 0:
		# At this boundary the engine has completed AND synchronized four steps.
		# Pause before another arena callback/solver step, not in the render phase.
		for controller in controllers:
			controller.capture_history()
		_reply_step()
		return
	remaining -= 1

func _send(message: Dictionary) -> void:
	var payload := JSON.stringify(message, "", false).to_utf8_buffer()
	var packet := PackedByteArray()
	packet.resize(4)
	packet.encode_u32(0, payload.size())
	packet.append_array(payload)
	if stream.put_data(packet) != OK:
		fail("Training bridge write failure")

func _handle(message: Dictionary) -> void:
	match message.get("type", ""):
		"handshake":
			if message.get("major_version") != "0":
				fail("Unsupported Godot RL protocol")
		"env_info":
			_send({"type": "env_info", "n_agents": controllers.size(), "action_space": {"move": {"size": 2, "action_type": "continuous"}}, "observation_space": {"obs": {"size": [52], "space": "box", "low": -1.1, "high": 1.1}}})
		"reset":
			var obs := []
			var info := []
			for i in range(controllers.size()):
				var controller := controllers[i]
				if message.get("seed") != null:
					controller.rng.seed = int(message.seed) + i * 1009
				controller.reset_episode()
				obs.append({"obs": Array(controller.observation())})
				info.append({"delay_ticks": controller.delay_ticks, "seed_state": str(controller.rng.state)})
			_send({"type": "reset", "obs": obs, "info": info})
		"action":
			var actions = message.get("action", [])
			if not actions is Array or actions.size() != controllers.size():
				fail("Invalid action batch")
				return
			for i in range(controllers.size()):
				var vector = actions[i].get("move", []) if actions[i] is Dictionary else []
				if not vector is Array or vector.size() != 2 or not (vector[0] is float or vector[0] is int) or not (vector[1] is float or vector[1] is int) or not is_finite(float(vector[0])) or not is_finite(float(vector[1])):
					fail("Action must be two finite numbers")
					return
				controllers[i].set_action(Vector2(clampf(vector[0], -1, 1), clampf(vector[1], -1, 1)))
			remaining = 4
			waiting = false
			get_tree().paused = false
		"configure":
			for controller in controllers:
				controller.mode = str(message.get("mode", controller.mode))
				controller.limit_ticks = clampi(int(message.get("limit_ticks", controller.limit_ticks)), 4, 36000)
				controller.shaping = clampf(float(message.get("shaping", controller.shaping)), 0, 0.1)
				controller.hit_reward = clampf(float(message.get("hit_reward", controller.hit_reward)), 0, 0.1)
				controller.opponent_mode = str(message.get("opponent_mode", controller.opponent_mode))
				controller.fixed_style = str(message.get("opponent_style", controller.fixed_style))
				controller.evaluation_match = bool(message.get("evaluation_match", controller.evaluation_match))
				if message.has("opponents"):
					controller.opponents.assign(message.opponents)
			if message.has("rng_states"):
				for i in range(controllers.size()):
					controllers[i].rng.state = int(message.rng_states[i])
			_send({"type": "configured"})
		"inspect":
			var states := []
			for controller in controllers:
				states.append({"ticks": controller.arena.ticks, "rng_state": str(controller.rng.state), "integration_ticks": controller.arena.puck.integration_ticks, "episode_ticks": controller.episode_ticks, "puck": [controller.arena.puck.position.x, controller.arena.puck.position.y], "velocity": [controller.arena.puck.linear_velocity.x, controller.arena.puck.linear_velocity.y], "world": str(controller.arena.get_world_2d().get_instance_id())})
			_send({"type": "inspect", "states": states})
		"fixture":
			var index := clampi(int(message.get("index", 0)), 0, controllers.size() - 1)
			var controller := controllers[index]
			controller.reset_episode()
			controller.arena.paddles[0].reset_at(Vector2(80, 930))
			controller.arena.paddles[1].reset_at(Vector2(80, 70))
			if message.get("case") == "goal":
				controller.arena.puck.reset_at(Vector2(300, 0), Vector2(0, -2300))
			else:
				controller.arena.puck.reset_at(Vector2(300, 500), Vector2(120, 0))
			controller.arena.last_position = controller.arena.puck.position
			controller.history.reset(controller.arena, 0)
			_send({"type": "fixture"})
		"close":
			stream.disconnect_from_host()
			get_tree().quit()
		_:
			fail("Unsupported bridge command")

func _reply_step() -> void:
	get_tree().paused = true
	waiting = true
	deadline = Time.get_ticks_msec() + timeout_msec
	var obs := []
	var rewards := []
	var terminated := []
	var truncated := []
	var infos := []
	for controller in controllers:
		var info := {"physics_ticks": controller.episode_ticks, "hits": controller.arena.contacts[0], "winner": controller.winner, "stalls": controller.stalls}
		var final_obs := Array(controller.observation())
		rewards.append(controller.finish_step())
		terminated.append(controller.terminated)
		truncated.append(controller.truncated)
		if controller.terminated or controller.truncated:
			info["terminal_observation"] = final_obs
			info["TimeLimit.truncated"] = controller.truncated and not controller.terminated
			info["episode"] = {"r": controller.episode_reward, "l": ceili(controller.episode_ticks / 4.0)}
			controller.reset_episode()
			info["reset_info"] = {"delay_ticks": controller.delay_ticks, "seed_state": str(controller.rng.state)}
		infos.append(info)
		obs.append({"obs": Array(controller.observation())})
	_send({"type": "step", "obs": obs, "reward": rewards, "terminated": terminated, "truncated": truncated, "info": infos})
