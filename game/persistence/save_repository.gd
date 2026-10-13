class_name SaveRepository
extends RefCounted
## Synchronous, process-serialized two-generation persistence for JSON-safe data.
## A successful result means the promoted slot has been reopened and verified.

signal diagnostic(event: Dictionary)

const SCHEMA_VERSION: int = 2
const MAX_FILE_BYTES: int = 1024 * 1024
const MAX_SAFE_INTEGER: int = 9007199254740991
const MAX_DEPTH: int = 32
const MAX_VALUES: int = 100000
const SLOT_NAMES: Array[String] = ["slot_a.json", "slot_b.json"]
const Settings = preload("res://persistence/game_settings.gd")
static var _io_mutex: Mutex = Mutex.new()
var _directory: String = "user://saves"


func configure(directory: String = "user://saves") -> Dictionary:
	_io_mutex.lock()
	var result := _configure(directory)
	_io_mutex.unlock()
	return result


func save(payload: Dictionary) -> Dictionary:
	_io_mutex.lock()
	var result := _save(payload)
	_io_mutex.unlock()
	_emit_diagnostic("save", result)
	return result


func load() -> Dictionary:
	_io_mutex.lock()
	var result := _load()
	_io_mutex.unlock()
	_emit_diagnostic("load", result)
	return result


func _configure(directory: String) -> Dictionary:
	if directory.is_empty() or directory.begins_with("res://"):
		return _failure("invalid_path", "存档目录必须是可写用户目录或绝对路径。")
	if not directory.begins_with("user://") and not directory.is_absolute_path():
		return _failure("invalid_path", "存档目录不能使用相对路径。")
	var absolute := ProjectSettings.globalize_path(directory).simplify_path()
	if absolute.get_base_dir() == absolute:
		return _failure("invalid_path", "存档目录不能是文件系统根目录。")
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	if error != OK:
		return _failure("io_error", "无法创建存档目录。", error)
	_directory = absolute
	return {"ok": true, "code": "configured", "message": "存档目录已配置。"}


func _save(payload: Dictionary) -> Dictionary:
	if not _json_safe(payload, 0, {"count": 0}):
		return _failure("invalid_payload", "存档包含不能持久化的数据类型、深度或数值。")
	var payload_json := JSON.stringify(payload, "", true, true)
	if payload_json.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure("invalid_payload", "存档数据超过容量上限。")
	var directory_error := _ensure_directory()
	if directory_error != OK:
		return _failure("io_error", "无法访问存档目录。", directory_error)
	var scan := _scan_slots()
	if scan.future:
		return _failure("future_schema", "检测到更新版本存档，当前版本不会覆盖它。")
	var latest: Dictionary = scan.latest
	if latest.is_empty() and scan.has_existing:
		return _failure("recovery_required", "所有存档槽均无法验证，请保留文件并选择恢复。")
	var sequence: int = int(latest.get("sequence", 0)) + 1
	if sequence > MAX_SAFE_INTEGER:
		return _failure("sequence_exhausted", "存档序号达到安全上限，未修改存档。")
	var target_index: int = 0 if latest.is_empty() else 1 - int(latest.slot_index)
	var target_path := _slot_path(target_index)
	var temporary_path := target_path + ".tmp"
	var envelope := {
		"schema_version": SCHEMA_VERSION,
		"sequence": sequence,
		"payload_json": payload_json,
		"checksum": _checksum(SCHEMA_VERSION, sequence, payload_json),
	}
	var encoded := JSON.stringify(envelope, "", true, true)
	if encoded.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return _failure("invalid_payload", "序列化存档超过容量上限。")
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return _failure("io_error", "存档临时文件无法写入；有效存档保持原样。", FileAccess.get_open_error())
	file.store_string(encoded)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _failure("io_error", "存档写入失败；有效存档保持原样。", write_error)
	var temporary_result := _read_slot(temporary_path, target_index)
	if not temporary_result.ok:
		return _failure("verification_failed", "存档写入后的校验失败；有效存档保持原样。")
	if temporary_result.sequence != sequence or temporary_result.payload_json != payload_json:
		return _failure("verification_failed", "存档回读与写入内容不一致；有效存档保持原样。")
	# Only the older/inactive generation may be replaced. The latest remains intact.
	if FileAccess.file_exists(target_path):
		var remove_error := DirAccess.remove_absolute(target_path)
		if remove_error != OK:
			return _failure("io_error", "无法替换旧存档槽；最新有效存档保持原样。", remove_error)
	var rename_error := DirAccess.rename_absolute(temporary_path, target_path)
	if rename_error != OK:
		return _failure("io_error", "存档提交失败；最新有效存档保持原样。", rename_error)
	var committed := _read_slot(target_path, target_index)
	if not committed.ok or committed.sequence != sequence or committed.payload_json != payload_json:
		return _failure("verification_failed", "提交后的存档未通过回读校验。")
	return _success(committed.data, sequence, false, false, "saved", "存档已写入并回读验证。")


func _load() -> Dictionary:
	var scan := _scan_slots()
	if scan.future:
		return _failure("future_schema", "检测到更新版本存档，请使用对应或更新的游戏版本。")
	var latest: Dictionary = scan.latest
	if latest.is_empty():
		if scan.has_existing:
			return _failure("recovery_required", "所有存档槽均无法验证，未自动新建或覆盖进度。")
		return _failure("not_found", "尚未创建存档。")
	var recovered: bool = scan.has_invalid
	return _success(latest.data, latest.sequence, recovered, latest.migrated, "loaded", "已从有效存档槽恢复。" if recovered else "存档已加载。")


