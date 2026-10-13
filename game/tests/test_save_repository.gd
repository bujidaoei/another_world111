extends GdUnitTestSuite

const Repository = preload("res://persistence/save_repository.gd")
var _directory: String
var _repository: RefCounted


func before_test() -> void:
	_directory = "user://tests/save_repository/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_repository = Repository.new()
	assert_bool(_repository.configure(_directory).ok).is_true()


func after_test() -> void:
	if _directory.begins_with("user://tests/save_repository/"):
		_remove_test_directory(ProjectSettings.globalize_path(_directory))
	_repository = null


func test_new_directory_reports_missing_without_creating_a_save() -> void:
	var result: Dictionary = _repository.load()
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("not_found")
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_a.json"))).is_false()


func test_json_payload_roundtrip_and_detached_data() -> void:
	var original := {"world": {"level": 2, "realm": 1}, "inventory": ["铜", null, true], "settings": {"master_volume": 0.7}}
	var saved: Dictionary = _repository.save(original)
	assert_bool(saved.ok).is_true()
	original.world.level = 99
	var loaded: Dictionary = _repository.load()
	assert_bool(loaded.ok).is_true()
	assert_int(int(loaded.data.world.level)).is_equal(2)
	assert_int(loaded.schema_version).is_equal(2)
	assert_int(loaded.sequence).is_equal(1)
	assert_bool(loaded.recovered).is_false()


func test_repeated_saves_rotate_and_keep_two_valid_generations() -> void:
	for value in range(1, 7):
		assert_bool(_repository.save({"progress": value}).ok).is_true()
	assert_int(int(_repository.load().data.progress)).is_equal(6)
	var a := _read_json("slot_a.json")
	var b := _read_json("slot_b.json")
	assert_array([int(a.sequence), int(b.sequence)]).contains_exactly_in_any_order([5, 6])
	assert_int(_repository.load().sequence).is_equal(6)


func test_corrupt_latest_slot_recovers_previous_valid_generation() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	assert_bool(_repository.save({"progress": 2}).ok).is_true()
	_write_text("slot_b.json", "{truncated")
	var result: Dictionary = _repository.load()
	assert_bool(result.ok).is_true()
	assert_bool(result.recovered).is_true()
	assert_int(int(result.data.progress)).is_equal(1)
	assert_bool(_repository.save({"progress": 3}).ok).is_true()
	assert_int(int(_repository.load().data.progress)).is_equal(3)


func test_checksum_and_sequence_tampering_are_rejected() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	assert_bool(_repository.save({"progress": 2}).ok).is_true()
	var altered := _read_json("slot_b.json")
	altered.sequence = 800
	_write_text("slot_b.json", JSON.stringify(altered))
	var result: Dictionary = _repository.load()
	assert_bool(result.ok).is_true()
	assert_bool(result.recovered).is_true()
	assert_int(result.sequence).is_equal(1)


func test_both_corrupt_slots_do_not_silently_reset_or_overwrite() -> void:
	_write_text("slot_a.json", "{invalid")
	_write_text("slot_b.json", "{}")
	var loaded: Dictionary = _repository.load()
	assert_bool(loaded.ok).is_false()
	assert_str(loaded.code).is_equal("recovery_required")
	var saved: Dictionary = _repository.save({"progress": 0})
	assert_bool(saved.ok).is_false()
	assert_str(saved.code).is_equal("recovery_required")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal("{invalid")


func test_future_schema_blocks_load_and_any_overwrite() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	var future := {"schema_version": 3, "sequence": 2, "payload_json": "{}", "checksum": "unknown future algorithm"}
	_write_text("slot_b.json", JSON.stringify(future))
	assert_str(_repository.load().code).is_equal("future_schema")
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))
	assert_str(_repository.save({"progress": 3}).code).is_equal("future_schema")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))).is_equal(before)


func test_v1_migration_is_pure_and_preserves_original_until_new_save() -> void:
	var payload_json := JSON.stringify({"progress": 7}, "", true, true)
	var v1 := {"schema_version": 1, "sequence": 8, "payload_json": payload_json, "checksum": ("1\n8\n" + payload_json).sha256_text()}
	_write_text("slot_a.json", JSON.stringify(v1))
	var original := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var result: Dictionary = _repository.load()
	assert_bool(result.ok).is_true()
	assert_bool(result.migrated).is_true()
	assert_bool(result.data.has("settings")).is_true()
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(original)
	assert_bool(_repository.save(result.data).ok).is_true()
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(original)
	assert_int(_repository.load().sequence).is_equal(9)


