extends GdUnitTestSuite

const Preferences = preload("res://persistence/user_preferences.gd")
const Bindings = preload("res://platform/input_bindings.gd")
var _test_root: String
var _directory: String
var _preferences: RefCounted
var _defaults: Dictionary
var _input_map_before: Dictionary


func before_test() -> void:
	_test_root = "user://tests/user_preferences/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directory = _test_root.path_join("preferences")
	_input_map_before = _input_map_snapshot()
	var bindings := Bindings.new()
	assert_bool(bindings.load_file().ok).is_true()
	_defaults = bindings.snapshot()
	_preferences = Preferences.new()
	assert_bool(_preferences.configure(_directory).ok).is_true()


func after_test() -> void:
	assert_dict(_input_map_snapshot()).is_equal(_input_map_before)
	if _test_root.begins_with("user://tests/user_preferences/"):
		_remove_directory(ProjectSettings.globalize_path(_test_root))
	_preferences = null


func test_first_load_does_not_create_preferences_or_game_progress() -> void:
	var result: Dictionary = _preferences.load()
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("not_found")
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_a.json"))).is_false()
	assert_bool(FileAccess.file_exists(_test_root.path_join("slot_a.json"))).is_false()


func test_title_settings_persist_without_game_progress_and_do_not_apply_inputmap() -> void:
	var settings := AWGameSettings.default_settings()
	settings.master_volume = 0.2
	settings.text_scale = 1.25
	var binding_snapshot := _defaults.duplicate(true)
	binding_snapshot.bindings["interact"] = KEY_Z
	var saved: Dictionary = _preferences.save(settings, binding_snapshot)
	assert_bool(saved.ok).is_true()
	var reopened := Preferences.new()
	assert_bool(reopened.configure(_directory).ok).is_true()
	var loaded: Dictionary = reopened.load()
	assert_bool(loaded.ok).is_true()
	assert_float(float(loaded.data.settings.master_volume)).is_equal(0.2)
	assert_float(float(loaded.data.settings.text_scale)).is_equal(1.25)
	assert_int(int(loaded.data.input_bindings.bindings.interact)).is_equal(KEY_Z)
	assert_bool(FileAccess.file_exists(_test_root.path_join("slot_a.json"))).is_false()
	assert_dict(_input_map_snapshot()).is_equal(_input_map_before)


func test_key_conflict_rejects_save_without_mutating_valid_slot_or_inputmap() -> void:
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var conflict := _defaults.duplicate(true)
	conflict.bindings["dodge"] = conflict.bindings.move_left
	var result: Dictionary = _preferences.save(AWGameSettings.default_settings(), conflict)
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("binding_conflict")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before)
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_b.json"))).is_false()


func test_invalid_or_oversized_settings_and_unknown_binding_fields_preserve_preferences() -> void:
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var settings := AWGameSettings.default_settings()
	settings.language = "x".repeat(1024 * 1024 + 1)
	assert_bool(_preferences.save(settings, _defaults).ok).is_false()
	settings = AWGameSettings.default_settings()
	settings.music_volume = NAN
	assert_bool(_preferences.save(settings, _defaults).ok).is_false()
	var bindings := _defaults.duplicate(true)
	bindings["unknown"] = "x".repeat(1024 * 1024 + 1)
	assert_bool(_preferences.save(AWGameSettings.default_settings(), bindings).ok).is_false()
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before)


func test_future_container_blocks_load_and_save_without_overwrite() -> void:
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	_write_text("slot_b.json", JSON.stringify({"schema_version": 3, "sequence": 2, "payload_json": "{}", "checksum": "future"}))
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))
	assert_str(_preferences.load().code).is_equal("future_schema")
	assert_str(_preferences.save(AWGameSettings.default_settings(), _defaults).code).is_equal("future_schema")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))).is_equal(before)


func test_future_binding_schema_blocks_save_of_old_defaults() -> void:
	var future_bindings := _defaults.duplicate(true)
	future_bindings.schema_version = 2
	var raw_repo := SaveRepository.new()
	assert_bool(raw_repo.configure(_directory).ok).is_true()
	assert_bool(raw_repo.save({"settings": AWGameSettings.default_settings(), "input_bindings": future_bindings}).ok).is_true()
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	assert_str(_preferences.load().code).is_equal("future_schema")
	assert_str(_preferences.save(AWGameSettings.default_settings(), _defaults).code).is_equal("future_schema")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before)


