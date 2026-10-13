extends GdUnitTestSuite

const Bindings = preload("res://platform/input_bindings.gd")
const Adapter = preload("res://platform/input_adapter.gd")
var _saved_maps: Dictionary = {}
var _nodes: Array[Node] = []

func before_test() -> void:
	for action: String in Bindings.ACTIONS:
		if InputMap.has_action(action):
			_saved_maps[action] = {"exists": true, "events": InputMap.action_get_events(action), "deadzone": InputMap.action_get_deadzone(action)}
		else:
			_saved_maps[action] = {"exists": false}

func after_test() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			if node.is_inside_tree():
				node.get_parent().remove_child(node)
			node.free()
	_nodes.clear()
	for action: String in ["move_left", "move_right", "move_forward", "move_back"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	for action: String in _saved_maps:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		if _saved_maps[action].exists:
			InputMap.add_action(action, float(_saved_maps[action].deadzone))
			for event: InputEvent in _saved_maps[action].events:
				InputMap.action_add_event(action, event)
	_saved_maps.clear()

func _bindings() -> RefCounted:
	var bindings := Bindings.new()
	assert_bool(bindings.load_file("res://config/input_bindings.json").ok).is_true()
	assert_bool(bindings.apply(bindings.snapshot()).ok).is_true()
	return bindings

func _adapter() -> Node:
	var adapter := Adapter.new()
	_nodes.append(adapter)
	add_child(adapter)
	adapter.blocked = false
	adapter.set_process(false)
	return adapter

func _key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func test_default_file_and_remap_replace_real_keyboard_events() -> void:
	var bindings := _bindings()
	assert_int(bindings.key_for("move_forward")).is_equal(KEY_W)
	assert_bool(_key(KEY_W).is_action_pressed("move_forward")).is_true()
	assert_bool(bindings.set_binding("move_forward", KEY_I).ok).is_true()
	assert_bool(_key(KEY_I).is_action_pressed("move_forward")).is_true()
	assert_bool(_key(KEY_W).is_action_pressed("move_forward")).is_false()
	assert_str(bindings.label_for("move_forward")).is_equal("向前移动")
	assert_str(bindings.key_label("move_forward")).is_equal("I")

func test_conflicts_invalid_keys_navigation_and_required_unbinds_are_rejected() -> void:
	var bindings := _bindings()
	var original: Dictionary = bindings.snapshot()
	var conflict: Dictionary = bindings.preview_remap("pulse", KEY_W)
	assert_bool(conflict.ok).is_false()
	assert_str(conflict.code).is_equal("binding_conflict")
	assert_str(conflict.data.conflict_action).is_equal("move_forward")
	for key: int in [KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_UP, -1, 123456789, 0]:
		assert_bool(bindings.set_binding("pulse", key).ok).is_false()
	assert_bool(bindings.set_binding("pause", KEY_P).ok).is_false()
	assert_bool(bindings.set_binding("unknown_action", KEY_J).ok).is_false()
	assert_dict(bindings.snapshot()).is_equal(original)
	assert_bool(_key(KEY_Q).is_action_pressed("pulse")).is_true()

func test_atomic_full_restore_accepts_swaps_and_rejects_late_invalid_fields() -> void:
	var bindings := _bindings()
	var swap: Dictionary = bindings.snapshot()
	swap.bindings.move_forward = KEY_A
	swap.bindings.move_left = KEY_W
	assert_bool(bindings.restore(swap).ok).is_true()
	assert_bool(_key(KEY_W).is_action_pressed("move_left")).is_true()
	assert_bool(_key(KEY_A).is_action_pressed("move_forward")).is_true()
	var original: Dictionary = bindings.snapshot()
	var invalid := original.duplicate(true)
	invalid.bindings.move_forward = KEY_J
	invalid.bindings.camera_reset = KEY_ENTER
	assert_bool(bindings.restore(invalid).ok).is_false()
	assert_dict(bindings.snapshot()).is_equal(original)
	assert_bool(_key(KEY_A).is_action_pressed("move_forward")).is_true()
	assert_bool(_key(KEY_J).is_action_pressed("move_forward")).is_false()
	invalid = original.duplicate(true)
	invalid.schema_version = Bindings.SCHEMA_VERSION + 1
	assert_bool(bindings.restore(invalid).ok).is_false()

func test_snapshot_schema_rejects_unknown_fields_versions_and_missing_actions_atomically() -> void:
	var bindings := _bindings()
	var original: Dictionary = bindings.snapshot()
	var extra := original.duplicate(true)
	extra.labels = {"move_forward": "unexpected metadata"}
	var future := original.duplicate(true)
	future.schema_version = Bindings.SCHEMA_VERSION + 1
	var fraction := original.duplicate(true)
	fraction.schema_version = 1.5
	var boolean := original.duplicate(true)
	boolean.schema_version = true
	var missing := original.duplicate(true)
	missing.bindings.erase("move_forward")
	var replaced := original.duplicate(true)
	replaced.bindings.erase("move_forward")
	replaced.bindings.unknown_action = KEY_I
	for candidate: Dictionary in [extra, future, fraction, boolean, missing, replaced]:
		assert_bool(bindings.restore(candidate).ok).is_false()
		assert_dict(bindings.snapshot()).is_equal(original)
		assert_bool(_key(KEY_W).is_action_pressed("move_forward")).is_true()
		assert_bool(_key(KEY_I).is_action_pressed("move_forward")).is_false()

func test_remap_preserves_gamepad_mouse_events_and_unrelated_ui_actions() -> void:
	var bindings := _bindings()
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mouse)
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	InputMap.action_add_event("dodge", joy)
	var ui_events: Array[InputEvent] = InputMap.action_get_events("ui_accept")
	assert_bool(bindings.set_binding("attack", KEY_J).ok).is_true()
	assert_bool(bindings.set_binding("dodge", KEY_K).ok).is_true()
	assert_bool(InputMap.action_has_event("attack", mouse)).is_true()
	assert_bool(InputMap.action_has_event("dodge", joy)).is_true()
	assert_array(InputMap.action_get_events("ui_accept")).is_equal(ui_events)
	assert_bool(bindings.set_binding("attack", 0).ok).is_true()
	assert_bool(InputMap.action_has_event("attack", mouse)).is_true()
	assert_bool(_key(KEY_J).is_action_pressed("attack")).is_false()

