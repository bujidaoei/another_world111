class_name AWInputAdapter
extends Node

signal diagnostic(result: Dictionary)

const Bindings = preload("res://platform/input_bindings.gd")
const Result = preload("res://config/rule_result.gd")
const MOVE_ACTIONS: Array[String] = ["move_left", "move_right", "move_forward", "move_back"]
const COMMAND_ACTIONS: Array[String] = ["dodge", "pulse", "anchor", "interact", "heal", "camera_lock", "camera_reset", "skill_secondary", "character_ability"]
var bindings: RefCounted = Bindings.new()
var initialization_result: Dictionary = {}
var movement := Vector2.ZERO
var aiming := Vector2.ZERO
var attack_held := false
var defend_held := false
var touch_mode := false
var blocked := true
var stick_deadzone: float = 0.18
var touch_deadzone: float = 0.12
var trigger_deadzone: float = 0.25
var queued_actions: Array[String] = []
var _keyboard_pressed: Dictionary = {}
var _touch_move := Vector2.ZERO
var _touch_aim := Vector2.ZERO
var _touch_attack := false
var _touch_defend := false
var _mouse_attack := false
var _mouse_defend := false
var _pad_needs_neutral: bool = false

func _ready() -> void:
	initialization_result = bindings.load_file()
	if not initialization_result.ok:
		blocked = true
		diagnostic.emit(initialization_result)
		return
	bindings.changed.connect(_on_bindings_changed)
	initialization_result = bindings.apply(bindings.snapshot())
	_install_device_actions()
	_pad_needs_neutral = false

func _install_device_actions() -> void:
	for action: String in ["attack", "defend"]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action == "attack" else MOUSE_BUTTON_RIGHT
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	var pad := {"dodge": JOY_BUTTON_A, "interact": JOY_BUTTON_X, "heal": JOY_BUTTON_Y, "pulse": JOY_BUTTON_LEFT_SHOULDER, "anchor": JOY_BUTTON_RIGHT_SHOULDER, "pause": JOY_BUTTON_START, "camera_reset": JOY_BUTTON_RIGHT_STICK, "camera_lock": JOY_BUTTON_BACK, "skill_secondary": JOY_BUTTON_DPAD_RIGHT, "character_ability": JOY_BUTTON_DPAD_UP}
	for action: String in pad:
		var event := InputEventJoypadButton.new()
		event.button_index = int(pad[action]) as JoyButton
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)

func configure(parameters: Dictionary) -> Dictionary:
	var candidate := {"stick_deadzone": stick_deadzone, "touch_deadzone": touch_deadzone, "trigger_deadzone": trigger_deadzone}
	for key: Variant in parameters:
		if not key is String or not candidate.has(key):
			return Result.failure("input_configuration_invalid", "输入参数名称无效。")
		var value: Variant = parameters[key]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) >= 0.9:
			return Result.failure("input_configuration_invalid", "死区必须为0至0.9之间的有限数值。")
		candidate[key] = float(value)
	stick_deadzone = candidate.stick_deadzone
	touch_deadzone = candidate.touch_deadzone
	trigger_deadzone = candidate.trigger_deadzone
	release_all()
	return Result.success(candidate)

func _process(_delta: float) -> void:
	if blocked or not bindings.ready:
		_clear_outputs()
		return
	var digital := Vector2(float(_keyboard_pressed.get("move_right", false)) - float(_keyboard_pressed.get("move_left", false)), float(_keyboard_pressed.get("move_back", false)) - float(_keyboard_pressed.get("move_forward", false)))
	movement = digital.limit_length(1.0) + apply_radial_deadzone(_touch_move, touch_deadzone)
	aiming = apply_radial_deadzone(_touch_aim, touch_deadzone)
	attack_held = _touch_attack or _mouse_attack
	defend_held = _touch_defend or _mouse_defend
	var devices := Input.get_connected_joypads()
	if not devices.is_empty():
		var device := int(devices[0])
		var left := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		var right := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		var right_trigger := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
		var left_trigger := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
		if _pad_needs_neutral and left.length() <= stick_deadzone and right.length() <= stick_deadzone and right_trigger <= trigger_deadzone and left_trigger <= trigger_deadzone:
			_pad_needs_neutral = false
		if not _pad_needs_neutral:
			movement += apply_radial_deadzone(left, stick_deadzone)
			var pad_aim := apply_radial_deadzone(right, stick_deadzone)
			if pad_aim != Vector2.ZERO:
				aiming = pad_aim
			attack_held = attack_held or right_trigger > trigger_deadzone
			defend_held = defend_held or left_trigger > trigger_deadzone
	movement = movement.limit_length(1.0)

