extends Control

const ARENA = preload("res://scenes/arena.tscn")
const TABLE = preload("res://scripts/table.gd")
const LEVELS = ["Easy", "Medium", "Hard", "Insane"]
const TINTS = [Color("ffbd73"), Color("65d3e5"), Color("e99cbe"), Color("b2d789")]
const PUCK_TINTS = [Color("eaf8ff"), Color("ffbd73"), Color("e99cbe"), Color("b2d789")]
var arena: Node2D
var arena_view: SubViewport
var arena_sprite: Sprite2D
var table_origin := Vector2.ZERO
var table_scale := 1.0
var table_stretch := Vector2.ONE
var touch_controls := false
var safe_bounds := Rect2()
var table: Node2D
var overlay: PanelContainer
var content: VBoxContainer
var score_label: Label
var human_score_label: Label
var state_label: Label
var pause_button: Button
var state := "menu"
var before_pause := "rally"
var timer := 0.0
var scores := [0, 0]
var serve_side := 0
var presentation_ticks := 0
var touch_id := -1
var drag_target := Vector2.ZERO
var drag_offset := Vector2.ZERO
var level := 1
var settings := {"table": 0, "puck": 0, "human": 0, "bot": 1, "sound": false, "haptics": true, "reduced_effects": false, "offset": 0.0, "level": 1, "settings_version": 1}
var actor: RefCounted
var history: RefCounted
var model_error := ""
var actor_times: Array[float] = []
var frames: Array[float] = []
var trail: Array[Vector2] = []
var audio: AudioStreamPlayer
var storage_ok := true
var last_sample_tick := 0
var last_decision_tick := -1
var particles: Array[Dictionary] = []
var panel_mode := "menu"
var browser_callbacks := []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	_load_settings()
	_build_theme()
	arena_view = SubViewport.new()
	arena_view.size = Vector2i(680, 1080)
	arena_view.world_2d = World2D.new()
	arena_view.transparent_bg = true
	arena_view.handle_input_locally = false
	arena_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(arena_view)
	arena = ARENA.instantiate()
	arena.position = Vector2(40, 40)
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	arena_view.add_child(arena)
	arena_sprite = Sprite2D.new()
	arena_sprite.texture = arena_view.get_texture()
	arena_sprite.centered = false
	add_child(arena_sprite)
	table = Node2D.new()
	table.set_script(TABLE)
	arena.add_child(table)
	arena.move_child(table, 0)
	arena.goal.connect(_goal)
	arena.stalled.connect(_stall)
	arena.impact.connect(_impact)
	audio = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/impact.wav"):
		audio.stream = load("res://assets/impact.wav")
	add_child(audio)
	_build_hud()
	_apply_cosmetics()
	resized.connect(_layout)
	_layout()
	_menu()
	if OS.has_feature("qa"):
		var qa = load("res://checks/runtime_check.gd").new()
		add_child(qa)
		qa.initialize(self)
	if OS.has_feature("web"):
		var pause_callback = JavaScriptBridge.create_callback(func(_args): _pause())
		browser_callbacks.append(pause_callback)
		JavaScriptBridge.get_interface("window").addEventListener("blur", pause_callback)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", pause_callback)
	preload("res://scripts/launch_intro.gd").play_on(self, bool(settings.reduced_effects))

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", Color("e3edf1"))
	theme.set_color("font_color", "Button", Color("e3edf1"))
	theme.set_constant("v_separation", "PopupMenu", 44)
	theme.set_font_size("font_size", "PopupMenu", 22)
	for type in ["Button", "OptionButton"]:
		for key in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("133041") if key == "normal" else Color("225167")
			box.border_color = Color("65d3e5") if key == "focus" else Color("294b5c")
			box.set_border_width_all(2 if key == "focus" else 1)
			box.set_corner_radius_all(10)
			box.content_margin_left = 20
			box.content_margin_right = 20
			box.content_margin_top = 12
			box.content_margin_bottom = 12
			theme.set_stylebox(key, type, box)

