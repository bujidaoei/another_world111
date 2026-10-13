extends RefCounted
class_name AWEquipmentService

const Result = preload("res://config/rule_result.gd")
const Instance = preload("res://features/equipment/equipment_instance.gd")
var _rules: RefCounted

func _init(rules: RefCounted) -> void:
	_rules = rules

func validate_equipment(equipment: Dictionary) -> Dictionary:
	return Instance.validate(equipment, _rules)

func create_drop(instance_id: String, tier: int, quality: String, slot_count: int, origin: Dictionary, seed_value: int) -> Dictionary:
	if not _rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	if instance_id.is_empty() or not tier in [1, 2] or not slot_count in [4, 5] or not quality in _rules.data.equipment.qualities:
		return Result.failure("drop_invalid", "装备掉落参数无效。")
	if not origin.get("location") is String or origin.location.is_empty() or not origin.get("acquired_at") is String or origin.acquired_at.is_empty() or not _rules.is_count(origin.get("level"), 1, 60):
		return Result.failure("drop_origin_invalid", "装备必须记录真实获得地点、等级与时间。")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var definitions: Array = _rules.data.equipment.affixes.keys()
	definitions.sort()
	var choices: Array = []
	_choose_ids(definitions, slot_count, [], 0, choices)
	if choices.is_empty():
		return Result.failure("no_legal_candidates", "没有足够的合法普通词条。")
	var selected: Array = choices[rng.randi_range(0, choices.size() - 1)].duplicate()
	_shuffle(selected, rng)
	var tier_data: Dictionary = _rules.data.equipment.tiers[str(tier)]
	var budget := int(tier_data["budget_%d" % slot_count])
	var base_value := floori(float(budget) / float(slot_count))
	var extra := budget % slot_count
	var affixes: Array = []
	for index: int in range(slot_count):
		affixes.append({"id": str(selected[index]), "value": base_value + (1 if index < extra else 0)})
	var equipment := {"instance_id": instance_id, "name": "闪电枪", "type": "lightning_spear", "slot": "weapon", "tier": tier, "quality": quality, "slot_count": slot_count, "affixes": affixes, "inherent_effect_id": "chain_lightning", "branch_id": "", "equipped": false, "history": {"acquired_at": origin.acquired_at, "location": origin.location, "level": int(origin.level), "ascensions": [], "first_six_chain": null, "branches": []}}
	var validation := validate_equipment(equipment)
	if not validation.ok:
		return validation
	return Result.success({"equipment": equipment, "rules_version": _rules.data.version, "seed": seed_value})

func preview_fusion(inventory: RefCounted, primary_id: String, material_id: String, locked_affix_ids: Array[String], realm: int, in_camp: bool, encounter_ended: bool) -> Dictionary:
	var eligibility := _eligibility(inventory, primary_id, realm, in_camp, encounter_ended)
	if not eligibility.ok:
		return eligibility
	if primary_id == material_id:
		return Result.failure("fusion_same_instance", "主装备不能用自己作材料。")
	var primary: Dictionary = eligibility.data.equipment
	var material: Dictionary = inventory.get_equipment(material_id)
	var validation := validate_equipment(material)
	if not validation.ok:
		return validation
	if material.get("equipped", false):
		return Result.failure("material_equipped", "已装备的物品不能作为融合材料。")
	for key: String in ["tier", "quality", "slot", "type"]:
		if primary[key] != material[key]:
			return Result.failure("fusion_incompatible", "融合要求同阶、同品质、同部位且武器类型相同。")
	if locked_affix_ids.size() > int(_rules.data.equipment.maximum_locks):
		return Result.failure("too_many_locks", "最多锁定两条普通词条。")
	var locked: Dictionary = {}
	var locked_value: int = 0
	for id: String in locked_affix_ids:
		if locked.has(id):
			return Result.failure("lock_invalid", "锁定词条不能重复。")
		var found: Dictionary = _find_affix(primary.affixes, id)
		if found.is_empty():
			return Result.failure("lock_invalid", "只能锁定主装备已有普通词条。")
		locked[id] = found.duplicate(true)
		locked_value += int(found.value)
	var pool: Array = []
	var seen: Dictionary = {}
	for source: Array in [primary.affixes, material.affixes]:
		for affix: Dictionary in source:
			var key := "%s:%d" % [affix.id, int(affix.value)]
			if not locked.has(affix.id) and not seen.has(key) and _compatible_with(affix.id, locked.keys()):
				pool.append(affix.duplicate(true))
				seen[key] = true
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (str(a.id) + ":" + str(a.value)) < (str(b.id) + ":" + str(b.value)))
	var tier: Dictionary = _rules.data.equipment.tiers[str(int(primary.tier))]
	var unfilled := int(primary.slot_count) - locked.size()
	var combinations: Array = []
	_choose_affixes(pool, unfilled, [], 0, int(tier["budget_%d" % int(primary.slot_count)]) - locked_value, combinations)
	if combinations.is_empty():
		return Result.failure("no_legal_candidates", "双方合格普通池无法组成完整合法成品，不消耗任何材料。")
	var outcomes: Array = []
	var probabilities: Dictionary = {}
	for choice: Array in combinations:
		var outcome: Array = []
		var cursor: int = 0
		for old: Dictionary in primary.affixes:
			if locked.has(old.id):
				outcome.append(old.duplicate(true))
			else:
				outcome.append(choice[cursor].duplicate(true))
				cursor += 1
		outcomes.append(outcome)
		for candidate: Dictionary in choice:
			probabilities[candidate.id] = float(probabilities.get(candidate.id, 0.0)) + 1.0 / float(combinations.size())
	var tier_material := str(tier.material)
	var cost := {"currency": int(_rules.data.equipment.fusion_currency)}
	cost[tier_material] = int(_rules.data.equipment.fusion_material) + locked.size() * int(_rules.data.equipment.lock_material)
	validation = _can_afford(inventory, cost)
	if not validation.ok:
		return validation
	return Result.success({"cost": cost, "outcomes": outcomes, "candidate_inclusion_probability": probabilities, "outcome_probability": 1.0 / float(outcomes.size()), "locked_affix_ids": locked_affix_ids.duplicate(), "rules_version": _rules.data.version, "primary": primary})