func test_interrupted_temp_write_is_ignored_and_replaced_on_next_save() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	_write_text("slot_b.json.tmp", "{half_written")
	assert_int(int(_repository.load().data.progress)).is_equal(1)
	assert_bool(_repository.save({"progress": 2}).ok).is_true()
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_b.json.tmp"))).is_false()
	assert_int(int(_repository.load().data.progress)).is_equal(2)


func test_write_failure_preserves_last_effective_slot() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory.path_join("slot_b.json.tmp")))).is_equal(OK)
	var result: Dictionary = _repository.save({"progress": 2})
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("io_error")
	assert_int(int(_repository.load().data.progress)).is_equal(1)


func test_commit_rename_failure_preserves_last_effective_slot() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory.path_join("slot_b.json")))).is_equal(OK)
	var result: Dictionary = _repository.save({"progress": 2})
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("io_error")
	assert_int(int(_repository.load().data.progress)).is_equal(1)


func test_oversized_and_engine_object_payloads_never_replace_valid_save() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	assert_str(_repository.save({"huge": "a".repeat(1024 * 1024)}).code).is_equal("invalid_payload")
	assert_str(_repository.save({"object": RefCounted.new()}).code).is_equal("invalid_payload")
	assert_str(_repository.save({"number": INF}).code).is_equal("invalid_payload")
	assert_int(int(_repository.load().data.progress)).is_equal(1)


func test_readonly_resource_path_is_rejected_at_configuration() -> void:
	assert_str(_repository.configure("res://persistence").code).is_equal("invalid_path")
	assert_bool(_repository.save({"progress": 1}).ok).is_true()


func test_oversized_corrupt_file_recovers_valid_slot() -> void:
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	_write_text("slot_b.json", "a".repeat(1024 * 1024 + 1))
	var result: Dictionary = _repository.load()
	assert_bool(result.ok).is_true()
	assert_bool(result.recovered).is_true()
	assert_int(int(result.data.progress)).is_equal(1)


func test_migration_failure_cannot_overwrite_only_old_slot() -> void:
	var payload_json := JSON.stringify({"progress": 7, "settings": "invalid old structure"}, "", true, true)
	var v1 := {"schema_version": 1, "sequence": 8, "payload_json": payload_json, "checksum": ("1\n8\n" + payload_json).sha256_text()}
	_write_text("slot_a.json", JSON.stringify(v1))
	assert_str(_repository.load().code).is_equal("recovery_required")
	assert_str(_repository.save({"progress": 0}).code).is_equal("recovery_required")
	assert_int(int(_read_json("slot_a.json").schema_version)).is_equal(1)


func test_two_repository_instances_share_generation_order_in_one_process() -> void:
	var second := Repository.new()
	assert_bool(second.configure(_directory).ok).is_true()
	assert_bool(_repository.save({"progress": 1}).ok).is_true()
	assert_bool(second.save({"progress": 2}).ok).is_true()
	assert_int(_repository.load().sequence).is_equal(2)
	assert_int(int(_repository.load().data.progress)).is_equal(2)


func test_diagnostic_event_contains_metadata_without_payload_or_path() -> void:
	var events: Array[Dictionary] = []
	_repository.diagnostic.connect(func(event: Dictionary) -> void: events.append(event))
	assert_bool(_repository.save({"private_test_value": "test_only"}).ok).is_true()
	assert_int(events.size()).is_equal(1)
	assert_str(events[0].code).is_equal("saved")
	assert_bool(events[0].has("data")).is_false()
	assert_bool(events[0].has("path")).is_false()
	assert_bool(events[0].has("private_test_value")).is_false()


func test_guard_rejects_latest_future_payload_before_any_temporary_or_slot_write() -> void:
	assert_bool(_repository.save({"domain_version": 2, "progress": 1}).ok).is_true()
	var later_writer := Repository.new()
	assert_bool(later_writer.configure(_directory).ok).is_true()
	assert_bool(later_writer.save({"domain_version": 3, "progress": 2}).ok).is_true()
	var before_a := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var before_b := FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))
	var result: Dictionary = _repository.save({"domain_version": 2, "progress": 3}, _supported_domain)
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("future_schema")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before_a)
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))).is_equal(before_b)
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_a.json.tmp"))).is_false()
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_b.json.tmp"))).is_false()


func test_guard_inspects_older_future_payload_and_keeps_preexisting_temporary_file() -> void:
	assert_bool(_repository.save({"domain_version": 3, "progress": 1}).ok).is_true()
	assert_bool(_repository.save({"domain_version": 2, "progress": 2}).ok).is_true()
	_write_text("slot_a.json.tmp", "old interrupted temporary generation")
	var before_a := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var before_b := FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))
	var result: Dictionary = _repository.save({"domain_version": 2, "progress": 3}, _supported_domain)
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("future_schema")
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before_a)
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))).is_equal(before_b)
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json.tmp"))).is_equal("old interrupted temporary generation")


