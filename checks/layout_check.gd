extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var sizes := [Vector2(360, 800), Vector2(600, 1340), Vector2(695, 1000), Vector2(768, 1024), Vector2(1024, 768), Vector2(1440, 900)]
	for viewport in sizes:
		main.size = viewport
		main._layout()
		await process_frame
		await process_frame
		main._layout()
		var table_rect := Rect2(main.table_origin, Vector2(600, 1000) * main.table_stretch)
		check(Rect2(Vector2.ZERO, viewport).encloses(table_rect), "Playable bounds clipped: " + str(viewport))
		check(table_rect.encloses(main.score_label.get_rect()) and table_rect.encloses(main.human_score_label.get_rect()), "Scores must be on the board")
		check(main.screen_to_table(main.score_label.get_rect().get_center()).distance_to(Vector2(535, 455)) < 0.001, "Bot score above centerline")
		check(main.screen_to_table(main.human_score_label.get_rect().get_center()).distance_to(Vector2(535, 545)) < 0.001, "Human score below centerline")
		check(table_rect.encloses(main.pause_button.get_rect()), "Pause must be on the board")
		check(main.pause_button.size.y >= 74, "Pause must keep its touch target")
		for point in [Vector2.ZERO, Vector2(600, 0), Vector2(0, 1000), Vector2(600, 1000), Vector2(300, 750)]:
			check(main.screen_to_table(main.table_to_screen(point)).distance_to(point) < 0.001, "Touch transform mismatch")
		check(is_equal_approx(main.table_stretch.x, main.table_stretch.y), "Puck and paddles must stay circular")
		var display_size: Vector2 = Vector2(680, 1080) * main.table_stretch
		check(is_equal_approx(display_size.x, viewport.x) or is_equal_approx(display_size.y, viewport.y), "Court must fill at least one display dimension")
		check(main.arena.scale == Vector2.ONE and main.arena.puck.scale == Vector2.ONE and main.arena.paddles[0].scale == Vector2.ONE, "Display stretch must not scale physics")
		check(Rect2(Vector2.ZERO, viewport).encloses(main.overlay.get_rect()), "Menu clipped")
	main.touch_controls = true
	main._layout()
	main.touch_controls = false
	main._layout()
	check(not main.has_node("Brand") and not main.has_node("Subtitle"), "Branding appears only in center board art")
	for child in main.get_children():
		if child is Label:
			check(not "DRAG" in child.text and not "KEYS" in child.text, "No input instructions outside board")
	main.scores = [4, 2]
	main._update_score()
	check(main.score_label.text == "2" and main.human_score_label.text == "4", "Pure numeric board scores")
	main._customize()
	main._fit_panel()
	check(main.content.get_parent() is ScrollContainer, "Long menus must scroll")
	check(Rect2(Vector2.ZERO, main.size).encloses(main.overlay.get_rect()), "Customization panel clipped")
	print(JSON.stringify({"check": "layout", "viewports": sizes.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
