extends GdUnitTestSuite

const Rules = preload("res://config/rules_config.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Expedition = preload("res://features/expedition/expedition_state.gd")
const Fixture = preload("res://tests/build_fixture.gd")
const Combat = preload("res://features/combat/combat_state.gd")
const EquipmentService = preload("res://features/equipment/equipment_service.gd")

func _rules() -> AWGameRules:
	var rules := Rules.new() as AWGameRules
	assert_bool(rules.load_file("res://config/rules.json").ok).is_true()
	return rules

func test_restore_rejects_unregistered_character_reward_context_without_mutation() -> void:
	var rules := _rules()
	var run := Expedition.new(rules) as AWExpeditionState
	assert_bool(run.begin("registered-run", "rain_court").ok).is_true()
	var before := run.snapshot()
	var invalid := before.duplicate(true)
	invalid["character_id"] = "unregistered_character"
	invalid["starting_coin_remainder"] = 19
	invalid["pending_coin_remainder"] = 19
	assert_bool(run.restore(invalid).ok).is_false()
	assert_dict(run.snapshot()).is_equal(before)

func _run(fixture: Dictionary, id: String, character: String = "thief") -> AWExpeditionState:
	var run := Expedition.new(fixture.rules, fixture.config) as AWExpeditionState
	assert_bool(run.begin(id, "rain_court", false, fixture.progress.realm, fixture.progress.level, character, fixture.roster.thief_coin_remainder).ok).is_true()
	return run

func _settle(run: AWExpeditionState, fixture: Dictionary) -> void:
	assert_bool(run.resolve("evacuated", fixture.progress).ok).is_true()
	assert_bool(run.reset().ok).is_true()
	assert_bool(run.commit_rewards(fixture.inventory, fixture.roster).ok).is_true()

func test_ten_registered_kills_across_two_successful_runs_pay_exactly_one_bonus_coin() -> void:
	var f := Fixture.create(0)
	var first := _run(f, "first")
	for id: String in first.enemy_ids():
		assert_bool(first.record_kill(id, f.progress).ok).is_true()
	assert_int(f.roster.thief_coin_remainder).is_equal(0)
	_settle(first, f)
	assert_int(f.inventory.count("currency")).is_equal(12)
	assert_int(f.roster.thief_coin_remainder).is_equal(12)
	var second := _run(f, "second")
	for index in range(4):
		assert_bool(second.record_kill(second.enemy_ids()[index], f.progress).ok).is_true()
	_settle(second, f)
	assert_int(f.inventory.count("currency")).is_equal(21)
	assert_int(f.roster.thief_coin_remainder).is_equal(0)
	assert_int(f.progress.level).is_equal(4)
	assert_bool(second.commit_rewards(f.inventory, f.roster).ok).is_false()
	assert_int(f.inventory.count("currency")).is_equal(21)

func test_failure_discards_pending_bonus_and_remainder_but_keeps_immediate_xp() -> void:
	var f := Fixture.create(0)
	assert_bool(f.roster.commit_coin_remainder(0, 18).ok).is_true()
	var run := _run(f, "failure")
	assert_bool(run.record_kill(run.enemy_ids()[0], f.progress).ok).is_true()
	assert_int(run.pending_loot.currency).is_equal(3)
	assert_int(run.snapshot().pending_coin_remainder).is_equal(0)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)
	assert_bool(run.resolve("failed", f.progress).ok).is_true()
	assert_bool(run.reset().ok).is_true()
	assert_dict(run.pending_loot).is_empty()
	assert_int(run.snapshot().pending_coin_remainder).is_equal(18)
	assert_bool(run.commit_rewards(f.inventory, f.roster).ok).is_false()
	assert_int(f.inventory.count("currency")).is_equal(0)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)
	assert_int(f.progress.experience).is_equal(6)

