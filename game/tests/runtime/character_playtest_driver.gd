extends Node
## Developer-only QA: domain data is observed, every player/menu command is an InputEvent.

class ExpeditionPilot:
	extends "res://tests/runtime/input_playtest_driver.gd"
	var pointer := Vector2.ZERO
	var click_handler: Callable
	func _process(delta: float) -> void:
		if stage in ["new", "confirm_new", "continue"]:
			elapsed += delta
			_stage_clock += delta
			_clock += delta
			if _clock < 0.1: return
			_clock = 0.0
			if stage == "new" and _click("开始新旅程"): _next("confirm_new")
			elif stage == "confirm_new":
				if session.session_started: _next("camp")
				else: _click("明确开始新旅程")
			elif stage == "continue":
				if session.session_started: _next("camp")
				else: _click("继续旅程")
			return
		if stage != "return":
			super._process(delta)
			return
		elapsed += delta
		_clock += delta
		_stage_clock += delta
		if _clock < 0.1: return
		_clock = 0.0
		if session.in_camp:
			completed_runs += 1
			_log("settled", _snapshot())
			_next("camp")
		elif _move_to(session.world.exit_position, 1.6):
			_press(session.input_adapter.bindings.key_for("interact"))
	func _log(event: String, data: Dictionary) -> void:
		results.append({"at_seconds": elapsed, "event": event, "data": data.duplicate(true)})
	func _combat() -> void:
		if session.in_camp:
			_fail("Real-input expedition failed")
			return
		var nearest: AWEnemyController
		var best := INF
		for child: Node in session.enemy_root.get_children():
			if child is AWEnemyController and child.active:
				var distance := session.player.global_position.distance_to(child.global_position)
				if distance < best:
					best = distance
					nearest = child
		if nearest == null:
			_release()
			_log("all_enemies_defeated", _snapshot())
			_gather_index = 0
			_next("gather")
			return
		_aim_at(nearest.global_position + Vector3.UP * 0.8)
		_mouse(MOUSE_BUTTON_LEFT, true)
		var away := session.player.global_position - nearest.global_position
		away.y = 0
		if best < 4.5:
			var goal := session.player.global_position + away.normalized() * 3.0
			goal.x = clampf(goal.x, -12.0, 12.0)
			goal.z = clampf(goal.z, -12.0, 12.0)
			_move_direction(goal - session.player.global_position)
		elif best > 7.2:
			_move_direction(-away)
		else:
			_move_direction(Vector3(-away.z, 0, away.x).normalized())
		if best < 3.8 and session.combat.cooldown_remaining("pulse") <= 0.0 and session.player.stamina >= float(session.character_config.skill("pulse").cost):
			_press(session.input_adapter.bindings.key_for("pulse"))
		if session.player.health < session.player.maximum_health * 0.6 and session.inventory.count("medkit") > 0:
			_press(session.input_adapter.bindings.key_for("heal"))
	func _move_direction(direction: Vector3) -> void:
		var right := session.player.camera.global_basis.x
		var forward := -session.player.camera.global_basis.z
		right.y = 0
		forward.y = 0
		var unit := direction.normalized() if direction.length() > 0.15 else Vector3.ZERO
		var x := unit.dot(right.normalized())
		var y := unit.dot(forward.normalized())
		_key(session.input_adapter.bindings.key_for("move_left"), x < -0.25)
		_key(session.input_adapter.bindings.key_for("move_right"), x > 0.25)
		_key(session.input_adapter.bindings.key_for("move_forward"), y > 0.25)
		_key(session.input_adapter.bindings.key_for("move_back"), y < -0.25)
	func _key(code: int, down: bool) -> void:
		if code == 0 or bool(_held_keys.get(code, false)) == down: return
		_held_keys[code] = down
		var event := InputEventKey.new()
		event.physical_keycode = code as Key
		event.keycode = code as Key
		event.pressed = down
		get_viewport().push_input(event, true)
	func _aim_at(position: Vector3) -> void:
		pointer = session.player.camera.unproject_position(position)
		var motion := InputEventMouseMotion.new()
		motion.position = pointer
		motion.global_position = pointer
		Input.warp_mouse(get_viewport().get_final_transform() * pointer)
		get_viewport().push_input(motion, true)
	func _mouse(button: int, down: bool) -> void:
		if bool(_held_mouse.get(button, false)) == down: return
		_held_mouse[button] = down
		var event := InputEventMouseButton.new()
		event.button_index = button as MouseButton
		event.position = pointer
		event.global_position = pointer
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
		get_viewport().push_input(event, true)
	func _click(text: String) -> bool:
		if not click_handler.is_valid() or not session.hud.modal.visible: return false
		var buttons := session.hud._modal_content.find_children("*", "Button", true, false)
		for item: Node in buttons:
			var button := item as Button
			if text not in button.text or button.disabled or not button.is_visible_in_tree(): continue
			return bool(click_handler.call(button))
		return false
	func _gather() -> void:
		# The reviewed navigation/gather loop calls KEY_E; translate only that emitted action.
		if session.input_adapter.bindings.key_for("interact") == KEY_E:
			super._gather()
			return
		var prefix := "conduit" if session.expedition.region_id == "conduit_yard" else "rain"
		var material := "alloy" if prefix == "conduit" else "scrap"
		var ids := [prefix + "_" + material + "_01", prefix + "_" + material + "_03", prefix + "_crystal_01"]
		if _gather_index >= ids.size():
			if not session.expedition.objective_completed:
				_fail("Objective missing after actual gathers")
				return
			_next("return")
			return
		var id: String = ids[_gather_index]
		if id in session.expedition.gathered_node_ids:
			_gather_index += 1
			_route.clear()
			return
		if _move_to(session.world.resource_positions[id], 1.65) and elapsed > _interact_clock:
			_press(session.input_adapter.bindings.key_for("interact"))
			_interact_clock = elapsed + 0.4

