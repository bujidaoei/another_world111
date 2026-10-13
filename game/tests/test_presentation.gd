extends GdUnitTestSuite

const Main = preload("res://presentation/main.tscn")
const Bindings = preload("res://platform/input_bindings.gd")
var _directory: String
var _sessions: Array[AWGameSession] = []
var _viewports: Array[SubViewport] = []
var _input_maps: Dictionary = {}

func before_test() -> void:
	get_tree().paused = false
	_directory = "user://tests/presentation/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	for action: String in Bindings.ACTIONS:
		_input_maps[action] = {"exists": InputMap.has_action(action)}
		if InputMap.has_action(action):
			_input_maps[action].events = InputMap.action_get_events(action)
			_input_maps[action].deadzone = InputMap.action_get_deadzone(action)

func after_test() -> void:
	get_tree().paused = false
	for session: AWGameSession in _sessions:
		if is_instance_valid(session):
			session.get_parent().remove_child(session)
			session.free()
	_sessions.clear()
	for viewport: SubViewport in _viewports:
		if is_instance_valid(viewport):
			remove_child(viewport)
			viewport.free()
	_viewports.clear()
	for action: String in _input_maps:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		if _input_maps[action].exists:
			InputMap.add_action(action, float(_input_maps[action].deadzone))
			for event: InputEvent in _input_maps[action].events:
				InputMap.action_add_event(action, event)
	_input_maps.clear()
	await get_tree().process_frame
	if _directory.begins_with("user://tests/presentation/"):
		var absolute := ProjectSettings.globalize_path(_directory).simplify_path()
		var allowed := ProjectSettings.globalize_path("user://tests/presentation").simplify_path()
		if absolute.begins_with(allowed + "/"):
			_cleanup_leaf(absolute.path_join("preferences"), absolute)
			_cleanup_leaf(absolute, allowed)

func _cleanup_leaf(absolute: String, allowed: String) -> void:
	assert_bool(absolute.begins_with(allowed + "/")).is_true()
	if not absolute.begins_with(allowed + "/") or not DirAccess.dir_exists_absolute(absolute):
		return
	var parent := DirAccess.open(absolute.get_base_dir())
	assert_object(parent).is_not_null()
	if parent == null:
		return
	assert_bool(parent.is_link(absolute)).is_false()
	if parent.is_link(absolute):
		return
	var directory := DirAccess.open(absolute)
	assert_object(directory).is_not_null()
	if directory == null:
		return
	# Fixtures own only these two leaf directories; never recursively delete an
	# unexpected child or follow a directory link during test cleanup.
	assert_array(directory.get_directories()).is_empty()
	for file_name: String in directory.get_files():
		assert_int(DirAccess.remove_absolute(absolute.path_join(file_name))).is_equal(OK)
	assert_int(DirAccess.remove_absolute(absolute)).is_equal(OK)

func _session() -> AWGameSession:
	var session := Main.instantiate() as AWGameSession
	session.save_directory = _directory
	_sessions.append(session)
	add_child(session)
	return session

func _new_game_session() -> AWGameSession:
	var session := _session()
	session._on_command("new_game")
	session._close_menu()
	return session

