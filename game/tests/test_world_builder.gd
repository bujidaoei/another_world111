extends GdUnitTestSuite

const Builder = preload("res://presentation/world_builder.gd")
var _worlds: Array[AWWorldBuilder] = []

func after_test() -> void:
	for world: AWWorldBuilder in _worlds:
		remove_child(world)
		world.free()
	_worlds.clear()
	await get_tree().process_frame

func _configuration() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Builder.CONFIGURATION_PATH)) as Dictionary

func _world(region: String = "rain_court") -> AWWorldBuilder:
	var world := Builder.new() as AWWorldBuilder
	add_child(world)
	_worlds.append(world)
	assert_bool(world.build(region)).is_true()
	assert_array(world.configuration_errors).is_empty()
	return world

func _at_player_height(world: AWWorldBuilder, position: Vector3) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.7
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.85)
	query.collision_mask = 1
	query.margin = 0.001
	query.exclude = [(world.get_node("PhysicalGround_Collision") as StaticBody3D).get_rid()]
	return world.get_world_3d().direct_space_state.intersect_shape(query, 32)

func test_runtime_configuration_rejects_unbounded_counts_invalid_types_and_duplicate_instances() -> void:
	var original := _configuration()
	assert_array(Builder.validate_configuration(original)).is_empty()
	var invalid := original.duplicate(true)
	invalid.floor.tile_count_axis = 4096
	assert_array(Builder.validate_configuration(invalid)).is_not_empty()
	invalid = original.duplicate(true)
	invalid.floor.tile_count_axis = 1.5
	assert_array(Builder.validate_configuration(invalid)).is_not_empty()
	invalid = original.duplicate(true)
	invalid.floor.seed = "not-a-seed"
	assert_array(Builder.validate_configuration(invalid)).is_not_empty()
	invalid = original.duplicate(true)
	invalid.model_definitions.pump_station.collision_shapes[0].size[0] = -1
	assert_array(Builder.validate_configuration(invalid)).is_not_empty()
	invalid = original.duplicate(true)
	invalid.regions.rain_court.placements.append(invalid.common_placements[0].duplicate(true))
	assert_array(Builder.validate_configuration(invalid)).is_not_empty()
	invalid = original.duplicate(true)
	invalid.model_definitions.pump_station.path = "res://assets/models/../outside.glb"
	assert_array(Builder.validate_configuration(invalid)).is_not_empty()

func test_region_identity_uses_different_layout_lighting_and_real_resource_types() -> void:
	var rain := _world()
	var conduit := _world("conduit_yard")
	assert_bool(rain.has_node("WestRouteCargo")).is_true()
	assert_bool(conduit.has_node("WestRouteCargo")).is_false()
	assert_bool(conduit.has_node("ConduitTankEastB")).is_true()
	assert_bool(rain.has_node("ConduitTankEastB")).is_false()
	assert_bool(rain.lighting_profile == conduit.lighting_profile).is_false()
	assert_bool(rain.resource_positions.has("rain_scrap_01")).is_true()
	assert_bool(conduit.resource_positions.has("conduit_alloy_01")).is_true()
	assert_vector(rain.camp_position).is_equal(Vector3(0, 0, 12))
	assert_vector(rain.bench_position).is_equal(Vector3(-3, 0, 12))
	assert_vector(rain.exit_position).is_equal(Vector3(0, 0, 9))
	assert_vector(rain.gate_position).is_equal(Vector3(0, 0, -13))