var session: AWGameSession
var stage: String = "idle"
var results: Array[Dictionary] = []
var elapsed: float = 0.0
var completed: bool = false
var succeeded: bool = false
var coverage: Dictionary = {"thief_two_runs": false, "healer_switch": false, "talent_draft_and_apply": false, "healer_three_presets": false, "self_heal": false, "pause_freeze": false, "title_continue_cooldown": false, "healer_actual_death": false, "thief_presets": false, "skill_slot_edit": false, "android": false, "physical_gamepad": false}
var _pilot: ExpeditionPilot
var _report_path: String
var _stage_started_us: int = 0
var _step_clock: float = 0.0
var _last_click_us: int = 0
var _input_pending: bool = false
var _gui_mouse_down: bool = false
var _gui_mouse_point := Vector2.ZERO
var _delivery_generation: int = 0
var _delivery_keys: Dictionary = {}
var _text_delivery_ok: bool = false
var _pilot_event_index: int = 0
var _settled_runs: int = 0
var _starting_resources: Dictionary = {}
var _starting_remainder: int = 0
var _heal_before: Dictionary = {}
var _pause_state: Dictionary = {}
var _paused_at_us: int = 0
var _title_state: Dictionary = {}
var _stored_state: Dictionary = {}
var _gameplay_seconds: float = 0.0
var _continue_gameplay_mark: float = 0.0
var _talent_before: Dictionary = {}
var _preset_index: int = 0
var _death_stock: Dictionary = {}

