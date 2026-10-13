extends GdUnitTestSuite

const Player = preload("res://presentation/player_controller.gd")
const Config = preload("res://config/character_visuals_config.gd")
const Animator = preload("res://presentation/character_animator.gd")
const Fixture = preload("res://tests/build_fixture.gd")
var _players: Array[AWPlayerController] = []
var _obstacles: Array[Node3D] = []

func after_test() -> void:
	get_tree().paused = false
	for player: AWPlayerController in _players:
		remove_child(player)
		player.free()
	_players.clear()
	for obstacle: Node3D in _obstacles:
		remove_child(obstacle)
		obstacle.free()
	_obstacles.clear()
	await get_tree().process_frame

func _player(id: String = "thief") -> AWPlayerController:
	var player := Player.new() as AWPlayerController
	add_child(player)
	_players.append(player)
	assert_bool(player.visual_ready).is_true()
	assert_dict(player.visual_error).is_empty()
	assert_bool(player.set_character(id).ok).is_true()
	player.active = true
	player.set_physics_process(false)
	player.animator.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return player

func _advance(player: AWPlayerController, seconds: float) -> void:
	# Match normal fixed physics updates; a one-shot request starts on its first
	# process evaluation, so one giant delta is not an elapsed-frame simulation.
	var steps := maxi(1, ceili(seconds * 60.0))
	for step: int in range(steps):
		player.animator.tree.advance(seconds / steps)
	player.animator.skeleton.force_update_all_bone_transforms()

func _bone(player: AWPlayerController, name: String) -> Vector3:
	var skeleton := player.animator.skeleton
	return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin

func _motion_inputs(player: AWPlayerController) -> void:
	var adapter := AWInputAdapter.new()
	player.add_child(adapter)
	adapter.set_process(false)
	adapter.blocked = false
	adapter.touch_mode = true
	player.input_adapter = adapter
	var camera := Camera3D.new()
	player.add_child(camera)
	player.camera = camera

