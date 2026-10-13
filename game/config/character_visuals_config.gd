class_name AWCharacterVisualsConfig
extends RefCounted

const Result = preload("res://config/rule_result.gd")
const PATH := "res://config/character_visuals.json"
const HEAL_BONES: Array[String] = ["Spine", "Head", "Clavicle_L", "UpperArm_L", "Forearm_L", "Hand_L"]

static func load_file(path: String = PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 131072:
		return _invalid("角色视觉配置无法读取或超出大小限制。")
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return _invalid("角色视觉配置不是合法JSON。")
	return validate(json.data)

static func validate(value: Variant) -> Dictionary:
	if not _keys(value, ["schema_version", "default_character", "model_scale", "weapon", "animation", "characters"]) or not _number(value.schema_version, 1, 1):
		return _invalid("视觉配置字段或版本无效。")
	if value.default_character not in ["thief", "healer"] or not _number(value.model_scale, .76, .76):
		return _invalid("角色或测量缩放合同无效。")
	var weapon: Variant = value.weapon
	if not _keys(weapon, ["mount_position", "scale", "models"]) or not _vector(weapon.mount_position) or not _number(weapon.scale, .62, .62) or not _keys(weapon.models, ["1", "2"]):
		return _invalid("武器挂点或阶级配置无效。")
	if Vector3(float(weapon.mount_position[0]), float(weapon.mount_position[1]), float(weapon.mount_position[2])) != Vector3(.42, 1.15, -.28):
		return _invalid("挂点偏离已有模型测量合同。")
	for tier: String in weapon.models:
		if not _model_path(weapon.models[tier]):
			return _invalid("武器必须使用本地GLB路径。")
	var animation: Variant = value.animation
	if not _keys(animation, ["walk_nominal_speed", "movement_threshold", "transition_seconds", "self_heal_fadein", "self_heal_fadeout", "self_heal_filter_bones"]):
		return _invalid("动画配置字段无效。")
	for key: String in ["walk_nominal_speed", "movement_threshold", "transition_seconds", "self_heal_fadein", "self_heal_fadeout"]:
		if not _number(animation[key], .001, 100 if key == "walk_nominal_speed" else 1):
			return _invalid("动画数值必须有限且在范围内。")
	if not animation.self_heal_filter_bones is Array or animation.self_heal_filter_bones.size() != HEAL_BONES.size():
		return _invalid("自疗必须只过滤已注册上身骨骼。")
	var seen: Dictionary = {}
	for bone: Variant in animation.self_heal_filter_bones:
		if not bone is String or bone not in HEAL_BONES or seen.has(bone):
			return _invalid("自疗过滤重复、越界或覆盖腿/右枪手。")
		seen[bone] = true
	if not _keys(value.characters, ["thief", "healer"]):
		return _invalid("角色视觉注册表不完整。")
	for id: String in value.characters:
		var definition: Variant = value.characters[id]
		if not _keys(definition, ["scene_path", "skeleton_path", "idle_clip", "walk_clip", "self_heal_clip"]) or not _model_path(definition.scene_path):
			return _invalid("角色模型或动作字段无效。")
		if not definition.skeleton_path is String or definition.skeleton_path != id + "_robot/" + id + "_robot_Rig/Skeleton3D" or definition.idle_clip != "Idle" or definition.walk_clip != "Walk" or definition.self_heal_clip != ("SelfHeal" if id == "healer" else ""):
			return _invalid("骨架/动作与已制作身份不一致。")
	return Result.success((value as Dictionary).duplicate(true))

static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in value:
		if not key is String or key not in expected:
			return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not _number(component, -100, 100):
			return false
	return true

static func _model_path(value: Variant) -> bool:
	return value is String and value.begins_with("res://assets/models/") and value.ends_with(".glb") and ".." not in value and "\\" not in value

static func _invalid(message: String) -> Dictionary:
	return Result.failure("character_visual_configuration_invalid", message)
