class_name AWWeatherEmitter
extends MultiMeshInstance3D
## Batched analytic rain: a single mesh submission and a pausable shader clock.

@export_range(1, 2000, 1) var amount := 850
@export var horizontal_extent := Vector2(16, 16)
@export var flight_height := 9.0
@export var minimum_speed := 14.0
@export var maximum_speed := 18.0
@export var wind := Vector2(0.4, 0.15)
@export var random_seed := 9012
@export var rain_material: ShaderMaterial
var _elapsed := 0.0
var _material: ShaderMaterial

func _ready() -> void:
	if amount < 1 or amount > 2000 or flight_height <= 0.0 or horizontal_extent.x <= 0 or horizontal_extent.y <= 0 or minimum_speed <= 0 or maximum_speed < minimum_speed or rain_material == null:
		push_error("Weather emitter configuration is invalid.")
		set_process(false)
		return
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.5)
	_material = rain_material.duplicate() as ShaderMaterial
	streak.material = _material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = streak
	multimesh.instance_count = amount
	multimesh.custom_aabb = AABB(Vector3(-horizontal_extent.x - 1, -1, -horizontal_extent.y - 1), Vector3(horizontal_extent.x * 2 + 2, flight_height + 2, horizontal_extent.y * 2 + 2))
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for index: int in range(amount):
		var center := Vector3(rng.randf_range(-horizontal_extent.x, horizontal_extent.x), 0, rng.randf_range(-horizontal_extent.y, horizontal_extent.y))
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, center))
		multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	_material.set_shader_parameter("flight_height", flight_height)
	_material.set_shader_parameter("minimum_speed", minimum_speed)
	_material.set_shader_parameter("maximum_speed", maximum_speed)
	_material.set_shader_parameter("wind", wind)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(delta: float) -> void:
	if _material:
		_elapsed += delta
		_material.set_shader_parameter("weather_time", _elapsed)