func _obstacle(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	add_child(body)
	body.position = position
	_obstacles.append(body)

func test_visual_configuration_rejects_wrong_types_paths_and_leg_or_gun_filters() -> void:
	var loaded := Config.load_file()
	assert_bool(loaded.ok).is_true()
	var invalid: Dictionary = loaded.data.duplicate(true)
	invalid.model_scale = "0.76"
	assert_bool(Config.validate(invalid).ok).is_false()
	invalid = loaded.data.duplicate(true)
	invalid.characters.thief.scene_path = "https://example.invalid/model.glb"
	assert_bool(Config.validate(invalid).ok).is_false()
	invalid = loaded.data.duplicate(true)
	invalid.animation.self_heal_filter_bones[0] = "Pelvis"
	assert_bool(Config.validate(invalid).ok).is_false()
	invalid = loaded.data.duplicate(true)
	invalid.animation.self_heal_filter_bones[1] = "Hand_R"
	assert_bool(Config.validate(invalid).ok).is_false()
	invalid = loaded.data.duplicate(true)
	invalid.animation.walk_nominal_speed = 0
	assert_bool(Config.validate(invalid).ok).is_false()

func test_true_skin_uses_tree_only_private_loop_resources_and_measured_mount() -> void:
	var player := _player("healer")
	assert_int(player.animator.skeleton.get_bone_count()).is_equal(17)
	assert_bool(player.animation_player.active).is_false()
	assert_bool(player.animation_player.is_playing()).is_false()
	assert_bool(player.animator.tree.active).is_true()
	assert_int(player.animation_player.get_animation("SelfHeal").loop_mode).is_equal(Animation.LOOP_NONE)
	assert_int(player.animation_player.get_animation("Walk").loop_mode).is_equal(Animation.LOOP_LINEAR)
	assert_vector(player.visual.scale).is_equal(Vector3.ONE * .76)
	assert_vector(player._weapon_mount.position).is_equal(Vector3(.42, 1.15, -.28))
	assert_vector((player._weapon_mount.get_child(0) as Node3D).scale).is_equal(Vector3.ONE * .62)
	var source := (load("res://assets/models/healer_robot.glb") as PackedScene).instantiate() as Node3D
	var source_player := source.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_object(source_player.get_animation("Walk")).is_not_same(player.animation_player.get_animation("Walk"))
	source.free()

func test_walk_rate_matches_actual_speed_and_real_bones_alternate_without_player_writes() -> void:
	var player := _player()
	player.animator.update_motion(2.584)
	_advance(player, .12)
	_advance(player, .04)
	var first := _bone(player, "Foot_L")
	_advance(player, .2)
	var second := _bone(player, "Foot_L")
	assert_float(first.distance_to(second)).is_greater(.2)
	assert_float(player.animator.walk_scale).is_equal_approx(1, .000001)
	player.animator.update_motion(5.168)
	assert_float(player.animator.walk_scale).is_equal_approx(2, .000001)
	player.animator.update_motion(0)
	_advance(player, .2)
	var playback := player.animator.tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	assert_str(str(playback.get_current_node())).is_equal("Idle")
	assert_bool(player.animation_player.is_playing()).is_false()

func test_healer_one_shot_keeps_feet_and_right_arm_base_tracks_and_returns_to_locomotion() -> void:
	var base := _player("healer")
	var repair := _player("healer")
	base.animator.update_motion(2.584)
	repair.animator.update_motion(2.584)
	_advance(base, .16)
	_advance(repair, .16)
	assert_bool(repair.play_self_heal().ok).is_true()
	assert_str(repair.play_self_heal().code).is_equal("character_animation_active")
	_advance(repair, 0)
	_advance(base, .5)
	_advance(repair, .5)
	assert_float(_bone(base, "Hand_L").distance_to(_bone(repair, "Hand_L"))).is_greater(.2)
	for bone: String in ["Foot_L", "Foot_R", "Shin_L", "Shin_R"]:
		assert_float(_bone(base, bone).distance_to(_bone(repair, bone))).is_less(.0001)
	var base_skeleton := base.animator.skeleton
	var repair_skeleton := repair.animator.skeleton
	for bone: String in ["Clavicle_R", "UpperArm_R", "Forearm_R", "Hand_R"]:
		assert_bool(base_skeleton.get_bone_pose_rotation(base_skeleton.find_bone(bone)).is_equal_approx(repair_skeleton.get_bone_pose_rotation(repair_skeleton.find_bone(bone)))).is_true()
	_advance(base, .6)
	_advance(repair, .6)
	assert_bool(bool(repair.animator.tree.get("parameters/Heal/active"))).is_false()
	assert_float(_bone(base, "Hand_L").distance_to(_bone(repair, "Hand_L"))).is_less(.001)
	var thief := _player()
	assert_str(thief.play_self_heal().code).is_equal("exclusive_skill_forbidden")

func test_identity_and_weapon_replacement_preserve_vitals_and_failed_configuration_is_atomic() -> void:
	var player := _player()
	var f := Fixture.create()
	player.combat_state = f.combat
	player.health = 40
	player.stamina = 30
	assert_bool(player.set_weapon_tier(2).ok).is_true()
	var shared := player.combat_state.snapshot()
	for index: int in range(12):
		assert_bool(player.set_character("healer" if index % 2 == 0 else "thief").ok).is_true()
		assert_int(player._weapon_mount.get_child_count()).is_equal(1)
		assert_int(player._visual_weapon_tier).is_equal(2)
		assert_float(player.health).is_equal(40.0)
		assert_float(player.stamina).is_equal(30.0)
		assert_dict(player.combat_state.snapshot()).is_equal(shared)
	var visual := player.visual
	assert_bool(player.set_character(player.character_id).ok).is_true()
	assert_object(player.visual).is_same(visual)
	assert_bool(player.set_weapon_tier(9).ok).is_false()
	assert_object(player.visual).is_same(visual)
	var invalid: Dictionary = Config.load_file().data
	invalid.characters.thief.scene_path = "res://assets/models/no_such_model.glb"
	assert_bool(player.configure_visuals(invalid).ok).is_false()
	assert_object(player.visual).is_same(visual)
	assert_bool(player.visual_ready).is_true()
	await get_tree().process_frame
	var visual_count := 0
	for child: Node in player.get_children():
		if child == player.visual:
			visual_count += 1
	assert_int(visual_count).is_equal(1)

func test_damage_consumes_real_shared_barrier_after_defense_and_dodge_never_recharges_resources() -> void:
	var player := _player()
	var f := Fixture.create()
	player.combat_state = f.combat
	var derived: Dictionary = f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory).data
	assert_bool(f.combat.cast("barrier", Fixture.combat_context(f), Fixture.vitals(f), derived, "shield-source").ok).is_true()
	var absorbed: Array[float] = []
	player.shield_absorbed.connect(func(amount: float) -> void: absorbed.append(amount))
	player.health = 100
	player.defending = true
	player.aim_direction = Vector3.FORWARD
	player.take_damage(20, Vector3.FORWARD)
	assert_float(player.health).is_equal(100.0)
	assert_float(absorbed[0]).is_equal_approx(6, .00001)
	player.defending = false
	player.take_damage(25, Vector3.FORWARD)
	assert_float(player.health).is_equal_approx(93, .00001)
	var adapter := AWInputAdapter.new()
	player.add_child(adapter)
	player.input_adapter = adapter
	var camera := Camera3D.new()
	player.add_child(camera)
	player.camera = camera
	player.configure(f.presentation.player)
	player.stamina = 0
	assert_bool(player.begin_dodge({"kind": "dodge", "duration": .24, "speed": 12}).ok).is_true()
	assert_float(player.stamina).is_equal(0.0)
	assert_float(f.combat.cooldown_remaining("dodge")).is_equal(0.0)
	assert_float(player.dodge_remaining).is_equal_approx(.24, .00001)