func test_snapshot_is_detached_and_reset_defaults_applies_to_input_map() -> void:
	var bindings := _bindings()
	var detached: Dictionary = bindings.snapshot()
	detached.bindings.move_forward = KEY_J
	assert_int(bindings.key_for("move_forward")).is_equal(KEY_W)
	bindings.set_binding("move_forward", KEY_I)
	assert_bool(bindings.reset_defaults().ok).is_true()
	assert_int(bindings.key_for("move_forward")).is_equal(KEY_W)
	assert_bool(_key(KEY_W).is_action_pressed("move_forward")).is_true()

func test_radial_deadzone_is_scaled_and_rotation_symmetric() -> void:
	assert_vector(Adapter.apply_radial_deadzone(Vector2(0.1, 0), 0.2)).is_equal(Vector2.ZERO)
	assert_vector(Adapter.apply_radial_deadzone(Vector2(0.6, 0), 0.2)).is_equal_approx(Vector2(0.5, 0), Vector2.ONE * 0.00001)
	var diagonal := Vector2.ONE.normalized() * 0.6
	assert_float(Adapter.apply_radial_deadzone(diagonal, 0.2).length()).is_equal_approx(0.5, 0.00001)
	assert_vector(Adapter.apply_radial_deadzone(Vector2(2, 0), 0.2)).is_equal(Vector2.RIGHT)