func test_imported_paving_surface_and_continuous_physical_ground_share_zero_height() -> void:
	var world := _world()
	var paving := world.get_node("AuthoredCourtyardPaving") as MultiMeshInstance3D
	assert_int(paving.multimesh.instance_count).is_equal(256)
	var mesh := paving.multimesh.mesh as ArrayMesh
	var top := -INF
	# Dummy RenderingServer returns identity for MultiMesh transforms in headless
	# mode. Check imported vertex data against the authored ground transform;
	# actual GPU instances require the separately recorded rendered-scene check.
	var origin_y: float = world._configuration.floor.tile_origin_y
	var transform := Transform3D(Basis.IDENTITY, Vector3.UP * origin_y) * world._paving_transform
	for surface: int in range(mesh.get_surface_count()):
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			top = maxf(top, (transform * vertex).y)
	assert_float(top).is_between(-0.001, 0.001)
	var foundation := world.get_node("CourtyardFoundation") as MeshInstance3D
	var foundation_top := foundation.position.y + (foundation.mesh as BoxMesh).size.y * 0.5
	assert_float(foundation_top).is_less(origin_y)
	for child: Node in world.get_children():
		if child is Node3D and str(child.name).begins_with("Drain_"):
			var grate := world._find_mesh(child)
			var grate_top := -INF
			for surface: int in range(grate.mesh.get_surface_count()):
				var vertices: PackedVector3Array = grate.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					grate_top = maxf(grate_top, (grate.global_transform * vertex).y)
			assert_float(grate_top).is_between(0.0, 0.002)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 3, 5), Vector3(0, -2, 5), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	assert_bool(hit.is_empty()).is_false()
	assert_str(str((hit.collider as Node).name)).is_equal("PhysicalGround_Collision")
	assert_float((hit.position as Vector3).y).is_between(-0.001, 0.001)
	assert_bool(paving.is_in_group("camera_occluders")).is_false()

func test_prop_collision_tracks_visuals_without_blocking_resources_or_core_anchors() -> void:
	var world := _world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for position: Vector3 in world.resource_positions.values():
		assert_array(_at_player_height(world, position)).is_empty()
	for position: Vector3 in [world.camp_position, world.exit_position, world.gate_position, world.bench_position + Vector3(0, 0, 1.5), Vector3(0, 0, 6)]:
		assert_array(_at_player_height(world, position)).is_empty()
	assert_array(_at_player_height(world, Vector3(-10, 0, -14))).is_not_empty()
	# The shelter is walkable; only columns, rear panel and cabinet block movement.
	assert_array(_at_player_height(world, Vector3(-8, 0, 12))).is_empty()
	var pump := world.get_node("WestPump") as Node3D
	var collision := world.get_node("WestPump_Collision") as StaticBody3D
	assert_object((collision.get_meta("occlusion_visual") as WeakRef).get_ref()).is_same(pump)
	var shape := collision.get_child(0) as CollisionShape3D
	assert_vector((shape.shape as BoxShape3D).size).is_equal(Vector3(7.26, 3.6, 4.8))
	assert_vector(shape.position).is_equal(Vector3(0, 1.8, 0))
	assert_float(pump.rotation.y).is_between(PI - 0.001, PI + 0.001)
	assert_bool(pump.is_in_group("camera_occluders")).is_true()
	assert_bool(world.get_node("CampShelter").is_in_group("camera_occluders")).is_true()

func test_closed_gate_and_low_south_boundary_have_real_blocking_shapes() -> void:
	var world := _world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_array(_at_player_height(world, Vector3(0, 0, -16))).is_not_empty()
	assert_array(_at_player_height(world, Vector3(0, 0, 16))).is_not_empty()
	assert_array(_at_player_height(world, Vector3(15.95, 0, 0))).is_not_empty()
	assert_array(_at_player_height(world, Vector3(-15.95, 0, 0))).is_not_empty()

func test_conduit_machinery_preserves_resource_approaches_and_central_travel_lane() -> void:
	var world := _world("conduit_yard")
	await get_tree().physics_frame
	await get_tree().physics_frame
	for position: Vector3 in world.resource_positions.values():
		assert_array(_at_player_height(world, position)).is_empty()
	for z: float in [6.0, 3.0, 0.0, -3.0, -6.0, -9.0, -12.0]:
		assert_array(_at_player_height(world, Vector3(0, 0, z))).is_empty()
	assert_array(_at_player_height(world, Vector3(13, 0, 6.5))).is_not_empty()