func test_guard_accepts_supported_generations_and_first_save_with_no_existing_slots() -> void:
	assert_bool(_repository.save({"domain_version": 2, "progress": 1}, _supported_domain).ok).is_true()
	assert_bool(_repository.save({"domain_version": 2, "progress": 2}, _supported_domain).ok).is_true()
	var previous := FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))
	assert_bool(_repository.save({"domain_version": 2, "progress": 3}, _supported_domain).ok).is_true()
	assert_int(_repository.load().sequence).is_equal(3)
	assert_int(int(_repository.load().data.progress)).is_equal(3)
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))).is_equal(previous)


func test_guard_only_receives_verified_payloads_and_corrupt_slot_still_recovers() -> void:
	assert_bool(_repository.save({"domain_version": 2, "progress": 1}).ok).is_true()
	assert_bool(_repository.save({"domain_version": 3, "progress": 2}).ok).is_true()
	var corrupted := _read_json("slot_b.json")
	corrupted["checksum"] = "not the actual checksum"
	_write_text("slot_b.json", JSON.stringify(corrupted))
	assert_bool(_repository.save({"domain_version": 2, "progress": 3}, _supported_domain).ok).is_true()
	assert_int(_repository.load().sequence).is_equal(2)
	assert_int(int(_repository.load().data.progress)).is_equal(3)


func test_invalid_guard_result_refuses_to_write_and_preserves_both_generations() -> void:
	assert_bool(_repository.save({"domain_version": 2, "progress": 1}).ok).is_true()
	assert_bool(_repository.save({"domain_version": 2, "progress": 2}).ok).is_true()
	var before_a := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var before_b := FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))
	for guard: Callable in [_invalid_guard_type, _invalid_guard_failure]:
		var result: Dictionary = _repository.save({"domain_version": 2, "progress": 3}, guard)
		assert_bool(result.ok).is_false()
		assert_str(result.code).is_equal("existing_validator_invalid")
		assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before_a)
		assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_b.json"))).is_equal(before_b)
		assert_bool(FileAccess.file_exists(_directory.path_join("slot_a.json.tmp"))).is_false()


func test_validator_receives_detached_payload_copy_and_preserves_new_candidate() -> void:
	assert_bool(_repository.save({"domain_version": 2, "nested": {"progress": 1}}).ok).is_true()
	var before := FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))
	var candidate := {"domain_version": 2, "nested": {"progress": 2}}
	assert_bool(_repository.save(candidate, _detached_copy_guard).ok).is_true()
	assert_int(candidate.nested.progress).is_equal(2)
	assert_int(int(_repository.load().data.nested.progress)).is_equal(2)
	assert_str(FileAccess.get_file_as_string(_directory.path_join("slot_a.json"))).is_equal(before)


func test_generic_save_without_domain_guard_keeps_original_json_repository_contract() -> void:
	assert_bool(_repository.save({"domain_version": 3, "progress": 1}).ok).is_true()
	assert_bool(_repository.save({"domain_version": 2, "progress": 2}).ok).is_true()
	assert_bool(_repository.save({"arbitrary_json_owner": "Repository intentionally does not know game schema"}).ok).is_true()
	assert_int(_repository.load().sequence).is_equal(3)
	assert_str(_repository.load().data.arbitrary_json_owner).is_equal("Repository intentionally does not know game schema")


func _supported_domain(existing: Dictionary) -> Dictionary:
	var version: Variant = existing.get("domain_version", 1)
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(version)) or float(version) != floorf(float(version)) or float(version) < 1.0:
		return AWRuleResult.failure("invalid_domain", "进度领域版本无效。")
	return AWRuleResult.failure("future_schema", "进度领域版本较新。") if float(version) > 2.0 else AWRuleResult.success()


func _invalid_guard_type(_existing: Dictionary) -> Variant:
	return false


func _invalid_guard_failure(_existing: Dictionary) -> Dictionary:
	return {"ok": false, "code": "", "message": "Malformed caller guard response"}


func _detached_copy_guard(existing: Dictionary) -> Dictionary:
	# Deliberately mutate the supplied copy to verify isolation against a bad caller.
	# Production guards stay pure; this does not replace or mock repository IO.
	existing.nested["progress"] = -100
	return _supported_domain(existing)


func _read_json(file_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(_directory.path_join(file_name))) as Dictionary


func _write_text(file_name: String, contents: String) -> void:
	var file := FileAccess.open(_directory.path_join(file_name), FileAccess.WRITE)
	assert_object(file).is_not_null()
	if file != null:
		file.store_string(contents)
		file.close()


func _remove_test_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in dir.get_directories():
		_remove_test_directory(path.path_join(dir_name))
	DirAccess.remove_absolute(path)
