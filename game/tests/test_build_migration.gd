extends GdUnitTestSuite

const Fixture = preload("res://tests/build_fixture.gd")
const Migration = preload("res://persistence/build_migration.gd")
const Repository = preload("res://persistence/save_repository.gd")
var _temporary_directories: Array[String] = []

func after_test() -> void:
	for path: String in _temporary_directories:
		assert_bool(path.begins_with("user://tests/build_migration/")).is_true()
		var absolute := ProjectSettings.globalize_path(path)
		var directory := DirAccess.open(absolute)
		if directory:
			for file: String in directory.get_files(): DirAccess.remove_absolute(absolute.path_join(file))
			DirAccess.remove_absolute(absolute)
	_temporary_directories.clear()

func _legacy_payload() -> Dictionary:
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/domain1_real_save_slot.json"))
	return JSON.parse_string(envelope.payload_json)

func _current_payload(f: Dictionary) -> Dictionary:
	var migrated: Dictionary = Migration.migrate_payload(_legacy_payload(), f.config, f.evaluator)
	assert_bool(migrated.ok).is_true()
	return migrated.data

func _input_snapshot() -> Dictionary:
	var state: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		var entries: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action): entries.append(event.as_text())
		state[str(action)] = entries
	return state

func test_real_frozen_domain1_container_migrates_without_grants_healing_or_live_mutation() -> void:
	var f := Fixture.create()
	var payload := _legacy_payload()
	var original := payload.duplicate(true)
	var live_world: Dictionary = f.progress.snapshot()
	var live_inventory: Dictionary = f.inventory.snapshot()
	var live_roster: Dictionary = f.roster.snapshot()
	var maps := _input_snapshot()
	var migrated: Dictionary = Migration.migrate_payload(payload, f.config, f.evaluator)
	assert_bool(migrated.ok).is_true()
	assert_bool(migrated.migrated).is_true()
	assert_int(migrated.data.size()).is_equal(14)
	assert_int(migrated.data.domain_version).is_equal(2)
	assert_dict(JSON.parse_string(JSON.stringify(migrated.data.world))).is_equal(original.world)
	assert_dict(migrated.data.inventory.resources).is_equal(original.inventory.resources)
	var expected_equipment: Dictionary = original.inventory.equipment.duplicate(true)
	for id: String in expected_equipment: expected_equipment[id]["equipped"] = id == original.active_weapon_id
	assert_dict(migrated.data.inventory.equipment).is_equal(expected_equipment)
	assert_int(migrated.data.inventory.equipment.size()).is_equal(original.inventory.equipment.size())
	assert_float(migrated.data.health).is_equal(float(original.health))
	assert_float(migrated.data.stamina).is_equal(float(original.stamina))
	assert_str(migrated.data.character_builds.active_character_id).is_equal("thief")
	for id: String in ["thief", "healer"]:
		assert_str(migrated.data.character_builds.profiles[id].applied_build.weapon_id).is_equal(original.active_weapon_id)
		assert_int(migrated.data.character_builds.profiles[id].presets.size()).is_equal(3)
		for slot: Dictionary in migrated.data.character_builds.profiles[id].presets: assert_object(slot.build).is_null()
	assert_float(migrated.data.combat_state.cooldowns.recovery_family).is_equal(0.0)
	assert_int(migrated.data.input_bindings.schema_version).is_equal(2)
	assert_dict(payload).is_equal(original)
	assert_dict(f.progress.snapshot()).is_equal(live_world)
	assert_dict(f.inventory.snapshot()).is_equal(live_inventory)
	assert_dict(f.roster.snapshot()).is_equal(live_roster)
	assert_dict(_input_snapshot()).is_equal(maps)
	var again: Dictionary = Migration.migrate_payload(migrated.data, f.config, f.evaluator)
	assert_bool(again.ok).is_true()
	assert_bool(again.migrated).is_false()
	assert_dict(again.data).is_equal(migrated.data)

func test_missing_legacy_version_is_supported_but_partial_new_domain_is_never_defaulted() -> void:
	var f := Fixture.create()
	var legacy := _legacy_payload()
	legacy.erase("domain_version")
	assert_bool(Migration.migrate_payload(legacy, f.config, f.evaluator).ok).is_true()
	for field: String in ["character_builds", "combat_state"]:
		var contaminated := legacy.duplicate(true)
		contaminated[field] = {}
		assert_str(Migration.migrate_payload(contaminated, f.config, f.evaluator).code).is_equal("payload_schema_invalid")
		var partial := _current_payload(f)
		partial.erase(field)
		assert_str(Migration.migrate_payload(partial, f.config, f.evaluator).code).is_equal("payload_schema_invalid")

