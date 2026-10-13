extends GdUnitTestSuite

const Fixture = preload("res://tests/build_fixture.gd")
const HUD = preload("res://presentation/game_hud.gd")
const Controller = preload("res://presentation/build_controller.gd")
var _fixture: Dictionary
var _hud: HUD
var _controller: Controller
var _live: Dictionary
var _applications: Array[Dictionary] = []
var _edit_count: int = 0
var _close_count: int = 0
var _operation_count: int = 0

func before_test() -> void:
	_fixture = Fixture.create()
	_live = {"context": Fixture.camp(), "vitals": Fixture.vitals(_fixture)}
	_applications.clear()
	_edit_count = 0
	_close_count = 0
	_operation_count = 0
	_hud = HUD.new()
	add_child(_hud)
	_controller = Controller.new()
	add_child(_controller)
	_controller.edited.connect(func() -> void: _edit_count += 1)
	_controller.closed.connect(func() -> void: _close_count += 1)
	_controller.build_applied.connect(func(data: Dictionary) -> void:
		_applications.append(data.duplicate(true))
		_live["vitals"] = data.new_vitals.duplicate(true))
	assert_bool(_configure(_fixture).ok).is_true()

func after_test() -> void:
	if is_instance_valid(_controller):
		remove_child(_controller)
		_controller.free()
	if is_instance_valid(_hud):
		remove_child(_hud)
		_hud.free()
	_fixture.clear()
	_live.clear()
	await get_tree().process_frame

func _configure(fixture: Dictionary) -> Dictionary:
	return _controller.configure(_hud, fixture.config, fixture.evaluator, fixture.roster, fixture.progress, fixture.inventory, fixture.combat, _context, _vitals, _operation_id)

func _context() -> Variant:
	var value: Variant = _live["context"]
	return value.duplicate(true) if value is Dictionary else value

func _vitals() -> Variant:
	var value: Variant = _live["vitals"]
	return value.duplicate(true) if value is Dictionary else value

func _operation_id() -> Variant:
	_operation_count += 1
	if bool(_live.get("leave_camp_on_allocation", false)): _live["context"]["camp"] = false
	return _live.get("operation_override", "build-menu-%d" % _operation_count)

func _control(name: String) -> Control:
	var control := _hud.find_child(name, true, false) as Control
	assert_object(control).is_not_null()
	return control

func _choose_skill(slot: int, index: int) -> void:
	var selector := _control("CommonSkill_" + str(slot)) as OptionButton
	selector.select(index)
	selector.item_selected.emit(index)

