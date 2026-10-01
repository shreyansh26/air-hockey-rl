extends RefCounted

const ART = preload("res://assets/boot-splash.png")

static func play_on(parent: Control, reduced_effects: bool) -> void:
	if reduced_effects or OS.has_feature("training") or DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 30
	parent.add_child(layer)
	var screen := ColorRect.new()
	screen.color = Color("071621")
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var logo := TextureRect.new()
	logo.texture = ART
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := minf(parent.size.x * 0.86, parent.size.y * 0.6)
	logo.size = Vector2.ONE * edge
	var destination := (parent.size - logo.size) / 2
	logo.position = destination + Vector2(0, 10)
	logo.modulate.a = 0.5
	screen.add_child(logo)
	# The menu is already ready: this visual never pauses or consumes input.
	var tween := parent.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel()
	tween.tween_property(logo, "position", destination, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(logo, "modulate:a", 1.0, 0.22)
	tween.chain().tween_property(screen, "modulate:a", 0.0, 0.28)
	tween.chain().tween_callback(layer.queue_free)
