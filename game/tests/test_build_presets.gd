extends GdUnitTestSuite

const Fixture = preload("res://tests/build_fixture.gd")
const Roster = preload("res://features/characters/character_roster.gd")

func test_six_slots_and_drafts_are_independent_deep_copies() -> void:
	var f := Fixture.create()
	for id: String in ["thief", "healer"]:
		for slot: int in range(3):
			var draft: Dictionary = f.roster.active_build()
			draft.talents["weapon_training"] = slot + (1 if id == "thief" else 4)
			assert_bool(f.roster.set_draft(id, draft).ok).is_true()
			var result: Dictionary = f.roster.save_preset(id, slot, id + str(slot))
			assert_bool(result.ok).is_true()
			result.data.preset.build.talents["weapon_training"] = 8
			draft.talents["weapon_training"] = 0
	for id: String in ["thief", "healer"]:
		for slot: int in range(3):
			assert_bool(f.roster.load_preset_draft(id, slot).ok).is_true()
			assert_int(f.roster.profile(id).draft.talents.weapon_training).is_equal(slot + (1 if id == "thief" else 4))
			var returned: Dictionary = f.roster.profile(id)
			returned.presets[slot].build.talents["weapon_training"] = 0
			assert_int(f.roster.profile(id).presets[slot].build.talents.weapon_training).is_equal(slot + (1 if id == "thief" else 4))
	assert_int(f.roster.active_build().talents.weapon_training).is_equal(0)

func test_empty_slots_invalid_names_and_indices_preserve_roster() -> void:
	var f := Fixture.create()
	var before: Dictionary = f.roster.snapshot()
	for slot: int in range(3): assert_str(f.roster.load_preset_draft("thief", slot).code).is_equal("preset_empty")
	for slot: int in [-1, 3]:
		assert_str(f.roster.save_preset("healer", slot, "合法名称").code).is_equal("preset_invalid")
		assert_str(f.roster.load_preset_draft("healer", slot).code).is_equal("preset_invalid")
	for name: String in ["", "   ", "一".repeat(25)]: assert_str(f.roster.save_preset("healer", 0, name).code).is_equal("preset_invalid")
	assert_str(f.roster.set_draft("future", f.roster.active_build()).code).is_equal("character_unknown")
	assert_dict(f.roster.snapshot()).is_equal(before)

func test_invalid_qualification_can_be_saved_but_not_applied() -> void:
	var f := Fixture.create(0)
	var draft: Dictionary = f.roster.active_build()
	draft.talents["vitality"] = 8
	draft["weapon_id"] = "missing"
	assert_bool(f.roster.set_draft("healer", draft).ok).is_true()
	var save: Dictionary = f.roster.save_preset("healer", 0, "待成长")
	assert_bool(save.ok).is_true()
	assert_bool(save.data.qualification.qualified).is_false()
	var before: Dictionary = f.roster.snapshot()
	assert_bool(f.roster.apply("healer", save.data.preset.build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "invalid-preset").ok).is_false()
	assert_dict(f.roster.snapshot()).is_equal(before)

func test_real_material_consumption_keeps_stale_references_and_history() -> void:
	var f := Fixture.create()
	var original: Dictionary = f.inventory.get_equipment("starter")
	var draft: Dictionary = f.roster.active_build()
	draft["weapon_id"] = "material"
	assert_bool(f.roster.set_draft("healer", draft).ok).is_true()
	assert_bool(f.roster.apply("healer", draft, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "equip-material").ok).is_true()
	assert_bool(f.roster.save_preset("healer", 0, "材料引用").ok).is_true()
	assert_bool(f.roster.apply("thief", f.roster.profile("thief").applied_build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "equip-starter").ok).is_true()
	var refs: Array = f.roster.references_to("material")
	assert_int(refs.size()).is_equal(3)
	assert_bool(f.inventory.grant({"currency": 200, "scrap": 20}, "fixture-fusion-stock").ok).is_true()
	var locks: Array[String] = []
	assert_bool(f.service.fuse(f.inventory, "starter", "material", locks, 1, true, true, "actual-fusion", 30).ok).is_true()
	assert_bool(f.inventory.get_equipment("material").is_empty()).is_true()
	assert_array(f.roster.references_to("material")).is_equal(refs)
	assert_dict(f.inventory.get_equipment("starter").history).is_equal(original.history)
	assert_bool(f.roster.load_preset_draft("healer", 0).ok).is_true()
	var stock: Dictionary = f.inventory.snapshot()
	var state: Dictionary = f.roster.snapshot()
	assert_str(f.roster.apply("healer", draft, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "stale-apply").code).is_equal("equipment_missing")
	assert_dict(f.inventory.snapshot()).is_equal(stock)
	assert_dict(f.roster.snapshot()).is_equal(state)
	var restored := Roster.new(f.config, f.evaluator)
	assert_bool(restored.restore(state, f.progress, f.inventory).ok).is_true()
	assert_dict(restored.snapshot()).is_equal(state)