func test_actual_collision_resolved_speed_stops_walk_when_wall_blocks_requested_movement() -> void:
	var player := _player()
	var f := Fixture.create()
	player.configure(f.presentation.player)
	_motion_inputs(player)
	player.input_adapter.movement = Vector2.RIGHT
	player.position.y = .1
	_obstacle(Vector3(0, -.2, 0), Vector3(20, .4, 20))
	_obstacle(Vector3(1.7, 1, 0), Vector3(.4, 2, 10))
	player.animator.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	player.set_physics_process(true)
	for frame: int in range(4):
		await get_tree().physics_frame
	assert_float(player.animator.horizontal_speed).is_greater(4.0)
	assert_float(player.animator.walk_scale).is_equal_approx(player.animator.horizontal_speed / 2.584, .00001)
	for frame: int in range(55):
		await get_tree().physics_frame
	assert_float(player.position.x).is_greater(.3)
	assert_float(player.position.x).is_less(1.2)
	assert_float(player.animator.horizontal_speed).is_less(.04)
	var playback := player.animator.tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	assert_str(str(playback.get_current_node())).is_equal("Idle")
	assert_vector(player.input_adapter.movement).is_equal(Vector2.RIGHT)
	assert_bool(player.animation_player.is_playing()).is_false()

func test_pause_freezes_heal_bone_pose_and_dodge_motion_then_resumes() -> void:
	var player := _player("healer")
	var f := Fixture.create()
	player.configure(f.presentation.player)
	_motion_inputs(player)
	player.animator.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	player.set_physics_process(true)
	assert_bool(player.play_self_heal().ok).is_true()
	assert_bool(player.begin_dodge({"kind": "dodge", "duration": .24, "speed": 12}).ok).is_true()
	for frame: int in range(6):
		await get_tree().physics_frame
	player.animator.skeleton.force_update_all_bone_transforms()
	var remaining := player.dodge_remaining
	var pose := _bone(player, "Hand_L")
	var position := player.position
	get_tree().paused = true
	for frame: int in range(32):
		await get_tree().physics_frame
	player.animator.skeleton.force_update_all_bone_transforms()
	assert_float(player.dodge_remaining).is_equal(remaining)
	assert_vector(player.position).is_equal(position)
	assert_float(_bone(player, "Hand_L").distance_to(pose)).is_less(.00001)
	assert_bool(bool(player.animator.tree.get("parameters/Heal/active"))).is_true()
	assert_bool(player.play_self_heal().ok).is_false()
	assert_bool(player.begin_dodge({"kind": "dodge", "duration": .24, "speed": 12}).ok).is_false()
	get_tree().paused = false
	for frame: int in range(65):
		await get_tree().physics_frame
	assert_float(player.dodge_remaining).is_equal(0.0)
	assert_bool(bool(player.animator.tree.get("parameters/Heal/active"))).is_false()

