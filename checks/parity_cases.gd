extends Node

func run() -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes("res://checks/fixtures/observations.bin")
	if bytes.size() != 10000 * 52 * 4:
		return {"error": "Missing 10k observation fixtures"}
	var observations := bytes.to_float32_array()
	var report := {}
	for level in ["easy", "medium", "hard", "insane"]:
		var actor = load("res://scripts/policy.gd").new()
		var error: String = actor.load_actor("res://models/" + level + "/actor.json")
		if error:
			return {"error": error}
		var expected := FileAccess.get_file_as_bytes("res://checks/fixtures/" + level + ".bin").to_float32_array()
		if expected.size() != 20000:
			return {"error": "Missing action fixtures"}
		var worst := 0.0
		var total_usec := 0
		var timings: Array[int] = []
		for i in range(10000):
			var obs := observations.slice(i * 52, (i + 1) * 52)
			var started := Time.get_ticks_usec()
			var action: Vector2 = actor.predict(obs)
			var elapsed := Time.get_ticks_usec() - started
			total_usec += elapsed
			timings.append(elapsed)
			worst = maxf(worst, maxf(absf(action.x - expected[i * 2]), absf(action.y - expected[i * 2 + 1])))
			if i % 32 == 31:
				await get_tree().process_frame
		if worst > 0.0001:
			return {"error": "Action parity failed", "level": level, "max_abs_error": worst}
		timings.sort()
		report[level] = {"observations": 10000, "max_abs_error": worst, "mean_ms": total_usec / 10000000.0, "p95_ms": timings[9499] / 1000.0, "weights_hash": actor.manifest.weights_sha256}
	return report