func _gui_key(key: Key, unicode: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.unicode = unicode
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func _settle_gui() -> void:
	# SpinBox queues its editing and submission callbacks in the real engine.
	await get_tree().process_frame
	await get_tree().process_frame

func _preset_action(slot: int, action_index: int) -> Button:
	var name_edit := _control("PresetName_" + str(slot)) as LineEdit
	return (name_edit.get_parent().get_child(name_edit.get_index() + 1) as HBoxContainer).get_child(action_index) as Button

func test_four_sections_render_complete_real_model_with_readable_numbers_and_focus() -> void:
	for section: String in ["overview", "talents", "skills", "presets"]:
		assert_bool(_controller.show(section).ok).is_true()
		var model := _controller.view_model()
		assert_str(model.character_id).is_equal("thief")
		assert_int(model.characters.size()).is_equal(2)
		assert_int(model.talent_nodes.size()).is_equal(9)
		assert_int(model.skill_options.size()).is_equal(3)
		assert_int(model.presets.size()).is_equal(3)
		assert_int(model.weapon_options.size()).is_equal(2)
		assert_bool("生命上限 125.00" in model.comparison_text).is_true()
		assert_bool("max_health" in model.comparison_text).is_false()
		assert_bool("0 / 世界总量 10" in model.qualification_text).is_true()
		assert_object(get_viewport().gui_get_focus_owner()).is_same(_control("BuildTab_" + section))
	assert_int(_operation_count).is_equal(0)
	assert_int(_edit_count).is_equal(0)

func test_real_talent_control_edits_only_draft_and_preserves_control_focus() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var before: Dictionary = _fixture.inventory.snapshot()
	var current: Dictionary = _fixture.roster.active_build()
	var rank := _control("Talent_vitality") as SpinBox
	rank.get_line_edit().grab_focus()
	rank.value = 3
	assert_int(_fixture.roster.profile("thief").draft.talents.vitality).is_equal(3)
	assert_dict(_fixture.roster.active_build()).is_equal(current)
	assert_dict(_fixture.inventory.snapshot()).is_equal(before)
	assert_float(_live.vitals.max_health).is_equal(125.0)
	assert_int(_edit_count).is_equal(1)
	assert_int(_operation_count).is_equal(0)
	assert_int(_applications.size()).is_equal(0)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(rank.get_line_edit())
	assert_bool("125.00 → 131.00" in _controller.view_model().comparison_text).is_true()

func test_selecting_identity_edits_other_profile_without_applying_or_saving() -> void:
	assert_bool(_controller.show().ok).is_true()
	(_control("Character_healer") as Button).pressed.emit()
	assert_str(_controller.selected_character_id).is_equal("healer")
	assert_str(_fixture.roster.active_character_id).is_equal("thief")
	(_control("BuildTab_talents") as Button).pressed.emit()
	(_control("Talent_weapon_training") as SpinBox).value = 4
	assert_int(_fixture.roster.profile("healer").draft.talents.weapon_training).is_equal(4)
	assert_int(_fixture.roster.profile("thief").draft.talents.weapon_training).is_equal(0)
	assert_int(_fixture.roster.profile("healer").applied_build.talents.weapon_training).is_equal(0)
	assert_int(_edit_count).is_equal(1)
	assert_int(_operation_count).is_equal(0)
	assert_int(_applications.size()).is_equal(0)

func test_rejected_duplicate_skill_restores_actual_control_and_keeps_all_state() -> void:
	assert_bool(_controller.show("skills").ok).is_true()
	var state: Dictionary = _fixture.roster.snapshot()
	var stock: Dictionary = _fixture.inventory.snapshot()
	_choose_skill(0, 1)
	assert_int((_control("CommonSkill_0") as OptionButton).selected).is_equal(0)
	assert_dict(_fixture.roster.snapshot()).is_equal(state)
	assert_dict(_fixture.inventory.snapshot()).is_equal(stock)
	assert_bool("重复" in _hud.notice.text).is_true()
	assert_int(_edit_count).is_equal(0)
	assert_int(_operation_count).is_equal(0)

func test_live_location_alive_and_started_guards_run_before_operation_allocation() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	(_control("Talent_vitality") as SpinBox).value = 2
	var before: Dictionary = _fixture.roster.snapshot()
	var inventory: Dictionary = _fixture.inventory.snapshot()
	for key: String in ["camp", "encounter_ended", "session_started"]:
		_live["context"] = Fixture.camp()
		_live["context"][key] = false
		(_control("ApplyBuild") as Button).pressed.emit()
		assert_dict(_fixture.roster.snapshot()).is_equal(before)
		assert_dict(_fixture.inventory.snapshot()).is_equal(inventory)
		assert_int(_operation_count).is_equal(0)
	_live["context"] = Fixture.camp()
	_live["vitals"]["health"] = 0.0
	(_control("ApplyBuild") as Button).pressed.emit()
	assert_int(_operation_count).is_equal(0)
	assert_int(_applications.size()).is_equal(0)
	assert_int(_fixture.roster.active_build().talents.vitality).is_equal(0)

func test_successful_apply_emits_real_data_once_and_scene_callback_keeps_vital_ratio() -> void:
	assert_bool(_controller.show().ok).is_true()
	(_control("Character_healer") as Button).pressed.emit()
	(_control("BuildTab_talents") as Button).pressed.emit()
	(_control("Talent_vitality") as SpinBox).value = 4
	var resources: Dictionary = _fixture.inventory.snapshot().resources
	var history: Dictionary = _fixture.inventory.get_equipment("starter").history
	var combat: Dictionary = _fixture.combat.snapshot()
	(_control("ApplyBuild") as Button).pressed.emit()
	assert_int(_operation_count).is_equal(1)
	assert_int(_applications.size()).is_equal(1)
	assert_int(_edit_count).is_equal(1)
	assert_str(_fixture.roster.active_character_id).is_equal("healer")
	assert_float(_live.vitals.health).is_equal_approx(53.2, 0.000001)
	assert_float(_live.vitals.max_health).is_equal(133.0)
	assert_float(_live.vitals.stamina).is_equal(80.0)
	assert_dict(_fixture.inventory.snapshot().resources).is_equal(resources)
	assert_dict(_fixture.inventory.get_equipment("starter").history).is_equal(history)
	assert_dict(_fixture.combat.snapshot()).is_equal(combat)
	_applications[0].effective_build.talents["vitality"] = 8
	assert_int(_fixture.roster.active_build().talents.vitality).is_equal(4)

func test_operation_allocation_transition_rechecks_live_providers_and_refuses_apply() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	(_control("Talent_vitality") as SpinBox).value = 2
	_live["leave_camp_on_allocation"] = true
	var before: Dictionary = _fixture.roster.snapshot()
	var stock: Dictionary = _fixture.inventory.snapshot()
	(_control("ApplyBuild") as Button).pressed.emit()
	assert_int(_operation_count).is_equal(1)
	assert_int(_applications.size()).is_equal(0)
	assert_dict(_fixture.roster.snapshot()).is_equal(before)
	assert_dict(_fixture.inventory.snapshot()).is_equal(stock)
	assert_bool("营地" in _hud.notice.text).is_true()

func test_real_save_buttons_store_three_independent_presets_and_load_only_draft() -> void:
	assert_bool(_controller.show("presets").ok).is_true()
	for slot: int in range(3):
		assert_bool(_controller.handle_intent("talent_rank", {"character_id": "thief", "node_id": "weapon_training", "rank": slot + 1}).ok).is_true()
		(_control("PresetName_" + str(slot)) as LineEdit).text = "流派" + str(slot)
		_preset_action(slot, 0).pressed.emit()
	for slot: int in range(3):
		assert_str(_fixture.roster.profile("thief").presets[slot].name).is_equal("流派" + str(slot))
		assert_int(_fixture.roster.profile("thief").presets[slot].build.talents.weapon_training).is_equal(slot + 1)
		_preset_action(slot, 1).pressed.emit()
		assert_int(_fixture.roster.profile("thief").draft.talents.weapon_training).is_equal(slot + 1)
	assert_int(_fixture.roster.active_build().talents.weapon_training).is_equal(0)
	assert_int(_operation_count).is_equal(0)
	assert_int(_applications.size()).is_equal(0)

func test_consumed_equipment_remains_visible_in_real_options_and_preset_reasons() -> void:
	assert_bool(_controller.show().ok).is_true()
	var weapon := _control("DraftWeapon") as OptionButton
	weapon.select(0)
	weapon.item_selected.emit(0)
	assert_str(_fixture.roster.profile("thief").draft.weapon_id).is_equal("material")
	assert_bool(_controller.show("presets").ok).is_true()
	(_control("PresetName_0") as LineEdit).text = "消耗前装备"
	_preset_action(0, 0).pressed.emit()
	assert_bool(_fixture.inventory.grant({"currency": 200, "scrap": 20}, "fixture-menu-fusion").ok).is_true()
	var locks: Array[String] = []
	assert_bool(_fixture.service.fuse(_fixture.inventory, "starter", "material", locks, 1, true, true, "menu-real-fusion", 30).ok).is_true()
	assert_bool(_controller.show().ok).is_true()
	var model := _controller.view_model()
	assert_int(model.weapon_options.size()).is_equal(2)
	assert_str(model.weapon_options[1].id).is_equal("material")
	assert_bool("失效" in model.weapon_options[1].label).is_true()
	assert_bool(model.apply_allowed).is_false()
	(_control("ApplyBuild") as Button).pressed.emit()
	assert_int(_operation_count).is_equal(0)
	assert_bool(_controller.show("presets").ok).is_true()
	assert_bool("不存在" in _controller.view_model().presets[0].status_text).is_true()
	assert_str(_fixture.roster.profile("thief").presets[0].build.weapon_id).is_equal("material")

func test_reconfigure_disconnects_old_menu_intents_and_binds_new_domain() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var original_view := _controller.view
	var next := Fixture.create()
	_live["vitals"] = Fixture.vitals(next)
	assert_bool(_configure(next).ok).is_true()
	original_view.requested.emit("talent_rank", {"character_id": "thief", "node_id": "vitality", "rank": 8})
	assert_int(_fixture.roster.profile("thief").draft.talents.vitality).is_equal(0)
	assert_int(next.roster.profile("thief").draft.talents.vitality).is_equal(0)
	assert_bool(_controller.show("talents").ok).is_true()
	(_control("Talent_vitality") as SpinBox).value = 2
	assert_int(next.roster.profile("thief").draft.talents.vitality).is_equal(2)
	assert_int(_fixture.roster.profile("thief").draft.talents.vitality).is_equal(0)

func test_invalid_provider_and_intent_types_do_not_trigger_runtime_errors_or_partial_apply() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var original: Dictionary = _fixture.roster.snapshot()
	for data: Dictionary in [{"character_id": "thief", "node_id": "vitality", "rank": true}, {"character_id": "thief", "node_id": "vitality", "rank": 1.5}, {"character_id": "healer", "node_id": "vitality", "rank": 2}, {"character_id": "thief", "node_id": "vitality", "rank": 2, "extra": 1}]:
		assert_bool(_controller.handle_intent("talent_rank", data).ok).is_false()
	assert_dict(_fixture.roster.snapshot()).is_equal(original)
	_live["context"] = []
	assert_bool(_controller.handle_intent("apply", {"character_id": "thief"}).ok).is_false()
	assert_int(_operation_count).is_equal(0)
	_live["context"] = Fixture.camp()
	_live["operation_override"] = 1
	assert_str(_controller.handle_intent("apply", {"character_id": "thief"}).code).is_equal("build_operation_invalid")
	assert_dict(_fixture.roster.snapshot()).is_equal(original)
	assert_int(_applications.size()).is_equal(0)

func test_back_emits_closed_and_rejects_stale_controls_afterward() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var state: Dictionary = _fixture.roster.snapshot()
	assert_bool(_controller.handle_intent("back", {}).ok).is_true()
	assert_int(_close_count).is_equal(1)
	assert_bool(_controller.handle_intent("talent_rank", {"character_id": "thief", "node_id": "vitality", "rank": 3}).ok).is_false()
	assert_dict(_fixture.roster.snapshot()).is_equal(state)
	assert_int(_edit_count).is_equal(0)

func test_over_budget_and_unlocked_stage_drafts_are_editable_but_preview_refuses_apply() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	(_control("Talent_vitality") as SpinBox).value = 8
	(_control("Talent_weapon_training") as SpinBox).value = 3
	assert_bool(_controller.view_model().apply_allowed).is_false()
	assert_bool("超过" in _controller.view_model().qualification_text).is_true()
	(_control("ApplyBuild") as Button).pressed.emit()
	assert_int(_operation_count).is_equal(0)
	assert_int(_fixture.roster.active_build().talents.vitality).is_equal(0)
	assert_bool(_controller.show("skills").ok).is_true()
	_choose_skill(1, 2)
	assert_str(_fixture.roster.profile("thief").draft.skill_loadout[1]).is_equal("focus")
	assert_int((_control("CommonSkill_1") as OptionButton).selected).is_equal(2)
	assert_bool("解锁" in _controller.view_model().qualification_text).is_true()
	assert_bool(_controller.view_model().apply_allowed).is_false()
	assert_int(_applications.size()).is_equal(0)

func test_retired_spinbox_value_update_does_not_edit_newly_selected_character() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var retired_rank := _control("Talent_vitality") as SpinBox
	assert_bool(_controller.handle_intent("select_character", {"character_id": "healer"}).ok).is_true()
	assert_bool(retired_rank.is_inside_tree()).is_false()
	# The old row has left the tree while awaiting queue_free.
	retired_rank.value = 7
	assert_int(_fixture.roster.profile("healer").draft.talents.vitality).is_equal(0)
	assert_int(_fixture.roster.profile("thief").draft.talents.vitality).is_equal(0)
	assert_int(_edit_count).is_equal(0)

func test_failed_configuration_keeps_existing_valid_menu_and_connections() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var existing_view := _controller.view
	var rejected := _controller.configure(_hud, _fixture.config, _fixture.evaluator, _fixture.roster, _fixture.progress, _fixture.inventory, _fixture.combat, Callable(), _vitals, _operation_id)
	assert_str(rejected.code).is_equal("build_controller_invalid")
	assert_object(_controller.view).is_same(existing_view)
	(_control("Talent_vitality") as SpinBox).value = 2
	assert_int(_fixture.roster.profile("thief").draft.talents.vitality).is_equal(2)
	assert_int(_edit_count).is_equal(1)

func test_cooldown_only_refresh_updates_real_clock_without_recomputing_build_qualification() -> void:
	assert_bool(_controller.show("skills").ok).is_true()
	var model := _controller.view_model()
	var derived: Dictionary = _fixture.evaluator.evaluate(_fixture.roster.active_build(), _fixture.progress, _fixture.inventory).data
	var cast: Dictionary = _fixture.combat.cast("barrier", Fixture.combat_context(_fixture), _live.vitals, derived, "menu-clock-real-cast")
	assert_bool(cast.ok).is_true()
	_live["vitals"] = cast.data.new_vitals
	assert_bool(_fixture.progress.award_experience(20, "fixture-clock-world-change").ok).is_true()
	assert_bool(_controller.refresh_cooldowns().ok).is_true()
	assert_bool("屏障 10.0秒" in _controller.view_model().cooldown_text).is_true()
	assert_bool("屏障 10.0秒" in (_control("BuildCooldowns") as Label).text).is_true()
	assert_str(_controller.view_model().qualification_text).is_equal(model.qualification_text)
	assert_bool(_controller.refresh().ok).is_true()
	assert_bool("世界总量 11" in _controller.view_model().qualification_text).is_true()
	assert_int(_operation_count).is_equal(0)
	assert_int(_edit_count).is_equal(0)

func test_cooldown_tick_preserves_unsubmitted_talent_text_then_enter_validates_real_draft() -> void:
	assert_bool(_controller.show("talents").ok).is_true()
	var rank := _control("Talent_vitality") as SpinBox
	var field := rank.get_line_edit()
	field.grab_focus()
	await _settle_gui()
	field.select_all()
	_gui_key(KEY_7, 55)
	await _settle_gui()
	assert_str(field.text).is_equal("7")
	assert_float(rank.value).is_equal(0.0)
	var draft: Dictionary = _fixture.roster.profile("thief").draft
	var qualification: String = _controller.view_model().qualification_text
	var derived: Dictionary = _fixture.evaluator.evaluate(_fixture.roster.active_build(), _fixture.progress, _fixture.inventory).data
	var cast: Dictionary = _fixture.combat.cast("barrier", Fixture.combat_context(_fixture), _live.vitals, derived, "menu-text-clock-cast")
	assert_bool(cast.ok).is_true()
	_live["vitals"] = cast.data.new_vitals
	assert_bool(_fixture.combat.tick(0.12, true).ok).is_true()
	assert_bool(_controller.refresh_cooldowns().ok).is_true()
	await _settle_gui()
	assert_bool("屏障 9.9秒" in _controller.view_model().cooldown_text).is_true()
	assert_str(field.text).is_equal("7")
	assert_dict(_fixture.roster.profile("thief").draft).is_equal(draft)
	assert_str(_controller.view_model().qualification_text).is_equal(qualification)
	assert_int(_edit_count).is_equal(0)
	assert_int(_operation_count).is_equal(0)
	assert_object(get_viewport().gui_get_focus_owner()).is_same(field)
	_gui_key(KEY_ENTER)
	await _settle_gui()
	assert_float(rank.value).is_equal(7.0)
	assert_int(_fixture.roster.profile("thief").draft.talents.vitality).is_equal(7)
	assert_bool(_controller.view_model().apply_allowed).is_true()
	assert_int(_edit_count).is_equal(1)
	assert_int(_fixture.roster.active_build().talents.vitality).is_equal(0)
	# A second actual Enter submits a structurally valid but over-budget draft.
	var over_budget := (_control("Talent_weapon_training") as SpinBox).get_line_edit()
	over_budget.grab_focus()
	await _settle_gui()
	over_budget.select_all()
	_gui_key(KEY_4, 52)
	_gui_key(KEY_ENTER)
	await _settle_gui()
	assert_int(_fixture.roster.profile("thief").draft.talents.weapon_training).is_equal(4)
	assert_bool(_controller.view_model().apply_allowed).is_false()
	assert_bool("超过" in _controller.view_model().qualification_text).is_true()
	(_control("ApplyBuild") as Button).pressed.emit()
	assert_bool("超过" in _hud.notice.text).is_true()
	assert_int(_operation_count).is_equal(0)
	assert_int(_applications.size()).is_equal(0)
	assert_int(_fixture.roster.active_build().talents.vitality).is_equal(0)
