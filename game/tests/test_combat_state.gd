extends GdUnitTestSuite

const Fixture = preload("res://tests/build_fixture.gd")
const Combat = preload("res://features/combat/combat_state.gd")

func _context(character: String = "healer", realm: int = 1, loadout: Array = ["pulse", "barrier"]) -> Dictionary:
	return {"active_character_id": character, "realm": realm, "weapon_tier": realm, "skill_loadout": loadout.duplicate(), "gameplay_running": true}

func _derived(f: Dictionary) -> Dictionary:
	return f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory).data

func test_self_heal_real_vitals_cost_and_shared_family_survive_restore() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var vitals := Fixture.vitals(f, 0.4, 80.0)
	var before := vitals.duplicate(true)
	var preview: Dictionary = state.preview_cast("self_heal", _context(), vitals, _derived(f))
	assert_bool(preview.ok).is_true()
	assert_float(preview.data.new_vitals.health).is_equal_approx(float(vitals.max_health) * 0.7, 0.000001)
	assert_float(preview.data.new_vitals.stamina).is_equal(45.0)
	assert_float(state.cooldown_remaining("recovery_family")).is_equal(0.0)
	assert_dict(vitals).is_equal(before)
	assert_bool(state.cast("self_heal", _context(), vitals, _derived(f), "heal-1").ok).is_true()
	assert_float(state.cooldown_remaining("self_heal")).is_equal(20.0)
	assert_float(state.cooldown_remaining("recovery_family")).is_equal(20.0)
	var reopened := Combat.new(f.config)
	assert_bool(reopened.restore(state.snapshot()).ok).is_true()
	assert_str(reopened.preview_recovery("medkit", _context("thief"), vitals).code).is_equal("recovery_cooldown_active")
	assert_bool(reopened.tick(19.0, false).ok).is_true()
	assert_float(reopened.cooldown_remaining("recovery_family")).is_equal(20.0)
	assert_bool(reopened.tick(20.0, true).ok).is_true()
	assert_bool(reopened.preview_recovery("rations", _context("thief"), vitals).ok).is_true()

func test_healing_identity_full_health_dead_pause_and_resource_rejections_are_atomic() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var vitals := Fixture.vitals(f)
	var original := state.snapshot()
	assert_str(state.cast("self_heal", _context("thief"), vitals, _derived(f), "identity").code).is_equal("exclusive_skill_forbidden")
	var full := vitals.duplicate(true)
	full["health"] = full.max_health
	assert_str(state.cast("self_heal", _context(), full, _derived(f), "full").code).is_equal("recovery_not_needed")
	var dead := vitals.duplicate(true)
	dead["health"] = 0.0
	assert_str(state.cast("self_heal", _context(), dead, _derived(f), "dead").code).is_equal("actor_dead")
	var paused := _context()
	paused["gameplay_running"] = false
	assert_str(state.cast("self_heal", paused, vitals, _derived(f), "pause").code).is_equal("gameplay_not_running")
	vitals["stamina"] = 34.99
	assert_str(state.cast("self_heal", _context(), vitals, _derived(f), "poor").code).is_equal("insufficient_stamina")
	assert_dict(state.snapshot()).is_equal(original)

func test_item_recovery_preflight_is_readonly_and_duplicate_cannot_consume_twice() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var vitals := Fixture.vitals(f)
	assert_bool(state.can_commit_recovery("medkit", _context(), vitals, "med-1").ok).is_true()
	assert_float(state.cooldown_remaining("recovery_family")).is_equal(0.0)
	var committed: Dictionary = state.commit_recovery("medkit", _context(), vitals, "med-1")
	assert_bool(committed.ok).is_true()
	assert_dict(committed.data.new_vitals).is_equal(vitals)
	assert_int(committed.data.cost.medkit).is_equal(1)
	assert_bool(state.tick(20.0, true).ok).is_true()
	assert_str(state.can_commit_recovery("medkit", _context(), vitals, "med-1").code).is_equal("duplicate_operation")
	assert_str(state.commit_recovery("rations", _context(), vitals, "med-1").code).is_equal("duplicate_operation")
	assert_float(state.cooldown_remaining("recovery_family")).is_equal(0.0)

