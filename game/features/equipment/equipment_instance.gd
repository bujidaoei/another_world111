extends RefCounted
class_name AWEquipmentInstance

const Result = preload("res://config/rule_result.gd")

static func validate(item: Dictionary, rules: RefCounted) -> Dictionary:
	if not rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	for key: String in ["instance_id", "name", "type", "slot", "quality", "inherent_effect_id", "branch_id"]:
		if not item.get(key) is String:
			return Result.failure("equipment_invalid", "装备身份字段无效。")
	if item.instance_id.is_empty() or item.type != "lightning_spear" or item.slot != "weapon" or not item.quality in rules.data.equipment.qualities or item.inherent_effect_id != "chain_lightning" or item.branch_id != "":
		return Result.failure("equipment_invalid", "装备类型、品质或专属能力超出当前版本。")
	if item.has("equipped") and not item.equipped is bool:
		return Result.failure("equipment_invalid", "装备穿戴标记无效。")
	if not rules.is_count(item.get("tier"), 1, 2) or not rules.is_count(item.get("slot_count"), 4, 5) or not item.get("affixes") is Array or item.affixes.size() != int(item.slot_count):
		return Result.failure("equipment_invalid", "装备阶级、槽数或词条数量无效。")
	var tier: Dictionary = rules.data.equipment.tiers[str(int(item.tier))]
	var total: int = 0
	var seen: Dictionary = {}
	for affix: Variant in item.affixes:
		if not affix is Dictionary or not affix.get("id") is String or not rules.data.equipment.affixes.has(affix.id) or seen.has(affix.id) or not rules.is_count(affix.get("value"), 1, int(tier.single_limit)):
			return Result.failure("affix_invalid", "词条重复、未注册或超过单条上限。")
		for excluded: Variant in rules.data.equipment.affixes[affix.id].incompatible:
			if seen.has(excluded):
				return Result.failure("affix_incompatible", "装备含互斥词条。")
		seen[affix.id] = true
		total += int(affix.value)
	if total > int(tier["budget_%d" % int(item.slot_count)]):
		return Result.failure("affix_budget", "词条总量超过阶级与槽数预算。")
	if not item.get("history") is Dictionary:
		return Result.failure("equipment_history", "装备缺少经历记录。")
	var history: Dictionary = item.history
	if not history.get("acquired_at") is String or history.acquired_at.is_empty() or not history.get("location") is String or history.location.is_empty() or not rules.is_count(history.get("level"), 1, 60) or not history.get("ascensions") is Array or not history.get("branches") is Array or history.get("first_six_chain") != null:
		return Result.failure("equipment_history", "装备经历字段无效或包含未发生的高阶事件。")
	if not history.branches.is_empty() or history.ascensions.size() > 1 or (int(item.tier) == 1 and not history.ascensions.is_empty()):
		return Result.failure("equipment_history", "当前阶级与已发生的装备经历不一致。")
	for event: Variant in history.ascensions:
		if not event is Dictionary or not event.get("location") is String or event.location.is_empty() or not event.get("at") is String or event.at.is_empty() or not rules.is_count(event.get("tier"), 2, 2) or not event.get("operation_id") is String or event.operation_id.is_empty():
			return Result.failure("equipment_history", "装备进阶经历无效。")
	return Result.success({"budget_used": total})
