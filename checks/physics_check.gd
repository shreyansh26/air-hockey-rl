extends SceneTree
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var cases = load("res://checks/physics_cases.gd").new()
    root.add_child(cases)
    var report: Dictionary = await cases.run()
    print(JSON.stringify(report))
    quit(0 if report.failures.is_empty() else 1)