func _label(text: String, size_px := 22) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 74
	button.pressed.connect(callback)
	content.add_child(button)
	return button

func _build_hud() -> void:
	touch_controls = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	score_label = _label("0", 60)
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(score_label)
	human_score_label = _label("0", 60)
	human_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(human_score_label)
	state_label = _label("", 14)
	state_label.modulate = Color("b3d2df")
	add_child(state_label)
	for label in [score_label, human_score_label, state_label]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.04, 0.06, 0.85))
		label.add_theme_constant_override("outline_size", 4)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.custom_minimum_size = Vector2(104, 74)
	pause_button.pressed.connect(_pause)
	add_child(pause_button)
	overlay = PanelContainer.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.025, 0.06, 0.087, 0.97)
	panel.border_color = Color("345365")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(18)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 26
	panel.content_margin_bottom = 26
	overlay.add_theme_stylebox_override("panel", panel)
	add_child(overlay)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	overlay.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)

func screen_to_table(point: Vector2) -> Vector2:
	return (point - table_origin) / table_stretch

func table_to_screen(point: Vector2) -> Vector2:
	return table_origin + point * table_stretch

func _layout() -> void:
	if not arena:
		return
	safe_bounds = Rect2(Vector2.ZERO, size)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0 and safe.has_area():
			var screen_scale := size / Vector2(screen)
			safe_bounds = Rect2(Vector2(safe.position) * screen_scale, Vector2(safe.size) * screen_scale)
	# Maximize the court while keeping circular art and collision footprints aligned.
	# Shared Arena physics remains at 600 × 1000 on every display.
	var display_rect := Rect2(Vector2.ZERO, size)
	var scale_fit := minf(size.x / 680.0, size.y / 1080.0)
	display_rect.size = Vector2(680, 1080) * scale_fit
	display_rect.position = (size - display_rect.size) / 2
	table_stretch = display_rect.size / Vector2(680, 1080)
	table_scale = minf(table_stretch.x, table_stretch.y)
	arena_sprite.scale = table_stretch
	arena_sprite.position = display_rect.position
	table_origin = arena_sprite.position + Vector2(40, 40) * table_stretch
	var court := Rect2(table_origin, Vector2(600, 1000) * table_stretch)
	var score_size := Vector2(minf(90, court.size.x * 0.16), maxf(50, 84 * table_scale))
	for label in [score_label, human_score_label]:
		label.add_theme_font_size_override("font_size", int(clampf(60 * table_scale, 32, 64)))
		label.size = score_size
	score_label.position = table_to_screen(Vector2(535, 455)) - score_label.size / 2
	human_score_label.position = table_to_screen(Vector2(535, 545)) - human_score_label.size / 2
	state_label.size = Vector2(220, 28)
	state_label.position = table_to_screen(Vector2(300, 595)) - state_label.size / 2
	pause_button.position = table_to_screen(Vector2(75, 500)) - pause_button.size / 2
	pause_button.position.x = clampf(pause_button.position.x, court.position.x + 12, court.end.x - pause_button.size.x - 12)
	overlay.size.x = minf(470, maxf(1, safe_bounds.size.x - 32))
	for child in content.get_children():
		if child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		elif child is HBoxContainer:
			for widget in child.get_children():
				if widget is OptionButton:
					widget.custom_minimum_size.x = minf(210, maxf(125, overlay.size.x / 2 - 24))
	if content.get_child_count() > 0 and content.get_child(0) is Label:
		content.get_child(0).add_theme_font_size_override("font_size", 32 if overlay.size.x < 410 else 42)
	overlay.size.y = minf(content.get_combined_minimum_size().y + 52, maxf(1, safe_bounds.size.y - 32))
	overlay.position = safe_bounds.position + (safe_bounds.size - overlay.size) / 2

func _clear_panel(title: String, subtitle := "") -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	content.add_child(_label(title, 42))
	if subtitle:
		var label := _label(subtitle, 19)
		label.modulate = Color("91abb9")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	overlay.show()
	call_deferred("_fit_panel")