func test_preview_rechecks_reference_and_duplicate_operation_before_commit() -> void:
	var f := Fixture.create()
	var build: Dictionary = f.roster.active_build()
	build["weapon_id"] = "material"
	var vitals := Fixture.vitals(f)
	assert_bool(f.roster.preview_apply("healer", build, f.progress, f.inventory, Fixture.camp(), vitals, f.combat).ok).is_true()
	var removed: Array[String] = ["material"]
	assert_bool(f.inventory.apply_operation("remove-material-fixture", {}, {}, {}, removed).ok).is_true()
	var before: Dictionary = f.roster.snapshot()
	assert_str(f.roster.apply("healer", build, f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "preview-confirm").code).is_equal("equipment_missing")
	assert_dict(f.roster.snapshot()).is_equal(before)
	assert_bool(f.roster.apply("healer", f.roster.active_build(), f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "once").ok).is_true()
	before = f.roster.snapshot()
	var stock: Dictionary = f.inventory.snapshot()
	assert_str(f.roster.apply("thief", f.roster.active_build(), f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "once").code).is_equal("duplicate_operation")
	assert_dict(f.roster.snapshot()).is_equal(before)
	assert_dict(f.inventory.snapshot()).is_equal(stock)

func test_apply_updates_only_equipped_markers_without_cloning_items() -> void:
	var f := Fixture.create()
	var items: Dictionary = f.inventory.snapshot().equipment
	var build: Dictionary = f.roster.active_build()
	build["weapon_id"] = "material"
	var preview: Dictionary = f.roster.preview_apply("healer", build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat)
	assert_bool(preview.ok).is_true()
	assert_dict(f.inventory.snapshot().equipment).is_equal(items)
	assert_bool(f.roster.apply("healer", build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "weapon-change").ok).is_true()
	assert_int(f.inventory.equipment_ids().size()).is_equal(2)
	for id: String in f.inventory.equipment_ids():
		var current: Dictionary = f.inventory.get_equipment(id)
		assert_bool(current.equipped).is_equal(id == "material")
		current.erase("equipped")
		var old: Dictionary = items[id].duplicate(true)
		old.erase("equipped")
		assert_dict(current).is_equal(old)
	var removed: Array[String] = ["material"]
	assert_str(f.inventory.can_apply_operation("consume-active", {}, {}, {}, removed).code).is_equal("material_equipped")

func test_restore_checks_inactive_applied_draft_and_each_preset() -> void:
	var f := Fixture.create()
	for slot: int in range(3): f.roster.save_preset("healer", slot, "疗愈" + str(slot))
	var before: Dictionary = f.roster.snapshot()
	for source: String in ["applied_build", "draft", "preset0", "preset1", "preset2"]:
		var candidate: Dictionary = before.duplicate(true)
		var build: Dictionary = candidate.profiles.healer.presets[int(source[-1])].build if source.begins_with("preset") else candidate.profiles.healer[source]
		build.talents["unknown"] = 0
		assert_str(f.roster.restore(candidate, f.progress, f.inventory).code).is_equal("build_schema_invalid")
		assert_dict(f.roster.snapshot()).is_equal(before)

func test_restore_strict_domain_future_identity_and_coin_remainder() -> void:
	var f := Fixture.create()
	var before: Dictionary = f.roster.snapshot()
	for value: Variant in [-1, 20, true, 0.5, NAN, "2"]:
		var candidate: Dictionary = before.duplicate(true)
		candidate["thief_coin_remainder"] = value
		assert_bool(f.roster.restore(candidate, f.progress, f.inventory).ok).is_false()
	for field: String in ["unknown", "profiles", "schema_version", "active_character_id"]:
		var candidate: Dictionary = before.duplicate(true)
		if field == "unknown": candidate[field] = 1
		elif field == "profiles": candidate.profiles.healer["character_id"] = "thief"
		elif field == "schema_version": candidate[field] = 2
		else: candidate[field] = "future"
		assert_bool(f.roster.restore(candidate, f.progress, f.inventory).ok).is_false()
	var missing: Dictionary = before.duplicate(true)
	missing.profiles.thief.applied_build["weapon_id"] = "missing"
	assert_str(f.roster.restore(missing, f.progress, f.inventory).code).is_equal("equipment_missing")
	assert_dict(f.roster.snapshot()).is_equal(before)

