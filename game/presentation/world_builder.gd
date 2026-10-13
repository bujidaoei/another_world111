class_name AWWorldBuilder
extends Node3D
## Authored scene layout and collision, independent of gameplay rewards and state.

const CONFIGURATION_PATH := "res://config/world_assets.json"
const COLORS := {"floor": Color("354447"), "cold": Color("71e1df"), "warm": Color("ffc475")}
var materials: Dictionary = {}
var region_id := "rain_court"
var camp_position := Vector3(0, 0, 12)
var bench_position := Vector3(-3, 0, 12)
var exit_position := Vector3(0, 0, 9)
var gate_position := Vector3(0, 0, -13)
var resource_positions: Dictionary = {}
var pickup_nodes: Dictionary = {}
var lighting_profile: Dictionary = {}
var configuration_errors := PackedStringArray()
var _configuration: Dictionary = {}
var _region: Dictionary = {}
var _models: Dictionary = {}
var _floor_material: StandardMaterial3D
var _wet_material: ShaderMaterial
var _paving_mesh: ArrayMesh
var _paving_transform := Transform3D.IDENTITY

func build(region: String) -> bool:
	if not get_children().is_empty():
		push_error("WorldBuilder requires a fresh node for each region")
		return false
	if not _load_configuration(region):
		return false
	region_id = region
	lighting_profile = _region["lighting_profile"].duplicate(true)
	camp_position = _vector(_configuration["anchors"]["camp"])
	bench_position = _vector(_configuration["anchors"]["bench"])
	exit_position = _vector(_configuration["anchors"]["exit"])
	gate_position = _vector(_configuration["anchors"]["gate"])
	_make_materials()
	_build_floor()
	_build_boundary()
	for placement: Dictionary in _configuration["common_placements"]:
		_place(placement)
	for placement: Dictionary in _region["placements"]:
		_place(placement)
	_build_practical_lights()
	_build_resources()
	_build_markers()
	return true

