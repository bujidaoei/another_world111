extends GdUnitTestSuite
## Real Main/InputEvent regressions; fixtures and filesystem faults are not PC acceptance.

const Main = preload("res://presentation/main.tscn")
const PROGRESS_IO := '{"code":"io_error","module":"save","operation":"save","version":"0.1.0"}'
const PREFERENCES_IO := '{"code":"io_error","module":"preferences","operation":"save"}'
var _test_root: String
var _session: AWGameSession
var _input_before: Dictionary = {}
var _blockers: Array[String] = []
var _auto_accept_quit: bool

func before_test() -> void:
	get_tree().paused = false
	_auto_accept_quit = get_tree().auto_accept_quit
	_test_root = "user://tests/rebinding_transition/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_input_before.clear()
	_blockers.clear()
	for action: StringName in InputMap.get_actions():
		_input_before[action] = {"events": InputMap.action_get_events(action), "deadzone": InputMap.action_get_deadzone(action)}

func after_test() -> void:
	get_tree().paused = false
	if is_instance_valid(_session):
		remove_child(_session)
		_session.free()
	_session = null
	for action: StringName in InputMap.get_actions(): InputMap.erase_action(action)
	for action: StringName in _input_before:
		InputMap.add_action(action, float(_input_before[action].deadzone))
		for event: InputEvent in _input_before[action].events: InputMap.action_add_event(action, event)
	get_tree().auto_accept_quit = _auto_accept_quit
	await get_tree().process_frame
	for path: String in _blockers: _remove_empty_blocker(path)
	var base := ProjectSettings.globalize_path(_test_root).simplify_path()
	for suffix: String in ["main/preferences", "main", ""]: _cleanup_leaf(base.path_join(suffix))

func _safe_path(path: String) -> bool:
	var allowed := ProjectSettings.globalize_path("user://tests/rebinding_transition").simplify_path()
	return path.simplify_path().begins_with(allowed + "/")

func _remove_empty_blocker(path: String) -> void:
	assert_bool(_safe_path(path)).is_true()
	if not _safe_path(path) or not DirAccess.dir_exists_absolute(path): return
	var parent := DirAccess.open(path.get_base_dir())
	assert_bool(parent.is_link(path)).is_false()
	if parent.is_link(path): return
	var directory := DirAccess.open(path)
	assert_array(directory.get_files()).is_empty()
	assert_array(directory.get_directories()).is_empty()
	if directory.get_files().is_empty() and directory.get_directories().is_empty():
		assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func _cleanup_leaf(path: String) -> void:
	assert_bool(_safe_path(path)).is_true()
	if not _safe_path(path) or not DirAccess.dir_exists_absolute(path): return
	var parent := DirAccess.open(path.get_base_dir())
	assert_bool(parent.is_link(path)).is_false()
	if parent.is_link(path): return
	var directory := DirAccess.open(path)
	assert_array(directory.get_directories()).is_empty()
	if not directory.get_directories().is_empty(): return
	for name: String in directory.get_files(): assert_int(DirAccess.remove_absolute(path.path_join(name))).is_equal(OK)
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func _new_session() -> AWGameSession:
	_session = Main.instantiate() as AWGameSession
	_session.save_directory = _test_root.path_join("main")
	add_child(_session)
	_session.set_process(false)
	assert_bool(_session._fatal_failure).is_false()
	if _session._fatal_failure: return null
	_session.player.set_physics_process(false)
	_session._on_command("new_game")
	assert_bool(_session.session_started).is_true()
	return _session

func _block_next_write(directory: String, sequence: int) -> String:
	var path := ProjectSettings.globalize_path(directory).simplify_path().path_join("slot_b.json.tmp" if sequence % 2 == 1 else "slot_a.json.tmp")
	assert_bool(_safe_path(path)).is_true()
	if not _safe_path(path): return ""
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_bool(DirAccess.dir_exists_absolute(path)).is_false()
	assert_int(DirAccess.make_dir_absolute(path)).is_equal(OK)
	_blockers.append(path)
	return path

