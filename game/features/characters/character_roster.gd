extends RefCounted
class_name AWCharacterRoster

const Result = preload("res://config/rule_result.gd")
const Config = preload("res://config/character_builds_config.gd")
const Evaluator = preload("res://features/characters/build_evaluator.gd")
const Rules = preload("res://config/rules_config.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const MAX_JSON_INTEGER: int = 9007199254740991
var _config: Config
var _evaluator: Evaluator
var _profiles: Dictionary = {}
var _progress: Progress
var _inventory: Inventory
var _active_character_id: String = ""
var _thief_coin_remainder: int = 0
var active_character_id: String:
	get: return _active_character_id
var thief_coin_remainder: int:
	get: return _thief_coin_remainder

func _init(config: Config, evaluator: Evaluator) -> void:
	_config = config
	_evaluator = evaluator

func initialize(weapon_id: String, progress: Progress, inventory: Inventory) -> Dictionary:
	if not _profiles.is_empty(): return Result.failure("roster_already_initialized", "已有角色档案不能重新初始化。")
	var build := _evaluator.default_build(weapon_id)
	var evaluation := _evaluator.evaluate(build, progress, inventory)
	if not evaluation.ok: return evaluation
	var profiles: Dictionary = {}
	for id: String in _config.data.characters:
		var slots: Array[Dictionary] = []
		for index: int in range(int(_config.data.limits.preset_slots)): slots.append({"name": "", "build": null})
		profiles[id] = {"character_id": id, "applied_build": build.duplicate(true), "draft": build.duplicate(true), "presets": slots}
	_profiles = profiles
	_active_character_id = "thief"
	_thief_coin_remainder = 0
	_progress = progress
	_inventory = inventory
	return Result.success({"snapshot": snapshot(), "derived_build": evaluation.data.duplicate(true)})

func profile(character_id: String) -> Dictionary:
	return _profiles.get(character_id, {}).duplicate(true)

func active_build() -> Dictionary:
	return profile(_active_character_id).get("applied_build", {}).duplicate(true)

func set_draft(character_id: String, build: Dictionary) -> Dictionary:
	if not _profiles.has(character_id): return _unknown()
	var validation := _evaluator.validate_structure(build)
	if not validation.ok: return validation
	_profiles[character_id]["draft"] = validation.data.build.duplicate(true)
	return Result.success({"draft": validation.data.build.duplicate(true), "qualification": _qualification(build)})

func save_preset(character_id: String, slot: int, name: String, progress: Progress = null, inventory: Inventory = null) -> Dictionary:
	if not _profiles.has(character_id): return _unknown()
	if not _slot_valid(slot) or not Config._text(name, int(_config.data.limits.preset_name_length)):
		return Result.failure("preset_invalid", "预设槽或名称无效。")
	var build: Dictionary = _profiles[character_id].draft.duplicate(true)
	var validation := _evaluator.validate_structure(build)
	if not validation.ok: return validation
	var saved := {"name": name, "build": build}
	_profiles[character_id]["presets"][slot] = saved.duplicate(true)
	var status := _evaluator.reference_status(build, progress if progress != null else _progress, inventory if inventory != null else _inventory)
	return Result.success({"preset": saved.duplicate(true), "qualification": status.data.duplicate(true)})

func load_preset_draft(character_id: String, slot: int) -> Dictionary:
	if not _profiles.has(character_id): return _unknown()
	if not _slot_valid(slot): return Result.failure("preset_invalid", "预设槽无效。")
	var saved: Dictionary = _profiles[character_id].presets[slot]
	if saved.build == null: return Result.failure("preset_empty", "该槽尚未保存构筑。")
	return set_draft(character_id, saved.build)

func preview_apply(character_id: String, source: Dictionary, progress: Progress, inventory: Inventory, context: Dictionary, vitals: Dictionary, _combat_state: RefCounted) -> Dictionary:
	if not _profiles.has(character_id): return _unknown()
	if not context.get("session_started") is bool or not context.session_started or not context.get("camp") is bool or not context.camp:
		return Result.failure("camp_required", "只能在已开始游戏的营地应用构筑。")
	if not context.get("encounter_ended") is bool or not context.encounter_ended:
		return Result.failure("encounter_active", "遭遇结束后才能应用构筑。")
	var evaluation := _evaluator.evaluate(source, progress, inventory)
	if not evaluation.ok: return evaluation
	var previous := _evaluator.evaluate(active_build(), progress, inventory)
	if not previous.ok: return previous
	var validity := _validate_vitals(vitals, previous.data.stats)
	if not validity.ok: return validity
	var stats: Dictionary = evaluation.data.stats
	var updates: Dictionary = {}
	for id: String in inventory.equipment_ids():
		var item := inventory.get_equipment(id)
		var expected: bool = id == source.weapon_id
		if item.get("equipped", false) != expected:
			item["equipped"] = expected
			updates[id] = item
	var new_vitals := {"health": float(vitals.health) / float(vitals.max_health) * float(stats.max_health), "stamina": minf(float(vitals.stamina), float(stats.max_stamina)), "max_health": float(stats.max_health), "max_stamina": float(stats.max_stamina)}
	var normalized: Dictionary = _evaluator.validate_structure(source).data.build
	return Result.success({"character_id": character_id, "effective_build": normalized.duplicate(true), "derived_build": evaluation.data.duplicate(true), "new_vitals": new_vitals, "equipment_updates": updates})

func apply(character_id: String, source: Dictionary, progress: Progress, inventory: Inventory, context: Dictionary, vitals: Dictionary, combat_state: RefCounted, operation_id: String) -> Dictionary:
	var preview := preview_apply(character_id, source, progress, inventory, context, vitals, combat_state)
	if not preview.ok: return preview
	var eligibility := inventory.can_apply_operation(operation_id, {}, {}, preview.data.equipment_updates)
	if not eligibility.ok: return eligibility
	var transaction := inventory.apply_operation(operation_id, {}, {}, preview.data.equipment_updates)
	if not transaction.ok: return transaction
	_profiles[character_id]["applied_build"] = preview.data.effective_build.duplicate(true)
	_active_character_id = character_id
	_progress = progress
	_inventory = inventory
	return Result.success(preview.data.duplicate(true))

func snapshot() -> Dictionary:
	return {"schema_version": 1, "active_character_id": _active_character_id, "profiles": _profiles.duplicate(true), "thief_coin_remainder": _thief_coin_remainder}

func restore(candidate: Dictionary, progress: Progress, inventory: Inventory) -> Dictionary:
	if not _config.ready: return Result.failure("rules_unavailable", "角色规则尚未载入。")
	if candidate.has("schema_version") and Rules.is_count(candidate.schema_version, 2, MAX_JSON_INTEGER): return Result.failure("future_schema", "角色档案来自较新版本。")
	if not Config._keys(candidate, ["schema_version", "active_character_id", "profiles", "thief_coin_remainder"]) or not Rules.is_count(candidate.get("schema_version"), 1, 1) or not candidate.get("active_character_id") is String or not _config.data.characters.has(candidate.active_character_id) or not Config._keys(candidate.get("profiles"), _config.data.characters.keys()) or not Rules.is_count(candidate.get("thief_coin_remainder"), 0, 19):
		return Result.failure("build_schema_invalid", "角色档案版本、身份或金币余数无效。")
	for id: String in _config.data.characters:
		var value: Variant = candidate.profiles[id]
		if not Config._keys(value, ["character_id", "applied_build", "draft", "presets"]) or value.character_id != id or not value.applied_build is Dictionary or not value.draft is Dictionary or not value.presets is Array or value.presets.size() != int(_config.data.limits.preset_slots):
			return Result.failure("build_schema_invalid", "角色档案或预设槽结构无效。")
		for build: Dictionary in [value.applied_build, value.draft]:
			var structure := _evaluator.validate_structure(build)
			if not structure.ok: return structure
		for slot: Variant in value.presets:
			if not Config._keys(slot, ["name", "build"]) or not slot.name is String: return Result.failure("build_schema_invalid", "预设内容结构无效。")
			if slot.build == null:
				if slot.name != "": return Result.failure("build_schema_invalid", "空预设不能带名称。")
			else:
				if not Config._text(slot.name, int(_config.data.limits.preset_name_length)) or not slot.build is Dictionary: return Result.failure("build_schema_invalid", "已保存预设缺少名称或构筑。")
				var structure := _evaluator.validate_structure(slot.build)
				if not structure.ok: return structure
	var evaluation := _evaluator.evaluate(candidate.profiles[candidate.active_character_id].applied_build, progress, inventory)
	if not evaluation.ok: return evaluation
	var profiles: Dictionary = candidate.profiles.duplicate(true)
	for id: String in profiles:
		for key: String in ["applied_build", "draft"]: profiles[id][key] = _evaluator.validate_structure(profiles[id][key]).data.build
		for saved: Dictionary in profiles[id].presets:
			if saved.build != null: saved["build"] = _evaluator.validate_structure(saved.build).data.build
	_profiles = profiles
	_active_character_id = candidate.active_character_id
	_thief_coin_remainder = int(candidate.thief_coin_remainder)
	_progress = progress
	_inventory = inventory
	return Result.success({"derived_build": evaluation.data.duplicate(true)})

func references_to(weapon_id: String) -> Array[Dictionary]:
	var references: Array[Dictionary] = []
	for id: String in _profiles:
		for kind: String in ["applied_build", "draft"]:
			if _profiles[id][kind].weapon_id == weapon_id: references.append({"character_id": id, "kind": kind, "slot": -1})
		for index: int in range(_profiles[id].presets.size()):
			var saved: Dictionary = _profiles[id].presets[index]
			if saved.build != null and saved.build.weapon_id == weapon_id: references.append({"character_id": id, "kind": "preset", "slot": index, "name": saved.name})
	return references

func can_commit_coin_remainder(expected: int, updated: int) -> Dictionary:
	if _profiles.is_empty() or expected != _thief_coin_remainder or updated < 0 or updated >= 20:
		return Result.failure("coin_remainder_invalid", "怪币余数已变化或超出合法范围。")
	return Result.success()

func commit_coin_remainder(expected: int, updated: int) -> Dictionary:
	var validation := can_commit_coin_remainder(expected, updated)
	if not validation.ok: return validation
	_thief_coin_remainder = updated
	return Result.success({"thief_coin_remainder": updated})

func _qualification(build: Dictionary) -> Dictionary:
	return _evaluator.reference_status(build, _progress, _inventory).data.duplicate(true)

func _slot_valid(slot: int) -> bool:
	return slot >= 0 and slot < int(_config.data.limits.preset_slots)

func _validate_vitals(vitals: Dictionary, current_stats: Dictionary) -> Dictionary:
	if not Config._keys(vitals, ["health", "stamina", "max_health", "max_stamina"]): return Result.failure("vitals_invalid", "生命与体力字段无效。")
	for key: String in vitals:
		if not Config._number(vitals[key], 0, 1000000): return Result.failure("vitals_invalid", "生命或体力不是有限合法数值。")
	if float(vitals.health) == 0.0: return Result.failure("actor_dead", "失去生命时不能切换或应用构筑。")
	if float(vitals.max_health) <= 0.0 or float(vitals.max_stamina) <= 0.0 or float(vitals.health) > float(vitals.max_health) or float(vitals.stamina) > float(vitals.max_stamina) or not is_equal_approx(float(vitals.max_health), float(current_stats.max_health)) or not is_equal_approx(float(vitals.max_stamina), float(current_stats.max_stamina)):
		return Result.failure("vitals_invalid", "当前上限与已生效构筑不一致。")
	return Result.success()

static func _unknown() -> Dictionary:
	return Result.failure("character_unknown", "角色不存在或档案尚未初始化。")