static func validate_configuration(raw: Variant) -> PackedStringArray:
	var issues := PackedStringArray()
	if not raw is Dictionary:
		issues.append("World configuration must be a dictionary")
		return issues
	var data: Dictionary = raw
	if data.get("schema_version") != 1:
		issues.append("Unsupported world configuration schema")
	for key: String in ["model_definitions", "anchors", "floor", "regions"]:
		if not data.get(key) is Dictionary:
			issues.append("Missing dictionary: " + key)
	for key: String in ["common_placements", "resource_locations"]:
		if not data.get(key) is Array:
			issues.append("Missing array: " + key)
	if not issues.is_empty():
		return issues
	var definitions: Dictionary = data["model_definitions"]
	for id: Variant in definitions:
		if not id is String or not definitions[id] is Dictionary:
			issues.append("Invalid model definition")
			continue
		var definition: Dictionary = definitions[id]
		var path: Variant = definition.get("path")
		if not path is String or not str(path).begins_with("res://assets/models/") or not str(path).ends_with(".glb") or ".." in str(path):
			issues.append("Invalid local model path: " + str(id))
		if not definition.get("camera_occluder") is bool:
			issues.append("Missing occlusion policy: " + str(id))
		if not definition.get("bounds_m") is Dictionary or not _valid_vector(definition["bounds_m"].get("min")) or not _valid_vector(definition["bounds_m"].get("max")):
			issues.append("Invalid measured model bounds: " + str(id))
		elif not _valid_vector(_difference(definition["bounds_m"]["max"], definition["bounds_m"]["min"]), true):
			issues.append("Inverted model bounds: " + str(id))
		if not definition.get("collision_shapes") is Array:
			issues.append("Missing collision shapes: " + str(id))
			continue
		for collider: Variant in definition["collision_shapes"]:
			if not collider is Dictionary or collider.get("type") != "box" or not _valid_vector(collider.get("size"), true) or not _valid_vector(collider.get("local_offset")):
				issues.append("Invalid collider size/offset: " + str(id))
	for anchor: String in ["camp", "bench", "exit", "gate"]:
		if not _valid_vector(data["anchors"].get(anchor)):
			issues.append("Invalid world anchor: " + anchor)
	var floor_data: Dictionary = data["floor"]
	if not _positive_number(floor_data.get("extent")) or not _positive_number(floor_data.get("tile_spacing")) or not _finite_number(floor_data.get("surface_y")) or not _finite_number(floor_data.get("tile_origin_y")):
		issues.append("Invalid physical ground dimensions")
	for key: String in ["physics_thickness", "foundation_clearance"]:
		if not _positive_number(floor_data.get(key)):
			issues.append("Invalid ground support dimension: " + key)
	if not _bounded_integer(floor_data.get("tile_count_axis"), 1, 32):
		issues.append("Tile count exceeds world budget")
	if not _bounded_integer(floor_data.get("seed"), 0, 2147483647):
		issues.append("Invalid floor seed")
	for key: String in ["boundary_half_extent", "boundary_thickness", "side_wall_height", "south_wall_height"]:
		if not _positive_number(floor_data.get(key)):
			issues.append("Invalid boundary dimension: " + key)
	if _positive_number(floor_data.get("extent")) and _positive_number(floor_data.get("boundary_half_extent")) and float(floor_data["extent"]) * 0.5 <= float(floor_data["boundary_half_extent"]):
		issues.append("Boundary must lie inside physical ground")
	if not definitions.has(floor_data.get("tile_asset", "")):
		issues.append("Unknown paving asset")
	for path_key: String in ["floor_material", "wet_material"]:
		if not floor_data.get(path_key) is String or not str(floor_data[path_key]).begins_with("res://presentation/") or ".." in str(floor_data[path_key]):
			issues.append("Invalid local floor material path")
	_validate_placements(data["common_placements"], definitions, issues)
	for region_key: Variant in data["regions"]:
		var region_data: Variant = data["regions"][region_key]
		if not region_data is Dictionary:
			issues.append("Invalid region: " + str(region_key))
			continue
		if not region_data.get("placements") is Array or not region_data.get("practical_lights") is Array or not region_data.get("puddles") is Array or not region_data.get("lighting_profile") is Dictionary:
			issues.append("Incomplete region layout: " + str(region_key))
			continue
		_validate_placements(region_data["placements"], definitions, issues)
		var common_ids: Dictionary = {}
		for placement: Variant in data["common_placements"]:
			if placement is Dictionary:
				common_ids[placement.get("id", "")] = true
		for placement: Variant in region_data["placements"]:
			if placement is Dictionary and common_ids.has(placement.get("id", "")):
				issues.append("Region placement duplicates common identity")
		if not region_data.get("resource_prefix") is String or not region_data.get("metal_type") in ["scrap", "alloy"]:
			issues.append("Invalid region resource identity")
		var profile: Dictionary = region_data["lighting_profile"]
		for color_key: String in ["ambient_color", "sun_color", "fog_color", "water_color", "ground_tint"]:
			if not profile.get(color_key) is String or not Color.html_is_valid(str(profile.get(color_key, ""))):
				issues.append("Invalid region color: " + color_key)
		for number_key: String in ["ambient_energy", "sun_energy", "fog_density", "ground_roughness"]:
			if not _positive_number(profile.get(number_key)):
				issues.append("Invalid lighting value: " + number_key)
		if _positive_number(profile.get("ground_roughness")) and float(profile["ground_roughness"]) > 1.0:
			issues.append("Ground roughness must not exceed one")
		if region_data["practical_lights"].size() > 6:
			issues.append("Practical lights exceed mobile world budget")
		for light_data: Variant in region_data["practical_lights"]:
			if not light_data is Dictionary or not _valid_vector(light_data.get("position")) or not _positive_number(light_data.get("energy")) or not _positive_number(light_data.get("range")) or not light_data.get("color") is String or not Color.html_is_valid(str(light_data["color"])):
				issues.append("Invalid practical light")
		for puddle: Variant in region_data["puddles"]:
			if not puddle is Dictionary or not _valid_vector(puddle.get("center")) or not puddle.get("size") is Array or puddle["size"].size() != 2:
				issues.append("Invalid puddle layout")
			elif not _positive_number(puddle["size"][0]) or not _positive_number(puddle["size"][1]):
				issues.append("Invalid puddle extent")
			if puddle is Dictionary and not _bounded_integer(puddle.get("seed"), 0, 2147483647):
				issues.append("Invalid puddle seed")
	for resource: Variant in data["resource_locations"]:
		if not resource is Dictionary or not _valid_vector(resource.get("position")) or not resource.get("type") in ["metal", "crystal"] or not resource.get("number") is String:
			issues.append("Invalid resource location")
	return issues

