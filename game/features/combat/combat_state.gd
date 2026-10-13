extends RefCounted
class_name AWCombatState
## Pure shared gameplay-time authority. Scene effects and inventory transactions stay outside.

const Result = preload("res://config/rule_result.gd")
const Config = preload("res://config/character_builds_config.gd")
const COOLDOWN_KEYS: Array[String] = ["attack", "dodge", "pulse", "anchor", "barrier", "focus", "self_heal", "recovery_family"]
const EFFECT_KEYS: Array[String] = ["barrier_remaining", "barrier_capacity", "focus_remaining"]
const STAT_KEYS: Array[String] = ["max_health", "max_stamina", "move_speed", "stamina_recovery", "defense_drain", "passive_damage_reduction", "attack_damage", "attack_cooldown", "attack_range", "chain_falloff", "chain_range", "chain_targets", "anchor_range", "pulse_damage", "pulse_radius", "common_cooldown_multiplier", "barrier_capacity_multiplier", "barrier_capacity", "focus_damage_bonus"]
const OPERATION_LIMIT: int = 100000
var ready: bool = false
var _configuration: Dictionary = {}
var _presentation: Dictionary = {}
var _skills: Dictionary = {}
var _cooldowns: Dictionary = {}
var _effects: Dictionary = {}
var _operations: Dictionary = {}

func _init(config: Config) -> void:
	for key: String in COOLDOWN_KEYS: _cooldowns[key] = 0.0
	for key: String in EFFECT_KEYS: _effects[key] = 0.0
	if not config.ready: return
	_configuration = config.data.duplicate(true)
	_presentation = config.presentation_data()
	for key: String in config.data.skills: _skills[key] = config.skill(key)
	ready = true

func snapshot() -> Dictionary:
	return {"schema_version": 1, "cooldowns": _cooldowns.duplicate(true), "effects": _effects.duplicate(true)}

func cooldown_remaining(skill_id: String) -> float:
	return float(_cooldowns.get(skill_id, 0.0))

func weapon_damage_multiplier() -> float:
	return 1.0 + float(_skills.focus.damage_bonus) if ready and float(_effects.focus_remaining) > 0.0 else 1.0

func clear_effects() -> void:
	for key: String in EFFECT_KEYS: _effects[key] = 0.0

func tick(delta: float, gameplay_running: bool) -> Dictionary:
	if not ready: return _unavailable()
	if not is_finite(delta) or delta < 0.0: return Result.failure("combat_delta_invalid", "玩法时间必须为有限非负秒。")
	if gameplay_running:
		for key: String in COOLDOWN_KEYS: _cooldowns[key] = maxf(0.0, float(_cooldowns[key]) - delta)
		for key: String in ["barrier_remaining", "focus_remaining"]: _effects[key] = maxf(0.0, float(_effects[key]) - delta)
		if float(_effects.barrier_remaining) == 0.0: _effects["barrier_capacity"] = 0.0
	return Result.success(snapshot())