func _fit_panel() -> void:
	overlay.size.y = 0
	_layout()
	for child in content.get_children():
		if child is Button:
			child.grab_focus()
			break

func _menu() -> void:
	get_tree().paused = false
	state = "menu"
	panel_mode = "menu"
	_clear_input()
	arena.reset_rally()
	_reset_puck_visual()
	actor = null
	_clear_panel("PLAY THE TABLE", "A quick match. A worthy opponent.")
	_picker("Difficulty", LEVELS, level, func(index): level = index; settings.level = index; _save_settings())
	_button("Play", _start_match)
	_button("Customize", _customize)
	_button("Settings", _settings_menu)
	pause_button.hide()
	state_label.text = ""
	score_label.text = "0"
	human_score_label.text = "0"

func _picker(title: String, choices: Array, selected: int, callback: Callable, colors: Array = [], perforated := false) -> OptionButton:
	var row := HBoxContainer.new()
	var label := _label(title, 21)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(210, 74)
	for i in range(choices.size()):
		picker.add_item(choices[i])
		if not colors.is_empty():
			var swatch := Image.create(24, 24, false, Image.FORMAT_RGBA8)
			swatch.fill(colors[i])
			if perforated:
				for y in range(3, 24, 6):
					for x in range(3, 24, 6):
						swatch.set_pixel(x, y, colors[i].darkened(0.6))
			picker.set_item_icon(i, ImageTexture.create_from_image(swatch))
	picker.select(selected)
	if not colors.is_empty():
		_picker_tint(picker, colors[selected])
	picker.item_selected.connect(func(index):
		if not colors.is_empty():
			_picker_tint(picker, colors[index])
		callback.call(index))
	row.add_child(picker)
	content.add_child(row)
	return picker

func _picker_tint(picker: OptionButton, tint: Color) -> void:
	var ink := Color("08212b") if tint.srgb_to_linear().get_luminance() > 0.3 else Color("f4fbff")
	for key in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBoxFlat = theme.get_stylebox(key, "OptionButton").duplicate()
		box.bg_color = tint
		box.border_color = ink if key == "focus" else tint.lightened(0.25)
		picker.add_theme_stylebox_override(key, box)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		picker.add_theme_color_override(key, ink)
	picker.add_theme_constant_override("modulate_arrow", 1)

