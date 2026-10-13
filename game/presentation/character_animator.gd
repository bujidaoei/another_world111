class_name AWCharacterAnimator
extends Node
## Sole runtime animation writer; AnimationPlayer owns private clip data only.

const Result = preload("res://config/rule_result.gd")
var tree: AnimationTree
var player: AnimationPlayer
var skeleton: Skeleton3D
var initialized := false
var horizontal_speed := 0.0
var walk_scale := 0.0
var _configuration: Dictionary = {}
var _definition: Dictionary = {}
var _playback: AnimationNodeStateMachinePlayback
var _wanted := "Idle"
var _has_heal := false

static func inspect_model(model: Node3D, definition: Dictionary, filter_bones: Array) -> Dictionary:
	var skeleton_node := model.get_node_or_null(NodePath(definition.skeleton_path)) as Skeleton3D
	var animation_node := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton_node == null or skeleton_node.get_bone_count() != 17 or animation_node == null:
		return Result.failure("character_visual_asset_invalid", "角色缺少已制作17骨架或动画库。")
	var skin_meshes := 0
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.skin != null and mesh_instance.skin.get_bind_count() == 17 and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0 and mesh_instance.get_node_or_null(mesh_instance.skeleton) == skeleton_node:
			skin_meshes += 1
	if skin_meshes != 1:
		return Result.failure("character_visual_asset_invalid", "角色必须有与17骨架绑定的真实蒙皮网格。")
	for clip: String in [definition.idle_clip, definition.walk_clip]:
		if not animation_node.has_animation(clip) or animation_node.get_animation(clip).length <= 0:
			return Result.failure("character_visual_clip_missing", "角色缺少真实站立/步态动作。")
		var animation := animation_node.get_animation(clip)
		for index: int in range(skeleton_node.get_bone_count()):
			var bone := skeleton_node.get_bone_name(index)
			var path := NodePath(str(definition.skeleton_path) + ":" + bone)
			var has_transform := false
			for type: Animation.TrackType in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				var track := animation.find_track(path, type)
				if track >= 0 and animation.track_get_key_count(track) > 0:
					has_transform = true
			if not has_transform:
				return Result.failure("character_visual_clip_missing", "站立/步态缺少真实骨骼轨道。")
		if clip == str(definition.walk_clip):
			for bone: String in ["Thigh_L", "Shin_L", "Foot_L", "Thigh_R", "Shin_R", "Foot_R"]:
				var track := animation.find_track(NodePath(str(definition.skeleton_path) + ":" + bone), Animation.TYPE_ROTATION_3D)
				if track < 0 or animation.track_get_key_count(track) < 2:
					return Result.failure("character_visual_clip_missing", "步态必须有左右腿关节运动轨道。")
	if not str(definition.self_heal_clip).is_empty():
		if not animation_node.has_animation(definition.self_heal_clip):
			return Result.failure("character_visual_clip_missing", "疗愈者缺少真实自疗动作。")
		var heal := animation_node.get_animation(definition.self_heal_clip)
		if heal.length <= 0:
			return Result.failure("character_visual_clip_missing", "自疗动作时长无效。")
		for bone: String in filter_bones:
			if skeleton_node.find_bone(bone) < 0 or heal.find_track(NodePath(str(definition.skeleton_path) + ":" + bone), Animation.TYPE_ROTATION_3D) < 0:
				return Result.failure("character_visual_filter_invalid", "自疗过滤未匹配真实骨骼轨道。")
	return Result.success()

func configure(model: Node3D, definition: Dictionary, configuration: Dictionary) -> Dictionary:
	if initialized or not is_inside_tree() or not model.is_inside_tree():
		return Result.failure("character_animator_context_invalid", "动画器必须在角色树中首次配置。")
	var checked := inspect_model(model, definition, configuration.self_heal_filter_bones)
	if not checked.ok:
		return checked
	_definition = definition.duplicate(true)
	_configuration = configuration.duplicate(true)
	skeleton = model.get_node(NodePath(definition.skeleton_path)) as Skeleton3D
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	player.stop()
	player.active = false
	for library_name: StringName in player.get_animation_library_list():
		var library := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, library)
	player.get_animation(definition.idle_clip).loop_mode = Animation.LOOP_LINEAR
	player.get_animation(definition.walk_clip).loop_mode = Animation.LOOP_LINEAR
	_has_heal = not str(definition.self_heal_clip).is_empty()
	if _has_heal:
		player.get_animation(definition.self_heal_clip).loop_mode = Animation.LOOP_NONE
	var locomotion := AnimationNodeStateMachine.new()
	locomotion.add_node("Idle", _clip(definition.idle_clip))
	var walk := AnimationNodeBlendTree.new()
	walk.add_node("Clip", _clip(definition.walk_clip))
	walk.add_node("Rate", AnimationNodeTimeScale.new())
	walk.connect_node("Rate", 0, "Clip")
	walk.connect_node("output", 0, "Rate")
	locomotion.add_node("Walk", walk)
	for pair: Array in [["Idle", "Walk"], ["Walk", "Idle"]]:
		var transition := AnimationNodeStateMachineTransition.new()
		transition.xfade_time = float(configuration.transition_seconds)
		locomotion.add_transition(pair[0], pair[1], transition)
	var graph := AnimationNodeBlendTree.new()
	graph.add_node("Locomotion", locomotion)
	if _has_heal:
		graph.add_node("RepairClip", _clip(definition.self_heal_clip))
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = float(configuration.self_heal_fadein)
		shot.fadeout_time = float(configuration.self_heal_fadeout)
		shot.autorestart = false
		shot.filter_enabled = true
		for bone: String in configuration.self_heal_filter_bones:
			shot.set_filter_path(NodePath(str(definition.skeleton_path) + ":" + bone), true)
		graph.add_node("Heal", shot)
		graph.connect_node("Heal", 0, "Locomotion")
		graph.connect_node("Heal", 1, "RepairClip")
		graph.connect_node("output", 0, "Heal")
	else:
		graph.connect_node("output", 0, "Locomotion")
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.root_node = tree.get_path_to(model)
	tree.active = true
	_playback = tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
	_playback.start("Idle")
	tree.set("parameters/Locomotion/Walk/Rate/scale", 0.0)
	tree.advance(0)
	initialized = true
	return Result.success()

func update_motion(speed: float) -> void:
	if not initialized or not is_finite(speed) or speed < 0:
		return
	horizontal_speed = speed
	walk_scale = speed / float(_configuration.walk_nominal_speed)
	tree.set("parameters/Locomotion/Walk/Rate/scale", walk_scale)
	var wanted := "Walk" if speed > float(_configuration.movement_threshold) else "Idle"
	if wanted != _wanted:
		_wanted = wanted
		_playback.travel(wanted)

func play_self_heal() -> Dictionary:
	if not initialized or not _has_heal:
		return Result.failure("exclusive_skill_forbidden", "当前角色没有自疗动作。")
	if bool(tree.get("parameters/Heal/active")) or int(tree.get("parameters/Heal/request")) == AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE:
		return Result.failure("character_animation_active", "自疗表现已在执行，不能重复触发。")
	tree.set("parameters/Heal/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return Result.success()

func stop() -> void:
	initialized = false
	if is_instance_valid(tree):
		tree.active = false

func _exit_tree() -> void:
	stop()

func _clip(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node
