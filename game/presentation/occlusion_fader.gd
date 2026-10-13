class_name AWOcclusionFader
extends Node
## Region-scoped material instances keep a stable render pass during camera fades.

var camera: Camera3D
var target: Node3D
var minimum_alpha := 0.18
var check_interval := 0.12
var fade_rate := 9.0
var _clock := 0.0
var _states: Dictionary = {}
var _blocked: Dictionary = {}
var _world: WeakRef

func bind_world(world: Node3D) -> void:
	release_world()
	_world = weakref(world)
	for node: Node in get_tree().get_nodes_in_group("camera_occluders"):
		if world.is_ancestor_of(node):
			_prepare_tree(node)

func release_world() -> void:
	# The caller detaches the retired region first. Its owned material instances
	# are freed with the region, without mutating rendering resources at retirement.
	_states.clear()
	_blocked.clear()
	_world = null
	_clock = 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(target) or _world == null:
		return
	var world := _world.get_ref() as Node3D
	if not is_instance_valid(world) or not world.is_inside_tree():
		release_world()
		return
	_clock += delta
	if _clock >= check_interval:
		_clock = 0.0
		_blocked.clear()
		for mesh: Variant in _states:
			if is_instance_valid(mesh) and mesh.is_inside_tree():
				var from: Vector3 = mesh.to_local(camera.global_position)
				var to: Vector3 = mesh.to_local(target.global_position + Vector3.UP * 1.2)
				if mesh.get_aabb().intersects_segment(from, to):
					_blocked[mesh] = true
	for mesh: Variant in _states.keys():
		if not is_instance_valid(mesh):
			_states.erase(mesh)
			continue
		var state: Dictionary = _states[mesh]
		var wanted := minimum_alpha if _blocked.has(mesh) else 1.0
		var next_alpha := move_toward(float(state.alpha), wanted, delta * fade_rate)
		if is_equal_approx(next_alpha, float(state.alpha)):
			continue
		state.alpha = next_alpha
		for index: int in range(state.materials.size()):
			var material: BaseMaterial3D = state.materials[index]
			var color: Color = state.colors[index]
			color.a *= float(state.alpha)
			material.albedo_color = color

func _prepare_tree(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_prepare(node)
	for child: Node in node.get_children():
		_prepare_tree(child)

func _prepare(mesh: MeshInstance3D) -> void:
	var materials: Array[BaseMaterial3D] = []
	var colors: Array[Color] = []
	for index: int in range(mesh.mesh.get_surface_count()):
		var original := mesh.get_surface_override_material(index)
		var source := original if original else mesh.mesh.surface_get_material(index)
		if not source is BaseMaterial3D:
			return
		var instance := source.duplicate() as BaseMaterial3D
		instance.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials.append(instance)
		colors.append(instance.albedo_color)
	for index: int in range(materials.size()):
		mesh.set_surface_override_material(index, materials[index])
	_states[mesh] = {"materials": materials, "colors": colors, "alpha": 1.0}

func _exit_tree() -> void:
	release_world()