func preview_cast(skill_id: String, context: Dictionary, vitals: Dictionary, derived_build: Dictionary) -> Dictionary:
	if not ready: return _unavailable()
	if skill_id not in ["attack", "dodge", "anchor", "pulse", "barrier", "focus", "self_heal"]: return Result.failure("skill_unknown", "技能未注册。")
	var actor := _validate_actor(context, vitals)
	if not actor.ok: return actor
	if skill_id == "self_heal" and str(context.active_character_id) != "healer": return Result.failure("exclusive_skill_forbidden", "只有疗愈者可以发动自疗。")
	if skill_id in ["pulse", "barrier", "focus"]:
		if int(context.realm) < int(_skills[skill_id].required_realm): return Result.failure("skill_locked", "技能尚未达到解锁境界。")
		if skill_id not in context.skill_loadout: return Result.failure("skill_not_equipped", "该通用技能未装配。")
	if skill_id == "anchor" and (int(context.realm) < 2 or not _integer(context.get("weapon_tier"), 2, 2)):
		return Result.failure("realm_required", "导电锚点需要二阶境界与二阶电枪。")
	if cooldown_remaining(skill_id) > 0.0: return Result.failure("cooldown_active", "该技能仍在冷却。")
	if skill_id == "self_heal":
		var recovery := _validate_recovery(context, vitals)
		if not recovery.ok: return recovery
	var derived := _validate_derived(derived_build, vitals)
	if not derived.ok: return derived
	var stats: Dictionary = derived.data
	var cost: float = 0.0
	var cooldown: float = 0.0
	var effect_spec: Dictionary = {"kind": skill_id}
	match skill_id:
		"attack":
			cooldown = float(stats.attack_cooldown)
			effect_spec["damage"] = float(stats.attack_damage) * weapon_damage_multiplier()
			effect_spec["range"] = float(stats.attack_range)
		"dodge":
			cost = float(_presentation.player.dodge_cost)
			cooldown = float(_presentation.player.dodge_cooldown)
			effect_spec["duration"] = float(_presentation.player.dodge_duration)
			effect_spec["speed"] = float(_presentation.player.dodge_speed)
		"anchor":
			cost = float(_presentation.weapon.anchor_cost)
			cooldown = float(_presentation.weapon.anchor_cooldown)
			effect_spec["lifetime"] = float(_presentation.weapon.anchor_lifetime)
			effect_spec["range"] = float(stats.anchor_range)
		"pulse", "barrier", "focus", "self_heal":
			cost = float(_skills[skill_id].cost)
			cooldown = float(_skills[skill_id].cooldown)
			if skill_id != "self_heal": cooldown *= float(stats.common_cooldown_multiplier)
			match skill_id:
				"pulse":
					effect_spec["damage"] = float(stats.pulse_damage)
					effect_spec["radius"] = float(stats.pulse_radius)
				"barrier":
					effect_spec["duration"] = float(_skills.barrier.duration)
					effect_spec["capacity"] = float(stats.barrier_capacity)
				"focus":
					effect_spec["duration"] = float(_skills.focus.duration)
					effect_spec["damage_bonus"] = float(_skills.focus.damage_bonus)
				"self_heal":
					effect_spec["heal_amount"] = minf(float(vitals.max_health) - float(vitals.health), float(vitals.max_health) * float(_skills.self_heal.heal_fraction))
	if float(vitals.stamina) < cost: return Result.failure("insufficient_stamina", "体力不足，未施放或设置冷却。")
	var new_vitals := vitals.duplicate(true)
	new_vitals["stamina"] = float(vitals.stamina) - cost
	if skill_id == "self_heal": new_vitals["health"] = float(vitals.health) + float(effect_spec.heal_amount)
	return Result.success({"skill_id": skill_id, "cost": cost, "cooldown": cooldown, "new_vitals": new_vitals, "effect_spec": effect_spec})

func cast(skill_id: String, context: Dictionary, vitals: Dictionary, derived_build: Dictionary, operation_id: String) -> Dictionary:
	var operation := _validate_operation(operation_id)
	if not operation.ok: return operation
	var preview := preview_cast(skill_id, context, vitals, derived_build)
	if not preview.ok: return preview
	_cooldowns[skill_id] = float(preview.data.cooldown)
	match skill_id:
		"self_heal": _cooldowns["recovery_family"] = float(_configuration.recovery.family_cooldown)
		"barrier":
			_effects["barrier_remaining"] = float(preview.data.effect_spec.duration)
			_effects["barrier_capacity"] = float(preview.data.effect_spec.capacity)
		"focus": _effects["focus_remaining"] = float(preview.data.effect_spec.duration)
	_operations[operation_id] = true
	return preview

func preview_recovery(kind: String, context: Dictionary, vitals: Dictionary) -> Dictionary:
	if not ready: return _unavailable()
	if kind not in ["medkit", "rations"]: return Result.failure("recovery_kind_invalid", "恢复物品未注册。")
	var validation := _validate_recovery(context, vitals)
	if not validation.ok: return validation
	return Result.success({"kind": kind, "cost": {kind: 1}, "new_vitals": vitals.duplicate(true), "recovery_cooldown": float(_configuration.recovery.family_cooldown)})

