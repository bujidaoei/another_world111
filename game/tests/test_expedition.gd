extends GdUnitTestSuite

const Rules = preload("res://config/rules_config.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Expedition = preload("res://features/expedition/expedition_state.gd")

func _rules() -> RefCounted:
	var rules := Rules.new()
	assert_bool(rules.load_file("res://config/rules.json").ok).is_true()
	return rules

func test_real_objective_and_evacuation_commit_once() -> void:
	var rules := _rules()
	var inventory := Inventory.new(rules)
	var progress := Progress.new(rules)
	var run := Expedition.new(rules)
	assert_bool(run.begin("run-1", "rain_court").ok).is_true()
	for id: String in ["rain_guard_01", "rain_guard_02", "rain_guard_03"]:
		assert_bool(run.record_kill(id, progress).ok).is_true()
	for id: String in ["rain_scrap_01", "rain_scrap_02"]:
		assert_bool(run.gather(id).ok).is_true()
	assert_bool(run.complete_objective(progress).ok).is_true()
	assert_bool(run.complete_objective(progress).ok).is_false()
	assert_int(progress.level).is_equal(4)
	assert_int(progress.experience).is_equal(18)
	assert_int(inventory.count("currency")).is_equal(0)
	assert_bool(run.resolve("evacuated", progress).ok).is_true()
	assert_bool(run.reset().ok).is_true()
	assert_bool(run.commit_rewards("settle-1", inventory).ok).is_true()
	assert_int(inventory.count("currency")).is_equal(18)
	assert_int(inventory.count("scrap")).is_equal(9)
	assert_bool(run.commit_rewards("settle-2", inventory).ok).is_false()
	assert_int(inventory.count("currency")).is_equal(18)

func test_failure_discards_loot_and_retains_real_experience() -> void:
	var rules := _rules()
	var inventory := Inventory.new(rules)
	var progress := Progress.new(rules)
	var run := Expedition.new(rules)
	run.begin("run-1", "rain_court")
	run.record_kill("rain_guard_01", progress)
	run.gather("rain_scrap_01")
	assert_bool(run.resolve("failed", progress).ok).is_true()
	run.reset()
	assert_bool(run.commit_rewards("settle-1", inventory).ok).is_false()
	assert_int(inventory.count("scrap")).is_equal(0)
	assert_int(progress.experience).is_equal(6)

func test_short_disengagement_does_not_end_encounter_or_enable_camp() -> void:
	var run := Expedition.new(_rules())
	run.begin("run-1", "rain_court")
	assert_bool(run.aggro_lost().ok).is_true()
	assert_int(run.state).is_equal(Expedition.State.ACTIVE)
	assert_bool(run.is_ended()).is_false()
	assert_bool(run.reset().ok).is_false()

func test_unknown_or_duplicate_kills_and_nodes_cannot_invent_rewards() -> void:
	var rules := _rules()
	var progress := Progress.new(rules)
	var run := Expedition.new(rules)
	run.begin("run-1", "rain_court")
	assert_bool(run.record_kill("made_up_enemy", progress).ok).is_false()
	assert_bool(run.gather("made_up_node").ok).is_false()
	run.record_kill("rain_guard_01", progress)
	run.gather("rain_scrap_01")
	assert_bool(run.record_kill("rain_guard_01", progress).ok).is_false()
	assert_bool(run.gather("rain_scrap_01").ok).is_false()
	assert_int(progress.experience).is_equal(6)
	assert_int(run.pending_loot.scrap).is_equal(3)

func test_challenge_requires_gate_and_actual_guardian_defeat() -> void:
	var rules := _rules()
	var progress := Progress.new(rules)
	var run := Expedition.new(rules)
	assert_bool(run.begin("run-1", "conduit_yard", false, 1).ok).is_false()
	progress.award_experience(580, "qualified-kills")
	assert_bool(run.begin("trial-1", "rain_court", true, progress.realm, progress.level).ok).is_true()
	assert_bool(run.resolve("victory", progress).ok).is_false()
	assert_bool(run.record_kill("rain_warden", progress).ok).is_true()
	assert_bool(run.resolve("victory", progress).ok).is_true()
	assert_int(progress.realm).is_equal(2)
	assert_int(progress.level).is_equal(31)
	assert_int(run.pending_loot.alloy).is_equal(8)

func test_inventory_atomic_cost_deduplication_and_restore() -> void:
	var inventory := Inventory.new(_rules())
	assert_bool(inventory.grant({"scrap": 6}, "gather-settle").ok).is_true()
	var before: Dictionary = inventory.snapshot()
	assert_bool(inventory.apply_operation("craft-1", {"scrap": 7}, {"medkit": 1}).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(before)
	assert_bool(inventory.apply_operation("craft-2", {"scrap": 2}, {"medkit": 1}).ok).is_true()
	assert_bool(inventory.apply_operation("craft-2", {"scrap": 2}, {"medkit": 1}).ok).is_false()
	assert_int(inventory.count("scrap")).is_equal(4)
	assert_int(inventory.count("medkit")).is_equal(3)
	var restored := Inventory.new(_rules())
	assert_bool(restored.restore(inventory.snapshot()).ok).is_true()
	assert_bool(restored.apply_operation("craft-2", {"scrap": 2}, {"medkit": 1}).ok).is_false()

func test_reused_run_id_is_rejected_after_settlement() -> void:
	var rules := _rules()
	var progress := Progress.new(rules)
	var inventory := Inventory.new(rules)
	var run := Expedition.new(rules)
	run.begin("run-1", "rain_court")
	run.resolve("evacuated", progress)
	run.reset()
	run.commit_rewards("settle-1", inventory)
	assert_bool(run.begin("run-1", "rain_court").ok).is_false()

func test_restore_rejects_terminal_state_without_outcome_or_real_victory() -> void:
	var rules := _rules()
	var run := Expedition.new(rules)
	run.begin("run-1", "rain_court", true, 1, 30)
	var original: Dictionary = run.snapshot()
	var invalid := original.duplicate(true)
	invalid.state = Expedition.State.VICTORY
	invalid.outcome = "victory"
	assert_bool(run.restore(invalid).ok).is_false()
	assert_dict(run.snapshot()).is_equal(original)
	invalid = original.duplicate(true)
	invalid.state = Expedition.State.ENDED
	assert_bool(run.restore(invalid).ok).is_false()
	assert_dict(run.snapshot()).is_equal(original)