func test_json_roundtrip_and_remainder_compare_and_set_are_safe() -> void:
	var f := Fixture.create()
	assert_bool(f.roster.can_commit_coin_remainder(0, 19).ok).is_true()
	assert_int(f.roster.thief_coin_remainder).is_equal(0)
	assert_bool(f.roster.commit_coin_remainder(0, 19).ok).is_true()
	assert_bool(f.roster.commit_coin_remainder(0, 3).ok).is_false()
	assert_bool(f.roster.commit_coin_remainder(19, 20).ok).is_false()
	var snapshot: Dictionary = f.roster.snapshot()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	assert_bool(f.roster.restore(parsed, f.progress, f.inventory).ok).is_true()
	assert_str(JSON.stringify(f.roster.snapshot())).is_equal(JSON.stringify(snapshot))
	assert_int(f.roster.thief_coin_remainder).is_equal(19)

func test_restore_rejects_active_budget_and_skill_but_preserves_invalid_inactive_qualification() -> void:
	var f := Fixture.create(0)
	var before: Dictionary = f.roster.snapshot()
	for id: String in ["thief", "healer"]:
		var candidate: Dictionary = before.duplicate(true)
		candidate.profiles[id].applied_build.talents["vitality"] = 8
		candidate.profiles[id].applied_build["skill_loadout"] = ["pulse", "focus"]
		if id == "thief":
			assert_str(f.roster.restore(candidate, f.progress, f.inventory).code).is_equal("talent_budget")
			assert_dict(f.roster.snapshot()).is_equal(before)
		else:
			assert_bool(f.roster.restore(candidate, f.progress, f.inventory).ok).is_true()
			assert_int(f.roster.profile("healer").applied_build.talents.vitality).is_equal(8)
			assert_bool(f.roster.apply("healer", f.roster.profile("healer").applied_build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "inactive-invalid").ok).is_false()
	var candidate: Dictionary = before.duplicate(true)
	candidate.profiles.thief.applied_build["skill_loadout"] = ["pulse", "focus"]
	assert_str(f.roster.restore(candidate, f.progress, f.inventory).code).is_equal("skill_locked")

func test_snapshots_have_only_json_string_keys_and_all_slot_pairings_validate() -> void:
	var f := Fixture.create()
	_assert_string_keys(f.roster.snapshot())
	for location: String in ["thief", "healer"]:
		for index: int in range(3):
			for invalid: Dictionary in [{"name": "有名无构筑", "build": null}, {"name": "", "build": f.roster.active_build()}, {"name": "正常", "build": []}, {"name": "", "build": null, "extra": true}]:
				var before: Dictionary = f.roster.snapshot()
				var candidate: Dictionary = before.duplicate(true)
				candidate.profiles[location]["presets"][index] = invalid
				assert_str(f.roster.restore(candidate, f.progress, f.inventory).code).is_equal("build_schema_invalid")
				assert_dict(f.roster.snapshot()).is_equal(before)

func _assert_string_keys(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			assert_bool(typeof(key) == TYPE_STRING).is_true()
			_assert_string_keys(value[key])
	elif value is Array:
		for child: Variant in value: _assert_string_keys(child)

func test_restore_rejects_foreign_domain_fields_and_string_name_keys_without_partial_load() -> void:
	var f := Fixture.create()
	var before: Dictionary = f.roster.snapshot()
	for domain_key: String in ["combat_state", "world", "inventory", "stats", "active_resonances"]:
		var candidate: Dictionary = before.duplicate(true)
		candidate[domain_key] = {}
		assert_str(f.roster.restore(candidate, f.progress, f.inventory).code).is_equal("build_schema_invalid")
		assert_dict(f.roster.snapshot()).is_equal(before)
	var named: Dictionary = before.duplicate(true)
	var profiles: Dictionary = named.profiles
	named.erase("profiles")
	named[StringName("profiles")] = profiles
	assert_str(f.roster.restore(named, f.progress, f.inventory).code).is_equal("build_schema_invalid")
	var bad_build: Dictionary = f.roster.active_build()
	bad_build["combat_state"] = f.combat.snapshot()
	assert_str(f.roster.set_draft("healer", bad_build).code).is_equal("build_schema_invalid")
	assert_dict(f.roster.snapshot()).is_equal(before)

func test_all_json_safe_future_roster_versions_return_future_schema_and_preserve_state() -> void:
	var f := Fixture.create()
	var before: Dictionary = f.roster.snapshot()
	for version: int in [2, 1000001, 9007199254740991]:
		var candidate: Dictionary = before.duplicate(true)
		candidate["schema_version"] = version
		assert_str(f.roster.restore(candidate, f.progress, f.inventory).code).is_equal("future_schema")
		assert_dict(f.roster.snapshot()).is_equal(before)