func test_focus_release_does_not_resume_movement_from_global_input_poll_or_echo() -> void:
	var adapter := _adapter()
	Input.action_press("move_forward")
	adapter._unhandled_input(_key(KEY_W))
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.UP)
	adapter._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_vector(adapter.movement).is_equal(Vector2.ZERO)
	assert_bool(Input.is_action_pressed("move_forward")).is_true()
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.ZERO)
	adapter._unhandled_input(_key(KEY_W, true, true))
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.ZERO)
	adapter._input(_key(KEY_W, false))
	adapter._unhandled_input(_key(KEY_W))
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.UP)

func test_unhandled_keyboard_movement_release_and_mouse_hold_share_ui_safe_adapter() -> void:
	var adapter := _adapter()
	adapter._unhandled_input(_key(KEY_W))
	adapter._unhandled_input(_key(KEY_D))
	adapter._process(0.016)
	assert_float(adapter.movement.length()).is_equal_approx(1.0, 0.00001)
	adapter._input(_key(KEY_W, false))
	adapter._input(_key(KEY_D, false))
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.ZERO)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	adapter._unhandled_input(mouse)
	adapter._process(0.016)
	assert_bool(adapter.attack_held).is_true()
	mouse.pressed = false
	adapter._input(mouse)
	adapter._process(0.016)
	assert_bool(adapter.attack_held).is_false()

func test_configure_is_atomic_and_remapping_releases_old_held_state() -> void:
	var adapter := _adapter()
	assert_bool(adapter.configure({"stick_deadzone": 0.3, "touch_deadzone": 0.1, "trigger_deadzone": 0.2}).ok).is_true()
	assert_bool(adapter.configure({"stick_deadzone": 0.5, "touch_deadzone": 1.0}).ok).is_false()
	assert_float(adapter.stick_deadzone).is_equal(0.3)
	adapter._unhandled_input(_key(KEY_W))
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.UP)
	assert_bool(adapter.set_binding("move_forward", KEY_I).ok).is_true()
	assert_vector(adapter.movement).is_equal(Vector2.ZERO)
	adapter._unhandled_input(_key(KEY_I))
	adapter._process(0.016)
	assert_vector(adapter.movement).is_equal(Vector2.UP)

func _legacy_snapshot(bindings: RefCounted) -> Dictionary:
	var legacy: Dictionary = bindings.snapshot()
	legacy["schema_version"] = 1
	legacy.bindings.erase("skill_secondary")
	legacy.bindings.erase("character_ability")
	return legacy

func test_legacy_migration_preserves_custom_bindings_without_applying_inputmap() -> void:
	var bindings := _bindings()
	var legacy := _legacy_snapshot(bindings)
	legacy.bindings["move_forward"] = KEY_Z
	var before: Dictionary = bindings.snapshot()
	var migrated: Dictionary = bindings.validate(legacy)
	assert_bool(migrated.ok).is_true()
	assert_int(int(migrated.data.schema_version)).is_equal(2)
	assert_int(int(migrated.data.bindings.move_forward)).is_equal(KEY_Z)
	assert_int(int(migrated.data.bindings.get("skill_secondary", 0))).is_equal(KEY_X)
	assert_int(int(migrated.data.bindings.get("character_ability", 0))).is_equal(KEY_T)
	assert_dict(bindings.snapshot()).is_equal(before)
	assert_bool(_key(KEY_W).is_action_pressed("move_forward")).is_true()
	assert_bool(_key(KEY_Z).is_action_pressed("move_forward")).is_false()
	var second: Dictionary = bindings.validate(migrated.data)
	assert_dict(second.data).is_equal(migrated.data)

func test_legacy_default_collisions_choose_fixed_unused_keys_without_replacing_players_keys() -> void:
	var bindings := _bindings()
	var legacy := _legacy_snapshot(bindings)
	legacy.bindings["move_forward"] = KEY_X
	legacy.bindings["move_back"] = KEY_T
	legacy.bindings["attack"] = KEY_I
	var migrated: Dictionary = bindings.validate(legacy)
	assert_bool(migrated.ok).is_true()
	assert_int(int(migrated.data.bindings.move_forward)).is_equal(KEY_X)
	assert_int(int(migrated.data.bindings.move_back)).is_equal(KEY_T)
	assert_int(int(migrated.data.bindings.attack)).is_equal(KEY_I)
	assert_int(int(migrated.data.bindings.get("skill_secondary", 0))).is_equal(KEY_J)
	assert_int(int(migrated.data.bindings.get("character_ability", 0))).is_equal(KEY_K)

