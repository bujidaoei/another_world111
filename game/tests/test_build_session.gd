extends GdUnitTestSuite
## Integration units use explicit injury/realm/position fixtures, never PC playtest evidence.

const Main = preload("res://presentation/main.tscn")
const Bindings = preload("res://platform/input_bindings.gd")
const Repository = preload("res://persistence/save_repository.gd")
var _root_directory: String
var _directories: Array[String] = []
var _sessions: Array[AWGameSession] = []
var _viewports: Array[SubViewport] = []
var _input_snapshot: Dictionary = {}

func before_test() -> void:
	get_tree().paused = false
	_root_directory = "user://tests/build_session/%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_directories.clear()
	for action: String in Bindings.ACTIONS:
		_input_snapshot[action] = {"exists": InputMap.has_action(action)}
		if InputMap.has_action(action):
			_input_snapshot[action]["events"] = InputMap.action_get_events(action)
			_input_snapshot[action]["deadzone"] = InputMap.action_get_deadzone(action)

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
	for action: String in _input_snapshot:
		if InputMap.has_action(action): InputMap.erase_action(action)
		if _input_snapshot[action].exists:
			InputMap.add_action(action, float(_input_snapshot[action].deadzone))
			for event: InputEvent in _input_snapshot[action].events: InputMap.action_add_event(action, event)
	_input_snapshot.clear()
	await get_tree().process_frame
	var allowed := ProjectSettings.globalize_path("user://tests/build_session").simplify_path()
	var base := ProjectSettings.globalize_path(_root_directory).simplify_path()
	assert_bool(base.begins_with(allowed + "/")).is_true()
	if not base.begins_with(allowed + "/"): return
	for directory: String in _directories:
		var path := ProjectSettings.globalize_path(directory).simplify_path()
		if path.begins_with(base + "/"):
			_cleanup_leaf(path.path_join("preferences"), path)
			_cleanup_leaf(path, base)
	_cleanup_leaf(base, allowed)

func _cleanup_leaf(path: String, allowed: String) -> void:
	assert_bool(path.begins_with(allowed + "/")).is_true()
	if not path.begins_with(allowed + "/") or not DirAccess.dir_exists_absolute(path): return
	var parent := DirAccess.open(path.get_base_dir())
	assert_object(parent).is_not_null()
	if parent == null: return
	assert_bool(parent.is_link(path)).is_false()
	if parent.is_link(path): return
	var directory := DirAccess.open(path)
	assert_array(directory.get_directories()).is_empty()
	if not directory.get_directories().is_empty(): return
	for name: String in directory.get_files(): assert_int(DirAccess.remove_absolute(path.path_join(name))).is_equal(OK)
	assert_int(DirAccess.remove_absolute(path)).is_equal(OK)

func _directory(suffix: String) -> String:
	var path := _root_directory.path_join(suffix)
	if not path in _directories: _directories.append(path)
	return path

func _session(suffix: String = "first", parent: Node = null) -> AWGameSession:
	var session := Main.instantiate() as AWGameSession
	session.save_directory = _directory(suffix)
	_sessions.append(session)
	if parent == null: add_child(session)
	else: parent.add_child(session)
	# Tests drive production methods explicitly; no incidental regeneration/checkpoint ticks.
	session.set_process(false)
	if session.player != null: session.player.set_physics_process(false)
	assert_bool(session._fatal_failure).is_false()
	if session._fatal_failure: return null
	assert_object(session.player).is_not_null()
	if session.player == null: return null
	return session

func _new_session(suffix: String = "first", parent: Node = null) -> AWGameSession:
	var session := _session(suffix, parent)
	if session == null: return null
	session._on_command("new_game")
	session._close_menu()
	assert_bool(session.session_started).is_true()
	assert_bool(session.save_blocked).is_false()
	return session

func _saved(session: AWGameSession) -> Dictionary:
	var saved: Dictionary = session.repository.load()
	assert_bool(saved.ok).is_true()
	return saved.data.duplicate(true)

