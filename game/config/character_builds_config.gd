extends RefCounted
class_name AWCharacterBuildsConfig

const Result = preload("res://config/rule_result.gd")
const Rules = preload("res://config/rules_config.gd")
const Presentation = preload("res://config/presentation_config.gd")
const TALENT_REGISTRY := {
	"weapon_training": ["attack", "damage"], "pulse_mastery": ["attack", "skill_damage"], "conduction": ["attack", "chain_falloff"],
	"vitality": ["guard", "maximum_health"], "reserve": ["guard", "maximum_stamina"], "defense_efficiency": ["guard", "defense_drain_reduction"],
	"mobility": ["utility", "move_speed"], "stamina_recovery": ["utility", "stamina_recovery"], "skill_haste": ["utility", "common_cooldown_reduction"],
}
var ready: bool = false
var data: Dictionary = {}
var _skills: Dictionary = {}
var _presentation: Dictionary = {}

func load_file(path: String = "res://config/character_builds.json", presentation: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 131072:
		return _invalid("角色配置无法读取或超出大小限制。", "file")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return _invalid("角色配置不是合法JSON对象。", "file")
	var validation := validate(json.data)
	if not validation.ok:
		return validation
	var base := Presentation.load_file() if presentation.is_empty() else Presentation.validate(presentation)
	if not base.ok:
		return base
	var candidate: Dictionary = json.data
	for skill_id: String in candidate.skills:
		if skill_id != "pulse" and float(candidate.skills[skill_id].cost) > float(base.data.player.maximum_stamina):
			return _invalid("基础体力无法使用已注册技能。", "skills." + skill_id + ".cost")
	data = candidate.duplicate(true)
	_presentation = base.data.duplicate(true)
	_skills = data.skills.duplicate(true)
	_skills["pulse"]["cost"] = float(_presentation.weapon.pulse_cost)
	_skills["pulse"]["cooldown"] = float(_presentation.weapon.pulse_cooldown)
	_skills["pulse"]["damage"] = float(_presentation.weapon.pulse_damage)
	_skills["pulse"]["radius"] = float(_presentation.weapon.pulse_radius)
	ready = true
	return Result.success({"version": data.version, "schema_version": 1})

func skill(skill_id: String) -> Dictionary:
	return _skills.get(skill_id, {}).duplicate(true)

func presentation_matches(presentation: Dictionary) -> bool:
	return ready and _presentation == presentation

func presentation_data() -> Dictionary:
	return _presentation.duplicate(true)

func validate(candidate: Dictionary) -> Dictionary:
	if not _keys(candidate, ["schema_version", "version", "characters", "talents", "skills", "resonances", "recovery", "limits"]) or not Rules.is_count(candidate.get("schema_version"), 1, 1) or not _text(candidate.get("version"), 64):
		return _invalid("角色配置章节或版本无效。", "schema_version")
	if not _keys(candidate.characters, ["thief", "healer"]) or not _keys(candidate.talents, TALENT_REGISTRY.keys()) or not _keys(candidate.skills, ["pulse", "barrier", "focus", "self_heal"]) or not _keys(candidate.resonances, ["wandering_conductor", "charged_guard"]):
		return _invalid("角色、节点、技能或共鸣注册表缺失或多余。", "registry")
	for id: String in candidate.characters:
		var character: Variant = candidate.characters[id]
		if not _keys(character, ["label", "description", "exclusive_skill", "monster_coin_numerator", "monster_coin_denominator"]) or not _text(character.label, 24) or not _text(character.description, 256) or character.exclusive_skill != ("self_heal" if id == "healer" else "") or not Rules.is_count(character.monster_coin_denominator, 20, 20) or not Rules.is_count(character.monster_coin_numerator, 1 if id == "thief" else 0, 1 if id == "thief" else 0):
			return _invalid("角色身份或怪币比例无效。", "characters." + id)
	for id: String in candidate.talents:
		var node: Variant = candidate.talents[id]
		if not _keys(node, ["label", "description", "branch", "rank_limit", "cost", "stat", "per_rank"]) or not _text(node.label, 24) or not _text(node.description, 256) or node.branch != TALENT_REGISTRY[id][0] or node.stat != TALENT_REGISTRY[id][1] or not Rules.is_count(node.rank_limit, 8, 8) or not Rules.is_count(node.cost, 1, 1) or not _number(node.per_rank, 0.0001, 0.1):
			return _invalid("天赋节点身份、成本或效果无效。", "talents." + id)
	for id: String in candidate.skills:
		var skill_data: Variant = candidate.skills[id]
		var fields := ["label", "description", "kind", "required_realm", "stage"]
		fields.append_array(["source"] if id == "pulse" else ["cost", "cooldown"])
		if id == "barrier": fields.append_array(["duration", "capacity"])
		if id == "focus": fields.append_array(["duration", "damage_bonus"])
		if id == "self_heal": fields.append("heal_fraction")
		if not _keys(skill_data, fields) or not _text(skill_data.label, 24) or not _text(skill_data.description, 256) or skill_data.kind != ("exclusive" if id == "self_heal" else "common") or not Rules.is_count(skill_data.required_realm, 2 if id == "focus" else 1, 2 if id == "focus" else 1) or not Rules.is_count(skill_data.stage, int(skill_data.required_realm), int(skill_data.required_realm)):
			return _invalid("技能身份、阶段或字段无效。", "skills." + id)
		if id == "pulse":
			if skill_data.source != "presentation.weapon": return _invalid("脉冲参数必须取中央表现配置。", "skills.pulse.source")
			continue
		if not _number(skill_data.cost, 0.1, 1000) or not _number(skill_data.cooldown, 0.05, 300): return _invalid("技能成本或冷却无效。", "skills." + id)
		if id in ["barrier", "focus"] and not _number(skill_data.duration, 0.05, float(skill_data.cooldown)): return _invalid("技能持续时间超过冷却。", "skills." + id + ".duration")
		if id == "barrier" and not _number(skill_data.capacity, 0.1, 10000): return _invalid("屏障容量无效。", "skills.barrier.capacity")
		if id == "focus" and not _number(skill_data.damage_bonus, 0.001, 1): return _invalid("聚焦增量无效。", "skills.focus.damage_bonus")
		if id == "self_heal" and not _number(skill_data.heal_fraction, 0.001, 1): return _invalid("治疗比例无效。", "skills.self_heal.heal_fraction")
	if not _keys(candidate.recovery, ["family_cooldown"]) or not _number(candidate.recovery.family_cooldown, 0.05, 300) or candidate.skills.self_heal.cooldown != candidate.recovery.family_cooldown:
		return _invalid("专属自疗与恢复家族冷却不一致。", "recovery")
	var limits: Variant = candidate.limits
	if not _keys(limits, ["preset_slots", "preset_name_length", "weapon_id_length", "common_skill_slots", "chain_falloff_maximum", "passive_damage_reduction_maximum", "defense_drain_multiplier_minimum", "common_cooldown_multiplier_minimum"]): return _invalid("构筑限制字段无效。", "limits")
	for pair: Array in [["preset_slots", 3], ["preset_name_length", 24], ["weapon_id_length", 128], ["common_skill_slots", 2]]:
		if not Rules.is_count(limits[pair[0]], pair[1], pair[1]): return _invalid("当前版本固定数量无效。", "limits." + pair[0])
	if not _number(limits.chain_falloff_maximum, 0.05, 0.98) or not _number(limits.passive_damage_reduction_maximum, 0, 0.4) or not _number(limits.defense_drain_multiplier_minimum, 0.1, 1) or not _number(limits.common_cooldown_multiplier_minimum, 0.1, 1): return _invalid("派生属性界限无效。", "limits")
	if not is_equal_approx(float(limits.defense_drain_multiplier_minimum), 1.0 - 8.0 * float(candidate.talents.defense_efficiency.per_rank)) or not is_equal_approx(float(limits.common_cooldown_multiplier_minimum), 1.0 - 8.0 * float(candidate.talents.skill_haste.per_rank)):
		return _invalid("天赋满级乘数与限制不一致。", "limits")
	for id: String in candidate.resonances:
		var resonance: Variant = candidate.resonances[id]
		if not _keys(resonance, ["label", "description", "branch", "points", "weapon_type", "weapon_tier", "required_skill", "required_skill_stage", "stat", "value"]) or not _text(resonance.label, 24) or not _text(resonance.description, 256) or not Rules.is_count(resonance.points, 8, 8) or resonance.weapon_type != "lightning_spear": return _invalid("共鸣定义无效。", "resonances." + id)
		var conductor := id == "wandering_conductor"
		if resonance.branch != ("utility" if conductor else "guard") or resonance.required_skill != ("anchor" if conductor else "barrier") or resonance.stat != ("anchor_range" if conductor else "barrier_capacity_multiplier") or not Rules.is_count(resonance.weapon_tier, 2 if conductor else 1, 2 if conductor else 1) or not Rules.is_count(resonance.required_skill_stage, 2 if conductor else 1, 2 if conductor else 1) or not _number(resonance.value, 0.01 if conductor else 1.0, 10.0 if conductor else 2.0): return _invalid("共鸣跨引用或效果无效。", "resonances." + id)
	return Result.success(candidate.duplicate(true))

static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size(): return false
	for key: Variant in value:
		if not key is String or not key in expected: return false
	return true

static func _text(value: Variant, maximum: int) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= maximum

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _invalid(message: String, field: String) -> Dictionary:
	return Result.failure("character_configuration_invalid", message + " [" + field + "]")