func fuse(inventory: RefCounted, primary_id: String, material_id: String, locked_affix_ids: Array[String], realm: int, in_camp: bool, encounter_ended: bool, operation_id: String, seed_value: int) -> Dictionary:
	var preview := preview_fusion(inventory, primary_id, material_id, locked_affix_ids, realm, in_camp, encounter_ended)
	if not preview.ok:
		return preview
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var equipment: Dictionary = preview.data.primary.duplicate(true)
	equipment.affixes = preview.data.outcomes[rng.randi_range(0, preview.data.outcomes.size() - 1)].duplicate(true)
	var updates := {primary_id: equipment}
	var remove_ids: Array[String] = [material_id]
	var transaction: Dictionary = inventory.apply_operation(operation_id, preview.data.cost, {}, updates, remove_ids)
	if not transaction.ok:
		return transaction
	return Result.success({"equipment": equipment.duplicate(true), "cost": preview.data.cost.duplicate(true), "seed": seed_value, "rules_version": _rules.data.version})

func preview_expansion(inventory: RefCounted, instance_id: String, realm: int, in_camp: bool, encounter_ended: bool) -> Dictionary:
	var eligibility := _eligibility(inventory, instance_id, realm, in_camp, encounter_ended)
	if not eligibility.ok:
		return eligibility
	var equipment: Dictionary = eligibility.data.equipment
	if int(equipment.slot_count) != 4:
		return Result.failure("slot_limit", "扩槽仅支持四槽至五槽。")
	var selected: Array = []
	for affix: Dictionary in equipment.affixes:
		selected.append(affix.id)
	var candidates: Array[String] = []
	for id: String in _rules.data.equipment.affixes:
		if not id in selected and _compatible_with(id, selected):
			candidates.append(id)
	candidates.sort()
	if candidates.is_empty():
		return Result.failure("no_legal_candidates", "没有可加入的合法词条，不消耗扩槽材料。")
	var tier: Dictionary = _rules.data.equipment.tiers[str(int(equipment.tier))]
	var cost := {str(tier.material): int(_rules.data.equipment.expansion_material)}
	var validation := _can_afford(inventory, cost)
	if not validation.ok:
		return validation
	return Result.success({"equipment": equipment, "cost": cost, "candidates": candidates, "candidate_probability": 1.0 / float(candidates.size()), "new_value": int(tier.budget_5) - int(tier.budget_4)})

func expand_slot(inventory: RefCounted, instance_id: String, realm: int, in_camp: bool, encounter_ended: bool, operation_id: String, seed_value: int) -> Dictionary:
	var preview := preview_expansion(inventory, instance_id, realm, in_camp, encounter_ended)
	if not preview.ok:
		return preview
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var equipment: Dictionary = preview.data.equipment.duplicate(true)
	equipment.slot_count = 5
	equipment.affixes.append({"id": preview.data.candidates[rng.randi_range(0, preview.data.candidates.size() - 1)], "value": int(preview.data.new_value)})
	var updates := {instance_id: equipment}
	var transaction: Dictionary = inventory.apply_operation(operation_id, preview.data.cost, {}, updates)
	if not transaction.ok:
		return transaction
	return Result.success({"equipment": equipment.duplicate(true), "cost": preview.data.cost.duplicate(true), "seed": seed_value})