func can_commit_recovery(kind: String, context: Dictionary, vitals: Dictionary, operation_id: String) -> Dictionary:
	var operation := _validate_operation(operation_id)
	return preview_recovery(kind, context, vitals) if operation.ok else operation

func commit_recovery(kind: String, context: Dictionary, vitals: Dictionary, operation_id: String) -> Dictionary:
	var preview := can_commit_recovery(kind, context, vitals, operation_id)
	if not preview.ok: return preview
	_cooldowns["recovery_family"] = float(_configuration.recovery.family_cooldown)
	_operations[operation_id] = true
	return preview

func absorb_damage(post_defense_damage: float) -> Dictionary:
	if not ready: return _unavailable()
	if not is_finite(post_defense_damage) or post_defense_damage < 0.0: return Result.failure("combat_damage_invalid", "伤害必须为有限非负值。")
	var absorbed := minf(post_defense_damage, float(_effects.barrier_capacity)) if float(_effects.barrier_remaining) > 0.0 else 0.0
	_effects["barrier_capacity"] = maxf(0.0, float(_effects.barrier_capacity) - absorbed)
	return Result.success({"absorbed": absorbed, "health_damage": post_defense_damage - absorbed})

func restore(candidate: Dictionary) -> Dictionary:
	if not ready: return _unavailable()
	if _integer(candidate.get("schema_version"), 2, 9007199254740991): return Result.failure("future_schema", "检测到更新版本共享战斗状态，当前版本不会覆盖它。")
	if not _keys(candidate, ["schema_version", "cooldowns", "effects"]) or not _integer(candidate.get("schema_version"), 1, 1) or not _keys(candidate.get("cooldowns"), COOLDOWN_KEYS) or not _keys(candidate.get("effects"), EFFECT_KEYS):
		return Result.failure("combat_schema_invalid", "共享战斗状态字段或版本无效。")
	var maxima := {"attack": float(_presentation.weapon.attack_cooldown), "dodge": float(_presentation.player.dodge_cooldown), "anchor": float(_presentation.weapon.anchor_cooldown), "recovery_family": float(_configuration.recovery.family_cooldown)}
	for key: String in _skills: maxima[key] = float(_skills[key].cooldown)
	var normalized_cooldowns: Dictionary = {}
	for key: String in COOLDOWN_KEYS:
		if not _number(candidate.cooldowns[key], 0.0, float(maxima[key])): return Result.failure("combat_schema_invalid", "共享冷却超出合法范围。")
		normalized_cooldowns[key] = float(candidate.cooldowns[key])
	var effect_maxima := {"barrier_remaining": float(_skills.barrier.duration), "barrier_capacity": _maximum_barrier_capacity(), "focus_remaining": float(_skills.focus.duration)}
	var normalized_effects: Dictionary = {}
	for key: String in EFFECT_KEYS:
		if not _number(candidate.effects[key], 0.0, float(effect_maxima[key])): return Result.failure("combat_schema_invalid", "持续效果超出合法范围。")
		normalized_effects[key] = float(candidate.effects[key])
	if float(normalized_effects.barrier_remaining) == 0.0 and float(normalized_effects.barrier_capacity) != 0.0: return Result.failure("combat_schema_invalid", "已过期屏障不能保留吸收容量。")
	if float(normalized_effects.barrier_remaining) > float(normalized_cooldowns.barrier) or float(normalized_effects.focus_remaining) > float(normalized_cooldowns.focus) or float(normalized_cooldowns.self_heal) > float(normalized_cooldowns.recovery_family):
		return Result.failure("combat_schema_invalid", "持续效果与其共享技能或恢复冷却不配对。")
	_cooldowns = normalized_cooldowns
	_effects = normalized_effects
	_operations.clear()
	return Result.success(snapshot())