func _fixture_realm_two(session: AWGameSession, ascend_weapon: bool = true) -> void:
	# Only an integration-unit prerequisite; this is not a played guardian victory.
	assert_bool(session.progress.award_experience(580, "fixture-realm-growth").ok).is_true()
	assert_bool(session.progress.complete_ascension("rain_warden", "fixture-realm-qualification", {"challenge_id": "rain_warden", "outcome": "victory", "run_id": "fixture-guardian-state", "defeated_enemy_ids": ["rain_warden"]}).ok).is_true()
	if ascend_weapon:
		assert_bool(session.inventory.grant({"scrap": 10, "alloy": 5}, "fixture-gear-materials").ok).is_true()
		assert_bool(session.equipment.ascend(session.inventory, session.active_weapon_id, 2, true, true, "fixture-gear-ascension", {"location": "camp", "at": "2026-10-13T12:00:00+08:00"}).ok).is_true()
	assert_bool(session._apply_equipment_stats()).is_true()

func _apply_build(session: AWGameSession, character: String, loadout: Array = ["pulse", "barrier"]) -> Dictionary:
	session._show_builds()
	assert_bool(session.build_controller.handle_intent("select_character", {"character_id": character}).ok).is_true()
	var build: Dictionary = session.roster.profile(character).draft
	build["skill_loadout"] = loadout.duplicate()
	assert_bool(session.roster.set_draft(character, build).ok).is_true()
	assert_bool(session.build_controller.refresh().ok).is_true()
	var applied: Dictionary = session.build_controller.handle_intent("apply", {"character_id": character})
	assert_bool(applied.ok).is_true()
	session._close_menu()
	return applied

