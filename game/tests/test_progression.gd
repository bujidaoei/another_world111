extends GdUnitTestSuite

const Rules = preload("res://config/rules_config.gd")
const Progress = preload("res://features/progression/world_progress.gd")

func _rules() -> RefCounted:
	var rules := Rules.new()
	assert_bool(rules.load_file("res://config/rules.json").ok).is_true()
	return rules

func test_level_gate_banks_experience_without_extra_points() -> void:
	var progress := Progress.new(_rules())
	assert_bool(progress.award_experience(640, "combat-1").ok).is_true()
	assert_int(progress.level).is_equal(30)
	assert_int(progress.banked_experience).is_equal(60)
	assert_int(progress.earned_talent_points).is_equal(29)

func test_ascension_requires_victory_then_releases_bank_once() -> void:
	var progress := Progress.new(_rules())
	progress.award_experience(640, "combat-1")
	assert_bool(progress.complete_ascension("rain_warden", "ascend-1", {}).ok).is_false()
	var proof := {"challenge_id": "rain_warden", "run_id": "challenge-1", "defeated_enemy_ids": ["rain_warden"], "outcome": "victory"}
	assert_bool(progress.complete_ascension("rain_warden", "ascend-1", proof).ok).is_true()
	assert_int(progress.realm).is_equal(2)
	assert_int(progress.level).is_equal(33)
	assert_int(progress.earned_talent_points).is_equal(32)
	assert_bool(progress.complete_ascension("rain_warden", "ascend-1", proof).ok).is_false()
	assert_int(progress.level).is_equal(33)

func test_duplicate_negative_and_invalid_restore_leave_progress_unchanged() -> void:
	var progress := Progress.new(_rules())
	progress.award_experience(20, "kill-1")
	var original: Dictionary = progress.snapshot()
	assert_bool(progress.award_experience(20, "kill-1").ok).is_false()
	assert_bool(progress.award_experience(-1, "kill-2").ok).is_false()
	var invalid := original.duplicate(true)
	invalid.level = 31
	assert_bool(progress.restore(invalid).ok).is_false()
	assert_dict(progress.snapshot()).is_equal(original)

func test_restore_preserves_banked_xp_and_operation_deduplication() -> void:
	var progress := Progress.new(_rules())
	progress.award_experience(700, "kill-1")
	var restored := Progress.new(_rules())
	assert_bool(restored.restore(progress.snapshot()).ok).is_true()
	assert_int(restored.banked_experience).is_equal(120)
	assert_bool(restored.award_experience(20, "kill-1").ok).is_false()

func test_configuration_rejects_bad_budget_and_unknown_resource() -> void:
	var rules := _rules()
	var data: Dictionary = rules.data.duplicate(true)
	data.equipment.tiers["1"].budget_5 = 99
	assert_bool(rules.validate(data).ok).is_false()
	data = rules.data.duplicate(true)
	data.regions.rain_court.nodes.rain_scrap_01 = {"unregistered": 3}
	assert_bool(rules.validate(data).ok).is_false()

func test_restore_rejects_fabricated_or_inconsistent_ascension_records() -> void:
	var progress := Progress.new(_rules())
	var original: Dictionary = progress.snapshot()
	var fabricated := original.duplicate(true)
	fabricated.ascension_records = {"rain_warden": {}}
	assert_bool(progress.restore(fabricated).ok).is_false()
	assert_dict(progress.snapshot()).is_equal(original)
	fabricated = original.duplicate(true)
	fabricated.realm = 2
	fabricated.level = 31
	fabricated.earned_talent_points = 30
	fabricated.ascension_records = {"rain_warden": {"run_id": "run", "operation_id": "missing-operation", "realm": 2}}
	assert_bool(progress.restore(fabricated).ok).is_false()
	assert_dict(progress.snapshot()).is_equal(original)

func test_second_realm_restore_requires_level30_and_preserves_zero_bank_boundary() -> void:
	var rules := _rules()
	var qualified := Progress.new(rules)
	# A domain unit fixture proves the exact legal transition boundary, without
	# pretending this is the separate native-input progression acceptance run.
	qualified.award_experience(580, "unit-qualification")
	var proof := {"challenge_id": "rain_warden", "run_id": "unit-trial", "defeated_enemy_ids": ["rain_warden"], "outcome": "victory"}
	assert_bool(qualified.complete_ascension("rain_warden", "unit-trial:ascension", proof).ok).is_true()
	assert_int(qualified.level).is_equal(30)
	assert_int(qualified.realm).is_equal(2)
	var legal: Dictionary = qualified.snapshot()
	var restored := Progress.new(rules)
	assert_bool(restored.restore(legal).ok).is_true()
	var original: Dictionary = restored.snapshot()
	for lower_level: int in [1, 29]:
		var impossible := legal.duplicate(true)
		impossible.level = lower_level
		impossible.earned_talent_points = lower_level - 1
		assert_bool(restored.restore(impossible).ok).is_false()
		assert_dict(restored.snapshot()).is_equal(original)

func test_configuration_requires_expandable_pools_and_complete_platform_values() -> void:
	var rules := _rules()
	var invalid: Dictionary = rules.data.duplicate(true)
	invalid.equipment.affixes = {"power": invalid.equipment.affixes.power, "vitality": invalid.equipment.affixes.vitality, "guard": invalid.equipment.affixes.guard, "reach": invalid.equipment.affixes.reach}
	assert_bool(rules.validate(invalid).ok).is_false()
	invalid = rules.data.duplicate(true)
	invalid.combat.chain_range = -1
	assert_bool(rules.validate(invalid).ok).is_false()
