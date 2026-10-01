extends RefCounted

const CONFIG = preload("res://resources/physics.tres")
const CAPACITY = 64
const TIME_BOUND_TICKS = 60.0
var samples: Array[PackedFloat32Array] = []
var cursor := 0
var previous_action := Vector2.ZERO

func sample(arena: Node2D, side: int) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var sign_frame := 1.0 if side == 0 else -1.0
	for body in [arena.puck, arena.paddles[side], arena.paddles[1 - side]]:
		var speed: float = CONFIG.puck_speed if body == arena.puck else CONFIG.paddle_speed
		values.append(clampf((body.position.x / CONFIG.width * 2 - 1) * sign_frame, -1.1, 1.1))
		values.append(clampf((body.position.y / CONFIG.height * 2 - 1) * sign_frame, -1.1, 1.1))
		values.append(clampf(body.linear_velocity.x / speed * sign_frame, -1, 1))
		values.append(clampf(body.linear_velocity.y / speed * sign_frame, -1, 1))
	return values

func reset(arena: Node2D, side: int) -> void:
	var initial := sample(arena, side)
	samples.clear()
	for _i in range(CAPACITY):
		samples.append(initial.duplicate())
	cursor = 0
	previous_action = Vector2.ZERO

func record(arena: Node2D, side: int) -> void:
	cursor = (cursor + 1) % CAPACITY
	samples[cursor] = sample(arena, side)

func encode(delay_ticks: int) -> PackedFloat32Array:
	assert(delay_ticks >= 0 and delay_ticks + 12 < CAPACITY)
	var result := PackedFloat32Array()
	result.resize(52)
	for frame in range(4):
		var age := delay_ticks + (3 - frame) * 4
		var values := samples[posmod(cursor - age, CAPACITY)]
		for feature in range(12):
			result[frame * 12 + feature] = values[feature]
	result[48] = previous_action.x
	result[49] = previous_action.y
	result[50] = delay_ticks / TIME_BOUND_TICKS
	result[51] = delay_ticks / TIME_BOUND_TICKS
	return result