func _customize() -> void:
	panel_mode = "customize"
	_clear_panel("MAKE IT YOURS", "A fresh finish. The same game.")
	var previews := HBoxContainer.new()
	previews.add_theme_constant_override("separation", 10)
	for entry in [["You", arena.paddles[0]], ["Puck", arena.puck], ["Bot", arena.paddles[1]]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tile := TextureRect.new()
		var crop := AtlasTexture.new()
		crop.atlas = arena_view.get_texture()
		crop.region = Rect2(arena.position + entry[1].position - Vector2(60, 60), Vector2(120, 120))
		tile.texture = crop
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.custom_minimum_size.y = 112
		column.add_child(tile)
		column.add_child(_label(entry[0], 16))
		previews.add_child(column)
	content.add_child(previews)
	_picker("Table", ["Atlantic", "Evergreen", "Graphite"], settings.table, func(i): settings.table = i; _apply_cosmetics(); _save_settings(), [TABLE.SKINS[0].tint, TABLE.SKINS[1].tint, TABLE.SKINS[2].tint], true)
	_picker("Puck", ["Ice", "Apricot", "Rose", "Lime"], settings.puck, func(i): settings.puck = i; _apply_cosmetics(); _save_settings(), PUCK_TINTS)
	_picker("Your paddle", ["Apricot", "Glacier", "Rose", "Lime"], settings.human, func(i): settings.human = i; _apply_cosmetics(); _save_settings(), TINTS)
	_picker("Bot paddle", ["Apricot", "Glacier", "Rose", "Lime"], settings.bot, func(i): settings.bot = i; _apply_cosmetics(); _save_settings(), TINTS)
	_button("Reset appearance", func(): settings.table = 0; settings.puck = 0; settings.human = 0; settings.bot = 1; _apply_cosmetics(); _save_settings(); _customize())
	_button("Done", _menu)

func _toggle(title: String, key: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.custom_minimum_size.y = 74
	toggle.button_pressed = settings[key]
	toggle.toggled.connect(func(value): settings[key] = value; _apply_cosmetics(); _save_settings())
	content.add_child(toggle)
	return toggle

func _settings_menu() -> void:
	panel_mode = "settings"
	_clear_panel("SETTINGS", "Keep your eye on the puck.")
	for entry in [["Sound", "sound"], ["Haptics", "haptics"], ["Reduced effects", "reduced_effects"]]:
		_toggle(entry[0], entry[1])
	content.add_child(_label("Touch offset", 20))
	var offset := HSlider.new()
	offset.max_value = 100
	offset.step = 10
	offset.value = settings.offset
	offset.custom_minimum_size.y = 48
	offset.value_changed.connect(func(value): settings.offset = value; _save_settings())
	content.add_child(offset)
	if not storage_ok:
		content.add_child(_label("Settings last for this session only.", 18))
	_button("Done", _menu)

func _apply_cosmetics() -> void:
	if not settings.sound and audio:
		audio.stop()
	if not arena:
		return
	table.apply_finish(settings.table)
	arena.puck.tint = PUCK_TINTS[settings.puck]
	arena.paddles[0].tint = TINTS[settings.human]
	arena.paddles[1].tint = TINTS[settings.bot]
	for body in [arena.puck, arena.paddles[0], arena.paddles[1]]:
		body.reduced_effects = settings.reduced_effects
		body.queue_redraw()
	if settings.reduced_effects:
		particles.clear()
		trail.clear()

func _start_match() -> void:
	model_error = ""
	if ResourceLoader.exists("res://scripts/policy.gd") and FileAccess.file_exists("res://models/manifest.json"):
		actor = load("res://scripts/policy.gd").new()
		var error: String = actor.load_actor("res://models/" + LEVELS[level].to_lower() + "/actor.json")
		if error:
			model_error = error
			_clear_panel("MODEL UNAVAILABLE", error)
			_button("Menu", _menu)
			return
		history = load("res://scripts/observation.gd").new()
	else:
		_clear_panel("MODEL UNAVAILABLE", "Rebuild with the bundled trained policies.")
		_button("Menu", _menu)
		return
	scores = [0, 0]
	serve_side = randi_range(0, 1)
	pause_button.show()
	_begin_serve(0.7, true)

func _begin_serve(seconds: float, new_match := false) -> void:
	if new_match:
		_clear_input()
		arena.reset_rally(serve_side)
	# Presentation-only serve: training keeps Arena.reset_rally's original setup.
	_hold_puck()
	arena.puck.reset_at(Vector2(300, 500))
	arena.last_position = arena.puck.position
	arena.ticks = 0
	arena.quiet_ticks = 0
	arena.contacts = [0, 0]
	arena.last_stall_reason = ""
	_reset_puck_visual()
	trail.clear()
	if history:
		history.reset(arena, 1)
	last_sample_tick = 0
	last_decision_tick = -1
	presentation_ticks = 0
	state = "countdown"
	timer = seconds
	overlay.hide()
	_update_score()

func _hold_puck() -> void:
	arena.running = false
	arena.puck.freeze = true
	for paddle in arena.paddles:
		paddle.freeze = false

func _physics_process(delta: float) -> void:
	if state == "paused" or state in ["menu", "results"]:
		return
	if state == "countdown":
		timer -= delta
		state_label.text = "READY"
		if timer <= 0:
			arena.launch(serve_side)
			history.reset(arena, 1) # Match training's duplicated initial launch state.
			last_sample_tick = 0
			last_decision_tick = -1
			state = "rally"
			state_label.text = ""
	elif state == "goal":
		timer -= delta
		if timer <= 0:
			if scores.max() >= 7:
				_clear_input()
				arena.set_running(false)
				state = "results"
				_clear_panel("YOU WIN" if scores[0] >= 7 else "BOT WINS", str(scores[0]) + "  —  " + str(scores[1]))
				_button("Rematch", _start_match)
				_button("Menu", _menu)
				pause_button.hide()
			else:
				_begin_serve(0.45)
	if state in ["rally", "countdown", "goal"]:
		if touch_id != -1:
			arena.drive_to(0, drag_target)
		else:
			var keys := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
			arena.paddles[0].set_command(keys)
		var decision_tick: int = arena.puck.integration_ticks
		if state != "rally":
			presentation_ticks += 1
			decision_tick = presentation_ticks
			if history:
				history.record(arena, 1)
		elif history and arena.puck.integration_ticks > last_sample_tick:
			history.record(arena, 1)
			last_sample_tick = arena.puck.integration_ticks
		if decision_tick % 4 == 0 and decision_tick != last_decision_tick:
			last_decision_tick = decision_tick
			if actor:
				var started := Time.get_ticks_usec()
				var action: Vector2 = actor.predict(history.encode(actor.delay_ticks))
				if actor.error:
					model_error = actor.error
					arena.set_running(false)
					state = "results"
					_clear_panel("MODEL ERROR", model_error)
					_button("Menu", _menu)
					return
				actor_times.append((Time.get_ticks_usec() - started) / 1000.0)
				if actor_times.size() > 3600:
					actor_times.pop_front()
				history.previous_action = action
				arena.paddles[1].set_command(-action)

func _process(delta: float) -> void:
	if state == "goal":
		var progress := clampf((0.55 - timer) / 0.28, 0, 1)
		arena.puck.visual_offset = Vector2(0, (-1 if serve_side == 1 else 1) * 28 * progress)
		arena.puck.modulate.a = 1.0 - smoothstep(0.2, 1.0, progress)
		arena.puck.queue_redraw()
	frames.append(delta * 1000)
	if frames.size() > 7200:
		frames.pop_front()
	if state == "rally" and not settings.reduced_effects:
		trail.append(arena.puck.position)
		if trail.size() > 6:
			trail.pop_front()
	for particle in particles:
		particle.life -= delta
		particle.point += particle.velocity * delta
	particles = particles.filter(func(particle): return particle.life > 0)
	queue_redraw()

func _draw() -> void:
	if arena and state == "rally" and not settings.reduced_effects:
		for i in range(1, trail.size()):
			draw_line(table_to_screen(trail[i - 1]), table_to_screen(trail[i]), Color(0.8, 0.96, 1, 0.1 * float(i) / trail.size()), 6 * table_scale, true)
	for particle in particles:
		draw_circle(table_to_screen(particle.point), 2 * table_scale, Color(0.8, 0.96, 1.0, particle.life / 0.18))

func _goal(side: int) -> void:
	if state != "rally":
		return
	scores[side] += 1
	_update_score()
	if settings.haptics and OS.get_name() == "Android":
		Input.vibrate_handheld(40)
	state = "goal"
	timer = 0.55
	serve_side = 1 - side
	_hold_puck()
	presentation_ticks = 0
	last_decision_tick = -1
	state_label.text = "YOUR POINT" if side == 0 else "BOT POINT"
	trail.clear()

func _reset_puck_visual() -> void:
	arena.puck.visual_offset = Vector2.ZERO
	arena.puck.modulate.a = 1.0
	arena.puck.queue_redraw()

func _stall() -> void:
	if state == "rally":
		_begin_serve(0.45)
		state_label.text = "LET'S RE-SERVE"

func _update_score() -> void:
	score_label.text = str(scores[1])
	human_score_label.text = str(scores[0])

func _pause() -> void:
	if state not in ["rally", "countdown", "goal"]:
		return
	before_pause = state
	state = "paused"
	_clear_input()
	get_tree().paused = true
	_clear_panel("PAUSED", "The table can wait.")
	_button("Resume", _resume)
	_toggle("Sound", "sound")
	_button("Menu", _menu)

func _resume() -> void:
	state = before_pause
	get_tree().paused = false
	overlay.hide()

func _clear_input() -> void:
	touch_id = -1
	drag_offset = Vector2.ZERO
	if arena:
		for paddle in arena.paddles:
			paddle.set_command(Vector2.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not touch_controls:
		touch_controls = true
	if event is InputEventMouse and event.device == -1:
		return # UI receives touch-emulated mouse; paddle input owns the real touch ID.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if (state == "menu" and panel_mode != "menu") or state == "results":
			_menu()
		else:
			_resume() if state == "paused" else _pause()
	if state not in ["rally", "countdown", "goal"]:
		return
	if event is InputEventScreenTouch:
		if event.index == touch_id and (not event.pressed or event.canceled):
			_clear_input()
		elif event.pressed and not event.canceled and touch_id == -1:
			_grab(event.position, event.index)
	elif event is InputEventScreenDrag and event.index == touch_id:
		_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and touch_id == -1:
			_grab(event.position, -2)
		elif not event.pressed and touch_id == -2:
			_clear_input()
	elif event is InputEventMouseMotion and touch_id == -2:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_drag(event.position)
		else:
			_clear_input()

func _grab(point: Vector2, id: int) -> void:
	var local: Vector2 = screen_to_table(point)
	if Rect2(0, 500, 600, 500).has_point(local):
		touch_id = id
		drag_offset = arena.paddles[0].position - local if id == -2 else Vector2.ZERO
		_drag(point)

func _drag(point: Vector2) -> void:
	var offset: float = settings.offset if touch_id >= 0 else 0.0
	drag_target = arena.clamp_target(screen_to_table(point) + drag_offset - Vector2(0, offset), 0)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == "paused":
			_menu()
		elif state == "results" or (state == "menu" and panel_mode != "menu"):
			_menu()
		elif state == "menu":
			get_tree().quit()
		else:
			_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _impact(speed: float, _side: int) -> void:
	if not settings.reduced_effects and state == "rally" and speed > 150 and particles.size() < 24:
		for i in range(3):
			particles.append({"point": arena.puck.position, "velocity": Vector2.RIGHT.rotated(randf() * TAU) * 180, "life": 0.18})
	if settings.sound and state == "rally" and audio.stream:
		audio.volume_db = lerpf(-24, -8, clampf(speed / 2300, 0, 1))
		audio.pitch_scale = randf_range(0.9, 1.1)
		audio.play()

func _load_settings(path := "user://settings.cfg") -> void:
	var config := ConfigFile.new()
	var loaded := config.load(path) == OK
	var saved_version = config.get_value("game", "settings_version", 0) if loaded else 1
	var migrate_sound: bool = loaded and (typeof(saved_version) != TYPE_INT or saved_version < 1)
	if loaded:
		for key in settings:
			var value = config.get_value("game", key, settings[key])
			if typeof(value) == typeof(settings[key]):
				settings[key] = value
	# Legacy installs had Sound on by default. Mute once; subsequent explicit choices persist.
	settings.settings_version = 1
	if migrate_sound or OS.has_feature("qa"):
		settings.sound = false
	for key in ["table", "puck", "human", "bot", "level"]:
		settings[key] = clampi(settings[key], 0, 2 if key == "table" else 3)
	settings.offset = clampf(settings.offset, 0, 100)
	if not is_finite(settings.offset):
		settings.offset = 0.0
	level = settings.level
	storage_ok = OS.is_userfs_persistent()
	if migrate_sound:
		_save_settings(path)

func _save_settings(path := "user://settings.cfg") -> void:
	var config := ConfigFile.new()
	for key in settings:
		config.set_value("game", key, settings[key])
	storage_ok = config.save(path) == OK and OS.is_userfs_persistent()
