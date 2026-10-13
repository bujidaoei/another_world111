extends GdUnitTestSuite
## Real filesystem fault integration; exit probes run in separate headless processes.

const Main = preload("res://presentation/main.tscn")
const Bindings = preload("res://platform/input_bindings.gd")
const PROGRESS_IO_DIAGNOSTIC := '{"code":"io_error","module":"save","operation":"save","version":"0.1.0"}'
const PREFERENCES_IO_DIAGNOSTIC := '{"code":"io_error","module":"preferences","operation":"save"}'
const PROGRESS_FUTURE_DIAGNOSTIC := '{"code":"future_schema","module":"save","operation":"save","version":"0.1.0"}'
const EXIT_PROBE := """
extends SceneTree
const Main = preload("res://presentation/main.tscn")
var session: AWGameSession
var observed: Dictionary = {}
var root_path: String
var result_path: String
var blocker: String
var mode: String
func _initialize() -> void:
	_run.call_deferred()
func _slots(path: String) -> Dictionary:
	var hashes := {}
	for name: String in ["slot_a.json", "slot_b.json"]:
		var full := path.path_join(name)
		hashes[name] = {"exists": FileAccess.file_exists(full), "sha256": FileAccess.get_sha256(full) if FileAccess.file_exists(full) else ""}
	return hashes
func _write() -> void:
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(observed))
		file.close()
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	root_path = args[0]
	result_path = args[1]
	mode = args[2]
	var allowed := ProjectSettings.globalize_path("user://tests/session_persistence").simplify_path()
	if not root_path.begins_with(allowed + "/"):
		quit(90)
		return
	session = Main.instantiate() as AWGameSession
	session.save_directory = root_path.path_join("main")
	root.add_child(session)
	session.set_process(false)
	if session._fatal_failure:
		observed["startup_failed"] = true
		_write()
		quit(91)
		return
	session.player.set_physics_process(false)
	session._on_command("new_game")
	var baseline: Dictionary = session.preferences.save(session.settings, session.input_adapter.snapshot_bindings())
	if not baseline.ok:
		observed["baseline_failed"] = baseline
		_write()
		quit(92)
		return
	var fault_path := session.save_directory if mode == "progress" else session.save_directory.path_join("preferences")
	var repository: RefCounted = session.repository if mode == "progress" else session.preferences._repository
	var prior: Dictionary = repository.load()
	blocker = ProjectSettings.globalize_path(fault_path).path_join("slot_b.json.tmp" if int(prior.sequence) % 2 == 1 else "slot_a.json.tmp")
	if not blocker.begins_with(root_path + "/") or FileAccess.file_exists(blocker) or DirAccess.dir_exists_absolute(blocker):
		quit(93)
		return
	if DirAccess.make_dir_absolute(blocker) != OK:
		quit(94)
		return
	observed["baseline_slots"] = _slots(fault_path)
	observed["original_mode"] = session._modal_mode
	observed["original_paused"] = paused
	observed["original_modal_visible"] = session.hud.modal.visible
	if mode == "preferences": session._on_setting("master_volume", 0.25)
	else: session.player.health *= 0.4
	var commands: Array[String] = []
	session.hud.command.connect(func(action: String) -> void: commands.append(action))
	session._request_quit()
	observed["quitting_after_request"] = session._quitting
	observed["dirty_after_request"] = session._preferences_dirty
	observed["slots_after_request"] = _slots(fault_path)
	observed["modal_visible_after_request"] = session.hud.modal.visible
	var buttons: Array[String] = []
	for node: Node in session.hud._modal_content.get_children():
		if node is Button: buttons.append(node.text)
	observed["buttons_after_request"] = buttons
	_write()
	await create_timer(0.4, true, false, true).timeout
	observed["survived_failed_quit"] = true
	for node: Node in session.hud._modal_content.get_children():
		if node is Button and "取消" in node.text:
			node.pressed.emit()
			break
	observed["cancel_commands"] = commands.duplicate()
	observed["mode_after_cancel"] = session._modal_mode
	observed["paused_after_cancel"] = paused
	observed["quitting_after_cancel"] = session._quitting
	observed["dirty_after_cancel"] = session._preferences_dirty
	var blocked_directory := DirAccess.open(blocker)
	if blocked_directory == null or not blocked_directory.get_files().is_empty() or not blocked_directory.get_directories().is_empty():
		quit(95)
		return
	if DirAccess.remove_absolute(blocker) != OK:
		quit(96)
		return
	var retry: Variant = session.call("_save_progress", false) if mode == "progress" else session.call("_save_preferences")
	observed["retry_result"] = retry
	observed["dirty_after_retry"] = session._preferences_dirty
	observed["slots_after_retry"] = _slots(fault_path)
	observed["completed"] = true
	_write()
	# Only the isolated child now exercises successful production shutdown,
	# including AudioServer playback retirement. The parent runner remains alive.
	session._request_quit()
	observed["final_production_quitting_started"] = session._quitting
	_write()
"""

