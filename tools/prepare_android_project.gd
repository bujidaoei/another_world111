extends SceneTree
## Enable the actual Android texture import format in the isolated source copy.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected isolated project.godot path.")
		quit(1)
		return
	var config := ConfigFile.new()
	if config.load(args[0]) != OK:
		push_error("Cannot read isolated Android project settings.")
		quit(1)
		return
	config.set_value("rendering", "textures/vram_compression/import_etc2_astc", true)
	if not config.has_section_key("application", "config/icon") or str(config.get_value("application", "config/icon")).is_empty():
		config.set_value("application", "config/icon", "res://assets/ui/app_icon.svg")
	if config.save(args[0]) != OK:
		push_error("Cannot write isolated Android texture settings.")
		quit(1)
		return
	print(JSON.stringify({"ok": true, "android_texture_import": "ETC2/ASTC enabled", "main_scene": config.get_value("application", "run/main_scene", "")}))
	quit(0)
