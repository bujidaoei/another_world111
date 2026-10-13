extends GdUnitTestSuite

const Settings = preload("res://persistence/game_settings.gd")


func test_defaults_are_valid_and_detached() -> void:
	var first := Settings.default_settings()
	assert_bool(Settings.validate(first).ok).is_true()
	first.master_volume = 0.0
	assert_float(Settings.default_settings().master_volume).is_equal(0.75)


func test_normalize_preserves_present_values_and_fills_missing_settings() -> void:
	var result := Settings.normalize({"master_volume": 0.5, "language": "en"})
	assert_bool(result.ok).is_true()
	assert_float(result.data.master_volume).is_equal(0.5)
	assert_float(result.data.text_scale).is_equal(1.0)
	assert_str(result.data.language).is_equal("en")


func test_numeric_boundaries_and_types_are_validated() -> void:
	var settings := Settings.default_settings()
	settings.text_scale = 0.85
	settings.camera_shake = 0
	settings.master_volume = 1
	assert_bool(Settings.validate(settings).ok).is_true()
	settings.text_scale = 1.51
	assert_bool(Settings.validate(settings).ok).is_false()
	settings.text_scale = 1.5
	settings.master_volume = true
	assert_bool(Settings.validate(settings).ok).is_false()
	settings.master_volume = NAN
	assert_bool(Settings.validate(settings).ok).is_false()


func test_unknown_incomplete_or_invalid_switch_settings_are_rejected() -> void:
	assert_bool(Settings.normalize({"language": "unknown"}).ok).is_false()
	assert_bool(Settings.normalize({"reduced_flashing": "false"}).ok).is_false()
	assert_bool(Settings.normalize({"unrecognized": 1}).ok).is_false()
	assert_bool(Settings.validate({}).ok).is_false()


func test_settings_survive_real_repository_roundtrip() -> void:
	var directory := "user://tests/settings_repository/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var repository := SaveRepository.new()
	assert_bool(repository.configure(directory).ok).is_true()
	var settings := Settings.default_settings()
	settings.language = "en"
	settings.reduced_flashing = true
	assert_bool(repository.save({"settings": settings}).ok).is_true()
	var loaded := repository.load()
	assert_bool(loaded.ok).is_true()
	assert_bool(Settings.validate(loaded.data.settings).ok).is_true()
	assert_bool(loaded.data.settings.reduced_flashing).is_true()
	for file_name: String in ["slot_a.json", "slot_b.json"]:
		var path := ProjectSettings.globalize_path(directory.path_join(file_name))
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