static func _validate_placements(placements: Array, definitions: Dictionary, issues: PackedStringArray) -> void:
	var ids: Dictionary = {}
	for placement: Variant in placements:
		if not placement is Dictionary:
			issues.append("Placement must be a dictionary")
			continue
		if not placement.get("id") is String or ids.has(placement.get("id")):
			issues.append("Placement identity missing or duplicated")
		ids[placement.get("id", "")] = true
		if not definitions.has(placement.get("asset", "")) or not _valid_vector(placement.get("position")) or not _valid_vector(placement.get("scale"), true) or not _finite_number(placement.get("yaw")) or not placement.get("collision") is bool:
			issues.append("Invalid placement: " + str(placement.get("id", "")))

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _positive_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0

static func _bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _finite_number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _difference(a: Array, b: Array) -> Array:
	return [float(a[0]) - float(b[0]), float(a[1]) - float(b[1]), float(a[2]) - float(b[2])]

static func _valid_vector(value: Variant, positive: bool = false) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component: Variant in value:
		if not _finite_number(component) or absf(float(component)) > 1000.0 or (positive and float(component) <= 0.0):
			return false
	return true

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _load_configuration(region: String) -> bool:
	var file := FileAccess.open(CONFIGURATION_PATH, FileAccess.READ)
	if file == null:
		configuration_errors = PackedStringArray(["Cannot read runtime world configuration"])
	else:
		var raw: Variant = JSON.parse_string(file.get_as_text())
		configuration_errors = validate_configuration(raw)
		if configuration_errors.is_empty():
			_configuration = raw
			if not _configuration["regions"].has(region):
				configuration_errors.append("Unknown region: " + region)
			else:
				_region = _configuration["regions"][region]
	if not configuration_errors.is_empty():
		push_error("World configuration rejected: " + "; ".join(configuration_errors))
		return false
	for id: String in _configuration["model_definitions"]:
		var path: String = _configuration["model_definitions"][id]["path"]
		var scene := load(path) as PackedScene
		if scene == null:
			configuration_errors.append("Cannot load model: " + id)
			push_error("World asset missing or not imported: " + id)
			return false
		_models[id] = scene
	_floor_material = load(_configuration["floor"]["floor_material"]) as StandardMaterial3D
	_wet_material = load(_configuration["floor"]["wet_material"]) as ShaderMaterial
	if _floor_material == null or _wet_material == null or _wet_material.shader == null:
		configuration_errors.append("Floor materials do not match required PBR/shader types")
		push_error(configuration_errors[-1])
		return false
	var template := (_models[_configuration["floor"]["tile_asset"]] as PackedScene).instantiate() as Node3D
	var source := _find_mesh(template)
	if source == null or not source.mesh is ArrayMesh or source.mesh.get_surface_count() < 1:
		configuration_errors.append("Paving model must contain an imported ArrayMesh")
		push_error(configuration_errors[-1])
		template.free()
		return false
	_paving_mesh = source.mesh as ArrayMesh
	_paving_transform = source.transform
	var ancestor := source.get_parent() as Node3D
	while ancestor != null:
		_paving_transform = ancestor.transform * _paving_transform
		if ancestor == template:
			break
		ancestor = ancestor.get_parent() as Node3D
	template.free()
	return true

func _make_materials() -> void:
	for key: String in COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[key]
		material.roughness = 0.70
		if key in ["warm", "cold"]:
			material.emission_enabled = true
			material.emission = COLORS[key]
			material.emission_energy_multiplier = 1.2
		materials[key] = material