func _touch(index: int, pressed: bool, position: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	return event

func test_real_main_scene_initializes_title_and_original_assets_without_save_mutation() -> void:
	var session := _session()
	assert_object(session.player).is_not_null()
	assert_object(session.camera_rig.camera).is_not_null()
	assert_object(session.world).is_not_null()
	assert_bool(session.rules.ready).is_true()
	assert_bool(session.hud.modal.visible).is_true()
	assert_bool(session.input_adapter.blocked).is_true()
	assert_bool(session.session_started).is_false()
	assert_str(session.save_directory).is_equal(_directory)
	assert_bool(FileAccess.file_exists(_directory.path_join("slot_a.json"))).is_false()
	assert_bool(session.inventory.get_equipment("starter-lightning").is_empty()).is_false()
	assert_bool(ResourceLoader.exists("res://assets/models/survivor_robot.glb")).is_true()
	assert_bool(session.player.visual.get_child_count() > 0).is_true()

@warning_ignore("unused_parameter")
func test_south_boundary_prevents_falling_outside_the_playable_floor(timeout := 6000) -> void:
	var session := _new_game_session()
	session.input_adapter.set_process(false)
	session.input_adapter.movement = Vector2(0, 1)
	session.camera_rig.set_process(false)
	session.camera_rig.rotation = Vector3.ZERO
	session.player.global_position = Vector3(0, 0.2, 15)
	for frame: int in range(100):
		await get_tree().physics_frame
	assert_float(session.player.global_position.z).is_less(16.0)
	assert_float(session.player.global_position.y).is_greater(-0.5)
	assert_bool(session.player.active).is_true()
	assert_float(session.player.health).is_equal(session.player.maximum_health)

func test_touch_reset_releases_both_sticks_and_accepts_a_new_finger() -> void:
	var session := _new_game_session()
	session.hud.set_touch_visible(true)
	var move: AWVirtualStick = session.hud._sticks[0]
	var aim: AWVirtualStick = session.hud._sticks[1]
	move._gui_input(_touch(3, true, Vector2(120, 75)))
	aim._gui_input(_touch(4, true, Vector2(120, 75)))
	assert_int(move.finger).is_equal(3)
	assert_int(aim.finger).is_equal(4)
	assert_bool(session.input_adapter._touch_attack).is_true()
	session._set_menu_block(true)
	assert_int(move.finger).is_equal(-1)
	assert_int(aim.finger).is_equal(-1)
	assert_vector(session.input_adapter._touch_move).is_equal(Vector2.ZERO)
	assert_vector(session.input_adapter._touch_aim).is_equal(Vector2.ZERO)
	assert_bool(session.input_adapter._touch_attack).is_false()
	session._set_menu_block(false)
	move._gui_input(_touch(5, true, Vector2(30, 75)))
	assert_int(move.finger).is_equal(5)
	assert_float(session.input_adapter._touch_move.x).is_less(0.0)
	move._gui_input(_touch(5, false, Vector2(30, 75)))
	assert_int(move.finger).is_equal(-1)

func test_touch_visibility_and_focus_loss_clear_hold_state_and_pause_game() -> void:
	var session := _new_game_session()
	session.hud.set_touch_visible(true)
	var stick: AWVirtualStick = session.hud._sticks[0]
	stick._gui_input(_touch(3, true, Vector2(120, 75)))
	stick.hide()
	assert_int(stick.finger).is_equal(-1)
	assert_vector(stick.value).is_equal(Vector2.ZERO)
	stick.show()
	stick._gui_input(_touch(5, true, Vector2(120, 75)))
	session.input_adapter.set_touch_defense(true)
	session._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_int(stick.finger).is_equal(-1)
	assert_bool(session.input_adapter._touch_defend).is_false()
	assert_bool(session.input_adapter._touch_attack).is_false()
	assert_bool(session.input_adapter.blocked).is_true()
	assert_bool(get_tree().paused).is_true()
	session._close_menu()
	assert_bool(get_tree().paused).is_false()
	assert_bool(session.input_adapter._touch_defend).is_false()

func test_enemy_prepared_attack_expires_after_player_leaves_aggro_range() -> void:
	var session := _new_game_session()
	session.player.set_physics_process(false)
	session.player.global_position = Vector3(0, 0.2, 14)
	var enemy := AWEnemyController.new()
	enemy.setup("unit-only-spitter", "spitter", session.parameters.enemy, session.player)
	enemy.set_physics_process(false)
	session.enemy_root.add_child(enemy)
	enemy.global_position = Vector3(0, 0.2, -10)
	enemy._prepared = true
	enemy.windup = 0.1
	enemy._attack_position = Vector3(0, 0.2, -9)
	var health := session.player.health
	enemy._physics_process(0.2)
	assert_bool(enemy._prepared).is_false()
	assert_float(enemy.windup).is_less_equal(0.0)
	assert_float(session.player.health).is_equal(health)
	assert_float(enemy.cooldown).is_equal(float(session.parameters.enemy.attack_cooldown))

func test_pause_stops_ai_windup_and_combat_cooldowns_until_resume() -> void:
	var session := _new_game_session()
	session._begin_run("rain_court", false)
	session.player.set_physics_process(false)
	var enemy: AWEnemyController = session.enemy_root.get_child(0)
	enemy._prepared = true
	enemy.windup = 1.0
	session._attack_cooldown = 2.0
	session._pulse_cooldown = 4.0
	session._show_pause()
	for frame: int in range(12):
		await get_tree().process_frame
	assert_float(enemy.windup).is_equal(1.0)
	assert_float(session._attack_cooldown).is_equal(2.0)
	assert_float(session._pulse_cooldown).is_equal(4.0)
	assert_bool(session.input_adapter.blocked).is_true()
	session._close_menu()
	for frame: int in range(4):
		await get_tree().physics_frame
	assert_float(enemy.windup).is_less(1.0)
	assert_float(session._attack_cooldown).is_less(2.0)

func test_viewport_ui_dispatch_consumes_mouse_attack_before_world_adapter() -> void:
	var session := _new_game_session()
	assert_bool(session.input_adapter.blocked).is_false()
	var button := Button.new()
	button.text = "UI input consumer"
	button.position = Vector2(600, 300)
	button.size = Vector2(180, 70)
	session.hud.root.add_child(button)
	await get_tree().process_frame
	var location := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = location
	motion.global_position = location
	get_viewport().push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = location
	press.global_position = location
	get_viewport().push_input(press, true)
	assert_bool(get_viewport().is_input_handled()).is_true()
	assert_bool(session.input_adapter._mouse_attack).is_false()
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)
	assert_bool(session.input_adapter._mouse_attack).is_false()
	assert_array(session.input_adapter.queued_actions).is_empty()

