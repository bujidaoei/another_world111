extends GdUnitTestSuite

const Fixture = preload("res://tests/build_fixture.gd")
const Config = preload("res://config/character_builds_config.gd")
const Evaluator = preload("res://features/characters/build_evaluator.gd")
const Combat = preload("res://features/combat/combat_state.gd")

func test_real_configuration_and_single_pulse_authority() -> void:
	var f := Fixture.create()
	assert_bool(f.config.ready).is_true()
	assert_int(f.config.data.talents.size()).is_equal(9)
	assert_float(f.config.skill("pulse").damage).is_equal(32.0)
	var shared: Dictionary = f.config.presentation_data()
	shared.weapon["attack_damage"] = 999.0
	assert_float(f.config.presentation_data().weapon.attack_damage).is_equal(24.0)
	assert_object(f.evaluator.get_rules()).is_same(f.rules)
	var evaluator_base: Dictionary = f.evaluator.presentation_data()
	evaluator_base.weapon["attack_damage"] = 999.0
	assert_float(f.evaluator.presentation_data().weapon.attack_damage).is_equal(24.0)
	assert_float(f.config.skill("pulse").cost).is_equal(30.0)
	assert_bool(f.config.data.skills.pulse.has("damage")).is_false()
	var changed: Dictionary = f.config.skill("pulse")
	changed["damage"] = 999
	assert_float(f.config.skill("pulse").damage).is_equal(32.0)
	var base: Dictionary = f.presentation.duplicate(true)
	base.weapon["pulse_damage"] = 40.0
	var config := Config.new()
	assert_bool(config.load_file("res://config/character_builds.json", base).ok).is_true()
	assert_float(config.skill("pulse").damage).is_equal(40.0)
	var mismatch := Evaluator.new(config, f.rules, f.presentation)
	assert_str(mismatch.evaluate(f.roster.active_build(), f.progress, f.inventory).code).is_equal("rules_unavailable")

func test_configuration_strict_registry_numbers_and_cross_references() -> void:
	var f := Fixture.create()
	var changes := [
		["schema_version", 2], ["schema_version", true], ["talents.weapon_training.per_rank", NAN],
		["talents.weapon_training.branch", "unknown"], ["talents.weapon_training.description", ""],
		["talents.weapon_training.rank_limit", 9], ["skills.pulse.damage", 42], ["skills.focus.required_realm", 1],
		["skills.barrier.duration", 11], ["skills.barrier.cost", false], ["recovery.family_cooldown", 21],
		["resonances.charged_guard.required_skill", "future"], ["limits.common_cooldown_multiplier_minimum", 0.8],
	]
	for change: Array in changes:
		var candidate: Dictionary = f.config.data.duplicate(true)
		var path := str(change[0]).split(".")
		var node: Dictionary = candidate
		for index: int in range(path.size() - 1): node = node[path[index]]
		node[str(path[-1])] = change[1]
		assert_bool(f.config.validate(candidate).ok).is_false()
		assert_bool(f.config.ready).is_true()
	var extra: Dictionary = f.config.data.duplicate(true)
	extra["unknown"] = {}
	assert_bool(f.config.validate(extra).ok).is_false()

func test_each_character_uses_same_world_budget_independently() -> void:
	var f := Fixture.create(10)
	var before: Dictionary = f.progress.snapshot()
	var build: Dictionary = f.roster.active_build()
	build.talents["weapon_training"] = 8
	build.talents["vitality"] = 2
	for id: String in ["thief", "healer"]:
		assert_bool(f.roster.set_draft(id, build).ok).is_true()
		assert_bool(f.roster.apply(id, build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "budget-" + id).ok).is_true()
	assert_dict(f.progress.snapshot()).is_equal(before)
	build.talents["vitality"] = 3
	assert_bool(f.roster.set_draft("healer", build).ok).is_true()
	var state: Dictionary = f.roster.snapshot()
	var stock: Dictionary = f.inventory.snapshot()
	assert_str(f.roster.apply("healer", build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "over-budget").code).is_equal("talent_budget")
	assert_dict(f.roster.snapshot()).is_equal(state)
	assert_dict(f.inventory.snapshot()).is_equal(stock)