func start(game: AWGameSession, report_prefix: String = "") -> Dictionary:
	if stage != "idle": return {"ok": false, "code": "driver_already_started", "message": "角色QA驱动已启动。"}
	if not is_instance_valid(game) or not game.is_inside_tree() or game.roster == null or game.combat == null or not game.combat.ready:
		return {"ok": false, "code": "driver_dependencies", "message": "主场景与角色模块尚未就绪。"}
	if DisplayServer.get_name() == "headless": return {"ok": false, "code": "rendered_input_required", "message": "真实输入QA需要有窗口渲染，不能用headless冒充。"}
	var save_path := ProjectSettings.globalize_path(game.save_directory).replace("\\", "/").simplify_path()
	var artifact_root := ProjectSettings.globalize_path("res://../artifacts").replace("\\", "/").simplify_path()
	var test_root := ProjectSettings.globalize_path("user://tests").replace("\\", "/").simplify_path()
	if not _within(save_path, artifact_root) and not _within(save_path, test_root):
		return {"ok": false, "code": "isolated_save_required", "message": "新档QA只允许独立artifacts或user://tests存档目录。"}
	_report_path = save_path.path_join("character-input.json") if report_prefix.is_empty() else ProjectSettings.globalize_path(report_prefix).replace("\\", "/").simplify_path() + ".json"
	if not _within(_report_path, artifact_root) and not _within(_report_path, test_root): return {"ok": false, "code": "isolated_report_required", "message": "报告目录必须独立。"}
	if DirAccess.make_dir_recursive_absolute(_report_path.get_base_dir()) != OK: return {"ok": false, "code": "report_unwritable", "message": "QA报告目录无法创建。"}
	session = game
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pilot = ExpeditionPilot.new()
	add_child(_pilot)
	_pilot.click_handler = _click_control
	_pilot.start(session, 2, true)
	_pilot.set_process(false)
	_next("thief_runs")
	_log("start", {"save_directory": save_path, "renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(), "input": "Viewport.push_input real keyboard/mouse/GUI; observe domains only"})
	return {"ok": true, "code": "driver_started", "message": "角色真实输入QA已启动。", "report": _report_path}

func _process(delta: float) -> void:
	if stage in ["idle", "done", "error"] or not is_instance_valid(session): return
	elapsed += delta
	# Count actual game-frame deltas even while an asynchronous click is pending.
	# Title, pause and offline wall time contribute no cooldown progress.
	if session.session_started and not get_tree().paused: _gameplay_seconds += delta
	if elapsed > 900.0 or _stage_seconds() > (240.0 if stage == "thief_runs" else 100.0):
		_fail("Stage timeout: " + stage)
		return
	# GUI delivery spans rendered frames. No stage may race a pending release/focus change.
	if _input_pending: return
	if stage == "thief_runs":
		_pilot._process(delta)
		_observe_pilot()
		if _pilot.stage == "error": _fail("Expedition input pilot failed")
		elif _pilot.stage == "done":
			_pilot._release()
			_pilot.stage = "idle"
			if _settled_runs != 2 or session.roster.active_character_id != "thief": _fail("Two actual thief settlements missing")
			else:
				coverage["thief_two_runs"] = true
				_next("build_enter")
		return
	if stage == "heal_observe":
		if session.combat.cooldown_remaining("self_heal") > 0.0:
			var heal: Dictionary = session.character_config.skill("self_heal")
			var expected := minf(float(_heal_before.max_health), float(_heal_before.health) + float(_heal_before.max_health) * float(heal.heal_fraction))
			if absf(session.player.health - expected) > 0.001 or absf(session.player.stamina - (float(_heal_before.stamina) - float(heal.cost))) > 0.75:
				_fail("Self-heal observed health/cost differ from actual configuration")
				return
			coverage["self_heal"] = true
			_log("actual_self_heal", {"before": _heal_before, "after": _snapshot(), "expected_health": expected, "cost": heal.cost})
			_press_action("pause")
			_next("pause_observe")
		return
	if stage == "pause_observe":
		if get_tree().paused:
			_pause_state = session.combat.snapshot()
			_paused_at_us = Time.get_ticks_usec()
			_next("pause_hold")
		return
	if stage == "pause_hold":
		if Time.get_ticks_usec() - _paused_at_us >= 2000000:
			if not get_tree().paused or session.combat.snapshot() != _pause_state:
				_fail("Paused shared cooldown/effects advanced")
				return
			coverage["pause_freeze"] = true
			_log("pause_frozen_two_real_seconds", {"combat": _pause_state})
			_next("to_title")
		return
	_step_clock += delta
	if _step_clock < 0.12: return
	_step_clock = 0.0
	if stage in ["wait_real_injury", "death_wait"] and get_tree().paused:
		_click_text("继续")
		return
	match stage:
		"build_enter":
			if _visible_control("Character_healer") != null:
				_next("select_healer")
			else: _click_text("角色构筑")
		"select_healer":
			if session.build_controller.selected_character_id == "healer":
				_log("healer_selected_gui_observed", _gui_state())
				_next("apply_healer")
			else: _click_name("Character_healer")
		"apply_healer":
			if session.roster.active_character_id == "healer":
				_next("healer_observe")
			elif session.build_controller.selected_character_id != "healer": _next("select_healer")
			else: _click_name("ApplyBuild")
		"healer_observe":
			if session.roster.active_character_id == "healer":
				coverage["healer_switch"] = true
				_log("healer_selected_and_applied", _snapshot())
				_talent_before = _snapshot()
				_next("talents_enter")
		"talents_enter":
			if _visible_control("Talent_vitality") != null:
				_next("talent_type")
			else: _click_name("BuildTab_talents")
		"talent_type":
			var rank := _visible_control("Talent_vitality") as SpinBox
			if rank != null:
				var field := rank.get_line_edit()
				if get_viewport().gui_get_focus_owner() != field: _click_control(field)
				elif _type_text(field, "1"): _next("talent_observe")
		"talent_observe":
			if not _text_delivery_ok:
				_next("talent_type")
				return
			if int(session.roster.profile("healer").draft.talents.vitality) == 1:
				if int(session.roster.active_build().talents.vitality) != 0 or absf(session.player.maximum_health - float(_talent_before.max_health)) > 0.001:
					_fail("Draft edit changed live build before apply")
					return
				_log("actual_talent_draft_only", _snapshot())
				_next("talent_apply")
		"talent_apply":
			if int(session.roster.active_build().talents.vitality) == 1: _next("talent_apply_observe")
			else: _click_name("ApplyBuild")
		"talent_apply_observe":
			if int(session.roster.active_build().talents.vitality) == 1:
				coverage["talent_draft_and_apply"] = true
				_log("actual_talent_applied", _snapshot())
				_next("presets_enter")
		"presets_enter":
			if _visible_control("PresetName_0") != null: _next("preset_type")
			else: _click_name("BuildTab_presets")
		"preset_type":
			var field := _visible_control("PresetName_" + str(_preset_index)) as LineEdit
			if field != null:
				if get_viewport().gui_get_focus_owner() != field: _click_control(field)
				elif _type_text(field, "Healer QA " + str(_preset_index + 1), false): _next("preset_save")
		"preset_save":
			var field := _visible_control("PresetName_" + str(_preset_index)) as LineEdit
			if field == null or field.text != "Healer QA " + str(_preset_index + 1):
				_next("preset_type")
				return
			var saves := _buttons_with_text("保存当前草稿")
			var saved: Dictionary = session.roster.profile("healer").presets[_preset_index]
			if saved.name == field.text and saved.build != null: _next("preset_observe")
			elif saves.size() > _preset_index: _click_control(saves[_preset_index])
		"preset_observe":
			var preset: Dictionary = session.roster.profile("healer").presets[_preset_index]
			if preset.name == "Healer QA " + str(_preset_index + 1) and preset.build != null:
				_log("actual_preset_saved", {"slot": _preset_index, "preset": preset})
				_preset_index += 1
				if _preset_index == 3:
					coverage["healer_three_presets"] = true
					_next("build_back")
				else: _next("preset_type")
		"build_back":
			if not _buttons_with_text("出发：雨庭").is_empty(): _next("healer_enter")
			else: _click_text("返回")
		"healer_enter":
			if not session.in_camp: _next("wait_real_injury")
			else: _click_text("出发：雨庭")
		"wait_real_injury":
			_pilot._release()
			if session.in_camp:
				_fail("Healer died before self-heal input")
				return
			if session.player.health > 0.0 and session.player.health < session.player.maximum_health - 1.0 and session.player.stamina >= float(session.character_config.skill("self_heal").cost):
				_heal_before = _snapshot()
				_press_action("character_ability")
				_next("heal_observe")
		"to_title":
			if not session.session_started and get_tree().paused: _next("title_observe")
			else:
				_title_state = session.combat.snapshot()
				_click_text("保存并回到标题")
		"title_observe":
			if not session.session_started and get_tree().paused:
				var stored: Dictionary = session.repository.load()
				if not stored.ok or not _json_semantic_equal(_title_state, stored.data.combat_state):
					_fail("Saved title checkpoint lost shared cooldown/effects")
					return
				_stored_state = stored.data.combat_state.duplicate(true)
				_log("saved_title_checkpoint", {"sequence": stored.sequence, "combat": _stored_state, "health": stored.data.health, "stamina": stored.data.stamina})
				_continue_gameplay_mark = _gameplay_seconds
				_next("continue_click")
		"continue_click":
			if session.session_started:
				if not session.in_camp:
					_fail("Continue did not restore camp")
					return
				var gameplay_advanced := _gameplay_seconds - _continue_gameplay_mark
				var expected_combat := _combat_after_gameplay(_stored_state, gameplay_advanced)
				var actual_combat := session.combat.snapshot()
				if expected_combat.is_empty() or not _json_semantic_equal(expected_combat, actual_combat):
					_log("continue_cooldown_mismatch", {"stored": _stored_state, "gameplay_seconds": gameplay_advanced, "expected": expected_combat, "actual": actual_combat})
					_fail("Title/continue reset or reduced shared recovery cooldown")
					return
				coverage["title_continue_cooldown"] = true
				_log("actual_continue_cooldown_preserved", {"gameplay_seconds": gameplay_advanced, "stored": _stored_state, "expected": expected_combat, "state": _snapshot()})
				_death_stock = session.inventory.snapshot().resources
				_next("death_enter")
			else: _click_text("继续旅程")
		"death_enter":
			if not session.in_camp: _next("death_wait")
			else: _click_text("出发：雨庭")
		"death_wait":
			_pilot._release()
			if session.in_camp:
				if session.expedition.outcome != "failed" or session.inventory.snapshot().resources != _death_stock:
					_fail("Actual death returned with wrong outcome or granted cargo")
					return
				coverage["healer_actual_death"] = true
				_log("actual_enemy_death_and_failure_camp", _snapshot())
				completed = true
				succeeded = true
				stage = "done"
				_log("done", {"coverage": coverage, "state": _snapshot()})

func _observe_pilot() -> void:
	while _pilot_event_index < _pilot.results.size():
		var event: Dictionary = _pilot.results[_pilot_event_index]
		_pilot_event_index += 1
		if event.event == "stage" and event.data.stage == "camp" and _settled_runs == 0 and _starting_resources.is_empty() and session.session_started:
			_starting_resources = session.inventory.snapshot().resources
			_starting_remainder = session.roster.thief_coin_remainder
		if event.event == "settled":
			_settled_runs += 1
			var region: Dictionary = session.rules.data.regions.rain_court
			var kill_count: int = session.expedition.defeated_enemy_ids.size()
			var base_coins := kill_count * int(region.kill_reward.get("currency", 0))
			var before_remainder := int(session.expedition.snapshot().starting_coin_remainder)
			var bonus := floori(float(before_remainder + base_coins) / 20.0)
			if kill_count != region.enemy_ids.size() or not session.expedition.objective_completed:
				_fail("Actual thief run lacks full kills/objective")
				return
			var expected_total: int = int(_starting_resources.currency) + _settled_runs * (region.enemy_ids.size() * int(region.kill_reward.currency) + int(region.objective.reward.currency)) + floori(float(_starting_remainder + _settled_runs * base_coins) / 20.0)
			var expected_remainder := (_starting_remainder + _settled_runs * base_coins) % 20
			if session.inventory.count("currency") != expected_total or session.roster.thief_coin_remainder != expected_remainder:
				_fail("Thief true monster/objective bonus or remainder mismatch")
				return
			_log("actual_thief_settlement", {"run": _settled_runs, "kills": kill_count, "bonus_this_run": bonus, "expected_total": expected_total, "expected_remainder": expected_remainder, "state": _snapshot()})

func _click_name(control_name: String) -> bool:
	return _click_control(_visible_control(control_name))

func _visible_control(control_name: String) -> Control:
	var control := session.hud.find_child(control_name, true, false) as Control
	return control if is_instance_valid(control) and control.is_visible_in_tree() else null

func _buttons_with_text(text: String) -> Array[Button]:
	var found: Array[Button] = []
	for node: Node in session.hud._modal_content.find_children("*", "Button", true, false):
		var button := node as Button
		if text in button.text and not button.disabled and button.is_visible_in_tree(): found.append(button)
	return found

func _click_text(text: String) -> bool:
	var candidates := _buttons_with_text(text)
	return _click_control(candidates[0]) if not candidates.is_empty() else false

func _click_control(control: Control) -> bool:
	if _input_pending or not is_instance_valid(control) or not control.is_visible_in_tree() or (control is BaseButton and control.disabled) or Time.get_ticks_usec() - _last_click_us < 350000: return false
	var rect := control.get_global_rect()
	var visible_rect := session.hud._modal_scroll.get_global_rect()
	if not visible_rect.encloses(rect):
		_input_pending = true
		_deliver_wheel(visible_rect.get_center(), MOUSE_BUTTON_WHEEL_DOWN if rect.position.y > visible_rect.position.y else MOUSE_BUTTON_WHEEL_UP, _delivery_generation)
		return false
	_input_pending = true
	_last_click_us = Time.get_ticks_usec()
	_deliver_click(control, _delivery_generation)
	# This acknowledges queued input only. Every caller must observe actual GUI/domain state.
	return true

func _move_gui_pointer(point: Vector2) -> void:
	Input.warp_mouse(get_viewport().get_final_transform() * point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)

func _gui_button(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.position = point
	click.global_position = point
	click.button_index = button
	click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	click.pressed = pressed
	get_viewport().push_input(click, true)

func _delivery_alive(generation: int) -> bool:
	return is_inside_tree() and generation == _delivery_generation and stage not in ["done", "error"] and is_instance_valid(session)

func _deliver_click(control: Control, generation: int) -> void:
	var point := control.get_global_rect().get_center()
	var target := {"path": str(control.get_path()), "name": str(control.name), "text": control.text if control is BaseButton or control is LineEdit else "", "logical_point": [point.x, point.y]}
	_move_gui_pointer(point)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	if not is_instance_valid(control) or not control.is_visible_in_tree() or not control.get_global_rect().has_point(point) or (control is BaseButton and control.disabled):
		_input_pending = false
		_log("gui_click_cancelled_layout", target)
		return
	_gui_mouse_point = point
	_gui_mouse_down = true
	_gui_button(point, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	# A pressed handler may rebuild/free the original Control; release still routes normally.
	_gui_button(point, MOUSE_BUTTON_LEFT, false)
	_gui_mouse_down = false
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_input_pending = false
	_last_click_us = Time.get_ticks_usec()
	_log("gui_click_delivered", {"target": target, "observed": _gui_state()})

func _deliver_wheel(point: Vector2, button: MouseButton, generation: int) -> void:
	_move_gui_pointer(point)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_gui_button(point, button, true)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_gui_button(point, button, false)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_input_pending = false
	_last_click_us = Time.get_ticks_usec()

func _gui_state() -> Dictionary:
	var focus := get_viewport().gui_get_focus_owner()
	var model: Dictionary = session.build_controller.view_model()
	return {"selected_character": session.build_controller.selected_character_id, "active_character": session.roster.active_character_id, "section": session.build_controller.view.section if session.build_controller.view != null else "", "focus": str(focus.get_path()) if is_instance_valid(focus) else "", "apply_allowed": model.get("apply_allowed", false), "apply_reason": model.get("apply_reason", "")}

func _press_action(action: String) -> void:
	_key_event(session.input_adapter.bindings.key_for(action), 0, false, true)
	_key_event(session.input_adapter.bindings.key_for(action), 0, false, false)

func _key_event(code: int, unicode: int, ctrl: bool, pressed: bool) -> void:
	if code != 0:
		if pressed: _delivery_keys[code] = ctrl
		else: _delivery_keys.erase(code)
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	event.keycode = code as Key
	event.unicode = unicode
	event.ctrl_pressed = ctrl
	event.pressed = pressed
	get_viewport().push_input(event, true)

func _type_text(field: LineEdit, value: String, submit: bool = true) -> bool:
	if _input_pending or not is_instance_valid(field) or get_viewport().gui_get_focus_owner() != field: return false
	_input_pending = true
	_text_delivery_ok = false
	_deliver_text(field, value, submit, _delivery_generation)
	return true

func _deliver_text(field: LineEdit, value: String, submit: bool, generation: int) -> void:
	var target := str(field.get_path())
	_log("gui_text_focus_observed", {"path": target, "before": field.text, "requested": value, "submit": submit})
	_key_event(KEY_A, 0, true, true)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_key_event(KEY_A, 0, true, false)
	_key_event(KEY_BACKSPACE, 0, false, true)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_key_event(KEY_BACKSPACE, 0, false, false)
	for character: String in value:
		if not is_instance_valid(field) or get_viewport().gui_get_focus_owner() != field:
			_input_pending = false
			_log("gui_text_focus_lost", {"path": target})
			return
		var code := character.to_upper().unicode_at(0)
		_key_event(code, character.unicode_at(0), false, true)
		await get_tree().process_frame
		if not _delivery_alive(generation): return
		_key_event(code, 0, false, false)
	if submit:
		_key_event(KEY_ENTER, 0, false, true)
		await get_tree().process_frame
		if not _delivery_alive(generation): return
		_key_event(KEY_ENTER, 0, false, false)
	await get_tree().process_frame
	if not _delivery_alive(generation): return
	_input_pending = false
	_text_delivery_ok = true
	_log("gui_text_delivered", {"path": target, "observed": field.text if is_instance_valid(field) else "<control replaced>", "requested": value, "submit": submit})

func _snapshot() -> Dictionary:
	return {"health": session.player.health, "max_health": session.player.maximum_health, "stamina": session.player.stamina, "max_stamina": session.player.maximum_stamina, "active_character": session.roster.active_character_id, "coin_remainder": session.roster.thief_coin_remainder, "combat": session.combat.snapshot(), "profiles": session.roster.snapshot().profiles, "resources": session.inventory.snapshot().resources, "level": session.progress.level, "realm": session.progress.realm, "camp": session.in_camp, "run": session.run_counter, "gui": _gui_state()}

func _next(next_stage: String) -> void:
	stage = next_stage
	_stage_started_us = Time.get_ticks_usec()
	_step_clock = 0.0
	_log("stage", {"stage": stage})

func _stage_seconds() -> float:
	return float(Time.get_ticks_usec() - _stage_started_us) / 1000000.0

func _log(event: String, data: Dictionary) -> void:
	results.append({"at_seconds": elapsed, "event": event, "data": data.duplicate(true)})
	if _report_path.is_empty(): return
	var output := FileAccess.open(_report_path, FileAccess.WRITE)
	if output == null:
		stage = "error"
		return
	output.store_string(JSON.stringify({"driver": "character InputEvent/UI QA", "stage": stage, "completed": completed, "ok": succeeded, "coverage": coverage, "results": results}, "\t"))
	output.flush()
	output.close()

func _fail(message: String) -> void:
	_cancel_delivery()
	if is_instance_valid(_pilot):
		_pilot._release()
		_pilot.stage = "idle"
	stage = "error"
	completed = true
	succeeded = false
	_log("failure", {"message": message, "state": _snapshot() if is_instance_valid(session) and session.player != null else {}})

func _exit_tree() -> void:
	_cancel_delivery()
	if is_instance_valid(_pilot): _pilot._release()

func _cancel_delivery() -> void:
	_delivery_generation += 1
	_input_pending = false
	if _gui_mouse_down and is_inside_tree(): _gui_button(_gui_mouse_point, MOUSE_BUTTON_LEFT, false)
	_gui_mouse_down = false
	if is_inside_tree():
		for code: int in _delivery_keys.keys(): _key_event(code, 0, bool(_delivery_keys[code]), false)
	_delivery_keys.clear()

static func _within(path: String, root: String) -> bool:
	return path.to_lower().begins_with(root.to_lower().trim_suffix("/") + "/")

static func _json_semantic_equal(expected: Variant, actual: Variant) -> bool:
	var expected_type := typeof(expected)
	var actual_type := typeof(actual)
	if expected_type in [TYPE_INT, TYPE_FLOAT] and actual_type in [TYPE_INT, TYPE_FLOAT]:
		var left := float(expected)
		var right := float(actual)
		if not is_finite(left) or not is_finite(right): return false
		# JSON parses integer schema fields as floats; their integral value stays exact.
		if expected_type == TYPE_INT or actual_type == TYPE_INT:
			return left == floorf(left) and right == floorf(right) and left == right
		return absf(left - right) <= 0.000000001
	if expected_type != actual_type: return false
	if expected_type == TYPE_DICTIONARY:
		if expected.size() != actual.size(): return false
		for key: Variant in expected:
			if not key is String or not actual.has(key): return false
			if key == "schema_version":
				if typeof(expected[key]) not in [TYPE_INT, TYPE_FLOAT] or typeof(actual[key]) not in [TYPE_INT, TYPE_FLOAT]: return false
				var left := float(expected[key])
				var right := float(actual[key])
				if not is_finite(left) or not is_finite(right) or left != floorf(left) or right != floorf(right) or left != right: return false
			elif not _json_semantic_equal(expected[key], actual[key]): return false
		for key: Variant in actual:
			if not key is String: return false
		return true
	if expected_type == TYPE_ARRAY:
		if expected.size() != actual.size(): return false
		for index: int in range(expected.size()):
			if not _json_semantic_equal(expected[index], actual[index]): return false
		return true
	return expected_type in [TYPE_NIL, TYPE_BOOL, TYPE_STRING] and expected == actual

static func _combat_after_gameplay(stored: Dictionary, seconds: float) -> Dictionary:
	if not is_finite(seconds) or seconds < 0.0 or stored.size() != 3 or typeof(stored.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] or stored.get("schema_version") != 1 or not stored.get("cooldowns") is Dictionary or not stored.get("effects") is Dictionary: return {}
	if stored.cooldowns.size() != AWCombatState.COOLDOWN_KEYS.size() or stored.effects.size() != AWCombatState.EFFECT_KEYS.size(): return {}
	var expected := stored.duplicate(true)
	for key: String in AWCombatState.COOLDOWN_KEYS:
		if not expected.cooldowns.has(key) or typeof(expected.cooldowns[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(expected.cooldowns[key])) or float(expected.cooldowns[key]) < 0.0: return {}
		expected.cooldowns[key] = maxf(0.0, float(expected.cooldowns[key]) - seconds)
	for key: String in AWCombatState.EFFECT_KEYS:
		if not expected.effects.has(key) or typeof(expected.effects[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(expected.effects[key])) or float(expected.effects[key]) < 0.0: return {}
	for key: String in ["barrier_remaining", "focus_remaining"]:
		expected.effects[key] = maxf(0.0, float(expected.effects[key]) - seconds)
	if float(expected.effects.barrier_remaining) == 0.0: expected.effects["barrier_capacity"] = 0.0
	return expected