func _build_floor() -> void:
	var floor_data: Dictionary = _configuration["floor"]
	var extent := float(floor_data["extent"])
	var surface_y := float(floor_data["surface_y"])
	var thickness := float(floor_data["physics_thickness"])
	_static_box("PhysicalGround_Collision", Vector3(0, surface_y - thickness * 0.5, 0), Vector3(extent, thickness, extent), null)
	var foundation_top := surface_y + float(floor_data["tile_origin_y"]) - float(floor_data["foundation_clearance"])
	_box("CourtyardFoundation", Vector3(0, foundation_top - thickness * 0.5, 0), Vector3(extent, thickness, extent), "floor", false)
	var mesh := _paving_mesh.duplicate() as ArrayMesh
	var floor_material := _floor_material.duplicate() as StandardMaterial3D
	floor_material.vertex_color_use_as_albedo = true
	floor_material.uv1_triplanar = true
	floor_material.uv1_world_triplanar = true
	floor_material.uv1_scale = Vector3.ONE * 0.45
	floor_material.albedo_color = Color(str(lighting_profile["ground_tint"]))
	floor_material.roughness = float(lighting_profile["ground_roughness"])
	floor_material.metallic = 0.0
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for surface in range(mesh.get_surface_count()):
		mesh.surface_set_material(surface, floor_material)
	var count := int(floor_data["tile_count_axis"])
	var spacing := float(floor_data["tile_spacing"])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = count * count
	multimesh.custom_aabb = AABB(Vector3(-extent * 0.5, surface_y - 0.2, -extent * 0.5), Vector3(extent, 0.5, extent))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(floor_data["seed"])
	var index := 0
	for x in range(count):
		for z in range(count):
			var origin := Vector3((x - count * 0.5) * spacing + spacing * 0.5, surface_y + float(floor_data["tile_origin_y"]), (z - count * 0.5) * spacing + spacing * 0.5)
			var basis := Basis(Vector3.UP, float(rng.randi_range(0, 3)) * PI * 0.5)
			multimesh.set_instance_transform(index, Transform3D(basis, origin) * _paving_transform)
			var value := rng.randf_range(0.88, 1.08)
			multimesh.set_instance_color(index, Color(value, value, value, 1))
			index += 1
	var paving := MultiMeshInstance3D.new()
	paving.name = "AuthoredCourtyardPaving"
	paving.multimesh = multimesh
	add_child(paving)
	for puddle: Dictionary in _region["puddles"]:
		_build_puddle(puddle)