func test_legacy_exhausted_migration_preserves_original_and_actual_input_events() -> void:
	var bindings := _bindings()
	var legacy := _legacy_snapshot(bindings)
	legacy.bindings["move_forward"] = KEY_X
	legacy.bindings["move_back"] = KEY_T
	legacy.bindings["attack"] = KEY_I
	legacy.bindings["defend"] = KEY_J
	legacy.bindings["dodge"] = KEY_K
	legacy.bindings["pulse"] = KEY_L
	var legacy_before := legacy.duplicate(true)
	var live_before: Dictionary = bindings.snapshot()
	var rejected: Dictionary = bindings.restore(legacy)
	assert_bool(rejected.ok).is_false()
	assert_str(rejected.code).is_equal("binding_migration_conflict")
	assert_dict(legacy).is_equal(legacy_before)
	assert_dict(bindings.snapshot()).is_equal(live_before)
	assert_bool(_key(KEY_W).is_action_pressed("move_forward")).is_true()

func test_legacy_snapshot_rejects_partial_new_actions_instead_of_dropping_them() -> void:
	var bindings := _bindings()
	var legacy := _legacy_snapshot(bindings)
	legacy.bindings["skill_secondary"] = KEY_X
	var before: Dictionary = bindings.snapshot()
	assert_str(bindings.validate(legacy).code).is_equal("bindings_actions_invalid")
	assert_dict(bindings.snapshot()).is_equal(before)

func test_new_named_keyboard_touch_and_gamepad_commands_are_consumed_once_and_blocked() -> void:
	var adapter := _adapter()
	adapter._unhandled_input(_key(KEY_X))
	adapter._unhandled_input(_key(KEY_T))
	assert_array(adapter.consume_actions()).is_equal(["skill_secondary", "character_ability"])
	assert_array(adapter.consume_actions()).is_empty()
	adapter._unhandled_input(_key(KEY_X, true, true))
	adapter._unhandled_input(_key(KEY_T, false))
	assert_array(adapter.consume_actions()).is_empty()
	for pair: Array in [["skill_secondary", JOY_BUTTON_DPAD_RIGHT], ["character_ability", JOY_BUTTON_DPAD_UP]]:
		var event := InputEventJoypadButton.new()
		event.button_index = int(pair[1]) as JoyButton
		event.pressed = true
		assert_bool(event.is_action_pressed(str(pair[0]))).is_true()
		adapter._unhandled_input(event)
	assert_array(adapter.consume_actions()).is_equal(["skill_secondary", "character_ability"])
	adapter.queue_touch("skill_secondary")
	adapter.queue_touch("character_ability")
	assert_array(adapter.consume_actions()).is_equal(["skill_secondary", "character_ability"])
	adapter.blocked = true
	adapter.queue_touch("skill_secondary")
	adapter._unhandled_input(_key(KEY_T))
	assert_array(adapter.consume_actions()).is_empty()
	adapter._unhandled_input(_key(KEY_ESCAPE, true, true))
	assert_array(adapter.consume_actions()).is_empty()
	adapter._unhandled_input(_key(KEY_ESCAPE))
	assert_array(adapter.consume_actions()).is_equal(["pause"])

func test_large_future_binding_version_still_reports_future_without_applying() -> void:
	var bindings := _bindings()
	var future: Dictionary = bindings.snapshot()
	future["schema_version"] = 2147483647
	var before: Dictionary = bindings.snapshot()
	assert_str(bindings.validate(future).code).is_equal("future_schema")
	assert_str(Bindings.normalize_snapshot(future).code).is_equal("future_schema")
	assert_dict(bindings.snapshot()).is_equal(before)
