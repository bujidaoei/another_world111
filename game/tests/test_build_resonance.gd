extends GdUnitTestSuite

const Fixture = preload("res://tests/build_fixture.gd")
const Config = preload("res://config/character_builds_config.gd")
const Evaluator = preload("res://features/characters/build_evaluator.gd")

func test_conductor_requires_eight_points_and_real_tier_two_anchor() -> void:
	var f := Fixture.create(29, 2)
	var item: Dictionary = f.service.create_drop("tier-two", 2, "rare", 4, {"location": "conduit_yard", "level": 30, "acquired_at": "2026-10-13T18:00:00+08:00"}, 27191).data.equipment
	f.inventory.add_equipment(item)
	for tier: int in [1, 2]:
		for points: int in [0, 7, 8]:
			var build: Dictionary = f.roster.active_build()
			build["weapon_id"] = "starter" if tier == 1 else "tier-two"
			build.talents["mobility"] = points
			var result: Dictionary = f.evaluator.evaluate(build, f.progress, f.inventory)
			assert_bool(result.ok).is_true()
			assert_bool("wandering_conductor" in result.data.active_resonances).is_equal(tier == 2 and points == 8)
			assert_float(result.data.stats.anchor_range).is_equal(8.5 if tier == 2 and points == 8 else 7.0)
			assert_int(result.data.stats.chain_targets).is_equal(3)
			if points < 8: assert_bool("branch_points" in result.data.inactive_resonance_reasons.wandering_conductor).is_true()
			if tier == 1: assert_bool("weapon_tier" in result.data.inactive_resonance_reasons.wandering_conductor).is_true()

func test_guard_requires_threshold_and_barrier_loadout() -> void:
	var f := Fixture.create(29, 2)
	for loaded: bool in [false, true]:
		for points: int in [0, 7, 8]:
			var build: Dictionary = f.roster.active_build()
			build["skill_loadout"] = ["pulse", "barrier"] if loaded else ["pulse", "focus"]
			build.talents["vitality"] = points
			var result: Dictionary = f.evaluator.evaluate(build, f.progress, f.inventory)
			assert_bool(result.ok).is_true()
			assert_bool("charged_guard" in result.data.active_resonances).is_equal(loaded and points == 8)
			assert_float(result.data.stats.barrier_capacity_multiplier).is_equal(1.15 if loaded and points == 8 else 1.0)
			assert_float(result.data.stats.barrier_capacity).is_equal_approx(27.6 if loaded and points == 8 else 24.0, 0.00001)
			if not loaded: assert_bool("skill_loadout" in result.data.inactive_resonance_reasons.charged_guard).is_true()

func test_affix_skill_damage_and_chain_range_use_registered_scales() -> void:
	var f := Fixture.create(8)
	var item: Dictionary = f.inventory.get_equipment("material")
	item["affixes"] = [{"id": "power", "value": 25}, {"id": "charge", "value": 25}, {"id": "reach", "value": 25}, {"id": "recovery", "value": 25}]
	assert_bool(f.inventory.apply_operation("fixture-affix-choice", {}, {}, {"material": item}).ok).is_true()
	var build: Dictionary = f.roster.active_build()
	build["weapon_id"] = "material"
	build.talents["pulse_mastery"] = 8
	var stats: Dictionary = f.evaluator.evaluate(build, f.progress, f.inventory).data.stats
	assert_float(stats.pulse_damage).is_equal_approx(43.52, 0.00001)
	assert_float(stats.chain_range).is_equal_approx(6.1875, 0.00001)
	assert_float(stats.stamina_recovery).is_equal_approx(23.75, 0.00001)

func test_max_ranks_bound_drain_cooldown_falloff_without_changing_identity() -> void:
	var f := Fixture.create(29, 2)
	var build: Dictionary = f.roster.active_build()
	for id: String in ["conduction", "defense_efficiency", "skill_haste"]: build.talents[id] = 8
	var result: Dictionary = f.evaluator.evaluate(build, f.progress, f.inventory)
	assert_bool(result.ok).is_true()
	assert_float(result.data.stats.chain_falloff).is_equal_approx(0.92, 0.00001)
	assert_float(result.data.stats.defense_drain).is_equal_approx(8.4, 0.00001)
	assert_float(result.data.stats.common_cooldown_multiplier).is_equal(0.92)
	assert_float(f.config.skill("self_heal").cooldown).is_equal(20.0)
	assert_int(result.data.stats.chain_targets).is_equal(3)
	assert_str(f.inventory.get_equipment("starter").inherent_effect_id).is_equal("chain_lightning")

func test_unlocked_skills_and_weapon_realm_are_qualification_not_structure() -> void:
	var f := Fixture.create()
	var build: Dictionary = f.roster.active_build()
	build["skill_loadout"] = ["pulse", "focus"]
	assert_bool(f.evaluator.validate_structure(build).ok).is_true()
	assert_str(f.evaluator.evaluate(build, f.progress, f.inventory).code).is_equal("skill_locked")
	var item: Dictionary = f.service.create_drop("too-high", 2, "rare", 4, {"location": "conduit_yard", "level": 30, "acquired_at": "2026-10-13T18:00:00+08:00"}, 27).data.equipment
	f.inventory.add_equipment(item)
	build["skill_loadout"] = ["pulse", "barrier"]
	build["weapon_id"] = "too-high"
	assert_bool(f.evaluator.validate_structure(build).ok).is_true()
	assert_str(f.evaluator.evaluate(build, f.progress, f.inventory).code).is_equal("realm_required")

func test_configured_falloff_cap_is_applied_to_current_authoritative_base() -> void:
	var f := Fixture.create(8)
	var presentation: Dictionary = f.presentation.duplicate(true)
	presentation.weapon["chain_falloff"] = 0.95
	var config := Config.new()
	assert_bool(config.load_file("res://config/character_builds.json", presentation).ok).is_true()
	var evaluator := Evaluator.new(config, f.rules, presentation)
	var build: Dictionary = f.roster.active_build()
	build.talents["conduction"] = 8
	assert_float(evaluator.evaluate(build, f.progress, f.inventory).data.stats.chain_falloff).is_equal(0.98)
	assert_float(f.evaluator.evaluate(build, f.progress, f.inventory).data.stats.chain_falloff).is_equal_approx(0.92, 0.00001)
