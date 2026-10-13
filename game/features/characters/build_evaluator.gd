extends RefCounted
class_name AWBuildEvaluator

const Result = preload("res://config/rule_result.gd")
const Config = preload("res://config/character_builds_config.gd")
const Rules = preload("res://config/rules_config.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Equipment = preload("res://features/equipment/equipment_instance.gd")
const Presentation = preload("res://config/presentation_config.gd")
var _config: Config
var _rules: Rules
var _presentation: Dictionary = {}
var _ready: bool = false

func _init(config: Config, rules: Rules, presentation: Dictionary) -> void:
	_config = config
	_rules = rules
	var validation := Presentation.validate(presentation)
	_ready = config.ready and rules.ready and validation.ok and config.presentation_matches(presentation)
	if _ready: _presentation = validation.data.duplicate(true)

func get_rules() -> Rules:
	return _rules

func presentation_data() -> Dictionary:
	return _presentation.duplicate(true)

func default_build(weapon_id: String) -> Dictionary:
	var talents: Dictionary = {}
	for id: String in Config.TALENT_REGISTRY: talents[id] = 0
	return {"talents": talents, "skill_loadout": ["pulse", "barrier"], "weapon_id": weapon_id}

func validate_structure(build: Dictionary) -> Dictionary:
	if not _ready:
		return Result.failure("rules_unavailable", "角色规则或基础参数尚未正确载入。")
	if not Config._keys(build, ["talents", "skill_loadout", "weapon_id"]) or not Config._keys(build.get("talents"), Config.TALENT_REGISTRY.keys()) or not Config._text(build.get("weapon_id"), int(_config.data.limits.weapon_id_length)):
		return Result.failure("build_schema_invalid", "构筑字段、节点或装备引用无效。")
	var spent := 0
	var branches := {"attack": 0, "guard": 0, "utility": 0}
	for id: String in _config.data.talents:
		var definition: Dictionary = _config.data.talents[id]
		if not Rules.is_count(build.talents[id], 0, int(definition.rank_limit)):
			return Result.failure("talent_rank", "天赋等级必须是合法的整数。")
		var cost := int(build.talents[id]) * int(definition.cost)
		spent += cost
		branches[str(definition.branch)] += cost
	if not build.skill_loadout is Array or build.skill_loadout.size() != int(_config.data.limits.common_skill_slots):
		return Result.failure("build_schema_invalid", "通用技能必须装配两个槽。")
	var seen: Dictionary = {}
	for id: Variant in build.skill_loadout:
		if id == "self_heal": return Result.failure("exclusive_skill_forbidden", "专属技能不占通用技能槽。")
		if not id is String or not id in ["pulse", "barrier", "focus"]: return Result.failure("build_schema_invalid", "通用技能未注册。")
		if seen.has(id): return Result.failure("skill_duplicate", "不能重复装配同一通用技能。")
		seen[id] = true
	var normalized: Dictionary = build.duplicate(true)
	for id: String in normalized.talents: normalized["talents"][id] = int(normalized.talents[id])
	return Result.success({"spent_points": spent, "branch_points": branches, "build": normalized})

func reference_status(build: Dictionary, progress: Progress, inventory: Inventory) -> Dictionary:
	var structure := validate_structure(build)
	if not structure.ok: return structure
	var reasons: Array[Dictionary] = []
	if int(structure.data.spent_points) > progress.earned_talent_points:
		reasons.append({"code": "talent_budget", "message": "构筑点数超过当前世界总量。"})
	for skill_id: String in build.skill_loadout:
		if progress.realm < int(_config.skill(skill_id).required_realm): reasons.append({"code": "skill_locked", "message": "技能尚未达到解锁境界。", "skill_id": skill_id})
	var item := inventory.get_equipment(build.weapon_id)
	if item.is_empty():
		reasons.append({"code": "equipment_missing", "message": "引用的装备已不存在。", "weapon_id": build.weapon_id})
	else:
		var validity := Equipment.validate(item, _rules)
		if not validity.ok:
			reasons.append({"code": validity.code, "message": validity.message})
		elif int(item.tier) > progress.realm:
			reasons.append({"code": "realm_required", "message": "装备超过当前境界。"})
	return Result.success({"qualified": reasons.is_empty(), "reasons": reasons, "spent_points": int(structure.data.spent_points), "available_points": progress.earned_talent_points, "branch_points": structure.data.branch_points.duplicate(true)})

func evaluate(build: Dictionary, progress: Progress, inventory: Inventory) -> Dictionary:
	var status := reference_status(build, progress, inventory)
	if not status.ok: return status
	if not status.data.qualified:
		var reason: Dictionary = status.data.reasons[0]
		return Result.failure(reason.code, reason.message)
	var item := inventory.get_equipment(build.weapon_id)
	var bonuses: Dictionary = {}
	for affix: Dictionary in item.affixes:
		var definition: Dictionary = _rules.data.equipment.affixes[affix.id]
		var stat := str(definition.stat)
		bonuses[stat] = float(bonuses.get(stat, 0.0)) + float(affix.value) * float(definition.scale)
	for talent_id: String in build.talents:
		var definition: Dictionary = _config.data.talents[talent_id]
		var stat := str(definition.stat)
		bonuses[stat] = float(bonuses.get(stat, 0.0)) + int(build.talents[talent_id]) * float(definition.per_rank)
	for value: float in bonuses.values():
		if not is_finite(value): return Result.failure("derived_stats_invalid", "装备与天赋派生值超出有限范围。")
	var player: Dictionary = _presentation.player
	var weapon: Dictionary = _presentation.weapon
	var limits: Dictionary = _config.data.limits
	var stats := {
		"max_health": float(player.maximum_health) * (1.0 + float(bonuses.get("maximum_health", 0.0))),
		"max_stamina": float(player.maximum_stamina) * (1.0 + float(bonuses.get("maximum_stamina", 0.0))),
		"move_speed": float(player.move_speed) * (1.0 + float(bonuses.get("move_speed", 0.0))),
		"stamina_recovery": float(player.stamina_recovery) * (1.0 + float(bonuses.get("stamina_recovery", 0.0))),
		"defense_drain": float(player.defense_drain) * maxf(float(limits.defense_drain_multiplier_minimum), 1.0 - float(bonuses.get("defense_drain_reduction", 0.0))),
		"passive_damage_reduction": clampf(float(bonuses.get("damage_reduction", 0.0)), 0.0, float(limits.passive_damage_reduction_maximum)),
		"attack_damage": float(weapon.attack_damage) * float(weapon.tier_damage_multipliers[str(int(item.tier))]) * (1.0 + float(bonuses.get("damage", 0.0))),
		"attack_cooldown": float(weapon.attack_cooldown) / (1.0 + float(bonuses.get("attack_speed", 0.0))),
		"attack_range": float(weapon.range),
		"chain_falloff": minf(float(limits.chain_falloff_maximum), float(weapon.chain_falloff) + float(bonuses.get("chain_falloff", 0.0))),
		"chain_range": float(_rules.data.combat.chain_range) * (1.0 + float(bonuses.get("chain_range", 0.0))),
		"chain_targets": int(_rules.data.combat.chain_targets),
		"anchor_range": float(_rules.data.combat.anchor_range),
		"pulse_damage": float(_config.skill("pulse").damage) * (1.0 + float(bonuses.get("skill_damage", 0.0))),
		"pulse_radius": float(_config.skill("pulse").radius),
		"common_cooldown_multiplier": maxf(float(limits.common_cooldown_multiplier_minimum), 1.0 - float(bonuses.get("common_cooldown_reduction", 0.0))),
		"barrier_capacity_multiplier": 1.0,
		"barrier_capacity": float(_config.skill("barrier").capacity),
		"focus_damage_bonus": float(_config.skill("focus").damage_bonus),
	}
	var active: Array[String] = []
	var inactive: Dictionary = {}
	for id: String in _config.data.resonances:
		var resonance: Dictionary = _config.data.resonances[id]
		var reasons: Array[String] = []
		if int(status.data.branch_points[resonance.branch]) < int(resonance.points): reasons.append("branch_points")
		if item.type != resonance.weapon_type or int(item.tier) < int(resonance.weapon_tier): reasons.append("weapon_tier")
		if resonance.required_skill == "anchor":
			if progress.realm < int(resonance.required_skill_stage) or int(item.tier) < int(_rules.data.combat.anchor_required_realm): reasons.append("skill_stage")
		else:
			if not resonance.required_skill in build.skill_loadout: reasons.append("skill_loadout")
			if progress.realm < int(_config.skill(resonance.required_skill).required_realm) or int(_config.skill(resonance.required_skill).stage) < int(resonance.required_skill_stage): reasons.append("skill_stage")
		if reasons.is_empty():
			active.append(id)
			if resonance.stat == "anchor_range": stats["anchor_range"] += float(resonance.value)
			else:
				stats["barrier_capacity_multiplier"] = float(resonance.value)
				stats["barrier_capacity"] *= float(resonance.value)
		else: inactive[id] = reasons
	for value: Variant in stats.values():
		if not is_finite(float(value)) or float(value) < 0.0: return Result.failure("derived_stats_invalid", "构筑派生属性超出有限范围。")
	return Result.success({"stats": stats, "active_resonances": active, "inactive_resonance_reasons": inactive, "spent_points": status.data.spent_points, "available_points": status.data.available_points, "branch_points": status.data.branch_points.duplicate(true)})