func test_save_and_fresh_scene_restore_exact_health_stamina_and_camp_checkpoint() -> void:
	var session := _new_game_session()
	session.player.set_physics_process(false)
	session.player.health = 42.5
	session.player.stamina = 31.25
	session._save_progress(false)
	assert_bool(session.save_available).is_true()
	var saved: Dictionary = session.repository.load()
	assert_bool(saved.ok).is_true()
	assert_float(float(saved.data.health)).is_equal(42.5)
	assert_float(float(saved.data.stamina)).is_equal(31.25)
	var restored := _session()
	restored.player.set_physics_process(false)
	assert_bool(restored.save_available).is_true()
	assert_float(restored.player.health).is_equal(42.5)
	assert_float(restored.player.stamina).is_equal(31.25)
	assert_bool(restored.in_camp).is_true()
	assert_bool(restored.hud.modal.visible).is_true()
	assert_dict(restored.progress.snapshot()).is_equal(session.progress.snapshot())
	assert_dict(restored.inventory.snapshot()).is_equal(saved.data.inventory)
	for resource: String in session.rules.data.resources:
		assert_int(restored.inventory.count(resource)).is_equal(session.inventory.count(resource))
	assert_dict(restored.inventory.get_equipment("starter-lightning").history).is_equal(saved.data.inventory.equipment["starter-lightning"].history)

func test_rejected_domain_restore_does_not_partially_change_active_progress() -> void:
	var session := _new_game_session()
	var original_world := session.progress.snapshot()
	var original_inventory := session.inventory.snapshot()
	var saved: Dictionary = session.repository.load().data
	# This is a unit fixture for validation; it does not award gameplay experience.
	saved.world.level = 2
	saved.world.earned_talent_points = 1
	saved.inventory.resources.scrap = -1
	assert_bool(session._restore_payload(saved).ok).is_false()
	assert_dict(session.progress.snapshot()).is_equal(original_world)
	assert_dict(session.inventory.snapshot()).is_equal(original_inventory)