func _validate_actor(context: Dictionary, vitals: Dictionary) -> Dictionary:
	if not context.get("active_character_id") is String or not _configuration.characters.has(context.active_character_id) or not _integer(context.get("realm"), 1, 2) or not context.get("gameplay_running") is bool or not context.get("skill_loadout") is Array or context.skill_loadout.size() != 2:
		return Result.failure("combat_context_invalid", "角色、境界或技能装配上下文无效。")
	var seen: Dictionary = {}
	for key: Variant in context.skill_loadout:
		if not key is String or key not in ["pulse", "barrier", "focus"] or seen.has(key): return Result.failure("combat_context_invalid", "通用技能装配无效或重复。")
		seen[key] = true
	if not _keys(vitals, ["health", "max_health", "stamina", "max_stamina"]) or not _number(vitals.get("max_health"), 0.001, 1000000000.0) or not _number(vitals.get("max_stamina"), 0.001, 1000000000.0) or not _number(vitals.get("health"), 0.0, float(vitals.max_health)) or not _number(vitals.get("stamina"), 0.0, float(vitals.max_stamina)):
		return Result.failure("combat_vitals_invalid", "生命和体力必须为当前上限内的有限数值。")
	if float(vitals.health) <= 0.0: return Result.failure("actor_dead", "角色已死亡，不能施放或恢复。")
	if not context.gameplay_running: return Result.failure("gameplay_not_running", "暂停、失焦或标题状态不能施放或恢复。")
	return Result.success()

func _validate_recovery(context: Dictionary, vitals: Dictionary) -> Dictionary:
	var actor := _validate_actor(context, vitals)
	if not actor.ok: return actor
	if float(vitals.health) >= float(vitals.max_health): return Result.failure("recovery_not_needed", "生命已满，未消耗资源或设置冷却。")
	if cooldown_remaining("recovery_family") > 0.0: return Result.failure("recovery_cooldown_active", "恢复能力与物品仍在共享冷却。")
	return Result.success()

func _validate_derived(derived: Dictionary, vitals: Dictionary) -> Dictionary:
	if not _keys(derived.get("stats"), STAT_KEYS): return Result.failure("combat_build_invalid", "战斗需要完整已生效派生属性。")
	var stats: Dictionary = derived.stats
	for key: String in STAT_KEYS:
		if not _number(stats[key], 0.0, 1000000000.0): return Result.failure("combat_build_invalid", "派生属性不是合法有限数值。")
	if not is_equal_approx(float(stats.max_health), float(vitals.max_health)) or not is_equal_approx(float(stats.max_stamina), float(vitals.max_stamina)) or not _number(stats.common_cooldown_multiplier, float(_configuration.limits.common_cooldown_multiplier_minimum), 1.0) or not _number(stats.barrier_capacity, float(_skills.barrier.capacity), _maximum_barrier_capacity()) or not _number(stats.attack_cooldown, 0.001, float(_presentation.weapon.attack_cooldown)) or float(stats.attack_damage) <= 0.0 or float(stats.pulse_damage) <= 0.0 or float(stats.pulse_radius) <= 0.0:
		return Result.failure("combat_build_invalid", "派生上限、技能数值或冷却乘数无效。")
	return Result.success(stats.duplicate(true))

func _validate_operation(operation_id: String) -> Dictionary:
	if not ready: return _unavailable()
	if operation_id.is_empty() or operation_id.length() > 128 or _operations.has(operation_id): return Result.failure("duplicate_operation", "操作已完成或标识无效。")
	if _operations.size() >= OPERATION_LIMIT: return Result.failure("combat_operation_limit", "本次会话操作记录达到安全容量，请保存后重新进入。")
	return Result.success()

func _maximum_barrier_capacity() -> float:
	return float(_skills.barrier.capacity) * float(_configuration.resonances.charged_guard.value)

func _unavailable() -> Dictionary:
	return Result.failure("rules_unavailable", "共享战斗配置尚未正确载入。")

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for key: Variant in value:
		if not key is String or key not in fields: return false
	return true
