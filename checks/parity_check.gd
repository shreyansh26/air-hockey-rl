extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var cases = load("res://checks/parity_cases.gd").new()
	root.add_child(cases)
	var report: Dictionary = await cases.run()
	print("PARITY " + JSON.stringify(report))
	quit(1 if report.has("error") else 0)