var _test_root: String
var _session: AWGameSession
var _input_before: Dictionary = {}
var _blockers: Array[String] = []
var _auto_accept_quit: bool

func before_test() -> void:
	get_tree().paused = false
	_auto_accept_quit = get_tree().auto_accept_quit
	_test_root = "user://tests/session_persistence/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_input_before.clear()
	_blockers.clear()
	for action: String in Bindings.ACTIONS:
		_input_before[action] = {"exists": InputMap.has_action(action)}
		if InputMap.has_action(action):
			_input_before[action]["events"] = InputMap.action_get_events(action)
			_input_before[action]["deadzone"] = InputMap.action_get_deadzone(action)

func after_test() -> void:
	get_tree().paused = false
	if is_instance_valid(_session):
		_session.get_parent().remove_child(_session)
		_session.free()
	_session = null
	for action: String in _input_before:
		if InputMap.has_action(action): InputMap.erase_action(action)
		if _input_before[action].exists:
			InputMap.add_action(action, float(_input_before[action].deadzone))
			for event: InputEvent in _input_before[action].events: InputMap.action_add_event(action, event)
	get_tree().auto_accept_quit = _auto_accept_quit
	await get_tree().process_frame
	for path: String in _blockers: _remove_empty_blocker(path)
	var base := ProjectSettings.globalize_path(_test_root).simplify_path()
	for child: String in ["main/preferences", "main", "probe-progress/main/preferences", "probe-progress/main", "probe-progress", "probe-preferences/main/preferences", "probe-preferences/main", "probe-preferences"]:
		_cleanup_leaf(base.path_join(child))
	_cleanup_leaf(base)

func _safe_path(path: String) -> bool:
	var allowed := ProjectSettings.globalize_path("user://tests/session_persistence").simplify_path()
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