func test_real_asset_preflight_rejects_unskinned_mesh_or_missing_bone_track_and_failed_reconfiguration_rolls_back() -> void:
	var loaded := Config.load_file()
	var model := (load(loaded.data.characters.thief.scene_path) as PackedScene).instantiate() as Node3D
	var mesh := model.find_child("thief_robot_Mesh", true, false) as MeshInstance3D
	if mesh == null:
		mesh = model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var skin := mesh.skin
	mesh.skin = null
	assert_bool(Animator.inspect_model(model, loaded.data.characters.thief, loaded.data.animation.self_heal_filter_bones).ok).is_false()
	mesh.skin = skin
	var source := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var library := source.get_animation_library("").duplicate(true) as AnimationLibrary
	source.remove_animation_library("")
	source.add_animation_library("", library)
	var walk := source.get_animation("Walk")
	var path := NodePath(str(loaded.data.characters.thief.skeleton_path) + ":Foot_L")
	walk.remove_track(walk.find_track(path, Animation.TYPE_ROTATION_3D))
	assert_str(Animator.inspect_model(model, loaded.data.characters.thief, loaded.data.animation.self_heal_filter_bones).code).is_equal("character_visual_clip_missing")
	model.free()
	var player := _player()
	var visual := player.visual
	var tree := player.animator.tree
	var broken: Dictionary = loaded.data.duplicate(true)
	broken.characters.healer.scene_path = "res://assets/models/lightning_rifle_t1.glb"
	assert_bool(player.configure_visuals(broken).ok).is_false()
	assert_object(player.visual).is_same(visual)
	assert_object(player.animator.tree).is_same(tree)
	assert_bool(tree.active).is_true()
	assert_bool(player.set_character("healer").ok).is_true()
	assert_str(player.character_id).is_equal("healer")

func test_damage_boundaries_pause_passive_reduction_and_death_emit_only_real_health_damage() -> void:
	var player := _player()
	var f := Fixture.create()
	player.combat_state = f.combat
	player.configure(f.presentation.player)
	player.config.passive_damage_reduction = .2
	player.defending = true
	player.aim_direction = Vector3.FORWARD
	var hurt: Array[float] = []
	var deaths: Array[bool] = []
	player.hurt.connect(func(amount: float) -> void: hurt.append(amount))
	player.died.connect(func() -> void: deaths.append(true))
	player.take_damage(20, Vector3.FORWARD)
	assert_float(player.health).is_equal_approx(95.2, .00001)
	assert_int(hurt.size()).is_equal(1)
	assert_float(hurt[0]).is_equal_approx(4.8, .00001)
	player.take_damage(-1, Vector3.FORWARD)
	player.take_damage(NAN, Vector3.FORWARD)
	player.take_damage(20, Vector3(INF, 0, 0))
	get_tree().paused = true
	player.take_damage(20, Vector3.FORWARD)
	get_tree().paused = false
	player.dodge_remaining = .1
	player.take_damage(20, Vector3.FORWARD)
	assert_float(player.health).is_equal_approx(95.2, .00001)
	assert_int(hurt.size()).is_equal(1)
	player.dodge_remaining = 0
	player.defending = false
	player.health = 3
	player.take_damage(10, Vector3.FORWARD)
	player.take_damage(10, Vector3.FORWARD)
	assert_float(player.health).is_equal(0.0)
	assert_bool(player.active).is_false()
	assert_int(deaths.size()).is_equal(1)
	assert_int(hurt.size()).is_equal(2)

func test_dodge_uses_applied_shared_cast_vitals_and_rejects_invalid_effect_without_partial_motion() -> void:
	var player := _player()
	var f := Fixture.create()
	player.combat_state = f.combat
	player.configure(f.presentation.player)
	_motion_inputs(player)
	var derived: Dictionary = f.evaluator.evaluate(f.roster.active_build(), f.progress, f.inventory).data
	var cast: Dictionary = f.combat.cast("dodge", Fixture.combat_context(f), Fixture.vitals(f), derived, "real-dodge-source")
	assert_bool(cast.ok).is_true()
	player.health = float(cast.data.new_vitals.health)
	player.stamina = float(cast.data.new_vitals.stamina)
	var stamina := player.stamina
	var shared: Dictionary = f.combat.snapshot()
	for invalid: Dictionary in [{"kind": "dodge", "duration": ".24", "speed": 12}, {"kind": "dodge", "duration": .5, "speed": 12}, {"kind": "dodge", "duration": .24, "speed": NAN}, {"kind": "dodge", "duration": .24, "speed": 12, "cost": 0}]:
		assert_bool(player.begin_dodge(invalid).ok).is_false()
		assert_float(player.dodge_remaining).is_equal(0.0)
		assert_float(player.stamina).is_equal(stamina)
		assert_dict(f.combat.snapshot()).is_equal(shared)
	assert_bool(player.begin_dodge(cast.data.effect_spec).ok).is_true()
	assert_float(player.stamina).is_equal(stamina)
	assert_dict(f.combat.snapshot()).is_equal(shared)
	assert_bool(player.begin_dodge(cast.data.effect_spec).ok).is_false()