static func apply_radial_deadzone(value: Vector2, deadzone: float) -> Vector2:
	if not is_finite(value.x) or not is_finite(value.y) or not is_finite(deadzone) or deadzone < 0.0 or deadzone >= 1.0:
		return Vector2.ZERO
	var magnitude := value.length()
	if magnitude <= deadzone:
		return Vector2.ZERO
	return value.normalized() * clampf((minf(magnitude, 1.0) - deadzone) / (1.0 - deadzone), 0.0, 1.0)

func _input(event: InputEvent) -> void:
	if not bindings.ready:
		return
	for action: String in MOVE_ACTIONS:
		if event.is_action_released(action):
			_keyboard_pressed.erase(action)
	if event.is_action_released("attack"):
		_mouse_attack = false
	if event.is_action_released("defend"):
		_mouse_defend = false

func _unhandled_input(event: InputEvent) -> void:
	if not bindings.ready or event.is_echo():
		return
	if event.is_action_pressed("pause"):
		queued_actions.append("pause")
		get_viewport().set_input_as_handled()
		return
	if blocked or event.is_echo():
		return
	for action: String in MOVE_ACTIONS:
		if event.is_action_pressed(action):
			_keyboard_pressed[action] = true
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("attack"):
		_mouse_attack = true
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("defend"):
		_mouse_defend = true
		get_viewport().set_input_as_handled()
		return
	for action: String in COMMAND_ACTIONS:
		if event.is_action_pressed(action):
			queued_actions.append(action)
			get_viewport().set_input_as_handled()
			return

func consume_actions() -> Array[String]:
	var result := queued_actions.duplicate()
	queued_actions.clear()
	return result

func release_all() -> void:
	_keyboard_pressed.clear()
	_touch_move = Vector2.ZERO
	_touch_aim = Vector2.ZERO
	_touch_attack = false
	_touch_defend = false
	_mouse_attack = false
	_mouse_defend = false
	_pad_needs_neutral = true
	queued_actions.clear()
	_clear_outputs()

func _clear_outputs() -> void:
	movement = Vector2.ZERO
	aiming = Vector2.ZERO
	attack_held = false
	defend_held = false

func set_touch_move(value: Vector2) -> void:
	_touch_move = Vector2.ZERO if blocked else value.limit_length(1.0)

func set_touch_aim(value: Vector2, firing: bool) -> void:
	_touch_aim = Vector2.ZERO if blocked else value.limit_length(1.0)
	_touch_attack = firing and not blocked

func set_touch_defense(value: bool) -> void:
	_touch_defend = value and not blocked

func queue_touch(action: String) -> void:
	if action == "pause" or (not blocked and action in COMMAND_ACTIONS):
		queued_actions.append(action)

func snapshot_bindings() -> Dictionary:
	return bindings.snapshot()

func restore_bindings(candidate: Dictionary) -> Dictionary:
	return bindings.restore(candidate)

func set_binding(action: String, key: int) -> Dictionary:
	return bindings.set_binding(action, key)

func _on_bindings_changed(_snapshot: Dictionary) -> void:
	release_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func _exit_tree() -> void:
	if bindings.changed.is_connected(_on_bindings_changed):
		bindings.changed.disconnect(_on_bindings_changed)
	release_all()