func test_structure_rejects_unknown_missing_rank_and_skill_errors_atomically() -> void:
	var f := Fixture.create()
	var before: Dictionary = f.roster.snapshot()
	for rank: Variant in [-1, 9, 0.5, true, NAN, INF, "1"]:
		var build: Dictionary = f.roster.active_build()
		build.talents["vitality"] = rank
		assert_str(f.roster.set_draft("thief", build).code).is_equal("talent_rank")
	for loadout: Array in [["pulse", "pulse"], ["pulse", "self_heal"], ["pulse", "future"], ["pulse"]]:
		var build: Dictionary = f.roster.active_build()
		build["skill_loadout"] = loadout
		assert_bool(f.roster.set_draft("thief", build).ok).is_false()
	for key: String in ["vitality", "unknown"]:
		var build: Dictionary = f.roster.active_build()
		if key == "unknown": build.talents[key] = 0
		else: build.talents.erase(key)
		assert_str(f.roster.set_draft("thief", build).code).is_equal("build_schema_invalid")
	assert_dict(f.roster.snapshot()).is_equal(before)

func test_draft_qualification_does_not_change_active_properties() -> void:
	var f := Fixture.create(0)
	var active: Dictionary = f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory)
	var draft: Dictionary = f.roster.active_build()
	draft.talents["vitality"] = 8
	draft["skill_loadout"] = ["pulse", "focus"]
	draft["weapon_id"] = "consumed-item"
	var result: Dictionary = f.roster.set_draft("thief", draft)
	assert_bool(result.ok).is_true()
	assert_bool(result.data.qualification.qualified).is_false()
	assert_int(result.data.qualification.reasons.size()).is_equal(3)
	assert_dict(f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory)).is_equal(active)
	draft.talents["vitality"] = 0
	assert_int(f.roster.profile("thief").draft.talents.vitality).is_equal(8)

func test_equipment_and_talent_percentages_add_on_original_base() -> void:
	var f := Fixture.create(29, 2)
	assert_int(f.progress.realm).is_equal(2)
	var baseline: Dictionary = f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory).data.stats
	assert_float(baseline.attack_damage).is_equal(30.0)
	assert_float(baseline.attack_cooldown).is_equal_approx(0.65 / 1.1, 0.00001)
	assert_float(baseline.max_health).is_equal(125.0)
	assert_float(baseline.max_stamina).is_equal(120.0)
	var item: Dictionary = f.service.create_drop("tier-two", 2, "rare", 4, {"location": "conduit_yard", "level": 30, "acquired_at": "2026-10-13T18:00:00+08:00"}, 27191).data.equipment
	item["affixes"] = f.inventory.get_equipment("starter").affixes
	assert_bool(f.inventory.add_equipment(item).ok).is_true()
	var build: Dictionary = f.roster.active_build()
	build["weapon_id"] = "tier-two"
	for id: String in ["weapon_training", "vitality", "reserve"]: build.talents[id] = 8
	var stats: Dictionary = f.evaluator.evaluate(build, f.progress, f.inventory).data.stats
	assert_float(stats.attack_damage).is_equal_approx(65.76, 0.00001)
	assert_float(stats.max_health).is_equal_approx(141.0, 0.00001)
	assert_float(stats.max_stamina).is_equal_approx(136.0, 0.00001)
	var second: Dictionary = f.evaluator.evaluate(build, f.progress, f.inventory).data.stats
	assert_dict(second).is_equal(stats)

func test_apply_preserves_vital_ratio_stamina_resources_and_combat() -> void:
	var f := Fixture.create(10)
	var original_resources: Dictionary = f.inventory.snapshot().resources
	var cooldowns: Dictionary = f.combat.snapshot()
	var build: Dictionary = f.roster.active_build()
	build.talents["vitality"] = 8
	build.talents["reserve"] = 2
	var applied: Dictionary = f.roster.apply("healer", build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "vital-apply")
	assert_bool(applied.ok).is_true()
	assert_float(applied.data.new_vitals.health).is_equal_approx(56.4, 0.00001)
	assert_float(applied.data.new_vitals.stamina).is_equal(80.0)
	assert_dict(f.inventory.snapshot().resources).is_equal(original_resources)
	assert_dict(f.combat.snapshot()).is_equal(cooldowns)

