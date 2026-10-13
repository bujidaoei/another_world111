extends GdUnitTestSuite

var _host: Node3D
var _camera: Camera3D
var _actor: Node3D
var _fader: AWOcclusionFader
var _source: StandardMaterial3D

func before_test() -> void:
	_host = Node3D.new()
	add_child(_host)
	_camera = Camera3D.new()
	_host.add_child(_camera)
	_camera.position = Vector3(0, 1.2, 10)
	_actor = Node3D.new()
	_host.add_child(_actor)
	_source = StandardMaterial3D.new()
	_source.albedo_color = Color(0.3, 0.6, 0.7, 1)
	_fader = AWOcclusionFader.new()
	_fader.camera = _camera
	_fader.target = _actor
	_host.add_child(_fader)
	_fader.set_process(false)

func after_test() -> void:
	remove_child(_host)
	_host.free()
	await get_tree().process_frame

func _region() -> Node3D:
	var region := Node3D.new()
	_host.add_child(region)
	var mesh := MeshInstance3D.new()
	mesh.name = "Occluder"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.material = _source
	mesh.position = Vector3(0, 1.2, 4)
	region.add_child(mesh)
	mesh.add_to_group("camera_occluders")
	return region

func test_fade_cycles_keep_material_identity_without_mutating_shared_source() -> void:
	var region := _region()
	var mesh := region.get_node("Occluder") as MeshInstance3D
	_fader.bind_world(region)
	var material := mesh.get_surface_override_material(0) as BaseMaterial3D
	assert_object(material).is_not_null()
	assert_bool(material == _source).is_false()
	for cycle in range(40):
		_camera.position.x = 0
		_fader._process(0.2)
		assert_float(material.albedo_color.a).is_equal_approx(_fader.minimum_alpha, 0.0001)
		_camera.position.x = 10
		_fader._process(0.2)
		assert_float(material.albedo_color.a).is_equal_approx(1.0, 0.0001)
		assert_object(mesh.get_surface_override_material(0)).is_same(material)
	assert_float(_source.albedo_color.a).is_equal(1.0)
	assert_int(_source.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)

func test_region_retirement_clears_references_before_binding_new_geometry() -> void:
	var first := _region()
	_fader.bind_world(first)
	_fader._process(0.2)
	_host.remove_child(first)
	_fader.release_world()
	first.free()
	assert_dict(_fader._states).is_empty()
	assert_dict(_fader._blocked).is_empty()
	var second := _region()
	_fader.bind_world(second)
	_fader._process(0.2)
	var material := (second.get_node("Occluder") as MeshInstance3D).get_surface_override_material(0) as BaseMaterial3D
	assert_float(material.albedo_color.a).is_equal_approx(_fader.minimum_alpha, 0.0001)
	assert_float(_source.albedo_color.a).is_equal(1.0)