func preview_ascension(inventory: RefCounted, instance_id: String, realm: int, in_camp: bool, encounter_ended: bool) -> Dictionary:
	var eligibility := _eligibility(inventory, instance_id, realm, in_camp, encounter_ended)
	if not eligibility.ok:
		return eligibility
	var equipment: Dictionary = eligibility.data.equipment
	if int(equipment.tier) != 1 or realm < 2:
		return Result.failure("ascension_ineligible", "装备进阶需要已通过二阶个人资格且装备仍为一阶。")
	var validation := _can_afford(inventory, _rules.data.equipment.ascension_cost)
	if not validation.ok:
		return validation
	return Result.success({"equipment": equipment, "cost": _rules.data.equipment.ascension_cost.duplicate(true)})

func ascend(inventory: RefCounted, instance_id: String, realm: int, in_camp: bool, encounter_ended: bool, operation_id: String, origin: Dictionary) -> Dictionary:
	var preview := preview_ascension(inventory, instance_id, realm, in_camp, encounter_ended)
	if not preview.ok:
		return preview
	if not origin.get("location") is String or origin.location.is_empty() or not origin.get("at") is String or origin.at.is_empty():
		return Result.failure("ascension_origin_invalid", "进阶必须记录真实地点与时间。")
	var equipment: Dictionary = preview.data.equipment.duplicate(true)
	var old_budget := float(_rules.data.equipment.tiers["1"]["budget_%d" % int(equipment.slot_count)])
	var new_budget := float(_rules.data.equipment.tiers["2"]["budget_%d" % int(equipment.slot_count)])
	equipment.tier = 2
	for affix: Dictionary in equipment.affixes:
		affix.value = maxi(1, int(floor(float(affix.value) * new_budget / old_budget)))
	equipment.history.ascensions.append({"tier": 2, "location": origin.location, "at": origin.at, "operation_id": operation_id})
	var updates := {instance_id: equipment}
	var transaction: Dictionary = inventory.apply_operation(operation_id, preview.data.cost, {}, updates)
	if not transaction.ok:
		return transaction
	return Result.success({"equipment": equipment.duplicate(true), "cost": preview.data.cost.duplicate(true)})

func _eligibility(inventory: RefCounted, instance_id: String, realm: int, in_camp: bool, encounter_ended: bool) -> Dictionary:
	if not in_camp or not encounter_ended:
		return Result.failure("camp_required", "装备培养只能在营地且遭遇结束后进行。")
	var equipment: Dictionary = inventory.get_equipment(instance_id)
	var validation := validate_equipment(equipment)
	if not validation.ok:
		return validation
	if realm < int(equipment.tier) or realm > int(_rules.data.progression.maximum_realm):
		return Result.failure("realm_required", "装备超过个人境界。")
	return Result.success({"equipment": equipment})

func _can_afford(inventory: RefCounted, cost: Dictionary) -> Dictionary:
	for resource: String in cost:
		if inventory.count(resource) < int(cost[resource]):
			return Result.failure("insufficient_resources", "资源不足：%s。" % resource)
	return Result.success()

func _find_affix(affixes: Array, id: String) -> Dictionary:
	for affix: Dictionary in affixes:
		if affix.id == id:
			return affix
	return {}

func _compatible_with(id: String, selected: Array) -> bool:
	for other: Variant in selected:
		if id == str(other) or other in _rules.data.equipment.affixes[id].incompatible:
			return false
	return true

func _choose_ids(pool: Array, needed: int, selected: Array, start: int, output: Array) -> void:
	if needed == 0:
		output.append(selected.duplicate())
		return
	for index: int in range(start, pool.size() - needed + 1):
		var id := str(pool[index])
		if not _compatible_with(id, selected):
			continue
		selected.append(id)
		_choose_ids(pool, needed - 1, selected, index + 1, output)
		selected.pop_back()

func _choose_affixes(pool: Array, needed: int, selected: Array, start: int, remaining_budget: int, output: Array) -> void:
	if needed == 0:
		output.append(selected.duplicate(true))
		return
	var ids: Array = []
	for existing: Dictionary in selected:
		ids.append(existing.id)
	for index: int in range(start, pool.size() - needed + 1):
		var candidate: Dictionary = pool[index]
		if int(candidate.value) > remaining_budget or not _compatible_with(candidate.id, ids):
			continue
		selected.append(candidate)
		_choose_affixes(pool, needed - 1, selected, index + 1, remaining_budget - int(candidate.value), output)
		selected.pop_back()

func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var saved: Variant = values[index]
		values[index] = values[other]
		values[other] = saved
