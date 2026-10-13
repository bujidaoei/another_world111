class_name AWPlayerController
extends CharacterBody3D

signal hurt(amount: float)
signal died
signal dodge_started
signal shield_absorbed(amount: float)
const Result = preload("res://config/rule_result.gd")
const VisualConfig = preload("res://config/character_visuals_config.gd")
const Animator = preload("res://presentation/character_animator.gd")
var maximum_health := 100.0
var health := 100.0
var maximum_stamina := 100.0
var stamina := 100.0
var config: Dictionary = {}
var input_adapter: AWInputAdapter
var camera: Camera3D
var active := false
var aim_direction := Vector3.FORWARD
var defending := false
var visual: Node3D
var animation_player: AnimationPlayer
var animator: AWCharacterAnimator
var combat_state: AWCombatState
var character_id := ""
var visual_ready := false
var visual_error: Dictionary = {}
var _visual_configuration: Dictionary = {}
var _model_scenes: Dictionary = {}
var _weapon_scenes: Dictionary = {}
var dodge_remaining := 0.0
var _dodge_direction := Vector3.FORWARD
var _dodge_speed := 0.0
var _hit_flash := 0.0
var _weapon_mount: Node3D
var _visual_weapon_tier := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	collision_layer = 2
	collision_mask = 1 | 4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	var loaded := VisualConfig.load_file()
	if not loaded.ok:
		visual_error = loaded
		return
	var configured := configure_visuals(loaded.data)
	if not configured.ok:
		visual_error = configured

func configure_visuals(candidate: Dictionary) -> Dictionary:
	var checked := VisualConfig.validate(candidate)
	if not checked.ok:
		visual_error = checked
		return checked
	if not is_inside_tree():
		return Result.failure("character_visual_context_invalid", "角色必须加入场景后配置视觉。")
	var models: Dictionary = {}
	var weapons: Dictionary = {}
	for id: String in checked.data.characters:
		var definition: Dictionary = checked.data.characters[id]
		if not ResourceLoader.exists(definition.scene_path):
			visual_error = Result.failure("character_visual_asset_missing", "角色GLB尚未导入。")
			return visual_error
		var packed := load(definition.scene_path) as PackedScene
		if packed == null:
			return Result.failure("character_visual_asset_invalid", "角色资源不是场景。")
		var instance := packed.instantiate()
		var model := instance as Node3D
		if model == null:
			instance.free()
			return Result.failure("character_visual_asset_invalid", "角色场景根类型无效。")
		var inspection := Animator.inspect_model(model, definition, checked.data.animation.self_heal_filter_bones)
		model.free()
		if not inspection.ok:
			visual_error = inspection
			return inspection
		models[id] = packed
	for tier: String in checked.data.weapon.models:
		var path: String = checked.data.weapon.models[tier]
		if not ResourceLoader.exists(path):
			return Result.failure("weapon_visual_missing", "电枪GLB尚未导入。")
		var packed := load(path) as PackedScene
		if packed == null:
			return Result.failure("weapon_visual_invalid", "电枪资源不是场景。")
		var inspection := _inspect_weapon(packed)
		if not inspection.ok:
			return inspection
		weapons[tier] = packed
	var id := character_id if not character_id.is_empty() else str(checked.data.default_character)
	var assembled := _assemble_character(id, checked.data, models, weapons)
	if not assembled.ok:
		visual_error = assembled
		return assembled
	_visual_configuration = checked.data.duplicate(true)
	_model_scenes = models
	_weapon_scenes = weapons
	_commit_character(id, assembled.data)
	return Result.success()

func _inspect_weapon(packed: PackedScene) -> Dictionary:
	var instance := packed.instantiate()
	var model := instance as Node3D
	var valid := model != null
	var meshes := 0
	if valid:
		for node: Node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
				meshes += 1
	instance.free()
	if not valid or meshes == 0:
		return Result.failure("weapon_visual_invalid", "电枪场景必须有可见三维网格。")
	return Result.success()

