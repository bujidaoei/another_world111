extends GdUnitTestSuite

const Config = preload("res://config/presentation_config.gd")

func _defaults() -> Dictionary:
	return Config.load_file().data

func _assert_rejected(candidate: Dictionary) -> void:
	var result: Dictionary = Config.validate(candidate)
	assert_bool(result.ok).is_false()
	assert_str(result.code).is_equal("presentation_configuration_invalid")
	assert_str(result.message).is_not_empty()
	assert_dict(result.data).is_empty()

func test_real_configuration_loads_and_does_not_expose_mutable_input_reference() -> void:
	var loaded: Dictionary = Config.load_file()
	assert_bool(loaded.ok).is_true()
	var candidate: Dictionary = loaded.data
	var validated: Dictionary = Config.validate(candidate)
	assert_bool(validated.ok).is_true()
	assert_dict(validated.data).is_equal(candidate)
	validated.data.player.move_speed = 0.0
	assert_float(float(candidate.player.move_speed)).is_greater(0.0)

func test_zero_combat_cooldown_is_rejected_before_scene_creation() -> void:
	var candidate := _defaults()
	candidate.weapon.attack_cooldown = 0.0
	_assert_rejected(candidate)

func test_nonfinite_and_wrong_type_numeric_fields_are_rejected() -> void:
	for value: Variant in [NAN, INF, -INF, true, "5.2"]:
		var candidate := _defaults()
		candidate.player.move_speed = value
		_assert_rejected(candidate)

func test_world_seed_requires_finite_nonnegative_integer() -> void:
	for value: Variant in [0.5, -1, NAN, INF, 4294967296]:
		var candidate := _defaults()
		candidate.world.seed = value
		_assert_rejected(candidate)
	var zero_seed := _defaults()
	zero_seed.world.seed = 0
	assert_bool(Config.validate(zero_seed).ok).is_true()

func test_unknown_or_missing_sections_and_fields_are_rejected() -> void:
	var unknown_section := _defaults()
	unknown_section.telemetry = {}
	_assert_rejected(unknown_section)
	var unknown_field := _defaults()
	unknown_field.weapon.extra_attack = 1
	_assert_rejected(unknown_field)
	var replaced_field := _defaults()
	replaced_field.camera.erase("distance")
	replaced_field.camera.unrecognized_distance = 22.0
	_assert_rejected(replaced_field)
	var missing_section := _defaults()
	missing_section.erase("input")
	_assert_rejected(missing_section)

func test_camera_distance_must_be_within_ordered_zoom_bounds() -> void:
	var below_minimum := _defaults()
	below_minimum.camera.minimum_distance = 25.0
	_assert_rejected(below_minimum)
	var above_maximum := _defaults()
	above_maximum.camera.maximum_distance = 18.0
	_assert_rejected(above_maximum)
	var reversed_bounds := _defaults()
	reversed_bounds.camera.minimum_distance = 30.0
	reversed_bounds.camera.maximum_distance = 12.0
	_assert_rejected(reversed_bounds)

func test_tier_damage_multipliers_require_exact_supported_tiers_and_finite_values() -> void:
	for tiers: Variant in [{"1": 1.0}, {"1": 1.0, "3": 2.0}, {"1": 1.0, "2": 2.0, "3": 3.0}, {"1": 1.0, "2": NAN}, {"1": 1.0, "2": true}, [1.0, 2.0]]:
		var candidate := _defaults()
		candidate.weapon.tier_damage_multipliers = tiers
		_assert_rejected(candidate)

func test_initial_stamina_must_cover_each_required_action() -> void:
	for field: String in ["dodge_cost", "pulse_cost", "anchor_cost"]:
		var candidate := _defaults()
		var section: String = "player" if field == "dodge_cost" else "weapon"
		candidate[section][field] = candidate.player.maximum_stamina + 1.0
		_assert_rejected(candidate)