func test_corrupt_latest_preferences_recovers_previous_valid_generation() -> void:
	var settings := AWGameSettings.default_settings()
	settings.master_volume = 0.2
	assert_bool(_preferences.save(settings, _defaults).ok).is_true()
	settings.master_volume = 0.8
	assert_bool(_preferences.save(settings, _defaults).ok).is_true()
	_write_text("slot_b.json", "{half_written")
	var loaded: Dictionary = _preferences.load()
	assert_bool(loaded.ok).is_true()
	assert_bool(loaded.recovered).is_true()
	assert_float(float(loaded.data.settings.master_volume)).is_equal(0.2)


func test_all_corrupt_preferences_are_diagnosed_and_not_cleared() -> void:
	_write_text("slot_a.json", "{broken")
	_write_text("slot_b.json", "{}")
	assert_str(_preferences.load().code).is_equal("recovery_required")
	assert_str(_preferences.save(AWGameSettings.default_settings(), _defaults).code).is_equal("recovery_required")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal("{broken")


func test_valid_checksum_with_invalid_domain_data_is_rejected_without_overwrite() -> void:
	var conflict := _defaults.duplicate(true)
	conflict.bindings["dodge"] = conflict.bindings.move_left
	var raw_repo := SaveRepository.new()
	assert_bool(raw_repo.configure(_directory).ok).is_true()
	assert_bool(raw_repo.save({"settings": AWGameSettings.default_settings(), "input_bindings": conflict}).ok).is_true()
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	assert_str(_preferences.load().code).is_equal("binding_conflict")
	assert_str(_preferences.save(AWGameSettings.default_settings(), _defaults).code).is_equal("binding_conflict")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before)


func test_preferences_and_progress_use_distinct_slots() -> void:
	var game_repo := SaveRepository.new()
	assert_bool(game_repo.configure(_test_root).ok).is_true()
	assert_bool(game_repo.save({"test_only_progress_namespace_sentinel": 1}).ok).is_true()
	var before := FileAccess.get_file_as_string(_test_root.path_join("slot_a.json"))
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	assert_str(FileAccess.get_file_as_string(_test_root.path_join("slot_a.json"))).is_equal(before)
	assert_bool(_preferences.load().ok).is_true()


func test_configure_failure_keeps_previous_preferences_repository() -> void:
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	assert_bool(_preferences.configure("res://persistence").ok).is_false()
	var loaded: Dictionary = _preferences.load()
	assert_bool(loaded.ok).is_true()
	assert_int(loaded.sequence).is_equal(1)
	var settings := AWGameSettings.default_settings()
	settings.music_volume = 0.15
	assert_bool(_preferences.save(settings, _defaults).ok).is_true()
	assert_int(_preferences.load().sequence).is_equal(2)


func test_real_temporary_write_failure_keeps_previous_valid_preferences() -> void:
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory.path_join("slot_b.json.tmp")))).is_equal(OK)
	var settings := AWGameSettings.default_settings()
	settings.music_volume = 0.15
	assert_str(_preferences.save(settings, _defaults).code).is_equal("io_error")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before)
	assert_float(float(_preferences.load().data.settings.music_volume)).is_equal(0.35)


func test_unconfigured_service_and_loaded_candidate_mutation_are_safe() -> void:
	var unconfigured := Preferences.new()
	assert_str(unconfigured.load().code).is_equal("preferences_not_ready")
	assert_str(unconfigured.save(AWGameSettings.default_settings(), _defaults).code).is_equal("preferences_not_ready")
	assert_bool(_preferences.save(AWGameSettings.default_settings(), _defaults).ok).is_true()
	var loaded: Dictionary = _preferences.load()
	loaded.data.settings.master_volume = 0.0
	loaded.data.input_bindings.bindings["interact"] = KEY_Z
	var unchanged: Dictionary = _preferences.load()
	assert_float(float(unchanged.data.settings.master_volume)).is_equal(0.75)
	assert_int(int(unchanged.data.input_bindings.bindings.interact)).is_equal(KEY_E)


func _input_map_snapshot() -> Dictionary:
	var state: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.as_text())
		state[str(action)] = events
	return state


func _write_text(file_name: String, text: String) -> void:
	var file := FileAccess.open(_directory.path_join(file_name), FileAccess.WRITE)
	assert_object(file).is_not_null()
	if file != null:
		file.store_string(text)
		file.close()


func _remove_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name: String in directory.get_directories():
		_remove_directory(path.path_join(dir_name))
	DirAccess.remove_absolute(path)