func test_wrong_settings_types_are_rejected_without_partial_restore_or_script_errors() -> void:
	var session := _new_game_session()
	var saved: Dictionary = session.repository.load().data
	var original_world := session.progress.snapshot()
	var original_inventory := session.inventory.snapshot()
	var original_bindings := session.input_adapter.snapshot_bindings()
	var original_settings := session.settings.duplicate(true)
	for wrong_type: Variant in [null, true, 1, "invalid", []]:
		var invalid := saved.duplicate(true)
		invalid.world.level = 2
		invalid.world.earned_talent_points = 1
		invalid.settings = wrong_type
		var result: Dictionary = session._restore_payload(invalid)
		assert_bool(result.ok).is_false()
		assert_dict(session.progress.snapshot()).is_equal(original_world)
		assert_dict(session.inventory.snapshot()).is_equal(original_inventory)
		assert_dict(session.settings).is_equal(original_settings)
		assert_dict(session.input_adapter.snapshot_bindings()).is_equal(original_bindings)

func _session_in_viewport(dimensions: Vector2i) -> AWGameSession:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.own_world_3d = true
	add_child(viewport)
	_viewports.append(viewport)
	var session := Main.instantiate() as AWGameSession
	session.save_directory = _directory
	_sessions.append(session)
	viewport.add_child(session)
	# A detached SubViewport has no SubViewportContainer to report mouse entry.
	# This is required by Viewport.push_input for real GUI hover/click routing.
	viewport.notify_mouse_entered()
	return session

func _settle_layout() -> void:
	for frame: int in range(4):
		await get_tree().process_frame

func _assert_modal_bounds(session: AWGameSession, dimensions: Vector2i) -> void:
	var rect := session.hud.modal.get_global_rect()
	assert_float(rect.position.x).is_greater_equal(0.0)
	assert_float(rect.position.y).is_greater_equal(0.0)
	assert_float(rect.end.x).is_less_equal(float(dimensions.x))
	assert_float(rect.end.y).is_less_equal(float(dimensions.y))
	assert_float(rect.size.x).is_greater(300.0)
	assert_float(rect.size.y).is_greater(300.0)

func test_modal_bounds_fit_both_supported_logical_viewports() -> void:
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		var session := _session_in_viewport(dimensions)
		await _settle_layout()
		_assert_modal_bounds(session, dimensions)
		session._show_camp()
		await _settle_layout()
		_assert_modal_bounds(session, dimensions)
		session._show_workbench()
		await _settle_layout()
		_assert_modal_bounds(session, dimensions)
		session.hud.show_settings(session.settings)
		await _settle_layout()
		_assert_modal_bounds(session, dimensions)

@warning_ignore("unused_parameter")
func test_long_fusion_menu_scrolls_with_real_wheel_events_and_last_button_is_clickable(timeout := 7000) -> void:
	var session := _session_in_viewport(Vector2i(1280, 720))
	session._new_game()
	# Unit-only inventory fixture for displaying the actual fusion menu.
	session.bench_built = true
	session.inventory.grant({"currency": 30, "scrap": 30}, "unit-menu-materials")
	var item: Dictionary = session.equipment.create_drop("unit-material", 1, "rare", 4, {"location": "unit-fixture", "level": 1, "acquired_at": "2026-10-13T00:00:00Z"}, 4).data.equipment
	session.inventory.add_equipment(item)
	session._show_fusion()
	var body: Label = session.hud._modal_content.get_child(1)
	body.text += "\n长文本布局验证：候选条件说明。".repeat(70)
	await _settle_layout()
	_assert_modal_bounds(session, Vector2i(1280, 720))
	var last_button := session.hud._modal_content.get_child(session.hud._modal_content.get_child_count() - 1) as Button
	var viewport := session.get_viewport()
	var at := session.hud._modal_scroll.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	for step: int in range(90):
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = at
		wheel.global_position = at
		viewport.push_input(wheel, true)
		var wheel_release := wheel.duplicate() as InputEventMouseButton
		wheel_release.pressed = false
		viewport.push_input(wheel_release, true)
		await get_tree().process_frame
	assert_int(session.hud._modal_scroll.scroll_vertical).is_greater(0)
	assert_bool(session.hud._modal_scroll.get_global_rect().encloses(last_button.get_global_rect())).is_true()
	at = last_button.get_global_rect().get_center()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	assert_object(viewport.gui_get_hovered_control()).is_same(last_button)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.global_position = at
	click.pressed = true
	viewport.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	viewport.push_input(click, true)
	assert_str(session._modal_mode).is_equal("workbench")
	assert_bool(session.input_adapter._mouse_attack).is_false()

