class_name AWCameraRig
extends Node3D

var target: Node3D
var camera: Camera3D
var config: Dictionary = {}
var locked := false
var yaw := 0.0
var pitch := -0.92
var distance := 20.0
var shake_strength := 0.0
var shake_multiplier := 0.3
var allow_input := false
var occlusion_fader: AWOcclusionFader

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 43.0
	camera.near = 0.15
	camera.far = 180.0
	camera.current = true
	add_child(camera)
	occlusion_fader = AWOcclusionFader.new()
	occlusion_fader.camera = camera
	occlusion_fader.target = target
	add_child(occlusion_fader)
	reset_view()

func configure(parameters: Dictionary) -> void:
	config = parameters.duplicate(true)
	if occlusion_fader:
		occlusion_fader.minimum_alpha = float(config.get("occlusion_alpha", 0.18))
		occlusion_fader.check_interval = float(config.get("occlusion_check_interval", 0.12))
	reset_view()

func reset_view() -> void:
	yaw = float(config.get("yaw", 0.0))
	pitch = float(config.get("pitch", -0.92))
	distance = float(config.get("distance", 20.0))

func _process(delta: float) -> void:
	if target == null:
		return
	var desired := target.global_position + Vector3(0.0, 0.7, -0.8)
	global_position = global_position.lerp(desired, 1.0 - exp(-float(config.get("follow_rate", 7.0)) * delta))
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
	shake_strength = maxf(0.0, shake_strength - delta * 4.0)
	camera.h_offset = sin(Time.get_ticks_msec() * 0.055) * shake_strength * shake_multiplier
	camera.v_offset = cos(Time.get_ticks_msec() * 0.061) * shake_strength * shake_multiplier * 0.6

func _unhandled_input(event: InputEvent) -> void:
	if not allow_input or locked:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		yaw -= event.screen_relative.x * float(config.get("sensitivity", 0.007))
		pitch = clampf(pitch - event.screen_relative.y * 0.004, -1.25, -0.55)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance - 1.2, float(config.get("minimum_distance", 12.0)), float(config.get("maximum_distance", 30.0)))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance + 1.2, float(config.get("minimum_distance", 12.0)), float(config.get("maximum_distance", 30.0)))
