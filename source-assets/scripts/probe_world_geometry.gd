extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output: Dictionary = {}
	var discrepancies := PackedStringArray()
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/world_assets.json"))
	for asset: String in config.model_definitions:
		var scene := load("res://assets/models/%s.glb" % asset) as PackedScene
		var model := scene.instantiate() as Node3D
		root.add_child(model)
		var vertices: Array[Vector3] = []
		var hierarchy: Array[Dictionary] = []
		_read(model, vertices, hierarchy)
		var minimum := Vector3(INF, INF, INF)
		var maximum := Vector3(-INF, -INF, -INF)
		for vertex: Vector3 in vertices:
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
		output[asset] = {"min": [minimum.x, minimum.y, minimum.z], "max": [maximum.x, maximum.y, maximum.z], "hierarchy": hierarchy}
		for axis: int in range(3):
			if absf(minimum[axis] - float(config.model_definitions[asset].bounds_m.min[axis])) > 0.005 or absf(maximum[axis] - float(config.model_definitions[asset].bounds_m.max[axis])) > 0.005:
				discrepancies.append(asset + " bound mismatch on axis " + str(axis))
		model.free()
	var world := load("res://presentation/world_builder.gd").new() as Node3D
	root.add_child(world)
	world.build("rain_court")
	var paving := world.get_node("AuthoredCourtyardPaving") as MultiMeshInstance3D
	output["floor_instances"] = {"paving_transform": str(world._paving_transform), "transform_first": str(paving.multimesh.get_instance_transform(0)), "transform_last": str(paving.multimesh.get_instance_transform(255)), "buffer_size": paving.multimesh.buffer.size(), "aabb": str(paving.multimesh.mesh.get_aabb())}
	world.free()
	var report := {"engine": Engine.get_version_info().string, "rendering_server_readback": "headless Dummy; identity matrices do not represent rendered instances", "tolerance_metres": 0.005, "assets": output, "discrepancies": discrepancies, "ok": discrepancies.is_empty()}
	print(JSON.stringify({"assets": config.model_definitions.size(), "discrepancies": discrepancies, "ok": discrepancies.is_empty()}))
	var file := FileAccess.open("res://../source-assets/evidence/godot-model-bounds.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	quit(0 if discrepancies.is_empty() else 1)

func _read(node: Node3D, vertices: Array[Vector3], hierarchy: Array[Dictionary]) -> void:
	hierarchy.append({"name": str(node.name), "transform": str(node.transform), "global_transform": str(node.global_transform)})
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			var local_vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in local_vertices:
				vertices.append(node.global_transform * vertex)
	for child: Node in node.get_children():
		if child is Node3D:
			_read(child, vertices, hierarchy)