func test_anchor_timeout_after_expedition_cleanup_does_not_capture_freed_nodes() -> void:
	var session := _new_game_session()
	# Legal unit fixture for testing node lifetime, separate from the real-input run.
	session.progress.award_experience(580, "unit-qualification")
	session.progress.complete_ascension("rain_warden", "unit-ascension", {"challenge_id": "rain_warden", "run_id": "unit-trial", "defeated_enemy_ids": ["rain_warden"], "outcome": "victory"})
	session.inventory.grant({"scrap": 10, "alloy": 5}, "unit-equipment-materials")
	assert_bool(session.equipment.ascend(session.inventory, session.active_weapon_id, 2, true, true, "unit-equipment-ascension", {"location": "unit-fixture", "at": "2026-10-13T00:00:00Z"}).ok).is_true()
	session._apply_equipment_stats()
	session.parameters.weapon.anchor_lifetime = 0.05
	session._begin_run("rain_court", false)
	session._place_anchor()
	assert_int(session._anchors.size()).is_equal(1)
	var reference: WeakRef = weakref(session._anchors[0])
	session._finish_run("evacuated")
	await get_tree().process_frame
	assert_that(reference.get_ref()).is_null()
	assert_array(session._anchors).is_empty()
	await await_millis(160)
	assert_array(session._anchors).is_empty()
	assert_bool(session.in_camp).is_true()
	assert_bool(session.player.active).is_true()

func test_camp_command_guards_reject_active_encounter_without_resource_or_health_changes() -> void:
	var session := _new_game_session()
	# Resources and facility are unit fixtures; no gameplay reward is being asserted.
	session.inventory.grant({"currency": 40, "scrap": 20, "crystal": 4}, "unit-guard-resources")
	session.bench_built = true
	session._begin_run("rain_court", false)
	session.player.health = 42.0
	var original := session.inventory.snapshot()
	for action: String in ["camp", "workbench", "fusion", "craft_medkit", "buy_rations", "use_rations", "expand", "advance"]:
		session._on_command(action)
		assert_dict(session.inventory.snapshot()).is_equal(original)
		assert_float(session.player.health).is_equal(42.0)
		assert_bool(session.hud.modal.visible).is_false()
		assert_bool(session.in_camp).is_false()
		assert_int(session.expedition.state).is_equal(AWExpeditionState.State.ACTIVE)

func test_workbench_mutations_require_a_built_facility() -> void:
	var session := _new_game_session()
	session.inventory.grant({"currency": 40, "scrap": 20, "crystal": 4}, "unit-facility-resources")
	var original := session.inventory.snapshot()
	for action: String in ["craft_medkit", "buy_rations", "expand", "advance", "confirm_fusion"]:
		session._on_command(action)
		assert_dict(session.inventory.snapshot()).is_equal(original)
		assert_bool(session.bench_built).is_false()

func test_binding_payload_roundtrip_and_failed_map_restore_are_atomic_with_world() -> void:
	var session := _new_game_session()
	assert_bool(session.input_adapter.set_binding("move_forward", KEY_I).ok).is_true()
	session._save_progress(false)
	var saved: Dictionary = session.repository.load().data
	assert_int(int(saved.input_bindings.bindings.move_forward)).is_equal(KEY_I)
	var restored := _session()
	assert_int(restored.input_adapter.bindings.key_for("move_forward")).is_equal(KEY_I)
	var original_world := restored.progress.snapshot()
	var original_bindings := restored.input_adapter.snapshot_bindings()
	var invalid := saved.duplicate(true)
	invalid.world.level = 2
	invalid.world.earned_talent_points = 1
	invalid.input_bindings.bindings.move_forward = KEY_ENTER
	assert_bool(restored._restore_payload(invalid).ok).is_false()
	assert_dict(restored.progress.snapshot()).is_equal(original_world)
	assert_dict(restored.input_adapter.snapshot_bindings()).is_equal(original_bindings)