func _semantic(value: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func test_real_main_controller_draft_apply_saves_domain_two_without_free_vitals() -> void:
	var session := _new_session()
	if session == null: return
	assert_bool(session.progress.award_experience(80, "fixture-talent-points").ok).is_true()
	session.player.health = session.player.maximum_health * 0.4
	session.player.stamina = 70.0
	var resources: Dictionary = session.inventory.snapshot().resources
	var weapon: Dictionary = session.inventory.get_equipment(session.active_weapon_id)
	var old_damage := float(session._stats.attack_damage)
	session._show_builds()
	assert_bool(session.build_controller.show("talents").ok).is_true()
	var rank := session.hud.find_child("Talent_vitality", true, false) as SpinBox
	assert_object(rank).is_not_null()
	rank.value = 4
	assert_float(session._stats.attack_damage).is_equal(old_damage)
	assert_int(session.roster.active_build().talents.vitality).is_equal(0)
	assert_float(session.player.maximum_health).is_equal(125.0)
	var button := session.hud.find_child("ApplyBuild", true, false) as Button
	button.pressed.emit()
	assert_int(session.roster.active_build().talents.vitality).is_equal(4)
	assert_float(session.player.maximum_health).is_equal(133.0)
	assert_float(session.player.health).is_equal_approx(53.2, 0.000001)
	assert_float(session.player.stamina).is_equal(70.0)
	assert_dict(session.inventory.snapshot().resources).is_equal(resources)
	assert_dict(session.inventory.get_equipment(session.active_weapon_id)).is_equal(weapon)
	var saved := _saved(session)
	assert_int(int(saved.domain_version)).is_equal(2)
	assert_int(int(saved.character_builds.profiles.thief.applied_build.talents.vitality)).is_equal(4)
	assert_float(float(saved.health)).is_equal_approx(session.player.health, 0.000001)

func test_real_barrier_cast_absorbs_player_damage_and_debits_stamina() -> void:
	var session := _new_session()
	if session == null: return
	var health := session.player.health
	var stamina := session.player.stamina
	session._cast_skill("barrier")
	assert_float(session.player.stamina).is_equal(stamina - 20.0)
	assert_float(session.combat.snapshot().effects.barrier_capacity).is_equal(24.0)
	session.player.take_damage(30.0, session.player.global_position + Vector3.FORWARD)
	assert_float(session.player.health).is_equal(health - 6.0)
	assert_float(session.combat.snapshot().effects.barrier_capacity).is_equal(0.0)
	assert_float(session.combat.cooldown_remaining("barrier")).is_equal(10.0)
	session._save_progress(false)
	assert_float(float(_saved(session).health)).is_equal(health - 6.0)

func test_real_focus_cast_increases_production_attack_against_registered_enemy() -> void:
	var session := _new_session()
	if session == null: return
	_fixture_realm_two(session, false)
	_apply_build(session, "thief", ["barrier", "focus"])
	session._begin_run("rain_court", false)
	for node: Node in session.enemy_root.get_children():
		(node as AWEnemyController).set_physics_process(false)
		node.position = Vector3(100.0 + node.get_index() * 4.0, 0.1, 100.0)
	var enemy := session.enemy_root.get_child(0) as AWEnemyController
	# A real registered actor at a controlled unobstructed position, not a damage substitute.
	enemy.global_position = session.player.global_position + Vector3.FORWARD * 2.0
	session.player.aim_direction = Vector3.FORWARD
	await get_tree().physics_frame
	session._cast_skill("focus")
	var before := enemy.health
	var damage := float(session._stats.attack_damage) * 1.15
	session._attack()
	assert_float(enemy.health).is_equal_approx(maxf(0.0, before - damage), 0.00001)
	assert_bool(session.combat.cooldown_remaining("attack") > 0.0).is_true()
	assert_bool(session.combat.cooldown_remaining("focus") > 0.0).is_true()
	assert_bool(session.expedition.defeated_enemy_ids.has(enemy.enemy_id)).is_equal(before <= damage)

func test_real_wandering_conductor_threshold_bridges_anchor_with_three_target_limit() -> void:
	for points: int in [7, 8]:
		var session := _new_session("anchor-threshold-" + str(points))
		if session == null: return
		_fixture_realm_two(session)
		var draft: Dictionary = session.roster.profile("thief").draft
		draft["talents"]["mobility"] = points
		assert_bool(session.roster.set_draft("thief", draft).ok).is_true()
		_apply_build(session, "thief")
		assert_int(session.progress.realm).is_equal(2)
		assert_int(session.progress.level).is_equal(30)
		assert_int(int(session.inventory.get_equipment(session.active_weapon_id).tier)).is_equal(2)
		assert_float(float(session._stats.chain_range)).is_equal(4.5)
		assert_int(int(session._stats.chain_targets)).is_equal(3)
		assert_float(float(session._stats.anchor_range)).is_equal(7.0 if points == 7 else 8.5)
		assert_bool(session._derived_build.active_resonances.has("wandering_conductor")).is_equal(points == 8)
		session._begin_run("rain_court", false)
		var actors: Array[AWEnemyController] = []
		for child: Node in session.enemy_root.get_children():
			var enemy := child as AWEnemyController
			enemy.set_physics_process(false)
			enemy.active = false
			enemy.global_position = Vector3(100.0 + child.get_index() * 4.0, 0.1, 100.0)
			# Registered scavengers share the same configured health; no enemy stat replacement.
			if child.get_index() in [0, 1, 3, 4]: actors.append(enemy)
		assert_int(actors.size()).is_equal(4)
		if actors.size() != 4: return
		var positions: Array[Vector3] = [Vector3(-3.0, 0.1, 1.0), Vector3(8.25, 0.1, 1.0), Vector3(8.25, 0.1, 4.0), Vector3(8.25, 0.1, 7.0)]
		var health_before: Array[float] = []
		for index: int in range(actors.size()):
			actors[index].active = true
			actors[index].global_position = positions[index]
			health_before.append(actors[index].health)
			assert_bool(session.expedition.enemy_ids().has(actors[index].enemy_id)).is_true()
		session.player.global_position = Vector3(4.75, 0.2, 3.5)
		session.player.aim_direction = Vector3.FORWARD
		await get_tree().physics_frame
		var stamina := session.player.stamina
		session._place_anchor()
		assert_int(session._anchors.size()).is_equal(1)
		if session._anchors.size() != 1: return
		var anchor: Node3D = session._anchors[0]
		assert_vector(anchor.global_position).is_equal_approx(Vector3(4.75, 0.2, 1.0), Vector3.ONE * 0.00001)
		assert_float(session.player.stamina).is_equal(stamina - 15.0)
		assert_float(session.combat.cooldown_remaining("anchor")).is_equal(3.0)
		var bridge_distance := (actors[0].global_position + Vector3.UP).distance_to(anchor.global_position)
		assert_float(bridge_distance).is_greater(7.0)
		assert_float(bridge_distance).is_less(8.5)
		session.player.global_position = Vector3(-5.0, 0.2, 1.0)
		session.player.aim_direction = Vector3.RIGHT
		await get_tree().physics_frame
		assert_object(session._find_target(session.player.global_position, Vector3.RIGHT, float(session._stats.attack_range), true, [])).is_same(actors[0])
		assert_object(session._find_target(actors[0].global_position + Vector3.UP, Vector3.ZERO, float(session._stats.chain_range), false, [actors[0]])).is_null()
		assert_object(session._find_target(anchor.global_position, Vector3.ZERO, float(session._stats.anchor_range), false, [actors[0]])).is_same(actors[1])
		assert_object(session._find_target(actors[1].global_position + Vector3.UP, Vector3.ZERO, float(session._stats.chain_range), false, [actors[0], actors[1]])).is_same(actors[2])
		assert_object(session._find_target(actors[2].global_position + Vector3.UP, Vector3.ZERO, float(session._stats.chain_range), false, [actors[0], actors[1], actors[2]])).is_same(actors[3])
		var world_before: Dictionary = session.progress.snapshot()
		var damage := float(session._stats.attack_damage)
		var falloff := float(session._stats.chain_falloff)
		session._attack()
		assert_float(actors[0].health).is_equal_approx(maxf(0.0, health_before[0] - damage), 0.00001)
		assert_float(actors[1].health).is_equal_approx(health_before[1] - (damage * falloff if points == 8 else 0.0), 0.00001)
		assert_float(actors[2].health).is_equal_approx(health_before[2] - (damage * falloff * falloff if points == 8 else 0.0), 0.00001)
		assert_float(actors[3].health).is_equal(health_before[3])
		assert_bool(session.combat.cooldown_remaining("attack") > 0.0).is_true()
		# Real tier-two affixes make the first hit lethal; the registered reward still settles normally.
		assert_bool(damage >= health_before[0]).is_true()
		assert_array(session.expedition.defeated_enemy_ids).contains_exactly([actors[0].enemy_id])
		assert_int(session.progress.experience).is_equal(int(world_before.experience) + int(session.rules.data.regions.rain_court.kill_experience))
		assert_int(session.progress.level).is_equal(int(world_before.level))
		assert_int(session.progress.banked_experience).is_equal(int(world_before.banked_experience))
		assert_int(int(session.expedition.pending_loot.currency)).is_equal(2)
		assert_int(int(session.expedition.snapshot().pending_coin_remainder)).is_equal(2)

func test_real_charged_guard_threshold_changes_cast_capacity_and_player_health_damage() -> void:
	for points: int in [7, 8]:
		var session := _new_session("barrier-threshold-" + str(points))
		if session == null: return
		_fixture_realm_two(session)
		var draft: Dictionary = session.roster.profile("thief").draft
		draft["talents"]["defense_efficiency"] = points
		assert_bool(session.roster.set_draft("thief", draft).ok).is_true()
		_apply_build(session, "thief")
		assert_int(session.progress.realm).is_equal(2)
		assert_int(session.progress.level).is_equal(30)
		assert_int(int(session.inventory.get_equipment(session.active_weapon_id).tier)).is_equal(2)
		assert_bool(session._derived_build.active_resonances.has("charged_guard")).is_equal(points == 8)
		assert_float(float(session._stats.passive_damage_reduction)).is_equal(0.0)
		assert_bool(session.player.defending).is_false()
		var health := session.player.health
		var stamina := session.player.stamina
		var capacity := 24.0 if points == 7 else 27.6
		session._cast_skill("barrier")
		assert_float(session.player.stamina).is_equal(stamina - 20.0)
		assert_float(float(session.combat.snapshot().effects.barrier_capacity)).is_equal_approx(capacity, 0.00001)
		assert_float(session.combat.cooldown_remaining("barrier")).is_equal(10.0)
		session.player.take_damage(30.0, session.player.global_position + Vector3.FORWARD)
		assert_float(session.player.health).is_equal_approx(health - (6.0 if points == 7 else 2.4), 0.00001)
		assert_float(float(session.combat.snapshot().effects.barrier_capacity)).is_equal(0.0)
		assert_float(session.combat.cooldown_remaining("barrier")).is_equal(10.0)

func test_real_recovery_family_survives_identity_preset_and_scene_reload() -> void:
	var first := _new_session()
	if first == null: return
	_apply_build(first, "healer")
	first.player.health = first.player.maximum_health * 0.4
	first.player.stamina = 80.0
	first._cast_skill("self_heal")
	assert_float(first.player.health / first.player.maximum_health).is_equal_approx(0.7, 0.000001)
	assert_float(first.player.stamina).is_equal(45.0)
	assert_float(first.combat.cooldown_remaining("self_heal")).is_equal(20.0)
	assert_float(first.combat.cooldown_remaining("recovery_family")).is_equal(20.0)
	assert_bool(first.roster.save_preset("healer", 0, "恢复流派").ok).is_true()
	var cooldowns: Dictionary = first.combat.snapshot()
	_apply_build(first, "thief")
	var medkits := first.inventory.count("medkit")
	var health := first.player.health
	first._use_consumable("medkit")
	assert_int(first.inventory.count("medkit")).is_equal(medkits)
	assert_float(first.player.health).is_equal(health)
	_apply_build(first, "healer")
	assert_bool(first.roster.load_preset_draft("healer", 0).ok).is_true()
	_apply_build(first, "healer")
	assert_dict(first.combat.snapshot()).is_equal(cooldowns)
	first._save_progress(false)
	var second := _session("first")
	if second == null: return
	assert_bool(get_tree().paused).is_true()
	assert_dict(second.combat.snapshot()).is_equal(cooldowns)
	second._on_command("continue")
	assert_str(second.roster.active_character_id).is_equal("healer")
	assert_float(second.player.health).is_equal_approx(health, 0.000001)
	assert_float(second.player.stamina).is_equal(45.0)
	assert_dict(second.combat.snapshot()).is_equal(cooldowns)
	second._use_consumable("rations")
	assert_int(second.inventory.count("rations")).is_equal(first.inventory.count("rations"))
	assert_float(second.player.health).is_equal_approx(health, 0.000001)

func test_real_item_use_prevents_self_heal_until_shared_gameplay_clock_expires() -> void:
	var session := _new_session()
	if session == null: return
	_apply_build(session, "healer")
	session.player.health = session.player.maximum_health * 0.2
	var count := session.inventory.count("medkit")
	session._use_consumable("medkit")
	assert_int(session.inventory.count("medkit")).is_equal(count - 1)
	assert_float(session.combat.cooldown_remaining("recovery_family")).is_equal(20.0)
	var health := session.player.health
	var stamina := session.player.stamina
	session._cast_skill("self_heal")
	assert_float(session.player.health).is_equal(health)
	assert_float(session.player.stamina).is_equal(stamina)
	assert_bool(session.combat.tick(20.0, false).ok).is_true()
	assert_float(session.combat.cooldown_remaining("recovery_family")).is_equal(20.0)
	assert_bool(session.combat.tick(20.0, true).ok).is_true()
	session._cast_skill("self_heal")
	assert_float(session.player.stamina).is_equal(stamina - 35.0)
	assert_bool(session.player.health > health).is_true()

func test_lethal_player_damage_returns_camp_clears_only_effects_and_preserves_cooldowns() -> void:
	var session := _new_session()
	if session == null: return
	_fixture_realm_two(session)
	_apply_build(session, "healer", ["barrier", "focus"])
	session._begin_run("rain_court", false)
	session._cast_skill("barrier")
	session._cast_skill("focus")
	var cooldowns: Dictionary = session.combat.snapshot().cooldowns
	var resources: Dictionary = session.inventory.snapshot().resources
	var world: Dictionary = session.progress.snapshot()
	session.player.take_damage(100000.0, session.player.global_position + Vector3.FORWARD)
	assert_bool(session.in_camp).is_true()
	assert_float(session.player.health).is_equal_approx(session.player.maximum_health * 0.35, 0.000001)
	assert_dict(session.combat.snapshot().cooldowns).is_equal(cooldowns)
	assert_float(session.combat.snapshot().effects.barrier_capacity).is_equal(0.0)
	assert_float(session.combat.snapshot().effects.focus_remaining).is_equal(0.0)
	assert_dict(session.inventory.snapshot().resources).is_equal(resources)
	assert_dict(session.progress.snapshot()).is_equal(world)
	assert_float(float(_saved(session).health)).is_equal_approx(session.player.health, 0.000001)

func test_zero_health_checkpoint_title_does_not_heal_continue_explicitly_recovers_failure() -> void:
	var first := _new_session()
	if first == null: return
	first._cast_skill("barrier")
	first.player.health = 0.0
	first.player.stamina = 40.0
	first._save_progress(false)
	var saved := _saved(first)
	assert_float(float(saved.health)).is_equal(0.0)
	var second := _session("first")
	if second == null: return
	assert_float(second.player.health).is_equal(0.0)
	assert_bool(second.session_started).is_false()
	assert_bool(get_tree().paused).is_true()
	assert_float(second.combat.cooldown_remaining("barrier")).is_equal(10.0)
	second._on_command("continue")
	assert_float(second.player.health).is_equal_approx(second.player.maximum_health * 0.35, 0.000001)
	assert_float(second.player.stamina).is_equal(40.0)
	assert_float(second.combat.cooldown_remaining("barrier")).is_equal(10.0)
	assert_float(second.combat.snapshot().effects.barrier_capacity).is_equal(0.0)
	assert_float(float(_saved(second).health)).is_equal_approx(second.player.health, 0.000001)

func test_future_domain_three_blocks_writes_and_new_journey_preserving_both_slots() -> void:
	var first := _new_session()
	if first == null: return
	var future := _saved(first)
	future["domain_version"] = 3
	future["future_build_domain"] = {"preserve": true}
	assert_bool(first.repository.save(future).ok).is_true()
	var hashes: Dictionary = {}
	for name: String in ["slot_a.json", "slot_b.json"]: hashes[name] = FileAccess.get_sha256(first.save_directory.path_join(name))
	var second := _session("first")
	if second == null: return
	assert_bool(second.save_blocked).is_true()
	assert_bool(second._future_domain).is_true()
	for action: String in ["new_game", "confirm_new", "continue"]: second._on_command(action)
	second._save_progress(false)
	assert_bool(second.session_started).is_false()
	for name: String in hashes: assert_str(FileAccess.get_sha256(first.save_directory.path_join(name))).is_equal(hashes[name])

func test_frozen_real_domain_one_save_migrates_without_copying_gear_or_resources() -> void:
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/domain1_real_save_slot.json"))
	var legacy: Dictionary = JSON.parse_string(envelope.payload_json)
	var repo := Repository.new()
	assert_bool(repo.configure(_directory("legacy")).ok).is_true()
	assert_bool(repo.save(legacy).ok).is_true()
	var session := _session("legacy")
	if session == null: return
	assert_bool(session.save_available).is_true()
	assert_str(session.active_weapon_id).is_equal(legacy.active_weapon_id)
	assert_str(_semantic(session.progress.snapshot())).is_equal(_semantic(legacy.world))
	assert_str(_semantic(session.inventory.snapshot().resources)).is_equal(_semantic(legacy.inventory.resources))
	assert_int(session.inventory.equipment_ids().size()).is_equal(legacy.inventory.equipment.size())
	for id: String in session.inventory.equipment_ids():
		var current: Dictionary = session.inventory.get_equipment(id)
		var original: Dictionary = legacy.inventory.equipment[id].duplicate(true)
		current.erase("equipped")
		original.erase("equipped")
		assert_str(_semantic(current)).is_equal(_semantic(original))
	for character: String in ["thief", "healer"]: assert_str(session.roster.profile(character).applied_build.weapon_id).is_equal(legacy.active_weapon_id)
	session._on_command("continue")
	assert_float(session.player.health).is_equal(float(legacy.health))
	assert_float(session.player.stamina).is_equal(float(legacy.stamina))
	session._save_progress(false)
	assert_int(int(_saved(session).domain_version)).is_equal(2)

func _earned_pending_rewards(session: AWGameSession) -> void:
	_fixture_realm_two(session)
	session._begin_run("rain_court", false)
	var enemies: Array[AWEnemyController] = []
	for node: Node in session.enemy_root.get_children():
		var enemy := node as AWEnemyController
		enemy.set_physics_process(false)
		enemy.position = Vector3(100.0 + node.get_index() * 4.0, 0.1, 100.0)
		enemies.append(enemy)
	for index: int in range(3):
		var enemy := enemies[index]
		enemy.global_position = session.player.global_position + Vector3.FORWARD * 2.0
		session.player.aim_direction = Vector3.FORWARD
		await get_tree().physics_frame
		session._attack()
		assert_bool(session.expedition.defeated_enemy_ids.has(enemy.enemy_id)).is_true()
		assert_bool(session.combat.tick(1.0, true).ok).is_true()
	for id: String in ["rain_scrap_01", "rain_scrap_02"]:
		session.player.global_position = session.world.resource_positions[id] + Vector3.UP * 0.2
		session._interact()
		assert_bool(session.expedition.gathered_node_ids.has(id)).is_true()
	assert_bool(session.expedition.objective_completed).is_true()
	assert_int(session._pending_equipment.size()).is_equal(1)

func test_settlement_capacity_failure_and_real_retry_commit_rewards_gear_remainder_once() -> void:
	var session := _new_session()
	if session == null: return
	await _earned_pending_rewards(session)
	var original: Dictionary = session.inventory.snapshot()
	var original_remainder := session.roster.thief_coin_remainder
	var world: Dictionary = session.progress.snapshot()
	var loot: Dictionary = session.expedition.pending_loot.duplicate(true)
	var remainder := int(session.expedition.snapshot().pending_coin_remainder)
	var drop: Dictionary = session._pending_equipment[0].duplicate(true)
	# Deliberate finite storage-capacity fixture; pending rewards were earned by attacks/interactions.
	session.rules.data.inventory["maximum_quantity"] = 9
	session._finish_run("evacuated")
	assert_bool(session.in_camp).is_false()
	assert_str(session._modal_mode).is_equal("settlement")
	assert_bool(session.expedition.rewards_committed).is_false()
	assert_dict(session.inventory.snapshot()).is_equal(original)
	assert_int(session.roster.thief_coin_remainder).is_equal(original_remainder)
	assert_int(session._pending_equipment.size()).is_equal(1)
	session.rules.data.inventory["maximum_quantity"] = 1000000
	session._on_command("retry_settlement")
	assert_bool(session.in_camp).is_true()
	assert_bool(session.expedition.rewards_committed).is_true()
	for resource: String in loot: assert_int(session.inventory.count(resource)).is_equal(int(original.resources[resource]) + int(loot[resource]))
	assert_dict(session.inventory.get_equipment(drop.instance_id)).is_equal(drop)
	assert_int(session.inventory.equipment_ids().size()).is_equal(original.equipment.size() + 1)
	assert_int(session.roster.thief_coin_remainder).is_equal(remainder)
	assert_dict(session.progress.snapshot()).is_equal(world)
	var once: Dictionary = session.inventory.snapshot()
	session._on_command("retry_settlement")
	session._finish_run("evacuated")
	assert_dict(session.inventory.snapshot()).is_equal(once)
	assert_int(session.roster.thief_coin_remainder).is_equal(remainder)

func test_abandon_pending_settlement_discards_rewards_without_failure_healing() -> void:
	var session := _new_session()
	if session == null: return
	await _earned_pending_rewards(session)
	session.player.health = session.player.maximum_health * 0.2
	var health := session.player.health
	var inventory: Dictionary = session.inventory.snapshot()
	var remainder := session.roster.thief_coin_remainder
	session.rules.data.inventory["maximum_quantity"] = 9
	session._finish_run("evacuated")
	assert_str(session._modal_mode).is_equal("settlement")
	session.rules.data.inventory["maximum_quantity"] = 1000000
	session._on_command("abandon_settlement")
	assert_bool(session.in_camp).is_true()
	assert_float(session.player.health).is_equal(health)
	assert_dict(session.inventory.snapshot()).is_equal(inventory)
	assert_int(session.roster.thief_coin_remainder).is_equal(remainder)
	assert_int(session._pending_equipment.size()).is_equal(0)

func _settle_layout() -> void:
	for frame: int in range(4): await get_tree().process_frame

@warning_ignore("unused_parameter")
func test_build_menu_both_logical_viewports_real_wheel_focus_and_gui_click_route(timeout := 7000) -> void:
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.own_world_3d = true
		add_child(viewport)
		_viewports.append(viewport)
		var session := _new_session("viewport-" + str(dimensions.x), viewport)
		if session == null: return
		viewport.notify_mouse_entered()
		session._show_builds()
		assert_bool(session.build_controller.show("talents").ok).is_true()
		await _settle_layout()
		var rect := session.hud.modal.get_global_rect()
		assert_float(rect.position.x).is_greater_equal(0.0)
		assert_float(rect.position.y).is_greater_equal(0.0)
		assert_float(rect.end.x).is_less_equal(float(dimensions.x))
		assert_float(rect.end.y).is_less_equal(float(dimensions.y))
		var tab := session.hud.find_child("BuildTab_talents", true, false) as Control
		assert_object(viewport.gui_get_focus_owner()).is_same(tab)
		var back := session.hud._modal_content.get_child(session.hud._modal_content.get_child_count() - 1) as Button
		var at := session.hud._modal_scroll.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		viewport.push_input(motion, true)
		for step: int in range(70):
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.position = at
			wheel.global_position = at
			wheel.pressed = true
			viewport.push_input(wheel, true)
			wheel = wheel.duplicate()
			wheel.pressed = false
			viewport.push_input(wheel, true)
			await get_tree().process_frame
		assert_int(session.hud._modal_scroll.scroll_vertical).is_greater(0)
		assert_bool(session.hud._modal_scroll.get_global_rect().encloses(back.get_global_rect())).is_true()
		at = back.get_global_rect().get_center()
		motion.position = at
		motion.global_position = at
		viewport.push_input(motion, true)
		assert_object(viewport.gui_get_hovered_control()).is_same(back)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = true
		viewport.push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		viewport.push_input(click, true)
		assert_str(session._modal_mode).is_equal("camp")
		assert_bool(session.input_adapter._mouse_attack).is_false()
