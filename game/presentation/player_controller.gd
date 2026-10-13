class_name AWPlayerController
extends CharacterBody3D

signal hurt(amount: float)
signal died
signal dodge_started
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
var dodge_remaining := 0.0
var dodge_cooldown := 0.0
var _dodge_direction := Vector3.FORWARD
var _hit_flash := 0.0
var _weapon_mount: Node3D
var _visual_weapon_tier := 0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.7
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	var model_path := "res://assets/models/survivor_robot.glb"
	if ResourceLoader.exists(model_path):
		visual = (load(model_path) as PackedScene).instantiate() as Node3D
		visual.scale = Vector3.ONE * 0.76
		add_child(visual)
		animation_player = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if animation_player:
			for clip: StringName in animation_player.get_animation_list():
				animation_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	else:
		visual = Node3D.new()
		var mesh := MeshInstance3D.new()
		mesh.mesh = CapsuleMesh.new()
		mesh.position.y = 0.9
		visual.add_child(mesh)
		add_child(visual)
	_weapon_mount = Node3D.new()
	_weapon_mount.name = "WeaponMount"
	_weapon_mount.position = Vector3(0.42, 1.15, -0.28)
	visual.add_child(_weapon_mount)
	set_weapon_tier(1)

func set_weapon_tier(tier: int) -> void:
	if _weapon_mount == null or tier == _visual_weapon_tier:
		return
	var path := "res://assets/models/lightning_rifle_t%d.glb" % tier
	if not ResourceLoader.exists(path):
		push_error("Weapon visual missing: " + path)
		return
	for child: Node in _weapon_mount.get_children():
		_weapon_mount.remove_child(child)
		child.queue_free()
	var weapon := (load(path) as PackedScene).instantiate() as Node3D
	weapon.scale = Vector3.ONE * 0.62
	_weapon_mount.add_child(weapon)
	_visual_weapon_tier = tier

func configure(parameters: Dictionary) -> void:
	config = parameters.duplicate(true)
	maximum_health = float(config.get("maximum_health", 100.0))
	maximum_stamina = float(config.get("maximum_stamina", 100.0))
	health = maximum_health
	stamina = maximum_stamina

func _physics_process(delta: float) -> void:
	dodge_cooldown = maxf(0.0, dodge_cooldown - delta)
	dodge_remaining = maxf(0.0, dodge_remaining - delta)
	_hit_flash = maxf(0.0, _hit_flash - delta)
	if not active or input_adapter == null:
		velocity = Vector3.ZERO
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
		horizontal = _dodge_direction * float(config.get("dodge_speed", 12.0))
	velocity = Vector3(horizontal.x, -2.0, horizontal.z)
	move_and_slide()
	if visual:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-aim_direction.x, -aim_direction.z), 1.0 - exp(-18.0 * delta))
		_play_animation("Walk" if desired.length() > 0.1 else "Idle")

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

func request_dodge() -> bool:
	var cost := float(config.get("dodge_cost", 24.0))
	if not active or dodge_cooldown > 0.0 or stamina < cost:
		return false
	stamina -= cost
	dodge_remaining = float(config.get("dodge_duration", 0.24))
	dodge_cooldown = float(config.get("dodge_cooldown", 0.7))
	var axes := input_adapter.movement
	_dodge_direction = aim_direction
	if axes.length() > 0.1:
		var direction := camera.global_basis.x * axes.x + camera.global_basis.z * axes.y
		direction.y = 0.0
		_dodge_direction = direction.normalized()
	dodge_started.emit()
	return true

func take_damage(amount: float, source_position: Vector3) -> void:
	if not active or health <= 0.0 or dodge_remaining > 0.04:
		return
	var multiplier := 1.0
	var direction := (source_position - global_position).normalized()
	if defending and direction.dot(aim_direction) > 0.0:
		multiplier = 1.0 - float(config.get("defense_reduction", 0.7))
	var actual := amount * multiplier * (1.0 - clampf(float(config.get("passive_damage_reduction", 0.0)), 0.0, 0.4))
	health = maxf(0.0, health - actual)
	hurt.emit(actual)
	_hit_flash = 0.2
	if health <= 0.0:
		active = false
		died.emit()

func _play_animation(wanted: String) -> void:
	if animation_player == null:
		return
	for clip: StringName in animation_player.get_animation_list():
		if String(clip).ends_with(wanted) and animation_player.current_animation != String(clip):
			animation_player.play(clip)
			break
