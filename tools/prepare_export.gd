extends SceneTree
## Build tool outside res://game; run in an empty tooling project.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected staging-project.godot, report.json, distribution-dir arguments.")
		quit(1)
		return
	var config := ConfigFile.new()
	if config.load(args[0]) != OK:
		push_error("Unable to read staging project configuration.")
		quit(1)
		return
	var removed: Array[String] = []
	if config.has_section("autoload"):
		for key: String in config.get_section_keys("autoload"):
			var value := str(config.get_value("autoload", key))
			if value.contains("res://addons/godot_ai/") or value.contains("res://addons/gdUnit4/"):
				config.erase_section_key("autoload", key)
				removed.append(key)
	if config.has_section("editor_plugins"):
		config.erase_section("editor_plugins")
	if config.save(args[0]) != OK:
		push_error("Unable to write staging project configuration.")
		quit(1)
		return
	var report := {"ok": true, "removed_debug_autoloads": removed, "editor_plugins_removed": true, "production_main_scene": config.get_value("application", "run/main_scene", ""), "godot_version": Engine.get_version_info().string}
	if not _write_text(args[1], JSON.stringify(report, "\t")) or not _write_text(args[2].path_join("GODOT_LICENSE.txt"), Engine.get_license_text()) or not _write_text(args[2].path_join("GODOT_THIRD_PARTY.json"), JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\t")):
		quit(1)
		return
	print(JSON.stringify(report))
	quit(0)


func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Unable to write export metadata.")
		return false
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(path) != text:
		push_error("Export metadata write/readback did not validate.")
		return false
	return true