func _slots(directory: String) -> Dictionary:
	var slots: Dictionary = {}
	for name: String in ["slot_a.json", "slot_b.json"]:
		var path := directory.path_join(name)
		slots[name] = {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return slots

func _block_next_write(directory: String, sequence: int) -> String:
	var path := ProjectSettings.globalize_path(directory).simplify_path().path_join("slot_b.json.tmp" if sequence % 2 == 1 else "slot_a.json.tmp")
	assert_bool(_safe_path(path)).is_true()
	if not _safe_path(path): return ""
	assert_bool(FileAccess.file_exists(path)).is_false()
	assert_bool(DirAccess.dir_exists_absolute(path)).is_false()
	assert_int(DirAccess.make_dir_absolute(path)).is_equal(OK)
	_blockers.append(path)
	return path

func _assert_result(result: Variant, expected_ok: bool, code: String = "") -> void:
	assert_bool(result is Dictionary).is_true()
	if not result is Dictionary: return
	assert_bool(result.get("ok", not expected_ok)).is_equal(expected_ok)
	if not code.is_empty(): assert_str(str(result.get("code", ""))).is_equal(code)

func test_real_progress_write_failure_preserves_slots_and_returns_result_then_retry_succeeds() -> void:
	var session := _new_session()
	if session == null: return
	var baseline: Dictionary = session.repository.load()
	assert_bool(baseline.ok).is_true()
	var original := _slots(session.save_directory)
	var blocker := _block_next_write(session.save_directory, int(baseline.sequence))
	session.player.health *= 0.4 # Explicit injury fixture; persist the real current value.
	var captured := {"result": null}
	await assert_error(func() -> void: captured["result"] = session.call("_save_progress", false)).is_push_error(PROGRESS_IO_DIAGNOSTIC)
	_assert_result(captured.result, false, "io_error")
	assert_dict(_slots(session.save_directory)).is_equal(original)
	assert_bool("失败" in session.hud.notice.text).is_true()
	_remove_empty_blocker(blocker)
	var retry: Variant = session.call("_save_progress", false)
	_assert_result(retry, true)
	var saved: Dictionary = session.repository.load()
	assert_bool(saved.ok).is_true()
	assert_int(int(saved.sequence)).is_equal(int(baseline.sequence) + 1)
	assert_float(float(saved.data.health)).is_equal(session.player.health)

func test_real_preferences_write_failure_keeps_dirty_and_original_slots_then_retry_succeeds() -> void:
	var session := _new_session()
	if session == null: return
	assert_bool(session.preferences.save(session.settings, session.input_adapter.snapshot_bindings()).ok).is_true()
	var directory := session.save_directory.path_join("preferences")
	var baseline: Dictionary = session.preferences.load()
	var original := _slots(directory)
	var blocker := _block_next_write(directory, int(baseline.sequence))
	session._on_setting("master_volume", 0.25)
	assert_bool(session._preferences_dirty).is_true()
	var captured := {"result": null}
	await assert_error(func() -> void: captured["result"] = session.call("_save_preferences")).is_push_error(PREFERENCES_IO_DIAGNOSTIC)
	_assert_result(captured.result, false, "io_error")
	assert_bool(session._preferences_dirty).is_true()
	assert_dict(_slots(directory)).is_equal(original)
	_remove_empty_blocker(blocker)
	var retry: Variant = session.call("_save_preferences")
	_assert_result(retry, true)
	assert_bool(session._preferences_dirty).is_false()
	var saved: Dictionary = session.preferences.load()
	assert_bool(saved.ok).is_true()
	assert_float(float(saved.data.settings.master_volume)).is_equal(0.25)
	assert_int(int(saved.sequence)).is_equal(int(baseline.sequence) + 1)

func test_already_running_session_preserves_external_future_domain_slot_on_next_save() -> void:
	var session := _new_session()
	if session == null: return
	var existing: Dictionary = session.repository.load()
	var future: Dictionary = existing.data.duplicate(true)
	future["domain_version"] = 3
	future["future_system"] = {"must_survive": true}
	assert_bool(session.repository.save(future).ok).is_true()
	var original := _slots(session.save_directory)
	var captured := {"result": null}
	await assert_error(func() -> void: captured["result"] = session.call("_save_progress", false)).is_push_error(PROGRESS_FUTURE_DIAGNOSTIC)
	_assert_result(captured.result, false, "future_schema")
	assert_dict(_slots(session.save_directory)).is_equal(original)
	assert_bool(session.save_blocked).is_true()

func test_title_save_failure_keeps_session_and_dirty_until_cancel_then_real_retry() -> void:
	var session := _new_session()
	if session == null: return
	assert_bool(session.preferences.save(session.settings, session.input_adapter.snapshot_bindings()).ok).is_true()
	var baseline: Dictionary = session.repository.load()
	var original := _slots(session.save_directory)
	var blocker := _block_next_write(session.save_directory, int(baseline.sequence))
	var preference_baseline: Dictionary = session.preferences.load()
	var preference_directory := session.save_directory.path_join("preferences")
	var preference_original := _slots(preference_directory)
	var preference_blocker := _block_next_write(preference_directory, int(preference_baseline.sequence))
	session.player.health *= 0.4
	session._on_setting("master_volume", 0.25)
	var inventory: Dictionary = session.inventory.snapshot()
	var roster: Dictionary = session.roster.snapshot()
	var health := session.player.health
	await _expect_title_failure_once(session)
	assert_bool(session.session_started).is_true()
	assert_bool(session._quitting).is_false()
	assert_bool(session._preferences_dirty).is_true()
	assert_float(session.player.health).is_equal(health)
	assert_dict(session.inventory.snapshot()).is_equal(inventory)
	assert_dict(session.roster.snapshot()).is_equal(roster)
	assert_dict(_slots(session.save_directory)).is_equal(original)
	assert_dict(_slots(preference_directory)).is_equal(preference_original)
	assert_bool(session.hud.modal.visible).is_true()
	var cancel := _menu_button(session, "取消")
	if cancel == null: return
	cancel.pressed.emit()
	assert_bool(session.session_started).is_true()
	assert_str(session._modal_mode).is_equal("camp")
	assert_bool(get_tree().paused).is_false()
	assert_bool(session._preferences_dirty).is_true()
	await _expect_title_failure_once(session)
	assert_bool(session.session_started).is_true()
	assert_bool(session._preferences_dirty).is_true()
	_remove_empty_blocker(blocker)
	_remove_empty_blocker(preference_blocker)
	var retry := _menu_button(session, "重试")
	if retry == null: return
	# The actual button sends retry_title, preserving the pending transition intent.
	await assert_error(func() -> void: retry.pressed.emit()).is_success()
	assert_bool(session.session_started).is_false()
	assert_str(session._modal_mode).is_equal("title")
	assert_bool(get_tree().paused).is_true()
	assert_bool(session._preferences_dirty).is_false()
	assert_array(session.hud._modal_layers).is_empty()
	var saved: Dictionary = session.repository.load()
	assert_float(float(saved.data.health)).is_equal(health)
	assert_int(int(saved.sequence)).is_equal(int(baseline.sequence) + 1)
	assert_float(float(session.preferences.load().data.settings.master_volume)).is_equal(0.25)

func _menu_button(session: AWGameSession, label: String) -> Button:
	for child: Node in session.hud._modal_content.get_children():
		if child is Button and label in child.text: return child
	assert_bool(false).override_failure_message("Missing actual menu button: " + label).is_true()
	return null

func _expect_title_failure_once(session: AWGameSession) -> void:
	var invocation := {"executed": false}
	var once := func() -> void:
		if invocation.executed: return
		invocation["executed"] = true
		session._on_command("title")
	# One production call produces two real diagnostics. Reuse the official logger
	# to assert each entry without executing the write operation a second time.
	var expectation := assert_error(once)
	await expectation.is_push_error(PREFERENCES_IO_DIAGNOSTIC)
	await expectation.is_push_error(PROGRESS_IO_DIAGNOSTIC)

func test_cancel_failed_quit_restores_pending_settlement_menu_without_committing_rewards() -> void:
	var session := _new_session()
	if session == null: return
	session._begin_run("rain_court", false)
	for child: Node in session.enemy_root.get_children():
		(child as AWEnemyController).set_physics_process(false)
	# Finite full-storage fixture. Pending resources are earned by a real registered interaction.
	assert_bool(session.inventory.grant({"scrap": int(session.rules.data.inventory.maximum_quantity)}, "unit-full-scrap-storage").ok).is_true()
	session.player.global_position = session.world.resource_positions["rain_scrap_01"]
	session._interact()
	assert_bool(session.expedition.gathered_node_ids.has("rain_scrap_01")).is_true()
	assert_int(int(session.expedition.pending_loot.scrap)).is_equal(3)
	session._finish_run("evacuated")
	assert_str(session._modal_mode).is_equal("settlement")
	assert_bool(session.player.active).is_false()
	assert_bool(session.expedition.rewards_committed).is_false()
	var original_content := session.hud._modal_content
	var original_retry := _menu_button(session, "重试入库")
	var original_abandon := _menu_button(session, "放弃未入库战利品")
	if original_retry == null or original_abandon == null: return
	var run: Dictionary = session.expedition.snapshot()
	var inventory: Dictionary = session.inventory.snapshot()
	var baseline: Dictionary = session.repository.load()
	var slots := _slots(session.save_directory)
	_block_next_write(session.save_directory, int(baseline.sequence))
	await assert_error(func() -> void: session._request_quit()).is_push_error(PROGRESS_IO_DIAGNOSTIC)
	assert_bool(session._quitting).is_false()
	var cancel := _menu_button(session, "取消")
	if cancel == null: return
	cancel.pressed.emit()
	assert_str(session._modal_mode).is_equal("settlement")
	assert_bool(session.player.active).is_false()
	assert_bool(session.hud.modal.visible).is_true()
	assert_bool(get_tree().paused).is_false()
	assert_object(session.hud._modal_content).is_same(original_content)
	assert_object(_menu_button(session, "重试入库")).is_same(original_retry)
	assert_object(_menu_button(session, "放弃未入库战利品")).is_same(original_abandon)
	assert_array(session.hud._modal_layers).is_empty()
	var labels: Array[String] = []
	for child: Node in session.hud._modal_content.get_children():
		if child is Button: labels.append(child.text)
	assert_array(labels).contains("重试入库")
	assert_array(labels).contains("放弃未入库战利品并回营")
	assert_dict(session.expedition.snapshot()).is_equal(run)
	assert_dict(session.inventory.snapshot()).is_equal(inventory)
	assert_dict(_slots(session.save_directory)).is_equal(slots)

func test_cancel_failed_quit_preserves_unsubmitted_preset_text_focus_scroll_and_control_identity() -> void:
	var session := _new_session()
	if session == null: return
	session._show_builds()
	assert_bool(session.build_controller.show("presets").ok).is_true()
	for frame: int in range(2): await get_tree().process_frame
	var field := session.hud.find_child("PresetName_2", true, false) as LineEdit
	assert_object(field).is_not_null()
	if field == null: return
	field.grab_focus()
	for frame: int in range(2): await get_tree().process_frame
	field.select_all()
	var event := InputEventKey.new()
	event.keycode = KEY_7
	event.physical_keycode = KEY_7
	event.unicode = 55
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
	for frame: int in range(2): await get_tree().process_frame
	assert_str(field.text).is_equal("7")
	session.hud._modal_scroll.scroll_vertical = 200
	for frame: int in range(2): await get_tree().process_frame
	var original_scroll := session.hud._modal_scroll.scroll_vertical
	assert_int(original_scroll).is_greater(0)
	var original_content := session.hud._modal_content
	var original_field_id := field.get_instance_id()
	var original_roster: Dictionary = session.roster.snapshot()
	assert_str(session.roster.profile("thief").presets[2].name).is_equal("")
	var baseline: Dictionary = session.repository.load()
	_block_next_write(session.save_directory, int(baseline.sequence))
	await assert_error(func() -> void: session._request_quit()).is_push_error(PROGRESS_IO_DIAGNOSTIC)
	assert_bool(session._quitting).is_false()
	assert_int(session.hud._modal_layers.size()).is_equal(1)
	var cancel := _menu_button(session, "取消")
	if cancel == null: return
	cancel.pressed.emit()
	for frame: int in range(2): await get_tree().process_frame
	assert_str(session._modal_mode).is_equal("build")
	assert_str(session.build_controller.view.section).is_equal("presets")
	assert_object(session.hud._modal_content).is_same(original_content)
	assert_int(field.get_instance_id()).is_equal(original_field_id)
	assert_str(field.text).is_equal("7")
	assert_object(get_viewport().gui_get_focus_owner()).is_same(field)
	assert_int(session.hud._modal_scroll.scroll_vertical).is_equal(original_scroll)
	assert_dict(session.roster.snapshot()).is_equal(original_roster)
	assert_array(session.hud._modal_layers).is_empty()

@warning_ignore("unused_parameter")
func test_failed_quit_survives_real_write_fault_and_cancel_restores_menu_in_child_process(timeout := 20000) -> void:
	for mode: String in ["progress", "preferences"]:
		var base := ProjectSettings.globalize_path(_test_root.path_join("probe-" + mode)).simplify_path()
		assert_bool(_safe_path(base)).is_true()
		assert_int(DirAccess.make_dir_recursive_absolute(base)).is_equal(OK)
		var script_path := base.path_join("exit_probe.gd")
		var observation_path := base.path_join("observation.json")
		var file := FileAccess.open(script_path, FileAccess.WRITE)
		assert_object(file).is_not_null()
		if file == null: return
		file.store_string(EXIT_PROBE)
		file.close()
		var output: Array = []
		var code := OS.execute(OS.get_executable_path(), ["--headless", "--verbose", "--path", ProjectSettings.globalize_path("res://"), "--script", script_path, "--", base, observation_path, mode], output, true)
		var log: String = "\n".join(output)
		var artifact_path := ProjectSettings.globalize_path("res://../artifacts/session-persistence-probes").path_join(_test_root.get_file() + "-" + mode)
		assert_int(DirAccess.make_dir_recursive_absolute(artifact_path)).is_equal(OK)
		file = FileAccess.open(artifact_path.path_join("child.log"), FileAccess.WRITE)
		file.store_string(log)
		file.close()
		assert_int(code).is_equal(0)
		assert_bool("SCRIPT ERROR:" in log).is_false()
		var error_headers: Array[String] = []
		for line: String in log.split("\n"):
			if line.begins_with("ERROR:"): error_headers.append(line.strip_edges())
		var expected_header := "ERROR: " + (PROGRESS_IO_DIAGNOSTIC if mode == "progress" else PREFERENCES_IO_DIAGNOSTIC)
		assert_array(error_headers).contains_exactly([expected_header])
		assert_bool(("_save_progress (res://presentation/game_session.gd:" if mode == "progress" else "_save_preferences (res://presentation/game_session.gd:") in log).is_true()
		assert_bool("exit_probe.gd:" in log).is_true()
		for unexpected: String in ["leaked", "rid allocations", "resources still in use"]:
			assert_bool(unexpected in log.to_lower()).is_false()
		assert_bool(FileAccess.file_exists(observation_path)).is_true()
		if not FileAccess.file_exists(observation_path): return
		var observed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(observation_path))
		file = FileAccess.open(artifact_path.path_join("observation.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(observed, "\t"))
		file.close()
		assert_bool(observed.get("startup_failed", false)).is_false()
		assert_bool(observed.get("quitting_after_request", true)).is_false()
		assert_dict(observed.slots_after_request).is_equal(observed.baseline_slots)
		assert_bool(observed.get("modal_visible_after_request", false)).is_true()
		var buttons: String = "|".join(observed.buttons_after_request)
		for label: String in ["重试", "放弃", "取消"]: assert_bool(label in buttons).is_true()
		if mode == "preferences": assert_bool(observed.get("dirty_after_request", false)).is_true()
		assert_bool(observed.get("survived_failed_quit", false)).is_true()
		assert_bool(observed.get("completed", false)).is_true()
		if not observed.get("completed", false):
			# Old production quit has already ended only this child; retain its failure evidence.
			_blockers.append(base.path_join("main" if mode == "progress" else "main/preferences").path_join("slot_b.json.tmp"))
			continue
		assert_array(observed.cancel_commands).contains("cancel_quit")
		assert_bool(observed.get("final_production_quitting_started", false)).is_true()
		assert_str(observed.mode_after_cancel).is_equal(observed.original_mode)
		assert_bool(observed.paused_after_cancel).is_equal(observed.original_paused)
		assert_bool(observed.quitting_after_cancel).is_false()
		_assert_result(observed.retry_result, true)
		if mode == "preferences":
			assert_bool(observed.dirty_after_cancel).is_true()
			assert_bool(observed.dirty_after_retry).is_false()
