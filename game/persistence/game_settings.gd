class_name AWGameSettings
extends RefCounted
## Persisted settings are normalized once at the boundary, then validated in full.

const VOLUME_FIELDS: Array[String] = ["master_volume", "music_volume", "sfx_volume", "ambience_volume", "camera_shake"]
const BOOLEAN_FIELDS: Array[String] = ["reduced_flashing", "camera_locked"]
const LANGUAGES: Array[String] = ["zh_CN", "en"]


static func default_settings() -> Dictionary:
	return {
		"master_volume": 0.75,
		"music_volume": 0.35,
		"sfx_volume": 0.75,
		"ambience_volume": 0.45,
		"text_scale": 1.0,
		"camera_shake": 0.3,
		"reduced_flashing": false,
		"language": "zh_CN",
		"camera_locked": false,
	}


static func normalize(settings: Dictionary) -> Dictionary:
	var normalized := default_settings()
	for key: Variant in settings:
		if not key is String or not normalized.has(key):
			return _invalid("设置中出现未知字段。")
		normalized[key] = settings[key]
	return validate(normalized)


static func validate(settings: Dictionary) -> Dictionary:
	var defaults := default_settings()
	if settings.size() != defaults.size():
		return _invalid("设置字段不完整或包含未知字段。")
	for key: String in defaults:
		if not settings.has(key):
			return _invalid("设置缺少必需字段。")
	for key: String in VOLUME_FIELDS:
		if not _number_in_range(settings[key], 0.0, 1.0):
			return _invalid("音量或镜头抖动设置超出0—1范围。")
	if not _number_in_range(settings.text_scale, 0.85, 1.5):
		return _invalid("字号倍率必须在0.85—1.5之间。")
	for key: String in BOOLEAN_FIELDS:
		if not settings[key] is bool:
			return _invalid("开关设置必须是布尔值。")
	if not settings.language is String or not LANGUAGES.has(settings.language):
		return _invalid("当前语言必须是zh_CN或en。")
	return {"ok": true, "code": "settings_valid", "message": "设置已验证。", "data": settings.duplicate(true)}


static func _number_in_range(value: Variant, lower: float, upper: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) >= lower and float(value) <= upper


static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "code": "invalid_settings", "message": message}