func test_future_versions_invalid_types_and_unknown_fields_are_rejected_without_side_effects() -> void:
	var f := Fixture.create()
	for version: Variant in [true, "2", null, 0, -1, 1.5, NAN, INF]:
		var payload := _legacy_payload()
		payload["domain_version"] = version
		assert_str(Migration.migrate_payload(payload, f.config, f.evaluator).code).is_equal("invalid_domain")
	var future := _legacy_payload()
	future["domain_version"] = 3
	assert_str(Migration.migrate_payload(future, f.config, f.evaluator).code).is_equal("future_schema")
	for field: String in ["character_builds", "combat_state"]:
		var payload := _current_payload(f)
		payload[field]["schema_version"] = 2
		assert_str(Migration.migrate_payload(payload, f.config, f.evaluator).code).is_equal("future_schema")
	var unknown := _current_payload(f)
	unknown["unexpected"] = {}
	assert_str(Migration.migrate_payload(unknown, f.config, f.evaluator).code).is_equal("payload_schema_invalid")

func test_legacy_equipped_markers_normalize_without_touching_identity_history_or_resources() -> void:
	var f := Fixture.create()
	var payload := _legacy_payload()
	for id: String in payload.inventory.equipment: payload.inventory.equipment[id]["equipped"] = id != payload.active_weapon_id
	var original := payload.duplicate(true)
	var migrated: Dictionary = Migration.migrate_payload(payload, f.config, f.evaluator)
	assert_bool(migrated.ok).is_true()
	for id: String in original.inventory.equipment:
		var before: Dictionary = original.inventory.equipment[id].duplicate(true)
		var after: Dictionary = migrated.data.inventory.equipment[id].duplicate(true)
		assert_bool(bool(after.equipped)).is_equal(id == payload.active_weapon_id)
		before.erase("equipped")
		after.erase("equipped")
		assert_dict(after).is_equal(before)
	assert_dict(migrated.data.inventory.resources).is_equal(original.inventory.resources)
	assert_dict(payload).is_equal(original)

func test_current_cooldowns_and_all_six_presets_survive_migration_without_reset() -> void:
	var f := Fixture.create()
	var payload := _current_payload(f)
	for id: String in ["thief", "healer"]:
		for index: int in range(3):
			payload.character_builds.profiles[id].presets[index] = {"name": "%s-%d" % [id, index], "build": payload.character_builds.profiles[id].applied_build.duplicate(true)}
	payload.combat_state.cooldowns["self_heal"] = 17.0
	payload.combat_state.cooldowns["recovery_family"] = 19.0
	payload.combat_state.cooldowns["barrier"] = 8.0
	payload.combat_state.effects["barrier_remaining"] = 2.0
	payload.combat_state.effects["barrier_capacity"] = 10.0
	var restored: Dictionary = Migration.migrate_payload(payload, f.config, f.evaluator)
	assert_bool(restored.ok).is_true()
	assert_dict(restored.data.combat_state).is_equal(payload.combat_state)
	assert_dict(restored.data.character_builds).is_equal(payload.character_builds)
	restored.data.character_builds.profiles.healer.presets[0].build.talents["vitality"] = 3
	assert_int(payload.character_builds.profiles.healer.presets[0].build.talents.vitality).is_equal(0)
	assert_int(restored.data.character_builds.profiles.thief.presets[0].build.talents.vitality).is_equal(0)

func test_active_missing_conflicting_or_illegal_build_rejects_but_inactive_stale_refs_survive() -> void:
	var f := Fixture.create()
	var inactive := _current_payload(f)
	inactive.character_builds.profiles.healer.applied_build["weapon_id"] = "consumed-item"
	inactive.character_builds.profiles.healer.draft["weapon_id"] = "consumed-item"
	var preserved: Dictionary = Migration.migrate_payload(inactive, f.config, f.evaluator)
	assert_bool(preserved.ok).is_true()
	assert_str(preserved.data.character_builds.profiles.healer.applied_build.weapon_id).is_equal("consumed-item")
	var conflict := _current_payload(f)
	conflict["active_weapon_id"] = "another-existing-reference"
	assert_str(Migration.migrate_payload(conflict, f.config, f.evaluator).code).is_equal("active_weapon_conflict")
	var missing := _current_payload(f)
	missing.inventory.equipment.erase(missing.active_weapon_id)
	assert_str(Migration.migrate_payload(missing, f.config, f.evaluator).code).is_equal("equipment_missing")
	var invalid := _current_payload(f)
	invalid.character_builds.profiles.thief.applied_build.talents["vitality"] = 9
	assert_str(Migration.migrate_payload(invalid, f.config, f.evaluator).code).is_equal("talent_rank")

func test_bad_domain_vitals_flags_counters_or_keys_never_get_clamped_or_defaults() -> void:
	var f := Fixture.create()
	for pair: Array in [["health", 999999.0], ["health", true], ["stamina", -1.0], ["bench_built", 1], ["run_counter", 1.5], ["operation_counter", -1]]:
		var invalid := _legacy_payload()
		invalid[str(pair[0])] = pair[1]
		var before := invalid.duplicate(true)
		assert_bool(Migration.migrate_payload(invalid, f.config, f.evaluator).ok).is_false()
		assert_dict(invalid).is_equal(before)
	var conflict := _legacy_payload()
	conflict.input_bindings.bindings["pulse"] = conflict.input_bindings.bindings.move_forward
	assert_str(Migration.migrate_payload(conflict, f.config, f.evaluator).code).is_equal("binding_conflict")
	var oversized := _legacy_payload()
	oversized.inventory.applied_operations["x".repeat(Repository.MAX_FILE_BYTES + 1)] = true
	assert_str(Migration.migrate_payload(oversized, f.config, f.evaluator).code).is_equal("payload_invalid")