func test_objective_currency_never_enters_monster_bonus_accumulator() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	var run := _run(f, "objective")
	for index in range(3):
		run.record_kill(run.enemy_ids()[index], f.progress)
	for node_id: String in ["rain_scrap_01", "rain_scrap_02"]:
		assert_bool(run.gather(node_id).ok).is_true()
	assert_bool(run.complete_objective(f.progress).ok).is_true()
	assert_int(run.pending_loot.currency).is_equal(19)
	assert_int(run.snapshot().pending_coin_remainder).is_equal(4)
	_settle(run, f)
	assert_int(f.roster.thief_coin_remainder).is_equal(4)

func test_healer_preserves_committed_thief_remainder_without_monster_bonus() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	assert_bool(f.roster.apply("healer", f.roster.profile("healer").draft, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), Combat.new(f.config), "healer-switch").ok).is_true()
	var run := _run(f, "healer", "healer")
	for id: String in run.enemy_ids():
		assert_bool(run.record_kill(id, f.progress).ok).is_true()
	_settle(run, f)
	assert_int(f.inventory.count("currency")).is_equal(12)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)

func test_duplicate_and_unknown_enemy_events_preserve_bonus_and_experience() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	var run := _run(f, "duplicates")
	run.record_kill(run.enemy_ids()[0], f.progress)
	var before := run.snapshot()
	var world_before: Dictionary = f.progress.snapshot()
	assert_bool(run.record_kill(run.enemy_ids()[0], f.progress).ok).is_false()
	assert_bool(run.record_kill("unregistered-enemy", f.progress).ok).is_false()
	assert_dict(run.snapshot()).is_equal(before)
	assert_dict(f.progress.snapshot()).is_equal(world_before)

func test_remainder_conflict_and_inventory_overflow_prevent_both_domain_commits() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	var run := _run(f, "cas")
	run.record_kill(run.enemy_ids()[0], f.progress)
	run.resolve("evacuated", f.progress)
	run.reset()
	f.roster.commit_coin_remainder(18, 19)
	var inventory_before: Dictionary = f.inventory.snapshot()
	assert_bool(run.commit_rewards(f.inventory, f.roster).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(inventory_before)
	assert_int(f.roster.thief_coin_remainder).is_equal(19)
	assert_bool(run.rewards_committed).is_false()
	f.roster.commit_coin_remainder(19, 18)
	f.inventory.grant({"currency": int(f.rules.data.inventory.maximum_quantity)}, "capacity-fixture")
	inventory_before = f.inventory.snapshot()
	assert_bool(run.commit_rewards(f.inventory, f.roster).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(inventory_before)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)
	assert_bool(run.rewards_committed).is_false()

func test_guardian_without_base_monster_currency_preserves_remainder() -> void:
	var f := Fixture.create(29)
	f.roster.commit_coin_remainder(0, 18)
	var run := Expedition.new(f.rules, f.config) as AWExpeditionState
	assert_bool(run.begin("trial", "rain_court", true, 1, 30, "thief", 18).ok).is_true()
	assert_bool(run.record_kill("rain_warden", f.progress).ok).is_true()
	assert_bool(run.resolve("victory", f.progress).ok).is_true()
	assert_bool(run.reset().ok).is_true()
	assert_bool(run.commit_rewards(f.inventory, f.roster).ok).is_true()
	assert_int(f.inventory.count("currency")).is_equal(0)
	assert_int(f.inventory.count("alloy")).is_equal(8)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)

func test_restore_rejects_forged_loot_even_when_coin_remainder_matches_registered_events() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	var run := _run(f, "loot")
	run.record_kill(run.enemy_ids()[0], f.progress)
	var before := run.snapshot()
	var invalid := before.duplicate(true)
	invalid["pending_loot"]["currency"] = 2
	assert_bool(run.restore(invalid).ok).is_false()
	assert_dict(run.snapshot()).is_equal(before)