func test_barrier_absorbs_remaining_capacity_then_expires_without_health_creation() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var vitals := Fixture.vitals(f)
	var cast: Dictionary = state.cast("barrier", _context(), vitals, _derived(f), "barrier-1")
	assert_bool(cast.ok).is_true()
	assert_float(cast.data.new_vitals.stamina).is_equal(60.0)
	assert_float(state.absorb_damage(10.0).data.absorbed).is_equal(10.0)
	var next: Dictionary = state.absorb_damage(20.0)
	assert_float(next.data.absorbed).is_equal(14.0)
	assert_float(next.data.health_damage).is_equal(6.0)
	assert_bool(state.tick(3.0, true).ok).is_true()
	assert_float(state.snapshot().effects.barrier_capacity).is_equal(0.0)
	assert_float(state.absorb_damage(7.0).data.health_damage).is_equal(7.0)
	assert_float(state.cooldown_remaining("barrier")).is_equal(7.0)

func test_common_haste_changes_skill_cooldown_but_never_recovery_family() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var derived := _derived(f)
	derived.stats["common_cooldown_multiplier"] = 0.92
	assert_bool(state.cast("pulse", _context(), Fixture.vitals(f), derived, "pulse-1").ok).is_true()
	assert_float(state.cooldown_remaining("pulse")).is_equal_approx(6.44, 0.000001)
	assert_bool(state.cast("self_heal", _context(), Fixture.vitals(f), derived, "heal-1").ok).is_true()
	assert_float(state.cooldown_remaining("self_heal")).is_equal(20.0)
	assert_float(state.cooldown_remaining("recovery_family")).is_equal(20.0)
	var swapped := _context("thief", 1, ["barrier", "pulse"])
	assert_str(state.cast("pulse", swapped, Fixture.vitals(f), derived, "pulse-2").code).is_equal("cooldown_active")

func test_focus_uses_real_realm_and_effect_cannot_stack_or_survive_expiration() -> void:
	var f := Fixture.create(29, 2)
	var state := Combat.new(f.config)
	var low := _context("thief", 1, ["pulse", "barrier"])
	assert_str(state.preview_cast("focus", low, Fixture.vitals(f), _derived(f)).code).is_equal("skill_locked")
	var context := _context("thief", 2, ["pulse", "focus"])
	assert_bool(state.cast("focus", context, Fixture.vitals(f), _derived(f), "focus-1").ok).is_true()
	assert_float(state.weapon_damage_multiplier()).is_equal(1.15)
	assert_str(state.cast("focus", context, Fixture.vitals(f), _derived(f), "focus-2").code).is_equal("cooldown_active")
	assert_bool(state.tick(4.0, true).ok).is_true()
	assert_float(state.weapon_damage_multiplier()).is_equal(1.0)
	assert_float(state.cooldown_remaining("focus")).is_equal(8.0)

func test_attack_dodge_anchor_share_finite_authority_and_clear_effects_preserves_cooldowns() -> void:
	var f := Fixture.create(29, 2)
	var state := Combat.new(f.config)
	var context := _context("thief", 2)
	var vitals := Fixture.vitals(f)
	var derived := _derived(f)
	assert_bool(state.cast("attack", context, vitals, derived, "attack-1").ok).is_true()
	assert_float(state.cooldown_remaining("attack")).is_equal(float(derived.stats.attack_cooldown))
	assert_bool(state.cast("dodge", context, vitals, derived, "dodge-1").ok).is_true()
	assert_float(state.cooldown_remaining("dodge")).is_equal(0.7)
	var weak := context.duplicate(true)
	weak["weapon_tier"] = 1
	assert_str(state.cast("anchor", weak, vitals, derived, "weak-anchor").code).is_equal("realm_required")
	assert_bool(state.cast("anchor", context, vitals, derived, "anchor-1").ok).is_true()
	assert_bool(state.cast("barrier", context, vitals, derived, "barrier-1").ok).is_true()
	var cools: Dictionary = state.snapshot().cooldowns
	state.clear_effects()
	assert_dict(state.snapshot().cooldowns).is_equal(cools)
	assert_float(state.snapshot().effects.barrier_remaining).is_equal(0.0)

func test_tick_and_damage_invalid_values_fail_without_partial_state_changes() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	state.cast("barrier", _context(), Fixture.vitals(f), _derived(f), "barrier-1")
	var original := state.snapshot()
	for value: float in [-1.0, NAN, INF]:
		assert_bool(state.tick(value, true).ok).is_false()
		assert_bool(state.absorb_damage(value).ok).is_false()
		assert_dict(state.snapshot()).is_equal(original)
	assert_bool(state.tick(1000.0, false).ok).is_true()
	assert_dict(state.snapshot()).is_equal(original)