func _settle_gui() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _key(code: Key, unicode: int = 0, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.unicode = unicode
	event.ctrl_pressed = ctrl
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func _button(label: String) -> Button:
	for child: Node in _session.hud._modal_content.get_children():
		if child is Button and label in child.text: return child
	assert_bool(false).override_failure_message("Missing actual menu button: " + label).is_true()
	return null

func _capture_then_failed_quit() -> AWGameSession:
	var session := _new_session()
	if session == null: return null
	session._on_command("settings")
	session._on_command("bindings")
	session._on_command("bind:move_forward")
	var baseline: Dictionary = session.repository.load()
	assert_bool(baseline.ok).is_true()
	_block_next_write(session.save_directory, int(baseline.sequence))
	await assert_error(func() -> void: session._request_quit()).is_push_error(PROGRESS_IO)
	assert_str(session._pending_persistence_action).is_equal("quit")
	assert_str(session._modal_mode).is_equal("save_failure")
	return session

func test_failed_quit_layer_receives_navigation_and_enter_before_rebinding_capture() -> void:
	var session: AWGameSession = await _capture_then_failed_quit()
	if session == null: return
	var bindings := session.input_adapter.snapshot_bindings()
	var cancel := _button("取消")
	var discard := _button("明确放弃")
	var retry := _button("重试")
	if cancel == null or discard == null or retry == null: return
	retry.grab_focus()
	await _settle_gui()
	_key(KEY_TAB)
	await _settle_gui()
	assert_object(get_viewport().gui_get_focus_owner()).is_same(discard)
	cancel.grab_focus()
	await _settle_gui()
	_key(KEY_ENTER)
	await _settle_gui()
	assert_str(session._pending_persistence_action).is_empty()
	assert_str(session._modal_mode).is_equal("settings")
	assert_str(session._binding_action).is_equal("move_forward")
	assert_dict(session.input_adapter.snapshot_bindings()).is_equal(bindings)
	assert_array(session.hud._modal_layers).is_empty()
	assert_bool(session._quitting).is_false()

func test_failed_quit_escape_restores_capture_content_without_replacing_failure_layer() -> void:
	var session := _new_session()
	if session == null: return
	session._on_command("settings")
	session._on_command("bindings")
	session._on_command("bind:move_forward")
	var original_content := session.hud._modal_content
	var baseline: Dictionary = session.repository.load()
	_block_next_write(session.save_directory, int(baseline.sequence))
	await assert_error(func() -> void: session._request_quit()).is_push_error(PROGRESS_IO)
	await _settle_gui()
	_key(KEY_ESCAPE)
	session._process(0.0) # Consume only the real input adapter's queued pause intent.
	await _settle_gui()
	assert_str(session._pending_persistence_action).is_empty()
	assert_object(session.hud._modal_content).is_same(original_content)
	assert_str(session._binding_action).is_equal("move_forward")
	assert_str(session._modal_mode).is_equal("settings")
	assert_array(session.hud._modal_layers).is_empty()

func test_normal_main_build_preset_text_and_talent_submission_reach_native_controls() -> void:
	var session := _new_session()
	if session == null: return
	session._on_command("builds")
	assert_bool(session.build_controller.show("presets").ok).is_true()
	var field := session.hud.find_child("PresetName_0", true, false) as LineEdit
	assert_object(field).is_not_null()
	if field == null: return
	field.grab_focus()
	await _settle_gui()
	_key(KEY_A, 0, true)
	_key(KEY_Q, 81)
	_key(KEY_7, 55)
	await _settle_gui()
	assert_str(field.text).is_equal("Q7")
	assert_str(session._binding_action).is_empty()
	assert_array(session.input_adapter.queued_actions).is_empty()
	assert_bool(session.build_controller.show("talents").ok).is_true()
	var rank := session.hud.find_child("Talent_vitality", true, false) as SpinBox
	assert_object(rank).is_not_null()
	if rank == null: return
	rank.get_line_edit().grab_focus()
	await _settle_gui()
	rank.get_line_edit().select_all()
	_key(KEY_7, 55)
	await _settle_gui()
	assert_str(rank.get_line_edit().text).is_equal("7")
	assert_int(int(session.roster.profile("thief").draft.talents.vitality)).is_equal(0)
	_key(KEY_ENTER)
	await _settle_gui()
	assert_int(int(session.roster.profile("thief").draft.talents.vitality)).is_equal(7)
	assert_int(int(session.roster.active_build().talents.vitality)).is_equal(0)
	assert_array(session.input_adapter.queued_actions).is_empty()

func test_synthetic_pad_pause_cancels_capture_before_gameplay_or_next_menu() -> void:
	var session := _new_session()
	if session == null: return
	session._on_command("settings")
	session._on_command("bindings")
	session._on_command("bind:move_forward")
	var bindings := session.input_adapter.snapshot_bindings()
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_START
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	session._process(0.0)
	assert_bool(session.hud.modal.visible).is_false()
	assert_str(session._binding_action).is_empty()
	session._on_command("builds")
	assert_bool(session.build_controller.show("presets").ok).is_true()
	var field := session.hud.find_child("PresetName_0", true, false) as LineEdit
	assert_object(field).is_not_null()
	if field == null: return
	field.grab_focus()
	await _settle_gui()
	_key(KEY_A, 0, true)
	_key(KEY_X, 88)
	await _settle_gui()
	assert_dict(session.input_adapter.snapshot_bindings()).is_equal(bindings)
	assert_bool(is_instance_valid(field)).is_true()
	if is_instance_valid(field): assert_str(field.text).is_equal("X")

func test_failed_rebind_preferences_remain_dirty_block_title_and_retry_real_write() -> void:
	await _verify_preferences_failure(false)

func test_failed_reset_preferences_remain_dirty_block_title_and_retry_real_write() -> void:
	await _verify_preferences_failure(true)

func _verify_preferences_failure(reset: bool) -> void:
	var session := _new_session()
	if session == null: return
	if reset: assert_bool(session.input_adapter.set_binding("move_forward", KEY_F8).ok).is_true()
	assert_bool(session.preferences.save(session.settings, session.input_adapter.snapshot_bindings()).ok).is_true()
	var baseline: Dictionary = session.preferences.load()
	var blocker := _block_next_write(session.save_directory.path_join("preferences"), int(baseline.sequence))
	if reset:
		await assert_error(func() -> void: session._on_command("bindings_reset")).is_push_error(PREFERENCES_IO)
	else:
		session._on_command("settings")
		session._on_command("bindings")
		session._on_command("bind:move_forward")
		await assert_error(func() -> void: _key(KEY_F8)).is_push_error(PREFERENCES_IO)
	assert_bool(session._preferences_dirty).is_true()
	assert_bool(session._preferences_write_failed).is_true()
	var expected_bindings := session.input_adapter.snapshot_bindings()
	assert_int(session.input_adapter.bindings.key_for("move_forward")).is_equal(KEY_W if reset else KEY_F8)
	await assert_error(func() -> void: session._on_command("title")).is_push_error(PREFERENCES_IO)
	assert_bool(session.session_started).is_true()
	assert_str(session._pending_persistence_action).is_equal("title")
	assert_bool(session._preferences_dirty).is_true()
	if session._pending_persistence_action.is_empty(): return
	_remove_empty_blocker(blocker)
	var retry := _button("重试")
	if retry == null: return
	retry.grab_focus()
	await _settle_gui()
	_key(KEY_ENTER)
	await _settle_gui()
	assert_bool(session.session_started).is_false()
	assert_str(session._pending_persistence_action).is_empty()
	assert_bool(session._preferences_dirty).is_false()
	assert_dict(session.preferences.load().data.input_bindings).is_equal(expected_bindings)