func _scan_slots() -> Dictionary:
	var latest: Dictionary = {}
	var has_existing := false
	var has_invalid := false
	var future := false
	for index in range(SLOT_NAMES.size()):
		var slot := _read_slot(_slot_path(index), index)
		has_existing = has_existing or slot.exists
		if slot.code == "future_schema":
			future = true
		if slot.exists and not slot.ok:
			has_invalid = true
		if slot.ok and (latest.is_empty() or slot.sequence > latest.sequence):
			latest = slot
	return {"latest": latest, "has_existing": has_existing, "has_invalid": has_invalid, "future": future}


func _read_slot(path: String, slot_index: int) -> Dictionary:
	var missing := {"ok": false, "code": "not_found", "exists": false}
	if not FileAccess.file_exists(path):
		if DirAccess.dir_exists_absolute(path):
			return {"ok": false, "code": "io_error", "exists": true}
		return missing
	var invalid := {"ok": false, "code": "invalid_format", "exists": true}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		invalid.code = "io_error"
		return invalid
	var length := file.get_length()
	if length <= 0 or length > MAX_FILE_BYTES:
		file.close()
		return invalid
	var bytes := file.get_buffer(length)
	file.close()
	if bytes.size() != length:
		invalid.code = "io_error"
		return invalid
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return invalid
	var envelope: Dictionary = parser.data
	var version_value: Variant = envelope.get("schema_version")
	if not _positive_integer(version_value):
		return invalid
	var version := int(version_value)
	if version > SCHEMA_VERSION:
		invalid.code = "future_schema"
		return invalid
	if version < 1 or not _positive_integer(envelope.get("sequence")):
		return invalid
	if not envelope.get("payload_json") is String or not envelope.get("checksum") is String:
		return invalid
	var sequence := int(envelope.sequence)
	var payload_json: String = envelope.payload_json
	if envelope.checksum != _checksum(version, sequence, payload_json):
		invalid.code = "checksum_mismatch"
		return invalid
	var payload_parser := JSON.new()
	if payload_parser.parse(payload_json) != OK or not payload_parser.data is Dictionary:
		return invalid
	var payload: Dictionary = payload_parser.data
	if not _json_safe(payload, 0, {"count": 0}):
		return invalid
	var migrated := version != SCHEMA_VERSION
	if version == 1:
		var migration := _migrate_v1(payload)
		if not migration.ok:
			invalid.code = "migration_failed"
			return invalid
		payload = migration.data
	return {
		"ok": true, "code": "valid", "exists": true, "slot_index": slot_index,
		"sequence": sequence, "schema_version": SCHEMA_VERSION, "data": payload,
		"payload_json": payload_json, "migrated": migrated,
	}


func _migrate_v1(payload: Dictionary) -> Dictionary:
	var migrated := payload.duplicate(true)
	if not migrated.has("settings"):
		migrated["settings"] = Settings.default_settings()
	elif not migrated.settings is Dictionary:
		return _failure("migration_failed", "旧版本设置结构无法迁移。")
	else:
		var settings_result := Settings.normalize(migrated.settings)
		if not settings_result.ok:
			return _failure("migration_failed", "旧版本设置内容无法迁移。")
		migrated["settings"] = settings_result.data
	return {"ok": true, "data": migrated}


func _json_safe(value: Variant, depth: int, budget: Dictionary) -> bool:
	budget.count += 1
	if depth > MAX_DEPTH or budget.count > MAX_VALUES:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -MAX_SAFE_INTEGER and value <= MAX_SAFE_INTEGER
		TYPE_FLOAT:
			return is_finite(value) and absf(value) <= MAX_SAFE_INTEGER
		TYPE_ARRAY:
			for item: Variant in value:
				if not _json_safe(item, depth + 1, budget):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _json_safe(value[key], depth + 1, budget):
					return false
			return true
		_:
			return false


func _positive_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and value >= 1 and value <= MAX_SAFE_INTEGER and float(value) == floorf(float(value))


func _checksum(version: int, sequence: int, payload_json: String) -> String:
	return ("%d\n%d\n%s" % [version, sequence, payload_json]).sha256_text()


func _ensure_directory() -> Error:
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))


func _slot_path(index: int) -> String:
	return ProjectSettings.globalize_path(_directory).path_join(SLOT_NAMES[index])


func _success(data: Dictionary, sequence: int, recovered: bool, migrated: bool, code: String, message: String) -> Dictionary:
	return {"ok": true, "code": code, "message": message, "data": data.duplicate(true), "sequence": sequence, "schema_version": SCHEMA_VERSION, "recovered": recovered, "migrated": migrated}


func _failure(code: String, message: String, os_error: int = OK) -> Dictionary:
	var result := {"ok": false, "code": code, "message": message}
	if os_error != OK:
		result.os_error = os_error
	return result


func _emit_diagnostic(operation: String, result: Dictionary) -> void:
	diagnostic.emit({"component": "persistence", "operation": operation, "ok": result.ok, "code": result.code, "schema_version": SCHEMA_VERSION, "sequence": result.get("sequence", 0)})