func set_character(id: String) -> Dictionary:
	if not visual_ready:
		return Result.failure("character_visual_not_ready", "角色视觉配置未就绪。")
	if not _model_scenes.has(id):
		return Result.failure("character_unknown", "角色视觉身份未注册。")
	if id == character_id:
		return Result.success({"character_id": id, "changed": false})
	var assembled := _assemble_character(id, _visual_configuration, _model_scenes, _weapon_scenes)
	if not assembled.ok:
		return assembled
	_commit_character(id, assembled.data)
	return Result.success({"character_id": id, "changed": true})

func _assemble_character(id: String, settings: Dictionary, models: Dictionary, weapons: Dictionary) -> Dictionary:
	var model := (models[id] as PackedScene).instantiate() as Node3D
	model.name = "CharacterVisual"
	model.scale = Vector3.ONE * float(settings.model_scale)
	model.rotation.y = visual.rotation.y if is_instance_valid(visual) else 0.0
	model.visible = false
	add_child(model)
	var driver := Animator.new() as AWCharacterAnimator
	driver.name = "CharacterAnimator"
	model.add_child(driver)
	var configured := driver.configure(model, settings.characters[id], settings.animation)
	if not configured.ok:
		remove_child(model)
		model.queue_free()
		return configured
	var mount := Node3D.new()
	mount.name = "WeaponMount"
	var mount_position: Array = settings.weapon.mount_position
	mount.position = Vector3(float(mount_position[0]), float(mount_position[1]), float(mount_position[2]))
	model.add_child(mount)
	var tier := _visual_weapon_tier if _visual_weapon_tier > 0 else 1
	var weapon := (weapons[str(tier)] as PackedScene).instantiate() as Node3D
	weapon.scale = Vector3.ONE * float(settings.weapon.scale)
	mount.add_child(weapon)
	return Result.success({"model": model, "animator": driver, "mount": mount, "tier": tier})

func _commit_character(id: String, assembly: Dictionary) -> void:
	if is_instance_valid(visual):
		if is_instance_valid(animator):
			animator.stop()
		remove_child(visual)
		visual.queue_free()
	visual = assembly.model
	visual.name = "CharacterVisual"
	animator = assembly.animator
	animation_player = animator.player
	_weapon_mount = assembly.mount
	_visual_weapon_tier = int(assembly.tier)
	character_id = id
	visual.visible = true
	visual_ready = true
	visual_error = {}

func set_weapon_tier(tier: int) -> Dictionary:
	if not visual_ready or not _weapon_scenes.has(str(tier)):
		return Result.failure("weapon_visual_tier_invalid", "电枪视觉阶级未注册或配置未就绪。")
	if tier == _visual_weapon_tier:
		return Result.success({"tier": tier, "changed": false})
	var weapon := (_weapon_scenes[str(tier)] as PackedScene).instantiate() as Node3D
	weapon.scale = Vector3.ONE * float(_visual_configuration.weapon.scale)
	for child: Node in _weapon_mount.get_children():
		_weapon_mount.remove_child(child)
		child.queue_free()
	_weapon_mount.add_child(weapon)
	_visual_weapon_tier = tier
	return Result.success({"tier": tier, "changed": true})

func play_self_heal() -> Dictionary:
	if not active or health <= 0.0 or get_tree().paused:
		return Result.failure("gameplay_not_running", "当前状态不能播放施放表现。")
	if not visual_ready:
		return Result.failure("character_visual_not_ready", "角色视觉未就绪。")
	return animator.play_self_heal()

func configure(parameters: Dictionary) -> void:
	config = parameters.duplicate(true)
	maximum_health = float(config.get("maximum_health", 100.0))
	maximum_stamina = float(config.get("maximum_stamina", 100.0))
	health = maximum_health
	stamina = maximum_stamina

