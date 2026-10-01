extends SceneTree

const PATH = "user://cosmetics-settings-check.cfg"
var failures: Array[String] = []

class TestMain extends "res://scripts/main.gd":
	func _load_settings(path := "user://cosmetics-settings-check.cfg") -> void:
		super._load_settings(path)
	func _save_settings(path := "user://cosmetics-settings-check.cfg") -> void:
		super._save_settings(path)

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var main := TestMain.new()
	root.add_child(main)
	check(not main.settings.sound, "fresh installs are muted")
	var config := ConfigFile.new()
	config.set_value("game", "sound", true)
	config.set_value("game", "table", 99)
	config.set_value("game", "human", "bad")
	config.set_value("game", "offset", "bad")
	config.save(PATH)
	main._load_settings()
	check(not main.settings.sound and main.settings.table == 2 and main.settings.human == 0 and main.settings.offset == 0, "legacy mute and corrupted appearance settings")
	config.load(PATH)
	check(config.get_value("game", "settings_version") == 1 and config.get_value("game", "sound") == false, "mute migration persists once")
	main._settings_menu()
	var sound: CheckButton
	for child in main.content.get_children():
		if child is CheckButton and child.text == "Sound":
			sound = child
	check(sound != null and not sound.button_pressed, "Settings exposes muted Sound toggle")
	sound.button_pressed = true
	check(main.settings.sound, "Sound can be enabled explicitly")
	main._load_settings()
	check(main.settings.sound == not OS.has_feature("qa"), "explicit choice survives reload; QA starts muted")
	main._customize()
	var previews: HBoxContainer = main.content.get_child(2)
	check(previews.get_child_count() == 3, "live preview includes You, Puck, Bot")
	for column in previews.get_children():
		var crop: AtlasTexture = column.get_child(0).texture
		check(crop.atlas == main.arena_view.get_texture(), "preview uses actual game rendering")
	var picker: OptionButton = main.content.get_child(4).get_child(1)
	check(picker.get_item_text(0) == "Ice" and picker.get_item_text(3) == "Lime" and picker.get_item_icon(3) != null, "puck options keep names and show swatches")
	picker.select(3)
	picker.item_selected.emit(3)
	check(main.settings.puck == 3 and main.arena.puck.tint == main.PUCK_TINTS[3], "selection updates live puck immediately")
	check(picker.get_theme_stylebox("normal").bg_color == main.PUCK_TINTS[3], "selection box previews selected tint")
	main._load_settings()
	check(main.settings.puck == 3, "appearance selection persists")
	main._settings_menu()
	for child in main.content.get_children():
		if child is CheckButton and child.text == "Sound":
			child.button_pressed = false
	check(not main.settings.sound and not main.audio.playing, "Sound can be disabled immediately")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print(JSON.stringify({"check": "cosmetics_settings", "failures": failures}))
	quit(0 if failures.is_empty() else 1)