func test_invalid_vitals_context_and_derived_build_cannot_commit_cooldowns() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var original := state.snapshot()
	for value: Variant in [NAN, INF, true, "100", -1.0]:
		var vitals := Fixture.vitals(f)
		vitals["stamina"] = value
		assert_bool(state.cast("barrier", _context(), vitals, _derived(f), "invalid-vitals").ok).is_false()
	var context := _context()
	context["realm"] = true
	assert_bool(state.cast("barrier", context, Fixture.vitals(f), _derived(f), "invalid-context").ok).is_false()
	var invalid := _derived(f)
	invalid.stats["common_cooldown_multiplier"] = NAN
	assert_bool(state.cast("pulse", _context(), Fixture.vitals(f), invalid, "invalid-derived").ok).is_false()
	assert_dict(state.snapshot()).is_equal(original)

func test_snapshot_is_exact_deep_copied_and_rejects_future_missing_and_nonfinite_values() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	state.cast("barrier", _context(), Fixture.vitals(f), _derived(f), "barrier-1")
	var original := state.snapshot()
	assert_int(original.size()).is_equal(3)
	assert_int(original.cooldowns.size()).is_equal(8)
	assert_int(original.effects.size()).is_equal(3)
	for key: Variant in original.keys(): assert_bool(key is String).is_true()
	var detached := state.snapshot()
	detached.cooldowns["pulse"] = 5.0
	assert_dict(state.snapshot()).is_equal(original)
	for version: Variant in [2, true, 1.5, "1"]:
		var invalid := original.duplicate(true)
		invalid["schema_version"] = version
		assert_bool(state.restore(invalid).ok).is_false()
		assert_dict(state.snapshot()).is_equal(original)
	for value: Variant in [NAN, INF, true, -1.0, 301.0]:
		var invalid := original.duplicate(true)
		invalid.cooldowns["pulse"] = value
		assert_bool(state.restore(invalid).ok).is_false()
		assert_dict(state.snapshot()).is_equal(original)
	var missing := original.duplicate(true)
	missing.cooldowns.erase("attack")
	assert_bool(state.restore(missing).ok).is_false()
	var unpaired := original.duplicate(true)
	unpaired.effects["barrier_remaining"] = 0.0
	assert_bool(state.restore(unpaired).ok).is_false()
	assert_dict(state.snapshot()).is_equal(original)

func test_restore_rejects_unpaired_effect_cooldowns_and_recovery_family_atomically() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var original := state.snapshot()
	var barrier := original.duplicate(true)
	barrier.effects["barrier_remaining"] = 3.0
	barrier.effects["barrier_capacity"] = 24.0
	var focus := original.duplicate(true)
	focus.effects["focus_remaining"] = 4.0
	var recovery := original.duplicate(true)
	recovery.cooldowns["self_heal"] = 20.0
	for invalid: Dictionary in [barrier, focus, recovery]:
		assert_bool(state.restore(invalid).ok).is_false()
		assert_dict(state.snapshot()).is_equal(original)

func test_confirm_recovery_revalidates_after_preview_and_never_reserves_cooldown() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var vitals := Fixture.vitals(f)
	assert_bool(state.can_commit_recovery("rations", _context(), vitals, "food-1").ok).is_true()
	assert_float(state.cooldown_remaining("recovery_family")).is_equal(0.0)
	assert_bool(state.cast("self_heal", _context(), vitals, _derived(f), "heal-1").ok).is_true()
	var current := state.snapshot()
	assert_str(state.commit_recovery("rations", _context(), vitals, "food-1").code).is_equal("recovery_cooldown_active")
	assert_dict(state.snapshot()).is_equal(current)

func test_large_future_combat_schema_is_distinct_from_corruption_and_preserves_state() -> void:
	var f := Fixture.create()
	var state := Combat.new(f.config)
	var original := state.snapshot()
	var future := original.duplicate(true)
	future["schema_version"] = 2147483647
	assert_str(state.restore(future).code).is_equal("future_schema")
	assert_dict(state.snapshot()).is_equal(original)