func _physics_process(delta: float) -> void:
	dodge_remaining = maxf(0.0, dodge_remaining - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	if not active or not is_instance_valid(input_adapter) or not is_instance_valid(camera) or not visual_ready:
		velocity = Vector3.ZERO
		if is_instance_valid(animator):
			animator.update_motion(0.0)
		return
	var axes := input_adapter.movement
	var cam_right := camera.global_basis.x
	var cam_forward := -camera.global_basis.z
	cam_right.y = 0.0
	cam_forward.y = 0.0
	var desired := (cam_right.normalized() * axes.x - cam_forward.normalized() * axes.y).limit_length(1.0)
	_update_aim()
	defending = input_adapter.defend_held and stamina > 2.0 and dodge_remaining <= 0.0
	if defending:
		stamina = maxf(0.0, stamina - float(config.get("defense_drain", 10.0)) * delta)
	else:
		stamina = minf(maximum_stamina, stamina + float(config.get("stamina_recovery", 19.0)) * delta)
	var speed := float(config.get("move_speed", 5.2)) * (0.45 if defending else 1.0)
	var horizontal := desired * speed
	if dodge_remaining > 0.0:
		horizontal = _dodge_direction * _dodge_speed
	velocity = Vector3(horizontal.x, -2.0, horizontal.z)
	move_and_slide()
	if visual:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-aim_direction.x, -aim_direction.z), 1.0 - exp(-18.0 * delta))
		var actual_velocity := get_real_velocity()
		animator.update_motion(Vector2(actual_velocity.x, actual_velocity.z).length())

func _update_aim() -> void:
	if input_adapter.aiming.length() > 0.15:
		var right := camera.global_basis.x
		var forward := -camera.global_basis.z
		var direction := right * input_adapter.aiming.x - forward * input_adapter.aiming.y
		direction.y = 0.0
		aim_direction = direction.normalized()
	elif not input_adapter.touch_mode:
		var mouse := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse)
		var direction := camera.project_ray_normal(mouse)
		var plane := Plane(Vector3.UP, global_position.y + 0.8)
		var point: Variant = plane.intersects_ray(origin, direction)
		if point is Vector3:
			var offset: Vector3 = point - global_position
			offset.y = 0.0
			if offset.length() > 0.1:
				aim_direction = offset.normalized()

func begin_dodge(effect_spec: Dictionary) -> Dictionary:
	if not active or health <= 0.0 or get_tree().paused or not is_instance_valid(input_adapter) or not is_instance_valid(camera) or dodge_remaining > 0.0:
		return Result.failure("dodge_motion_unavailable", "当前无法开始闪避运动。")
	if effect_spec.size() != 3 or effect_spec.get("kind") != "dodge" or not _dodge_number(effect_spec.get("duration"), 2.0) or not _dodge_number(effect_spec.get("speed"), 100.0):
		return Result.failure("dodge_effect_invalid", "闪避效果参数无效。")
	if not is_equal_approx(float(effect_spec.duration), float(config.get("dodge_duration", 0.24))) or not is_equal_approx(float(effect_spec.speed), float(config.get("dodge_speed", 12.0))):
		return Result.failure("dodge_effect_invalid", "闪避效果偏离当前已验证参数。")
	dodge_remaining = float(effect_spec.duration)
	_dodge_speed = float(effect_spec.speed)
	var axes := input_adapter.movement
	_dodge_direction = aim_direction
	if axes.length() > 0.1:
		var direction := camera.global_basis.x * axes.x + camera.global_basis.z * axes.y
		direction.y = 0.0
		_dodge_direction = direction.normalized()
	dodge_started.emit()
	return Result.success({"duration": dodge_remaining})

func _dodge_number(value: Variant, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= .001 and float(value) <= maximum

func take_damage(amount: float, source_position: Vector3) -> void:
	if not active or get_tree().paused or health <= 0.0 or dodge_remaining > 0.04 or not is_finite(amount) or amount < 0.0 or not source_position.is_finite():
		return
	var multiplier := 1.0
	var direction := (source_position - global_position).normalized()
	if defending and direction.dot(aim_direction) > 0.0:
		multiplier = 1.0 - float(config.get("defense_reduction", 0.7))
	var actual := amount * multiplier * (1.0 - clampf(float(config.get("passive_damage_reduction", 0.0)), 0.0, 0.4))
	if combat_state == null or not combat_state.ready:
		return
	var absorption := combat_state.absorb_damage(actual)
	if not absorption.ok:
		return
	if float(absorption.data.absorbed) > 0.0:
		shield_absorbed.emit(float(absorption.data.absorbed))
	var health_damage := float(absorption.data.health_damage)
	health = maxf(0.0, health - health_damage)
	if health_damage > 0.0:
		hurt.emit(health_damage)
	_hit_flash = 0.2
	if health <= 0.0:
		active = false
		died.emit()
