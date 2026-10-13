extends RefCounted
class_name AWGameRules

const Result = preload("res://config/rule_result.gd")
var data: Dictionary = {}
var ready: bool = false

func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return Result.failure("configuration_missing", "规则文件不存在。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("configuration_unreadable", "规则文件无法读取。")
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return Result.failure("configuration_invalid_json", "规则文件格式无效。")
	var validation := validate(json.data)
	if not validation.ok:
		return validation
	data = json.data.duplicate(true)
	ready = true
	return Result.success({"version": data.version})

static func is_count(value: Variant, minimum: int = 0, maximum: int = 1000000) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

func validate(candidate: Dictionary) -> Dictionary:
	for section: String in ["progression", "resources", "inventory", "regions", "challenge", "equipment", "camp", "combat"]:
		if not candidate.get(section) is Dictionary:
			return Result.failure("configuration_section", "缺少规则分区：%s。" % section)
	if not candidate.get("version") is String or candidate.version.is_empty():
		return Result.failure("configuration_version", "规则版本不能为空。")
	var progression: Dictionary = candidate.progression
	for field: String in ["levels_per_realm", "maximum_realm", "experience_per_level", "maximum_award"]:
		if not is_count(progression.get(field), 1):
			return Result.failure("configuration_progression", "成长参数无效：%s。" % field)
	if int(progression.maximum_realm) != 2 or int(progression.levels_per_realm) != 30:
		return Result.failure("configuration_scope", "此版本仅支持一至二阶、每阶30级。")
	var inventory: Dictionary = candidate.inventory
	if not is_count(inventory.get("maximum_quantity"), 1) or not is_count(inventory.get("cargo_capacity"), 1):
		return Result.failure("configuration_inventory", "库存容量或数量上限无效。")
	for resource: Variant in candidate.resources:
		if not resource is String or not candidate.resources[resource] is Dictionary or not is_count(candidate.resources[resource].get("weight")):
			return Result.failure("configuration_resource", "资源定义无效。")
	for resource: String in ["currency", "scrap", "alloy", "crystal", "medkit", "rations"]:
		if not candidate.resources.has(resource):
			return Result.failure("configuration_resource", "缺少版本规定资源：%s。" % resource)
	var amounts := validate_resources(inventory.get("starting_resources", {}), candidate.resources)
	if not amounts.ok:
		return amounts
	for region_id: Variant in candidate.regions:
		var region: Variant = candidate.regions[region_id]
		if not region is Dictionary or not is_count(region.get("required_realm"), 1, 2) or not region.get("enemy_ids") is Array or not region.get("nodes") is Dictionary or not region.get("objective") is Dictionary:
			return Result.failure("configuration_region", "区域定义无效。")
		var seen: Dictionary = {}
		for enemy: Variant in region.enemy_ids:
			if not enemy is String or enemy.is_empty() or seen.has(enemy):
				return Result.failure("configuration_enemy", "敌人标识无效或重复。")
			seen[enemy] = true
		for node_id: Variant in region.nodes:
			if not node_id is String or node_id.is_empty():
				return Result.failure("configuration_node", "采集节点标识无效。")
			amounts = validate_resources(region.nodes[node_id], candidate.resources)
			if not amounts.ok:
				return amounts
		if not is_count(region.get("kill_experience"), 1) or not is_count(region.objective.get("experience"), 1) or not is_count(region.objective.get("kills"), 1, region.enemy_ids.size()) or not is_count(region.objective.get("nodes"), 1, region.nodes.size()):
			return Result.failure("configuration_objective", "目标任务不可完成或经验无效。")
		for reward: Variant in [region.get("kill_reward"), region.objective.get("reward")]:
			amounts = validate_resources(reward, candidate.resources)
			if not amounts.ok:
				return amounts
	var equipment: Dictionary = candidate.equipment
	for cost_field: String in ["fusion_currency", "fusion_material", "lock_material", "maximum_locks", "expansion_material"]:
		if not is_count(equipment.get(cost_field), 1):
			return Result.failure("configuration_equipment_cost", "装备费用无效。")
	if int(equipment.maximum_locks) != 2 or not equipment.get("tiers") is Dictionary or not equipment.get("affixes") is Dictionary or not equipment.get("qualities") is Array:
		return Result.failure("configuration_equipment", "装备配置格式无效。")
	for tier_key: String in ["1", "2"]:
		var tier: Variant = equipment.tiers.get(tier_key)
		if not tier is Dictionary or not candidate.resources.has(tier.get("material")) or not is_count(tier.get("budget_4"), 4) or not is_count(tier.get("budget_5"), 5) or not is_count(tier.get("single_limit"), 1):
			return Result.failure("configuration_tier", "装备阶级参数无效。")
		if int(tier.budget_5) <= int(tier.budget_4) or int(tier.budget_4) > 4 * int(tier.single_limit) or int(tier.budget_5) > 5 * int(tier.single_limit) or int(tier.budget_5) - int(tier.budget_4) > int(tier.single_limit):
			return Result.failure("configuration_budget", "词条预算无法满足扩槽及单条限制。")
	for affix_id: Variant in equipment.affixes:
		var definition: Variant = equipment.affixes[affix_id]
		if not affix_id is String or not definition is Dictionary or not definition.get("label") is String or definition.label.is_empty() or not definition.get("category") is String or not definition.get("incompatible") is Array or not definition.get("stat") is String or not (definition.get("scale") is int or definition.get("scale") is float) or not is_finite(float(definition.scale)) or float(definition.scale) <= 0.0:
			return Result.failure("configuration_affix", "词条定义无效。")
	for affix_id: String in equipment.affixes:
		var definition: Dictionary = equipment.affixes[affix_id]
		for excluded: Variant in definition.incompatible:
			if not excluded is String or not equipment.affixes.has(excluded) or excluded == affix_id or not affix_id in equipment.affixes[excluded].incompatible:
				return Result.failure("configuration_affix_exclusion", "词条互斥必须有效且对称。")
	if equipment.affixes.size() < 5 or equipment.affixes.size() > 32 or not _has_compatible_set(equipment.affixes, equipment.affixes.keys(), [], 0, 5) or not _all_four_slot_sets_expand(equipment.affixes, equipment.affixes.keys(), [], 0):
		return Result.failure("configuration_affix_pool", "每个合法四槽组合必须至少有一个合法扩槽候选。")
	for cost: Variant in [equipment.get("ascension_cost"), candidate.camp.get("bench_cost"), candidate.camp.get("medkit_cost"), candidate.camp.get("rations_cost"), candidate.challenge.get("reward")]:
		amounts = validate_resources(cost, candidate.resources)
		if not amounts.ok:
			return amounts
	if candidate.challenge.get("enemy_id") != progression.get("ascension_challenge") or not is_count(candidate.challenge.get("minimum_level"), 30, 30) or not is_count(candidate.challenge.get("experience"), 1):
		return Result.failure("configuration_challenge", "晋阶挑战定义无效。")
	if not is_count(candidate.combat.get("chain_targets"), 3, 3) or not is_count(candidate.combat.get("anchor_required_realm"), 2, 2):
		return Result.failure("configuration_combat", "闪电链或锚点境界规则无效。")
	for range_field: String in ["chain_range", "anchor_range"]:
		var distance: Variant = candidate.combat.get(range_field)
		if not (distance is int or distance is float) or not is_finite(float(distance)) or float(distance) <= 0.0:
			return Result.failure("configuration_combat", "连锁与锚点距离必须是有限正值。")
	for healing: String in ["ration_healing", "medkit_healing"]:
		if not is_count(candidate.camp.get(healing), 1):
			return Result.failure("configuration_camp", "营地补给恢复量无效。")
	if not candidate.regions.has("rain_court") or not candidate.regions.has("conduit_yard"):
		return Result.failure("configuration_region", "当前版本缺少探索或二阶区域。")
	return Result.success()

func _all_four_slot_sets_expand(definitions: Dictionary, pool: Array, selected: Array, start: int) -> bool:
	if selected.size() == 4:
		for candidate: String in pool:
			if _affix_compatible(definitions, candidate, selected):
				return true
		return false
	for index: int in range(start, pool.size() - (4 - selected.size()) + 1):
		var id := str(pool[index])
		if not _affix_compatible(definitions, id, selected):
			continue
		selected.append(id)
		var expandable := _all_four_slot_sets_expand(definitions, pool, selected, index + 1)
		selected.pop_back()
		if not expandable:
			return false
	return true

func _affix_compatible(definitions: Dictionary, id: String, selected: Array) -> bool:
	for other: String in selected:
		if id == other or other in definitions[id].incompatible:
			return false
	return true

func _has_compatible_set(definitions: Dictionary, pool: Array, selected: Array, start: int, needed: int) -> bool:
	if needed == 0:
		return true
	for index: int in range(start, pool.size() - needed + 1):
		var id := str(pool[index])
		if not _affix_compatible(definitions, id, selected):
			continue
		selected.append(id)
		var found := _has_compatible_set(definitions, pool, selected, index + 1, needed - 1)
		selected.pop_back()
		if found:
			return true
	return false

func validate_resources(resources: Variant, definitions: Dictionary = {}) -> Dictionary:
	var known: Dictionary = definitions if not definitions.is_empty() else data.get("resources", {})
	if not resources is Dictionary:
		return Result.failure("resource_format", "资源必须为数量映射。")
	for resource: Variant in resources:
		if not resource is String or not known.has(resource) or not is_count(resources[resource]):
			return Result.failure("resource_invalid", "资源名称或数量无效。")
	return Result.success()