func _build_puddle(data: Dictionary) -> void:
	var water := MeshInstance3D.new()
	water.name = "IrregularWaterIsland"
	water.position = _vector(data["center"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data["seed"])
	var outline := PackedVector2Array()
	for i in range(18):
		var angle := float(i) * TAU / 18.0
		var radius := rng.randf_range(0.72, 1.0)
		outline.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	for i in range(18):
		for point: Vector2 in [Vector2.ZERO, outline[(i + 1) % 18], outline[i]]:
			vertices.append(Vector3(point.x * float(data["size"][0]) * 0.5, 0, point.y * float(data["size"][1]) * 0.5))
			normals.append(Vector3.UP)
			uv.append(point * 0.5 + Vector2.ONE * 0.5)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	water.mesh = mesh
	var material := _wet_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("water_color", Color(str(lighting_profile["water_color"])))
	water.material_override = material
	add_child(water)

func _build_boundary() -> void:
	# Continuous backing closes joins; the northern gate has a closed visual door.
	var floor_data: Dictionary = _configuration["floor"]
	var limit := float(floor_data["boundary_half_extent"])
	var thickness := float(floor_data["boundary_thickness"])
	var height := float(floor_data["side_wall_height"])
	var south_height := float(floor_data["south_wall_height"])
	var surface_y := float(floor_data["surface_y"])
	var span := limit * 2.0 + thickness * 2.0
	_static_box("WestBoundary", Vector3(-limit, surface_y + height * 0.5, 0), Vector3(thickness, height, span), null)
	_static_box("EastBoundary", Vector3(limit, surface_y + height * 0.5, 0), Vector3(thickness, height, span), null)
	_static_box("NorthBoundary", Vector3(0, surface_y + height * 0.5, -limit), Vector3(span, height, thickness), null)
	_static_box("SouthBoundary", Vector3(0, surface_y + south_height * 0.5, limit), Vector3(span, south_height, thickness), null)

func _place(data: Dictionary) -> Node3D:
	var definition: Dictionary = _configuration["model_definitions"][data["asset"]]
	var visual := (_models[data["asset"]] as PackedScene).instantiate() as Node3D
	visual.name = str(data["id"])
	visual.position = _vector(data["position"])
	visual.rotation.y = float(data["yaw"])
	visual.scale = _vector(data["scale"])
	visual.set_meta("asset_id", data["asset"])
	add_child(visual)
	var bounds: Dictionary = definition["bounds_m"]
	if bool(definition["camera_occluder"]) and (float(bounds["max"][1]) - float(bounds["min"][1])) * visual.scale.y > 2.0:
		visual.add_to_group("camera_occluders")
	if bool(data["collision"]) and not definition["collision_shapes"].is_empty():
		var body := StaticBody3D.new()
		body.name = str(data["id"]) + "_Collision"
		body.position = visual.position
		body.rotation.y = visual.rotation.y
		body.collision_layer = 1
		body.set_meta("occlusion_visual", weakref(visual))
		body.set_meta("asset_id", data["asset"])
		for collider: Dictionary in definition["collision_shapes"]:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = _vector(collider["size"]) * visual.scale
			shape.shape = box
			shape.position = _vector(collider["local_offset"]) * visual.scale
			body.add_child(shape)
		add_child(body)
	return visual

func _build_practical_lights() -> void:
	for data: Dictionary in _region["practical_lights"]:
		var lamp := OmniLight3D.new()
		lamp.name = "PracticalAreaLight"
		lamp.position = _vector(data["position"])
		lamp.light_color = Color(str(data["color"]))
		lamp.light_energy = float(data["energy"])
		lamp.omni_range = float(data["range"])
		lamp.shadow_enabled = false
		add_child(lamp)

func _build_resources() -> void:
	var prefix: String = _region["resource_prefix"]
	var metal_type: String = _region["metal_type"]
	for data: Dictionary in _configuration["resource_locations"]:
		var is_crystal := str(data["type"]) == "crystal"
		var type_name := "crystal" if is_crystal else metal_type
		var id := prefix + "_" + type_name + "_" + str(data["number"])
		var position := _vector(data["position"])
		resource_positions[id] = position
		var pickup := Node3D.new()
		pickup.name = id
		pickup.position = position
		add_child(pickup)
		var model_id := "conductive_anchor" if is_crystal else "cargo_crate"
		var visual := (_models[model_id] as PackedScene).instantiate() as Node3D
		visual.scale = Vector3.ONE * (0.55 if is_crystal else 0.58)
		pickup.add_child(visual)
		var label := Label3D.new()
		label.position.y = 1.15
		label.text = "晶片 · E" if is_crystal else ("合金 · E" if metal_type == "alloy" else "废铁 · E")
		label.font_size = 28
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = COLORS["cold"] if is_crystal else Color("dac9a9")
		pickup.add_child(label)
		pickup_nodes[id] = pickup

func _build_markers() -> void:
	_label(camp_position + Vector3(0, 2.0, 0), "回收营地", Color("ffda9b"))
	_label(bench_position + Vector3(0, 1.65, 0), "维护台 · E", Color("ffc078"))
	_label(gate_position + Vector3(0, 1.65, 0), "境界信标", COLORS["cold"])
	_label(exit_position + Vector3(0, 0.025, 0), "撤离 · E", Color("84e1c0"), false)
	var marker := MeshInstance3D.new()
	marker.name = "ExtractionRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 1.10
	ring.outer_radius = 1.22
	marker.mesh = ring
	marker.material_override = materials["cold"]
	marker.position = exit_position + Vector3.UP * 0.045
	marker.scale.y = 0.15
	add_child(marker)

func _static_box(node_name: String, location: Vector3, dimensions: Vector3, visual: Node3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = location
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	if visual != null:
		body.set_meta("occlusion_visual", weakref(visual))
	add_child(body)
	return body

func _box(node_name: String, location: Vector3, dimensions: Vector3, material_key: String, collision: bool) -> void:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	var box := BoxMesh.new()
	box.size = dimensions
	visual.mesh = box
	visual.material_override = materials[material_key]
	visual.position = location
	add_child(visual)
	if collision:
		_static_box(node_name + "_Collision", location, dimensions, null)

func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result
	return null

func _label(location: Vector3, text: String, color: Color, billboard: bool = true) -> void:
	var label := Label3D.new()
	label.position = location
	label.text = text
	label.font_size = 32
	label.pixel_size = 0.007
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	if not billboard:
		label.rotation.x = -PI * 0.5
	add_child(label)
