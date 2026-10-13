class_name AWEnemyController
extends CharacterBody3D

signal defeated(enemy_id: String, location: Vector3)
signal attack_telegraphed(location: Vector3, radius: float, duration: float)
var enemy_id := ""
var kind := "scavenger"
var health := 64.0
var maximum_health := 64.0
var target: AWPlayerController
var config: Dictionary = {}
var active := true
var visual: Node3D
var cooldown := 0.6
var windup := 0.0
var _attack_position := Vector3.ZERO
var _prepared := false
var _animation: AnimationPlayer

func setup(id: String, enemy_kind: String, parameters: Dictionary, player: AWPlayerController) -> void:
	enemy_id = id
	kind = enemy_kind
	config = parameters.duplicate(true)
	target = player
	maximum_health = float(config.get(kind + "_health", 64.0))
	health = maximum_health

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.48 if kind == "guardian" else 0.35
	capsule.height = 2.2 if kind == "guardian" else 1.6
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	var model_path := "res://assets/models/" + kind + ".glb"
	if ResourceLoader.exists(model_path):
		visual = (load(model_path) as PackedScene).instantiate() as Node3D
		visual.scale = Vector3.ONE * (0.88 if kind == "guardian" else 0.7)
		add_child(visual)
		_animation = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if _animation:
			for clip: StringName in _animation.get_animation_list():
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	else:
		visual = Node3D.new()
		var marker := MeshInstance3D.new()
		marker.mesh = CapsuleMesh.new()
		marker.position.y = 0.9
		visual.add_child(marker)
		add_child(visual)
	var bar := Label3D.new()
	bar.name = "HealthLabel"
	bar.position.y = 2.6 if kind == "guardian" else 2.0
	bar.font_size = 32
	bar.pixel_size = 0.006
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.modulate = Color(1.0, 0.65, 0.42)
	bar.text = "守卫" if kind == "guardian" else ("腐蚀者" if kind == "spitter" else "拾荒体")
	add_child(bar)

func _physics_process(delta: float) -> void:
	if not active or target == null or not target.active:
		velocity = Vector3.ZERO
		return
	cooldown = maxf(0.0, cooldown - delta)
	var offset := target.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if offset.length_squared() > 0.02:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-offset.x, -offset.z), 1.0 - exp(-9.0 * delta))
	if _prepared:
		windup -= delta
		velocity = Vector3.ZERO
		if windup <= 0.0:
			_resolve_attack()
		return
	if distance > 19.0:
		velocity = Vector3.ZERO
		return
	var range_value := float(config.get("ranged_range", 8.0)) if kind == "spitter" else float(config.get("attack_range", 1.6))
	if kind == "guardian":
		range_value = float(config.get("guardian_radius", 3.5))
	if distance <= range_value and cooldown <= 0.0:
		_prepared = true
		windup = float(config.get("ranged_windup", 1.0)) if kind == "spitter" else float(config.get("attack_windup", 0.7))
		_attack_position = target.global_position if kind == "spitter" else global_position
		attack_telegraphed.emit(_attack_position, 1.8 if kind == "spitter" else range_value, windup)
		_play("Idle")
	else:
		var speed := float(config.get("move_speed", 2.1)) * (0.75 if kind == "guardian" else 1.0)
		var motion := offset.normalized() * speed if distance > range_value * 0.8 else Vector3.ZERO
		velocity = Vector3(motion.x, -2.0, motion.z)
		move_and_slide()
		_play("Walk" if motion.length() > 0.1 else "Idle")

func _resolve_attack() -> void:
	_prepared = false
	cooldown = float(config.get("attack_cooldown", 1.8))
	var range_value := 1.8 if kind == "spitter" else float(config.get("attack_range", 1.6))
	if kind == "guardian":
		range_value = float(config.get("guardian_radius", 3.5))
	var origin := _attack_position if kind == "spitter" else global_position
	if target.global_position.distance_to(origin) <= range_value:
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP, 1)
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			target.take_damage(float(config.get("guardian_damage", 24.0)) if kind == "guardian" else float(config.get("attack_damage", 15.0)), global_position)

func take_damage(amount: float) -> void:
	if not active:
		return
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		active = false
		collision_layer = 0
		defeated.emit(enemy_id, global_position)
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3.ONE * 0.02, 0.35)
		tween.tween_callback(queue_free)

func _play(wanted: String) -> void:
	if _animation == null:
		return
	for clip: StringName in _animation.get_animation_list():
		if String(clip).ends_with(wanted) and _animation.current_animation != String(clip):
			_animation.play(clip)
			break
