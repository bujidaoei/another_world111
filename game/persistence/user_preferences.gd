class_name AWUserPreferences
extends RefCounted
## Independent global settings/keybindings; validation never mutates InputMap.

const Repository = preload("res://persistence/save_repository.gd")
const Settings = preload("res://persistence/game_settings.gd")
const Bindings = preload("res://platform/input_bindings.gd")
var _repository: RefCounted
var _binding_validator: RefCounted
var _configured: bool = false


func configure(directory: String) -> Dictionary:
	var candidate_bindings := Bindings.new()
	var defaults := candidate_bindings.load_file()
	if not defaults.ok:
		return defaults
	var candidate_repository := Repository.new()
	var result := candidate_repository.configure(directory)
	if not result.ok:
		return result
	_binding_validator = candidate_bindings
	_repository = candidate_repository
	_configured = true
	return {"ok": true, "code": "preferences_configured", "message": "全局偏好存储已配置。"}


func load() -> Dictionary:
	if not _configured:
		return _failure("preferences_not_ready", "全局偏好存储尚未配置。")
	var stored: Dictionary = _repository.load()
	if not stored.ok:
		return stored
	var validation := _validate_payload(stored.data)
	if not validation.ok:
		return validation
	stored["data"] = validation.data
	stored["code"] = "preferences_loaded"
	stored["message"] = "全局设置与键位已验证读取。"
	return stored


func save(settings: Dictionary, input_bindings: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("preferences_not_ready", "全局偏好存储尚未配置。")
	var validation := _validate_payload({"settings": settings, "input_bindings": input_bindings})
	if not validation.ok:
		return validation
	# A valid replacement is not permission to clear existing unreadable data.
	# Keep future/structurally damaged/domain-invalid preferences until recovery.
	var existing: Dictionary = _repository.load()
	if existing.ok:
		var existing_validation := _validate_payload(existing.data)
		if not existing_validation.ok:
			return existing_validation
	elif existing.code != "not_found":
		return existing
	var result: Dictionary = _repository.save(validation.data)
	if result.ok:
		result["code"] = "preferences_saved"
		result["message"] = "全局设置与键位已写入并回读验证。"
	return result


func _validate_payload(payload: Dictionary) -> Dictionary:
	if payload.size() != 2 or not payload.get("settings") is Dictionary or not payload.get("input_bindings") is Dictionary:
		return _failure("preferences_invalid", "偏好必须只包含完整设置与键位快照。")
	var candidate_bindings: Dictionary = payload.input_bindings
	if candidate_bindings.size() != 2 or not candidate_bindings.has("schema_version") or not candidate_bindings.has("bindings"):
		return _failure("preferences_invalid", "偏好键位快照包含未知或缺少字段。")
	var version: Variant = candidate_bindings.schema_version
	if (version is int or version is float) and is_finite(float(version)) and float(version) == floorf(float(version)) and float(version) > Bindings.SCHEMA_VERSION:
		return _failure("future_schema", "检测到更新版本键位偏好，当前版本不会覆盖它。")
	var settings_validation := Settings.validate(payload.settings)
	if not settings_validation.ok:
		return settings_validation
	var bindings_validation: Dictionary = _binding_validator.validate(candidate_bindings)
	if not bindings_validation.ok:
		return bindings_validation
	return {"ok": true, "code": "preferences_valid", "message": "偏好候选已验证。", "data": {"settings": settings_validation.data, "input_bindings": bindings_validation.data}}


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
