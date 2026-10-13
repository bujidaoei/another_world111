class_name AWInputBindings
extends RefCounted

signal changed(snapshot: Dictionary)

const Result = preload("res://config/rule_result.gd")
const ACTIONS: Array[String] = ["move_left", "move_right", "move_forward", "move_back", "attack", "defend", "dodge", "pulse", "anchor", "interact", "heal", "camera_lock", "camera_reset", "pause"]
const OPTIONAL_KEYS: Array[String] = ["attack", "defend"]
const RESERVED_KEYS: Array[int] = [KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]
const SCHEMA_VERSION: int = 1
var ready: bool = false
var _bindings: Dictionary = {}
var _defaults: Dictionary = {}
var _labels: Dictionary = {}

func load_file(path: String = "res://config/input_bindings.json") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Result.failure("bindings_unreadable", "键位配置无法读取。")
	if file.get_length() > 131072:
		return Result.failure("bindings_config_too_large", "键位配置超过支持大小。")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		return Result.failure("bindings_invalid_json", "键位配置格式无效。")
	var parsed: Dictionary = parser.data
	if parsed.size() != 3 or not parsed.has("schema_version") or not parsed.has("bindings") or not parsed.has("labels"):
		return Result.failure("bindings_config_invalid", "键位配置包含未知或缺少字段。")
	var validation := _validate_snapshot({"schema_version": parsed.schema_version, "bindings": parsed.bindings})
	if not validation.ok:
		return validation
	if not parsed.get("labels") is Dictionary or parsed.labels.size() != ACTIONS.size():
		return Result.failure("bindings_labels_invalid", "键位配置缺少动作名称。")
	for action: String in ACTIONS:
		if not parsed.labels.get(action) is String or str(parsed.labels[action]).is_empty():
			return Result.failure("bindings_labels_invalid", "动作名称无效：%s。" % action)
	_defaults = validation.data.duplicate(true)
	_bindings = validation.data.bindings.duplicate(true)
	_labels = parsed.labels.duplicate(true)
	ready = true
	return Result.success(snapshot())

func snapshot() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "bindings": _bindings.duplicate(true)}

func validate(candidate: Dictionary) -> Dictionary:
	if not ready:
		return Result.failure("bindings_not_ready", "键位配置尚未载入。")
	return _validate_snapshot(candidate)

func _validate_snapshot(candidate: Dictionary) -> Dictionary:
	if candidate.size() != 2 or not _integer(candidate.get("schema_version")) or int(candidate.schema_version) != SCHEMA_VERSION or not candidate.get("bindings") is Dictionary:
		return Result.failure("bindings_schema_invalid", "键位存档版本或结构无效。")
	var incoming: Dictionary = candidate.bindings
	if incoming.size() != ACTIONS.size():
		return Result.failure("bindings_actions_invalid", "键位必须包含此版本全部动作。")
	var normalized: Dictionary = {}
	var owners: Dictionary = {}
	for action: String in ACTIONS:
		if not incoming.has(action) or not _integer(incoming[action]):
			return _reject("binding_key_invalid", "动作键码必须是有效整数。", {"action": action})
		var key := int(incoming[action])
		if action == "pause":
			if key != KEY_ESCAPE:
				return _reject("binding_navigation_reserved", "暂停/返回的Escape键为保留导航键。", {"action": action})
		elif key in RESERVED_KEYS:
			return _reject("binding_navigation_reserved", "该按键保留给菜单导航。", {"action": action, "key": key})
		if key == 0:
			if not action in OPTIONAL_KEYS:
				return _reject("binding_required", "必要动作不能取消键盘绑定。", {"action": action})
		else:
			if not _valid_physical_key(key):
				return _reject("binding_key_invalid", "该物理键码无效或含组合修饰符。", {"action": action, "key": key})
			if owners.has(key):
				return _reject("binding_conflict", "该按键已用于另一动作。", {"action": action, "conflict_action": owners[key], "key": key})
			owners[key] = action
		normalized[action] = key
	return Result.success({"schema_version": SCHEMA_VERSION, "bindings": normalized})

func preview_remap(action: String, physical_keycode: int) -> Dictionary:
	if not ready:
		return Result.failure("bindings_not_ready", "键位配置尚未载入。")
	if not action in ACTIONS:
		return Result.failure("binding_action_unknown", "不存在该可配置动作。")
	var candidate := snapshot()
	candidate.bindings[action] = physical_keycode
	return validate(candidate)

func set_binding(action: String, physical_keycode: int) -> Dictionary:
	var preview := preview_remap(action, physical_keycode)
	if not preview.ok:
		return preview
	return apply(preview.data)

func apply(candidate: Dictionary) -> Dictionary:
	var validation := validate(candidate)
	if not validation.ok:
		return validation
	# Construct every replacement before mutating the shared InputMap.
	var prepared: Dictionary = {}
	for action: String in ACTIONS:
		var key := int(validation.data.bindings[action])
		if key != 0:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			prepared[action] = event
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for existing: InputEvent in InputMap.action_get_events(action):
			if existing is InputEventKey:
				InputMap.action_erase_event(action, existing)
		if prepared.has(action):
			InputMap.action_add_event(action, prepared[action])
	_bindings = validation.data.bindings.duplicate(true)
	var applied := snapshot()
	changed.emit(applied.duplicate(true))
	return Result.success(applied)

func restore(candidate: Dictionary) -> Dictionary:
	return apply(candidate)

func reset_defaults() -> Dictionary:
	if not ready:
		return Result.failure("bindings_not_ready", "键位配置尚未载入。")
	return apply(_defaults)

func key_for(action: String) -> int:
	return int(_bindings.get(action, 0))

func label_for(action: String) -> String:
	return str(_labels.get(action, action))

func key_label(action: String) -> String:
	var key := key_for(action)
	return "未绑定" if key == 0 else OS.get_keycode_string(key as Key)

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 0.0 and float(value) <= float(KEY_SPECIAL | 0xFFFF)

static func _valid_physical_key(key: int) -> bool:
	if key <= 0 or key > (KEY_SPECIAL | 0xFFFF):
		return false
	var name := OS.get_keycode_string(key as Key)
	return not name.is_empty() and int(OS.find_keycode_from_string(name)) == key

static func _reject(code: String, message: String, details: Dictionary) -> Dictionary:
	var result := Result.failure(code, message)
	result.data = details
	return result
