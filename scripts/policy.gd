extends RefCounted

var weights := PackedFloat32Array()
var hidden_a := PackedFloat32Array()
var hidden_b := PackedFloat32Array()
var matrices: Array[PackedVector4Array] = []
var biases: Array[PackedFloat32Array] = []
var input_groups := PackedVector4Array()
var hidden_groups := PackedVector4Array()
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
	matrices.clear()
	biases.clear()
	for layer in [[52, 64, 0], [64, 64, 3392], [64, 2, 7552]]:
		var columns: int = layer[0]
		var rows: int = layer[1]
		var offset: int = layer[2]
		var vectors := PackedVector4Array()
		vectors.resize(columns * rows / 4)
		for i in range(vectors.size()):
			var at := offset + i * 4
			vectors[i] = Vector4(weights[at], weights[at + 1], weights[at + 2], weights[at + 3])
		matrices.append(vectors)
		biases.append(weights.slice(offset + rows * columns, offset + rows * columns + rows))
	weights.clear()
	delay_ticks = int(manifest.get("delay_ticks", -1))
	if delay_ticks < 0 or delay_ticks > 40:
		return "Actor delay is outside the observation history."
	hidden_a.resize(64)
	hidden_b.resize(64)
	input_groups.resize(13)
	hidden_groups.resize(16)
	return ""

func predict(input: PackedFloat32Array) -> Vector2:
	if input.size() != 52 or matrices.size() != 3:
		error = "Invalid actor input/weights"
		return Vector2.ZERO
	for value in input:
		if not is_finite(value):
			error = "Non-finite observation"
			return Vector2.ZERO
	_group(input, input_groups)
	_layer(input_groups, hidden_a, 0)
	_group(hidden_a, hidden_groups)
	_layer(hidden_groups, hidden_b, 1)
	_group(hidden_b, hidden_groups)
	var action := Vector2.ZERO
	for row in range(2):
		var total: float = biases[2][row]
		var row_offset := row * 16
		for column in range(16):
			total += matrices[2][row_offset + column].dot(hidden_groups[column])
		if not is_finite(total):
			error = "Non-finite actor output"
			return Vector2.ZERO
		action[row] = clampf(total, -1, 1)
	return action

func _group(input: PackedFloat32Array, output: PackedVector4Array) -> void:
	for i in range(output.size()):
		var at := i * 4
		output[i] = Vector4(input[at], input[at + 1], input[at + 2], input[at + 3])

func _layer(input: PackedVector4Array, output: PackedFloat32Array, layer: int) -> void:
	var columns := input.size()
	for row in range(64):
		var total: float = biases[layer][row]
		var row_offset := row * columns
		for column in range(columns):
			total += matrices[layer][row_offset + column].dot(input[column])
		output[row] = tanh(total)
