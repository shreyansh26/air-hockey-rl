extends RefCounted

var weights := PackedFloat32Array()
var hidden_a := PackedFloat32Array()
var hidden_b := PackedFloat32Array()
var delay_ticks := 10
var manifest: Dictionary = {}
var error := ""

func load_actor(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "Missing actor: " + path
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return "Invalid actor manifest: " + path
	manifest = parsed
	if manifest.get("schema_version") != 1 or manifest.get("dims") != [52.0, 64.0, 64.0, 2.0] or manifest.get("activations") != ["tanh", "tanh", "clip"] or manifest.get("matrix_order") != "row-major":
		return "Unsupported actor contract: " + path
	var schema = JSON.parse_string(FileAccess.get_file_as_string("res://models/schema.json"))
	if not schema is Dictionary or manifest.get("physics_hash") != schema.get("physics_hash") or manifest.get("schema_hash") != FileAccess.get_sha256("res://models/schema.json") or manifest.get("physics_hz") != 120 or manifest.get("action_ticks") != 4:
		return "Actor physics/schema mismatch. Restore the matching model bundle."
	var binary := path.get_base_dir().path_join("actor.bin")
	if not FileAccess.file_exists(binary) or FileAccess.get_sha256(binary) != manifest.get("weights_sha256"):
		return "Actor checksum mismatch: " + binary
	var bytes := FileAccess.get_file_as_bytes(binary)
	if bytes.size() != 30728:
		return "Actor must contain exactly 7682 FP32 parameters."
	weights = bytes.to_float32_array()
	for value in weights:
		if not is_finite(value):
			return "Actor contains non-finite weights."
	delay_ticks = int(manifest.get("delay_ticks", -1))
	if delay_ticks < 0 or delay_ticks > 40:
		return "Actor delay is outside the observation history."
	hidden_a.resize(64)
	hidden_b.resize(64)
	return ""

func predict(input: PackedFloat32Array) -> Vector2:
	if input.size() != 52 or weights.size() != 7682:
		error = "Invalid actor input/weights"
		return Vector2.ZERO
	for value in input:
		if not is_finite(value):
			error = "Non-finite observation"
			return Vector2.ZERO
	_layer(input, hidden_a, 52, 64, 0, true)
	_layer(hidden_a, hidden_b, 64, 64, 3392, true)
	var action := Vector2.ZERO
	for row in range(2):
		var total: float = weights[7680 + row]
		var row_offset := 7552 + row * 64
		for column in range(64):
			total += weights[row_offset + column] * hidden_b[column]
		if not is_finite(total):
			error = "Non-finite actor output"
			return Vector2.ZERO
		action[row] = clampf(total, -1, 1)
	return action

func _layer(input: PackedFloat32Array, output: PackedFloat32Array, columns: int, rows: int, offset: int, activate: bool) -> void:
	for row in range(rows):
		var total: float = weights[offset + columns * rows + row]
		var row_offset := offset + row * columns
		for column in range(columns):
			total += weights[row_offset + column] * input[column]
		output[row] = tanh(total) if activate else total
