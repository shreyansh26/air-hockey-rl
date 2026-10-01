extends SceneTree

const INTRO = preload("res://scripts/launch_intro.gd")

func _initialize() -> void:
	assert(ProjectSettings.get_setting("application/boot_splash/minimum_display_time") == 0)
	var boot := ProjectSettings.get_setting("application/boot_splash/image") as String
	assert(boot == "res://assets/boot-splash.png")
	var image := Image.new()
	assert(image.load_png_from_buffer(FileAccess.get_file_as_bytes(boot)) == OK)
	assert(image.get_size() == Vector2i(600, 600))
	var source := Image.new()
	assert(source.load_svg_from_string(FileAccess.get_file_as_string("res://assets/boot-splash.svg")) == OK)
	if "--regenerate" in OS.get_cmdline_user_args():
		assert(source.save_png(boot) == OK)
		image.copy_from(source)
	assert(source.get_data() == image.get_data(), "Run launch_check.gd -- --regenerate after SVG artwork changes.")
	var config := ConfigFile.new()
	assert(config.load("res://export_presets.cfg") == OK)
	for preset in [1, 4, 5]:
		var section := "preset.%s.options" % preset
		assert(config.get_value(section, "version/code") == 2)
		assert(config.get_value(section, "version/name") == "0.1.1")
		assert(config.get_value(section, "screen/immersive_mode"))
		assert(config.get_value(section, "screen/edge_to_edge"))
		for key in ["launcher_icons/main_192x192", "launcher_icons/adaptive_foreground_432x432", "launcher_icons/adaptive_background_432x432"]:
			var icon := Image.new()
			assert(icon.load_svg_from_string(FileAccess.get_file_as_string(config.get_value(section, key))) == OK)
			assert(not icon.is_empty())
	var parent := Control.new()
	root.add_child(parent)
	var child_count := parent.get_child_count()
	INTRO.play_on(parent, true)
	assert(parent.get_child_count() == child_count, "Reduced effects must skip the intro.")
	print("Launch artwork, version, adaptive icons and reduced-effects checks passed.")
	quit()