func test_context_and_vitals_invalid_apply_leave_all_domains_unchanged() -> void:
	var f := Fixture.create()
	var roster: Dictionary = f.roster.snapshot()
	var inventory: Dictionary = f.inventory.snapshot()
	for key: String in ["camp", "encounter_ended", "session_started"]:
		for invalid: Variant in [false, 1, null]:
			var context := Fixture.camp()
			context[key] = invalid
			assert_bool(f.roster.apply("healer", f.roster.active_build(), f.progress, f.inventory, context, Fixture.vitals(f), f.combat, "guard-" + key).ok).is_false()
	for pair: Array in [["health", 0], ["health", 126], ["health", NAN], ["stamina", 121], ["stamina", -1], ["max_health", 100], ["max_stamina", INF], ["max_health", true]]:
		var vitals := Fixture.vitals(f)
		vitals[str(pair[0])] = pair[1]
		assert_bool(f.roster.apply("healer", f.roster.active_build(), f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "bad-vitals").ok).is_false()
	assert_dict(f.roster.snapshot()).is_equal(roster)
	assert_dict(f.inventory.snapshot()).is_equal(inventory)

func test_hundred_apply_cycles_do_not_compound_or_refill() -> void:
	var f := Fixture.create(8)
	var base: Dictionary = f.roster.active_build()
	var stronger: Dictionary = base.duplicate(true)
	stronger.talents["reserve"] = 8
	var vitals := Fixture.vitals(f, 0.4, 110.0)
	var resources: Dictionary = f.inventory.snapshot().resources
	var combat_before: Dictionary = f.combat.snapshot()
	for index: int in range(100):
		var result: Dictionary = f.roster.apply("thief" if index % 2 == 0 else "healer", stronger if index % 2 == 0 else base, f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "cycle-%d" % index)
		assert_bool(result.ok).is_true()
		vitals = result.data.new_vitals
	assert_float(vitals.health / vitals.max_health).is_equal_approx(0.4, 0.000001)
	assert_float(vitals.stamina).is_equal(110.0)
	assert_dict(f.inventory.snapshot().resources).is_equal(resources)
	assert_dict(f.combat.snapshot()).is_equal(combat_before)

func test_reinitializing_existing_roster_cannot_reset_configuration_or_remainder() -> void:
	var f := Fixture.create()
	assert_bool(f.roster.commit_coin_remainder(0, 19).ok).is_true()
	var build: Dictionary = f.roster.active_build()
	build.talents["weapon_training"] = 3
	f.roster.set_draft("healer", build)
	var original: Dictionary = f.roster.snapshot()
	assert_bool(f.roster.initialize("material", f.progress, f.inventory).ok).is_false()
	assert_dict(f.roster.snapshot()).is_equal(original)

func test_stamina_clamps_down_and_stays_down_after_restoring_higher_maximum() -> void:
	var f := Fixture.create(8)
	var base: Dictionary = f.roster.active_build()
	var higher: Dictionary = base.duplicate(true)
	higher.talents["reserve"] = 8
	var result: Dictionary = f.roster.apply("healer", higher, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), f.combat, "higher-first")
	assert_bool(result.ok).is_true()
	var vitals: Dictionary = result.data.new_vitals
	vitals["stamina"] = 130.0
	result = f.roster.apply("thief", base, f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "lower-max")
	assert_bool(result.ok).is_true()
	assert_float(result.data.new_vitals.stamina).is_equal(120.0)
	result = f.roster.apply("healer", higher, f.progress, f.inventory, Fixture.camp(), result.data.new_vitals, f.combat, "higher-again")
	assert_bool(result.ok).is_true()
	assert_float(result.data.new_vitals.stamina).is_equal(120.0)

func test_failed_configuration_reload_keeps_previous_ready_data() -> void:
	var f := Fixture.create()
	var before: Dictionary = f.config.data.duplicate(true)
	assert_bool(f.config.load_file("res://config/nonexistent-character-config.json").ok).is_false()
	assert_bool(f.config.ready).is_true()
	assert_dict(f.config.data).is_equal(before)
	var invalid_base: Dictionary = f.presentation.duplicate(true)
	invalid_base.weapon["pulse_cooldown"] = 0.0
	assert_bool(f.config.load_file("res://config/character_builds.json", invalid_base).ok).is_false()
	assert_dict(f.config.data).is_equal(before)
	assert_float(f.config.skill("pulse").cooldown).is_equal(7.0)

