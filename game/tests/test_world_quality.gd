extends GdUnitTestSuite
## Configuration tests exercise real validation; fixture paths do not claim asset import.

const Builder = preload("res://presentation/world_builder.gd")

func _configuration() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://config/world_assets.json")) as Dictionary

func test_current_world_configuration_remains_valid() -> void:
	assert_array(Builder.validate_configuration(_configuration())).is_empty()

func test_original_quality_model_directory_is_accepted_by_same_registry() -> void:
	var candidate := _configuration()
	candidate.model_definitions.paving_tiles.path = "res://assets/quality/repair_paving_a.glb"
	assert_array(Builder.validate_configuration(candidate)).is_empty()

func test_quality_registry_rejects_remote_traversal_and_similar_prefix_paths() -> void:
	for path: String in ["https://example.invalid/paving.glb", "res://assets/quality/../models/paving.glb", "res://assets/quality_escape/paving.glb", "res://assets/quality/paving.png", "assets/quality/paving.glb", "res://assets/quality\\paving.glb"]:
		var candidate := _configuration()
		candidate.model_definitions.paving_tiles.path = path
		assert_array(Builder.validate_configuration(candidate)).is_not_empty()
