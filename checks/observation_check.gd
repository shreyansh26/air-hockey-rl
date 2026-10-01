extends SceneTree
const OBS = preload("res://scripts/observation.gd")
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, text: String) -> void:
	if not value:
		failures.append(text)
		push_error(text)
func run() -> void:
	var arena = load("res://scenes/arena.tscn").instantiate()
	root.add_child(arena)
	await physics_frame
	arena.reset_rally()
	arena.puck.reset_at(Vector2(150, 250), Vector2(230, -460))
	var bottom = OBS.new()
	var top = OBS.new()
	bottom.reset(arena, 0)
	top.reset(arena, 1)
	var b: PackedFloat32Array = bottom.encode(10)
	var t: PackedFloat32Array = top.encode(10)
	check(b.size() == 52, "52 features")
	check(absf(b[0] + 0.5) < 0.00001 and absf(b[1] + 0.5) < 0.00001, "position normalization")
	check(absf(b[2] - 0.1) < 0.00001 and absf(b[3] + 0.2) < 0.00001, "velocity normalization")
	check(absf(t[0] + b[0]) < 0.00001 and absf(t[2] + b[2]) < 0.00001, "top rotation")
	check(absf(b[50] - 1.0 / 6) < 0.00001 and b[50] == b[51], "delay and age")
	for i in range(32):
		arena.puck.position.x = 100 + i
		bottom.record(arena, 0)
	b = bottom.encode(10)
	for frame in range(4):
		check(absf(b[frame * 12] - ((100 + 31 - 10 - (3 - frame) * 4) / 600.0 * 2 - 1)) < 0.00001, "oldest-to-newest history")
	bottom.previous_action = Vector2(0.2, -0.7)
	check(absf(bottom.encode(0)[48] - 0.2) < 0.00001, "previous action")
	bottom.reset(arena, 0)
	check(bottom.encode(10)[48] == 0, "history reset")
	arena.paddles[0].set_command(Vector2(2, 2))
	check(absf(arena.paddles[0].command.length() - 1) < 0.00001, "action vector cap")
	print(JSON.stringify({"check": "observation", "failures": failures}))
	quit(0 if failures.is_empty() else 1)