func test_numeric_overflow_in_derived_equipment_effect_is_rejected_before_apply() -> void:
	var f := Fixture.create()
	f.rules.data.equipment.affixes.power["scale"] = 1.0e308
	var before: Dictionary = f.roster.snapshot()
	var stock: Dictionary = f.inventory.snapshot()
	assert_str(f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory).code).is_equal("derived_stats_invalid")
	assert_str(f.roster.apply("healer", f.roster.active_build(), f.progress, f.inventory, Fixture.camp(), Fixture.vitals(Fixture.create()), f.combat, "overflow-apply").code).is_equal("derived_stats_invalid")
	assert_dict(f.roster.snapshot()).is_equal(before)
	assert_dict(f.inventory.snapshot()).is_equal(stock)

func test_real_cast_effects_and_recovery_cooldowns_survive_hundred_build_switches() -> void:
	var f := Fixture.create(29, 2)
	var item: Dictionary = f.service.create_drop("active-tier-two", 2, "rare", 4, {"location": "conduit_yard", "level": 30, "acquired_at": "2026-10-13T18:00:00+08:00"}, 27191).data.equipment
	assert_bool(f.inventory.add_equipment(item).ok).is_true()
	var build: Dictionary = f.roster.active_build()
	build["weapon_id"] = "active-tier-two"
	build["skill_loadout"] = ["barrier", "focus"]
	build.talents["vitality"] = 8
	build.talents["reserve"] = 8
	var application: Dictionary = f.roster.apply("healer", build, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f, 0.4, 120.0), f.combat, "real-cast-build")
	assert_bool(application.ok).is_true()
	var vitals: Dictionary = application.data.new_vitals
	var derived: Dictionary = application.data.derived_build
	for skill_id: String in ["barrier", "focus", "self_heal", "attack", "anchor", "dodge"]:
		var cast: Dictionary = f.combat.cast(skill_id, Fixture.combat_context(f), vitals, derived, "real-" + skill_id)
		assert_bool(cast.ok).is_true()
		vitals = cast.data.new_vitals
	assert_float(vitals.stamina).is_equal(2.0)
	assert_float(vitals.health / vitals.max_health).is_equal_approx(0.7, 0.000001)
	assert_bool(f.combat.tick(0.5, true).ok).is_true()
	var actual_state: Dictionary = f.combat.snapshot()
	assert_float(actual_state.effects.barrier_capacity).is_equal_approx(27.6, 0.000001)
	assert_float(actual_state.effects.barrier_remaining).is_equal(2.5)
	assert_float(actual_state.effects.focus_remaining).is_equal(3.5)
	assert_float(actual_state.cooldowns.self_heal).is_equal(19.5)
	assert_float(actual_state.cooldowns.recovery_family).is_equal(19.5)
	assert_bool(f.combat.tick(30.0, false).ok).is_true()
	assert_dict(f.combat.snapshot()).is_equal(actual_state)
	var weaker: Dictionary = build.duplicate(true)
	weaker["skill_loadout"] = ["pulse", "barrier"]
	weaker.talents["vitality"] = 0
	weaker.talents["reserve"] = 0
	var resources: Dictionary = f.inventory.snapshot().resources
	for index: int in range(100):
		application = f.roster.apply("thief" if index % 2 == 0 else "healer", weaker if index % 2 == 0 else build, f.progress, f.inventory, Fixture.camp(), vitals, f.combat, "real-switch-%d" % index)
		assert_bool(application.ok).is_true()
		vitals = application.data.new_vitals
		assert_dict(f.combat.snapshot()).is_equal(actual_state)
		assert_float(f.combat.weapon_damage_multiplier()).is_equal(1.15)
	assert_float(vitals.stamina).is_equal(2.0)
	assert_float(vitals.health / vitals.max_health).is_equal_approx(0.7, 0.000001)
	assert_dict(f.inventory.snapshot().resources).is_equal(resources)
	assert_str(f.combat.preview_recovery("medkit", Fixture.combat_context(f), vitals).code).is_equal("recovery_cooldown_active")
	assert_str(f.combat.cast("self_heal", Fixture.combat_context(f), vitals, application.data.derived_build, "real-self_heal").code).is_equal("duplicate_operation")
	var reloaded := Combat.new(f.config)
	assert_bool(reloaded.restore(actual_state).ok).is_true()
	assert_dict(reloaded.snapshot()).is_equal(actual_state)