func test_real_old_container_read_migrate_write_preserves_original_valid_slot_and_checksum() -> void:
	var f := Fixture.create()
	var path := "user://tests/build_migration/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_temporary_directories.append(path)
	var repository := Repository.new()
	assert_bool(repository.configure(path).ok).is_true()
	assert_int(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))).is_equal(OK)
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/domain1_real_save_slot.json")
	var original_file := FileAccess.open(path.path_join("slot_a.json"), FileAccess.WRITE)
	original_file.store_string(raw)
	original_file.close()
	var old: Dictionary = repository.load()
	assert_bool(old.ok).is_true()
	assert_int(old.sequence).is_equal(50)
	var migration: Dictionary = Migration.migrate_payload(old.data, f.config, f.evaluator)
	assert_bool(migration.ok).is_true()
	assert_bool(repository.save(migration.data).ok).is_true()
	assert_str(FileAccess.get_file_as_string(path.path_join("slot_a.json"))).is_equal(raw)
	var latest: Dictionary = repository.load()
	assert_bool(latest.ok).is_true()
	assert_int(latest.schema_version).is_equal(2)
	assert_int(latest.sequence).is_equal(51)
	assert_dict(latest.data.world).is_equal(old.data.world)
	assert_dict(latest.data.inventory.resources).is_equal(old.data.inventory.resources)

func test_old_equipment_missing_optional_equipped_marker_is_normalized_without_runtime_error() -> void:
	var f := Fixture.create()
	var legacy := _legacy_payload()
	for id: String in legacy.inventory.equipment: legacy.inventory.equipment[id].erase("equipped")
	var original := legacy.duplicate(true)
	var migrated: Dictionary = Migration.migrate_payload(legacy, f.config, f.evaluator)
	assert_bool(migrated.get("ok", false)).is_true()
	if not migrated.get("ok", false): return
	for id: String in migrated.data.inventory.equipment:
		assert_bool(migrated.data.inventory.equipment[id].equipped).is_equal(id == legacy.active_weapon_id)
	assert_dict(legacy).is_equal(original)

func test_realm1_cannot_restore_locked_focus_effect_or_focus_and_anchor_cooldowns() -> void:
	var f := Fixture.create()
	var base := _current_payload(f)
	assert_int(int(base.world.realm)).is_equal(1)
	var live_world: Dictionary = f.progress.snapshot()
	var live_roster: Dictionary = f.roster.snapshot()
	var maps := _input_snapshot()
	for state: Dictionary in [
		{"skill": "focus", "cooldown": 12.0, "focus_remaining": 0.0},
		{"skill": "focus", "cooldown": 12.0, "focus_remaining": 4.0},
		{"skill": "anchor", "cooldown": 3.0, "focus_remaining": 0.0},
	]:
		var invalid := base.duplicate(true)
		invalid.combat_state.cooldowns[str(state.skill)] = state.cooldown
		invalid.combat_state.effects["focus_remaining"] = state.focus_remaining
		var before := invalid.duplicate(true)
		var result: Dictionary = Migration.migrate_payload(invalid, f.config, f.evaluator)
		assert_bool(result.ok).is_false()
		assert_str(result.code).is_equal("skill_locked" if state.skill == "focus" else "realm_required")
		assert_dict(invalid).is_equal(before)
	assert_dict(f.progress.snapshot()).is_equal(live_world)
	assert_dict(f.roster.snapshot()).is_equal(live_roster)
	assert_dict(_input_snapshot()).is_equal(maps)

func test_realm2_keeps_shared_focus_and_anchor_state_after_unload_and_tier1_weapon_switch() -> void:
	var f := Fixture.create(29, 2)
	var candidate := _current_payload(f)
	candidate["world"] = f.progress.snapshot()
	assert_int(int(candidate.inventory.equipment[candidate.active_weapon_id].tier)).is_equal(1)
	assert_array(candidate.character_builds.profiles.thief.applied_build.skill_loadout).is_equal(["pulse", "barrier"])
	candidate.combat_state.cooldowns["focus"] = 11.0
	candidate.combat_state.cooldowns["anchor"] = 2.0
	candidate.combat_state.effects["focus_remaining"] = 3.0
	var before := candidate.duplicate(true)
	var result: Dictionary = Migration.migrate_payload(candidate, f.config, f.evaluator)
	assert_bool(result.ok).is_true()
	assert_dict(result.data.combat_state).is_equal(before.combat_state)
	assert_dict(result.data.character_builds).is_equal(before.character_builds)
	assert_str(result.data.active_weapon_id).is_equal(before.active_weapon_id)
	assert_dict(candidate).is_equal(before)
