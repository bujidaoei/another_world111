class_name AWPresentationConfig
extends RefCounted

const Result = preload("res://config/rule_result.gd")
const BOUNDS := {
	"player": {"move_speed": [0.1, 20], "dodge_speed": [0.1, 40], "dodge_duration": [0.05, 2], "dodge_cost": [1, 1000], "dodge_cooldown": [0.05, 30], "maximum_health": [1, 10000], "maximum_stamina": [1, 1000], "stamina_recovery": [0, 1000], "defense_reduction": [0, 0.95], "defense_drain": [0.1, 1000]},
	"weapon": {"attack_damage": [0.1, 10000], "attack_cooldown": [0.05, 30], "range": [1, 30], "chain_falloff": [0.05, 1], "pulse_damage": [0.1, 10000], "pulse_radius": [0.5, 12], "pulse_cost": [1, 1000], "pulse_cooldown": [0.05, 300], "anchor_lifetime": [0.2, 120], "anchor_cooldown": [0.05, 300], "anchor_cost": [1, 1000]},
	"enemy": {"scavenger_health": [1, 10000], "spitter_health": [1, 10000], "guardian_health": [1, 100000], "move_speed": [0.1, 20], "attack_damage": [0.1, 10000], "attack_range": [0.5, 12], "attack_windup": [0.1, 10], "attack_cooldown": [0.1, 30], "ranged_range": [1, 30], "ranged_windup": [0.1, 10], "guardian_damage": [0.1, 10000], "guardian_radius": [0.5, 12]},
	"camera": {"yaw": [-PI, PI], "pitch": [-1.35, -0.4], "distance": [6, 50], "minimum_distance": [6, 50], "maximum_distance": [6, 50], "follow_rate": [0.1, 30], "sensitivity": [0.0001, 0.03], "occlusion_alpha": [0.05, 0.5], "occlusion_check_interval": [0.05, 0.5]},
	"world": {"half_extent": [16, 16], "seed": [0, 4294967295], "interaction_range": [1, 4], "camp_radius": [1, 8]},
	"save": {"checkpoint_interval": [0.5, 30]},
	"input": {"stick_deadzone": [0, 0.89], "touch_deadzone": [0, 0.89]},
}

static func load_file(path: String = "res://config/presentation.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _invalid("表现配置无法读取。", "file")
	if file.get_length() > 131072:
		return _invalid("表现配置超过支持大小。", "file")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return _invalid("表现配置不是合法JSON对象。", "file")
	return validate(parser.data)

static func validate(candidate: Dictionary) -> Dictionary:
	if candidate.size() != BOUNDS.size() + 1 or not candidate.get("version") is String or str(candidate.version).is_empty():
		return _invalid("表现配置章节或版本无效。", "version")
	for section: String in BOUNDS:
		var data: Variant = candidate.get(section)
		if not data is Dictionary:
			return _invalid("表现配置缺少章节。", section)
		var expected: Dictionary = BOUNDS[section]
		var extra := 1 if section == "weapon" else 0
		if data.size() != expected.size() + extra:
			return _invalid("表现配置字段缺失或多余。", section)
		for key: String in expected:
			var value: Variant = data.get(key)
			var bounds: Array = expected[key]
			if not (value is float or value is int) or not is_finite(float(value)) or float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
				return _invalid("表现参数范围或类型无效。", section + "." + key)
	var multipliers: Variant = candidate.weapon.get("tier_damage_multipliers")
	if not multipliers is Dictionary or multipliers.size() != 2:
		return _invalid("武器阶级倍率缺失或多余。", "weapon.tier_damage_multipliers")
	for tier: String in ["1", "2"]:
		var value: Variant = multipliers.get(tier)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.1 or float(value) > 10:
			return _invalid("武器阶级倍率无效。", "weapon.tier_damage_multipliers." + tier)
	if not AWGameRules.is_count(candidate.world.seed, 0, 4294967295):
		return _invalid("场景随机种子必须为整数。", "world.seed")
	if candidate.camera.minimum_distance > candidate.camera.distance or candidate.camera.distance > candidate.camera.maximum_distance:
		return _invalid("镜头初始距离超出缩放限制。", "camera.distance")
	for cost: String in ["dodge_cost"]:
		if candidate.player[cost] > candidate.player.maximum_stamina:
			return _invalid("初始体力无法使用核心动作。", "player." + cost)
	for cost: String in ["pulse_cost", "anchor_cost"]:
		if candidate.weapon[cost] > candidate.player.maximum_stamina:
			return _invalid("初始体力无法使用核心技能。", "weapon." + cost)
	return Result.success(candidate.duplicate(true))

static func _invalid(message: String, field: String) -> Dictionary:
	return Result.failure("presentation_configuration_invalid", message + " [" + field + "]")
