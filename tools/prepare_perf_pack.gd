extends SceneTree
## Creates a QA launch pack; every production game resource remains byte-identical.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		_fail("Expected production-pack, audit-json, runner, work-directory and QA-pack.")
		return
	var audit: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if not audit is Dictionary or not bool(audit.get("ok", false)) or not ProjectSettings.load_resource_pack(args[0]):
		_fail("Cannot mount an independently audited production pack.")
		return
	var original := FileAccess.get_file_as_bytes("res://project.binary")
	var updated := _update_project_binary(original, args[2].get_base_dir().path_join("qa-main.tscn"))
	if updated.is_empty() or not _write_bytes(args[3].path_join("qa-project.binary"), updated):
		_fail("Cannot prepare QA project settings.")
		return
	var classes := ConfigFile.new()
	if classes.load("res://.godot/global_script_class_cache.cfg") != OK:
		_fail("Production global class cache is unavailable.")
		return
	var original_classes: Array = classes.get_value("", "list", [])
	for entry: Dictionary in original_classes:
		if str(entry.get("class", "")) == "AWPerformanceMeasure":
			_fail("Production cache already contains QA class.")
			return
	original_classes.append({"base": "SceneTree", "class": "AWPerformanceMeasure", "icon": "", "language": "GDScript", "path": args[2], "is_abstract": false, "is_tool": false})
	classes.set_value("", "list", original_classes)
	var cache_path := args[3].path_join("qa-class-cache.cfg")
	if classes.save(cache_path) != OK:
		_fail("Cannot prepare QA class cache.")
		return
	var packer := PCKPacker.new()
	if packer.pck_start(args[4]) != OK:
		_fail("Cannot create QA pack.")
		return
	var copied := 0
	for entry: Dictionary in audit.files:
		var name: String = entry.path
		var source_path := args[3].path_join("payload_%05d.bin" % copied)
		if name == "project.binary":
			source_path = args[3].path_join("qa-project.binary")
		elif name == ".godot/global_script_class_cache.cfg":
			source_path = cache_path
		elif not _write_bytes(source_path, FileAccess.get_file_as_bytes("res://" + name)):
			_fail("Cannot copy a production payload.")
			return
		if packer.add_file("res://" + name, source_path) != OK:
			_fail("Cannot add a production payload to the QA pack.")
			return
		copied += 1
	if packer.flush() != OK:
		_fail("QA pack flush failed.")
		return
	print(JSON.stringify({"ok": true, "files": copied, "modified_paths": ["project.binary", ".godot/global_script_class_cache.cfg"], "modified_settings": ["application/run/main_scene", "application/run/main_loop_type"], "external_runner": args[2]}))
	quit(0)

func _update_project_binary(original: PackedByteArray, external_startup_scene: String) -> PackedByteArray:
	var stream := StreamPeerBuffer.new()
	stream.data_array = original
	if stream.get_data(4)[1] != "ECFG".to_utf8_buffer():
		return PackedByteArray()
	var count := stream.get_u32()
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in count:
		var key_size := stream.get_u32()
		if key_size > stream.get_available_bytes():
			return PackedByteArray()
		var key: String = stream.get_data(key_size)[1].get_string_from_utf8()
		var value_size := stream.get_u32()
		if value_size > stream.get_available_bytes() or seen.has(key):
			return PackedByteArray()
		seen[key] = true
		var value: PackedByteArray = stream.get_data(value_size)[1]
		if key == "application/run/main_scene":
			value = var_to_bytes(external_startup_scene)
		elif key == "application/run/main_loop_type":
			value = var_to_bytes("AWPerformanceMeasure")
		entries.append({"key": key, "value": value})
	if stream.get_available_bytes() != 0 or not seen.has("application/run/main_scene"):
		return PackedByteArray()
	if not seen.has("application/run/main_loop_type"):
		entries.append({"key": "application/run/main_loop_type", "value": var_to_bytes("AWPerformanceMeasure")})
	var output := StreamPeerBuffer.new()
	output.put_data("ECFG".to_utf8_buffer())
	output.put_u32(entries.size())
	for entry: Dictionary in entries:
		var key: PackedByteArray = entry.key.to_utf8_buffer()
		output.put_u32(key.size())
		output.put_data(key)
		output.put_u32(entry.value.size())
		output.put_data(entry.value)
	return output.data_array

func _write_bytes(path: String, value: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(value)
	file.flush()
	var result := file.get_error() == OK
	file.close()
	return result and FileAccess.get_file_as_bytes(path) == value

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
