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
var table: Node2D
var overlay: PanelContainer
var content: VBoxContainer
var score_label: Label
var state_label: Label
var footer: Label
var pause_button: Button
var state := "menu"
var before_pause := "rally"
var timer := 0.0
var scores := [0, 0]
var serve_side := 0
var opening_side := 0
var touch_id := -1
var drag_target := Vector2.ZERO
var drag_offset := Vector2.ZERO
var level := 1
var settings := {"table": 0, "puck": 0, "human": 0, "bot": 1, "sound": true, "haptics": true, "reduced_effects": false, "offset": 0.0, "level": 1}
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
	var brand := _label("GLIDE", 38)
	brand.name = "Brand"
	brand.position = Vector2(32, 20)
	add_child(brand)
	var subtitle := _label("AIR HOCKEY", 15)
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(33, 68)
	subtitle.modulate = Color("7d9bab")
	add_child(subtitle)
	score_label = _label("YOU  0    :    0  BOT", 28)
	add_child(score_label)
	state_label = _label("FIRST TO 7", 15)
	state_label.modulate = Color("7d9bab")
	add_child(state_label)
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.custom_minimum_size = Vector2(115, 74)
	pause_button.pressed.connect(_pause)
	add_child(pause_button)
	footer = _label("DRAG TO MOVE   /   ARROW KEYS OR WASD", 16)
	footer.modulate = Color("91abb9")
	add_child(footer)
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
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	overlay.add_child(content)

func _layout() -> void:
	if not arena:
		return
	var safe_top := 0.0
	var safe_bottom := 0.0
	if OS.get_name() == "Android":
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.y > 0 and safe.size.y > 0:
			safe_top = safe.position.y * size.y / screen.y
			safe_bottom = maxf(0, (screen.y - safe.end.y) * size.y / screen.y)
	get_node("Brand").position.y = 20 + safe_top
	get_node("Subtitle").position.y = 68 + safe_top
	table_scale = minf((size.x - 64) / 680, (size.y - 240 - safe_top - safe_bottom) / 1080)
	arena_sprite.scale = Vector2.ONE * table_scale
	arena_sprite.position = Vector2((size.x - 680 * table_scale) / 2, 132 + safe_top)
	table_origin = arena_sprite.position + Vector2(40, 40) * table_scale
	score_label.position = Vector2(size.x / 2 - 175, 32 + safe_top)
	score_label.size.x = 350
	state_label.position = Vector2(size.x / 2 - 175, 77 + safe_top)
	state_label.size.x = 350
	pause_button.position = Vector2(size.x - 145, 27 + safe_top)
	footer.position = Vector2(0, size.y - 46 - safe_bottom)
	footer.size.x = size.x
	overlay.size.x = minf(470, size.x - 72)
	overlay.position = Vector2((size.x - overlay.size.x) / 2, maxf(120, (size.y - overlay.size.y) / 2))

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
	actor = null
	_clear_panel("PLAY THE TABLE", "A quick match. A worthy opponent.")
	_picker("Difficulty", LEVELS, level, func(index): level = index; settings.level = index; _save_settings())
	_button("Play", _start_match)
	_button("Customize", _customize)
	_button("Settings", _settings_menu)
	pause_button.hide()
	state_label.text = "FIRST TO 7"
	footer.text = "DRAG TO MOVE   /   ARROW KEYS OR WASD"
	score_label.text = "YOU    :    BOT"

func _picker(title: String, choices: Array, selected: int, callback: Callable) -> void:
	var row := HBoxContainer.new()
	var label := _label(title, 21)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(210, 74)
	for choice in choices:
		picker.add_item(choice)
	picker.select(selected)
	picker.item_selected.connect(callback)
	row.add_child(picker)
	content.add_child(row)

func _customize() -> void:
	panel_mode = "customize"
	_clear_panel("MAKE IT YOURS", "A fresh finish. The same game.")
	_picker("Table", ["Atlantic", "Evergreen", "Graphite"], settings.table, func(i): settings.table = i; _apply_cosmetics(); _save_settings())
	_picker("Puck", ["Ice", "Apricot", "Rose", "Lime"], settings.puck, func(i): settings.puck = i; _apply_cosmetics(); _save_settings())
	_picker("Your paddle", ["Apricot", "Glacier", "Rose", "Lime"], settings.human, func(i): settings.human = i; _apply_cosmetics(); _save_settings())
	_picker("Bot paddle", ["Apricot", "Glacier", "Rose", "Lime"], settings.bot, func(i): settings.bot = i; _apply_cosmetics(); _save_settings())
	_button("Reset appearance", func(): settings.table = 0; settings.puck = 0; settings.human = 0; settings.bot = 1; _apply_cosmetics(); _save_settings(); _customize())
	_button("Done", _menu)

