extends GdUnitTestSuite

const Rules = preload("res://config/rules_config.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Service = preload("res://features/equipment/equipment_service.gd")

func _rules() -> RefCounted:
	var rules := Rules.new()
	assert_bool(rules.load_file("res://config/rules.json").ok).is_true()
	return rules

func _origin(location: String = "rain_court") -> Dictionary:
	return {"location": location, "level": 1, "acquired_at": "2026-10-13T12:00:00+08:00"}

func _stock(rules: RefCounted, service: RefCounted) -> RefCounted:
	var inventory := Inventory.new(rules)
	inventory.grant({"currency": 200, "scrap": 100, "alloy": 100}, "test-fixture-resources")
	for item_id: String in ["primary", "material"]:
		var item: Dictionary = service.create_drop(item_id, 1, "rare", 4, _origin(), 12 if item_id == "primary" else 21).data.equipment
		inventory.add_equipment(item)
	return inventory

func test_fusion_preserves_identity_history_locks_and_cost_exactly_once() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	var original: Dictionary = inventory.get_equipment("primary")
	var locked: Array[String] = [original.affixes[0].id, original.affixes[1].id]
	var preview: Dictionary = service.preview_fusion(inventory, "primary", "material", locked, 1, true, true)
	assert_bool(preview.ok).is_true()
	assert_int(preview.data.cost.currency).is_equal(12)
	assert_int(preview.data.cost.scrap).is_equal(4)
	assert_bool(service.fuse(inventory, "primary", "material", locked, 1, true, true, "fuse-1", 34).ok).is_true()
	var current: Dictionary = inventory.get_equipment("primary")
	for key: String in ["instance_id", "tier", "quality", "slot_count", "inherent_effect_id", "branch_id", "history"]:
		assert_that(current[key]).is_equal(original[key])
	assert_dict(current.affixes[0]).is_equal(original.affixes[0])
	assert_dict(current.affixes[1]).is_equal(original.affixes[1])
	assert_bool(inventory.get_equipment("material").is_empty()).is_true()
	assert_int(inventory.count("currency")).is_equal(188)
	assert_int(inventory.count("scrap")).is_equal(96)
	assert_bool(service.fuse(inventory, "primary", "material", locked, 1, true, true, "fuse-1", 34).ok).is_false()
	assert_int(inventory.count("currency")).is_equal(188)

func test_fusion_invalid_context_locks_and_identity_do_not_consume() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	var before: Dictionary = inventory.snapshot()
	var item: Dictionary = inventory.get_equipment("primary")
	var three: Array[String] = [item.affixes[0].id, item.affixes[1].id, item.affixes[2].id]
	assert_bool(service.fuse(inventory, "primary", "material", three, 1, true, true, "invalid-1", 1).ok).is_false()
	assert_bool(service.fuse(inventory, "primary", "material", [], 1, true, false, "invalid-2", 1).ok).is_false()
	assert_bool(service.fuse(inventory, "primary", "primary", [], 1, true, true, "invalid-3", 1).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(before)

func test_expansion_preserves_every_old_affix_and_natural_five_slot_limits() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	var original: Dictionary = inventory.get_equipment("primary")
	assert_bool(service.expand_slot(inventory, "primary", 1, true, true, "expand-1", 123).ok).is_true()
	var expanded: Dictionary = inventory.get_equipment("primary")
	assert_int(expanded.slot_count).is_equal(5)
	for index: int in range(4):
		assert_dict(expanded.affixes[index]).is_equal(original.affixes[index])
	assert_int(expanded.affixes[4].value).is_equal(20)
	assert_bool(service.validate_equipment(expanded).ok).is_true()
	assert_bool(service.validate_equipment(service.create_drop("natural", 1, "rare", 5, _origin(), 75).data.equipment).ok).is_true()
	assert_int(inventory.count("scrap")).is_equal(92)

func test_ascension_requires_personal_realm_and_preserves_history_and_slots() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	var before: Dictionary = inventory.snapshot()
	assert_bool(service.ascend(inventory, "primary", 1, true, true, "ascend-1", {"location": "camp", "at": "2026-10-13T13:00:00+08:00"}).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(before)
	assert_bool(service.ascend(inventory, "primary", 2, true, true, "ascend-1", {"location": "camp", "at": "2026-10-13T13:00:00+08:00"}).ok).is_true()
	var advanced: Dictionary = inventory.get_equipment("primary")
	assert_int(advanced.tier).is_equal(2)
	assert_int(advanced.slot_count).is_equal(4)
	assert_str(advanced.quality).is_equal("rare")
	assert_str(advanced.history.location).is_equal("rain_court")
	assert_int(advanced.history.ascensions.size()).is_equal(1)
	assert_that(advanced.history.first_six_chain).is_null()
	assert_int(inventory.count("scrap")).is_equal(90)
	assert_int(inventory.count("alloy")).is_equal(95)
	assert_bool(service.validate_equipment(advanced).ok).is_true()

func test_seeded_generation_and_fusion_outcomes_always_respect_budget_and_exclusions() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	for tier: int in [1, 2]:
		for slots: int in [4, 5]:
			for seed_value: int in range(40):
				var first: Dictionary = service.create_drop("drop", tier, "rare", slots, _origin(), seed_value)
				var second: Dictionary = service.create_drop("drop", tier, "rare", slots, _origin(), seed_value)
				assert_bool(first.ok).is_true()
				assert_dict(first.data.equipment).is_equal(second.data.equipment)
				assert_bool(service.validate_equipment(first.data.equipment).ok).is_true()
	var inventory := _stock(rules, service)
	var preview: Dictionary = service.preview_fusion(inventory, "primary", "material", [], 1, true, true)
	assert_bool(preview.ok).is_true()
	for affixes: Array in preview.data.outcomes:
		var candidate: Dictionary = inventory.get_equipment("primary")
		candidate.affixes = affixes
		assert_bool(service.validate_equipment(candidate).ok).is_true()

func test_inventory_copy_isolation_and_equipped_material_rejection() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	var detached: Dictionary = inventory.get_equipment("primary")
	detached.affixes[0].value = 999
	assert_bool(service.validate_equipment(inventory.get_equipment("primary")).ok).is_true()
	var saved: Dictionary = inventory.snapshot()
	saved.equipment.material.equipped = true
	assert_bool(inventory.restore(saved).ok).is_true()
	var before: Dictionary = inventory.snapshot()
	assert_bool(service.fuse(inventory, "primary", "material", [], 1, true, true, "fuse-1", 1).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(before)

func test_previews_reject_insufficient_resources_without_mutation() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	inventory.apply_operation("empty-wallet", {"currency": 200, "scrap": 100, "alloy": 100})
	var before: Dictionary = inventory.snapshot()
	assert_bool(service.preview_fusion(inventory, "primary", "material", [], 1, true, true).ok).is_false()
	assert_bool(service.preview_expansion(inventory, "primary", 1, true, true).ok).is_false()
	assert_bool(service.preview_ascension(inventory, "primary", 2, true, true).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(before)

func test_all_legal_four_slot_type_sets_expand_at_single_affix_limit() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var ids: Array = rules.data.equipment.affixes.keys()
	ids.sort()
	var checked: int = 0
	for a: int in range(ids.size()):
		for b: int in range(a + 1, ids.size()):
			for c: int in range(b + 1, ids.size()):
				for d: int in range(c + 1, ids.size()):
					var item: Dictionary = service.create_drop("edge", 1, "rare", 4, _origin(), 1).data.equipment
					item.affixes = [{"id": ids[a], "value": 35}, {"id": ids[b], "value": 35}, {"id": ids[c], "value": 20}, {"id": ids[d], "value": 10}]
					if not service.validate_equipment(item).ok:
						continue
					var inventory := Inventory.new(rules)
					inventory.grant({"scrap": 8}, "fixture")
					inventory.add_equipment(item)
					assert_bool(service.expand_slot(inventory, "edge", 1, true, true, "expand", 1).ok).is_true()
					var expanded: Dictionary = inventory.get_equipment("edge")
					assert_int(expanded.affixes[0].value).is_equal(35)
					assert_bool(service.validate_equipment(expanded).ok).is_true()
					checked += 1
	assert_int(checked).is_equal(55)

func test_all_tiers_qualities_slots_and_locks_use_identical_currency_cost() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	for tier: int in [1, 2]:
		for quality: String in ["common", "rare"]:
			for slots: int in [4, 5]:
				for lock_count: int in [0, 1, 2]:
					var inventory := Inventory.new(rules)
					inventory.grant({"currency": 100, "scrap": 100, "alloy": 100}, "fixture")
					var primary: Dictionary = service.create_drop("primary", tier, quality, slots, _origin(), 1).data.equipment
					var material: Dictionary = service.create_drop("material", tier, quality, slots, _origin(), 2).data.equipment
					inventory.add_equipment(primary)
					inventory.add_equipment(material)
					var locks: Array[String] = []
					for index: int in range(lock_count):
						locks.append(primary.affixes[index].id)
					var preview: Dictionary = service.preview_fusion(inventory, "primary", "material", locks, tier, true, true)
					assert_bool(preview.ok).is_true()
					assert_int(preview.data.cost.currency).is_equal(12)
					var tier_material := "scrap" if tier == 1 else "alloy"
					assert_int(preview.data.cost[tier_material]).is_equal(2 + lock_count)
					assert_bool(service.fuse(inventory, "primary", "material", locks, tier, true, true, "fusion", 8).ok).is_true()
					assert_int(inventory.count("currency")).is_equal(88)

func test_invalid_budget_or_special_ability_restore_never_replaces_valid_inventory() -> void:
	var rules := _rules()
	var service := Service.new(rules)
	var inventory := _stock(rules, service)
	var original: Dictionary = inventory.snapshot()
	var invalid := original.duplicate(true)
	invalid.equipment.primary.affixes[0].value = 36
	assert_bool(inventory.restore(invalid).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(original)
	invalid = original.duplicate(true)
	invalid.equipment.material.inherent_effect_id = "unearned_realm_three_ability"
	assert_bool(inventory.restore(invalid).ok).is_false()
	assert_dict(inventory.snapshot()).is_equal(original)