func test_restore_validates_nonactive_equipment_and_rejects_active_over_realm_item() -> void:
	var session := _new_game_session()
	var saved: Dictionary = session.repository.load().data
	var original_world := session.progress.snapshot()
	var original_inventory := session.inventory.snapshot()
	var invalid := saved.duplicate(true)
	invalid.inventory.equipment["unit-unused"] = invalid.inventory.equipment[session.active_weapon_id].duplicate(true)
	invalid.inventory.equipment["unit-unused"].instance_id = "unit-unused"
	invalid.inventory.equipment["unit-unused"].affixes[0].value = 999
	assert_bool(session._restore_payload(invalid).ok).is_false()
	assert_dict(session.inventory.snapshot()).is_equal(original_inventory)
	invalid = saved.duplicate(true)
	invalid.inventory.equipment[session.active_weapon_id] = session.equipment.create_drop(session.active_weapon_id, 2, "rare", 4, {"location": "unit-fixture", "level": 1, "acquired_at": "2026-10-13T00:00:00Z"}, 4).data.equipment
	assert_bool(session._restore_payload(invalid).ok).is_false()
	assert_dict(session.progress.snapshot()).is_equal(original_world)
	assert_dict(session.inventory.snapshot()).is_equal(original_inventory)

func _slot_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	var directory := DirAccess.open(_directory)
	if directory != null:
		for file_name: String in directory.get_files():
			hashes[file_name] = FileAccess.get_sha256(_directory.path_join(file_name))
	return hashes

func test_future_progress_domain_is_blocked_and_title_commands_preserve_both_slots() -> void:
	var session := _new_game_session()
	var saved: Dictionary = session.repository.load().data
	assert_int(int(saved.domain_version)).is_equal(1)
	# This is a future-format unit fixture, not a fabricated gameplay result.
	var future := saved.duplicate(true)
	future.domain_version = 2
	future["character_builds"] = {"schema_version": 1, "unrecognized_future_content": true}
	var written: Dictionary = session.repository.save(future)
	assert_str(str(written.code)).is_equal("saved")
	assert_bool(written.ok).is_true()
	if not written.ok:
		return
	var before := _slot_hashes()
	assert_int(before.size()).is_equal(2)
	var restored := _session()
	assert_bool(restored.save_blocked).is_true()
	assert_bool(restored._future_domain).is_true()
	assert_bool(restored.session_started).is_false()
	for action: String in ["new_game", "confirm_new", "continue"]:
		restored._on_command(action)
		assert_bool(restored.session_started).is_false()
		assert_bool(restored.save_blocked).is_true()
		assert_dict(_slot_hashes()).is_equal(before)
	restored._save_progress(false)
	assert_dict(_slot_hashes()).is_equal(before)
	var found_new_game := false
	for child: Node in restored.hud._modal_content.get_children():
		if child is Button and child.text == "开始新旅程":
			found_new_game = true
			assert_bool(child.disabled).is_true()
	assert_bool(found_new_game).is_true()

func test_progress_domain_legacy_is_supported_and_invalid_versions_are_atomic() -> void:
	var session := _new_game_session()
	var saved: Dictionary = session.repository.load().data
	var original_world := session.progress.snapshot()
	var original_inventory := session.inventory.snapshot()
	var original_bindings := session.input_adapter.snapshot_bindings()
	for version: Variant in [null, true, 0, -1, 1.5, "1", NAN, INF]:
		var invalid := saved.duplicate(true)
		invalid.domain_version = version
		invalid.world.level = 2
		invalid.world.earned_talent_points = 1
		assert_bool(session._restore_payload(invalid).ok).is_false()
		assert_dict(session.progress.snapshot()).is_equal(original_world)
		assert_dict(session.inventory.snapshot()).is_equal(original_inventory)
		assert_dict(session.input_adapter.snapshot_bindings()).is_equal(original_bindings)
	var legacy := saved.duplicate(true)
	legacy.erase("domain_version")
	assert_bool(session._restore_payload(legacy).ok).is_true()
	assert_dict(session.progress.snapshot()).is_equal(original_world)
	assert_dict(session.inventory.snapshot()).is_equal(saved.inventory)