func test_older_ended_snapshot_cannot_replay_reward_into_newer_inventory() -> void:
	var f := Fixture.create(0)
	assert_bool(f.roster.apply("healer", f.roster.profile("healer").draft, f.progress, f.inventory, Fixture.camp(), Fixture.vitals(f), Combat.new(f.config), "healer-replay-fixture").ok).is_true()
	var run := _run(f, "canonical-replay", "healer")
	run.record_kill(run.enemy_ids()[0], f.progress)
	run.resolve("evacuated", f.progress)
	run.reset()
	var older := run.snapshot()
	assert_bool(run.commit_rewards(f.inventory, f.roster).ok).is_true()
	var newer_inventory: Dictionary = f.inventory.snapshot()
	var replay := Expedition.new(f.rules, f.config) as AWExpeditionState
	assert_bool(replay.restore(older).ok).is_true()
	assert_bool(replay.commit_rewards(f.inventory, f.roster).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(newer_inventory)
	assert_int(f.inventory.count("currency")).is_equal(2)

func _drop(f: Dictionary, id: String) -> Dictionary:
	return EquipmentService.new(f.rules).create_drop(id, 1, "common", 4, {"location": "unit-settlement-fixture", "level": 1, "acquired_at": "2026-10-13T00:00:00Z"}, 42).data.equipment

func test_late_invalid_or_duplicate_drop_rejects_resources_and_remainder_together() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	var run := _run(f, "invalid-drop-batch")
	run.record_kill(run.enemy_ids()[0], f.progress)
	run.resolve("evacuated", f.progress)
	run.reset()
	var first := _drop(f, "first-drop")
	var invalid := _drop(f, "late-invalid-drop")
	invalid.affixes[0].value = 999
	var before: Dictionary = f.inventory.snapshot()
	var bad_batch: Array[Dictionary] = [first, invalid]
	assert_bool(run.commit_rewards(f.inventory, f.roster, bad_batch).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(before)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)
	assert_bool(run.rewards_committed).is_false()
	var duplicate_batch: Array[Dictionary] = [first, first.duplicate(true)]
	assert_bool(run.commit_rewards(f.inventory, f.roster, duplicate_batch).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(before)
	assert_int(f.roster.thief_coin_remainder).is_equal(18)

func test_overflow_can_retry_same_run_once_with_atomic_drop_batch_and_original_history() -> void:
	var f := Fixture.create(0)
	f.roster.commit_coin_remainder(0, 18)
	var run := _run(f, "retry-batch")
	run.record_kill(run.enemy_ids()[0], f.progress)
	run.resolve("evacuated", f.progress)
	run.reset()
	var maximum: int = f.rules.data.inventory.maximum_quantity
	f.inventory.grant({"currency": maximum}, "unit-full-inventory")
	var first := _drop(f, "batch-drop-a")
	var second := _drop(f, "batch-drop-b")
	var additions: Array[Dictionary] = [first, second]
	var before: Dictionary = f.inventory.snapshot()
	assert_bool(run.commit_rewards(f.inventory, f.roster, additions).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(before)
	assert_bool(f.inventory.apply_operation("unit-free-three-coins", {"currency": 3}).ok).is_true()
	assert_bool(run.commit_rewards(f.inventory, f.roster, additions).ok).is_true()
	assert_int(f.inventory.count("currency")).is_equal(maximum)
	assert_int(f.roster.thief_coin_remainder).is_equal(0)
	assert_dict(f.inventory.get_equipment("batch-drop-a").history).is_equal(first.history)
	assert_dict(f.inventory.get_equipment("batch-drop-b").history).is_equal(second.history)
	var committed: Dictionary = f.inventory.snapshot()
	first.history.location = "mutated-test-copy"
	assert_dict(f.inventory.snapshot()).is_equal(committed)
	assert_bool(run.commit_rewards(f.inventory, f.roster, additions).ok).is_false()
	assert_dict(f.inventory.snapshot()).is_equal(committed)
	assert_bool(committed.applied_operations.has(run.settlement_operation_id())).is_true()