func _settings_menu() -> void:
	panel_mode = "settings"
	_clear_panel("SETTINGS", "Keep your eye on the puck.")
	for entry in [["Sound", "sound"], ["Haptics", "haptics"], ["Reduced effects", "reduced_effects"]]:
		var toggle := CheckButton.new()
		toggle.text = entry[0]
		toggle.custom_minimum_size.y = 74
		toggle.button_pressed = settings[entry[1]]
		var key: String = entry[1]
		toggle.toggled.connect(func(value): settings[key] = value; _apply_cosmetics(); _save_settings())
		content.add_child(toggle)
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
	serve_side = opening_side
	opening_side = 1 - opening_side
	pause_button.show()
	_begin_serve(2.0)

func _begin_serve(seconds: float) -> void:
	_clear_input()
	arena.reset_rally(serve_side)
	trail.clear()
	if history:
		history.reset(arena, 1)
	last_sample_tick = 0
	last_decision_tick = -1
	state = "countdown"
	timer = seconds
	overlay.hide()
	_update_score()

func _physics_process(delta: float) -> void:
	if state == "paused" or state in ["menu", "results"]:
		return
	if state == "countdown":
		timer -= delta
		state_label.text = "READY  " + str(maxi(1, ceili(timer)))
		if timer <= 0:
			arena.launch(serve_side)
			state = "rally"
			state_label.text = LEVELS[level].to_upper() + " • FIRST TO 7"
	elif state == "goal":
		timer -= delta
		if timer <= 0:
			_begin_serve(1.2)
	elif state == "rally":
		if touch_id != -1:
			arena.drive_to(0, drag_target)
		else:
			var keys := Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
			arena.paddles[0].set_command(keys)
		if history and arena.puck.integration_ticks > last_sample_tick:
			history.record(arena, 1)
			last_sample_tick = arena.puck.integration_ticks
		if arena.puck.integration_ticks % 4 == 0 and arena.puck.integration_ticks != last_decision_tick:
			last_decision_tick = arena.puck.integration_ticks
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
			draw_line(table_origin + trail[i - 1] * table_scale, table_origin + trail[i] * table_scale, Color(0.8, 0.96, 1, 0.1 * float(i) / trail.size()), 6 * table_scale, true)
	for particle in particles:
		draw_circle(table_origin + particle.point * table_scale, 2 * table_scale, Color(0.8, 0.96, 1.0, particle.life / 0.18))

func _goal(side: int) -> void:
	if state != "rally":
		return
	scores[side] += 1
	_clear_input()
	_update_score()
	if settings.haptics and OS.get_name() == "Android":
		Input.vibrate_handheld(40)
	if scores[side] >= 7:
		state = "results"
		_clear_panel("YOU WIN" if side == 0 else "BOT WINS", str(scores[0]) + "  —  " + str(scores[1]))
		_button("Rematch", _start_match)
		_button("Menu", _menu)
		pause_button.hide()
	else:
		state = "goal"
		timer = 1.0
		serve_side = 1 - side
		state_label.text = "YOUR POINT" if side == 0 else "BOT POINT"

func _stall() -> void:
	if state == "rally":
		_begin_serve(1.2)
		state_label.text = "LET'S RE-SERVE"

func _update_score() -> void:
	score_label.text = "YOU  %d    :    %d  BOT" % scores

func _pause() -> void:
	if state not in ["rally", "countdown", "goal"]:
		return
	before_pause = state
	state = "paused"
	_clear_input()
	get_tree().paused = true
	_clear_panel("PAUSED", "The table can wait.")
	_button("Resume", _resume)
	_button("Menu", _menu)

func _resume() -> void:
	state = before_pause
	get_tree().paused = false
	overlay.hide()

func _clear_input() -> void:
	touch_id = -1
	if arena:
		for paddle in arena.paddles:
			paddle.set_command(Vector2.ZERO)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == -1:
		return # UI receives touch-emulated mouse; paddle input owns the real touch ID.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if (state == "menu" and panel_mode != "menu") or state == "results":
			_menu()
		else:
			_resume() if state == "paused" else _pause()
	if state != "rally":
		return
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			_grab(event.position, event.index)
		elif event.index == touch_id and (not event.pressed or event.canceled):
			_clear_input()
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
	var local := (point - table_origin) / table_scale
	if Rect2(0, 500, 600, 500).has_point(local):
		touch_id = id
		drag_offset = arena.paddles[0].position - local
		drag_target = arena.paddles[0].position

func _drag(point: Vector2) -> void:
	drag_target = (point - table_origin) / table_scale + drag_offset - Vector2(0, settings.offset)

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

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		for key in settings:
			var value = config.get_value("game", key, settings[key])
			if typeof(value) == typeof(settings[key]):
				settings[key] = value
	for key in ["table", "puck", "human", "bot", "level"]:
		settings[key] = clampi(settings[key], 0, 2 if key == "table" else 3)
	settings.offset = clampf(settings.offset, 0, 100)
	if not is_finite(settings.offset):
		settings.offset = 0.0
	level = settings.level
	storage_ok = OS.is_userfs_persistent()

func _save_settings() -> void:
	var config := ConfigFile.new()
	for key in settings:
		config.set_value("game", key, settings[key])
	storage_ok = config.save("user://settings.cfg") == OK and OS.is_userfs_persistent()
