extends RefCounted
class_name AWBuildMigration
## Pure payload boundary: creates only candidate domain models, never applies live state or performs IO.

const Result = preload("res://config/rule_result.gd")
const Rules = preload("res://config/rules_config.gd")
const Config = preload("res://config/character_builds_config.gd")
const Evaluator = preload("res://features/characters/build_evaluator.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Roster = preload("res://features/characters/character_roster.gd")
const Combat = preload("res://features/combat/combat_state.gd")
const Settings = preload("res://persistence/game_settings.gd")
const Bindings = preload("res://platform/input_bindings.gd")
const Repository = preload("res://persistence/save_repository.gd")
const DOMAIN_VERSION: int = 2
const LEGACY_FIELDS: Array[String] = ["world", "inventory", "active_weapon_id", "run_counter", "operation_counter", "bench_built", "health", "stamina", "settings", "input_bindings", "interrupted_expedition"]

static func migrate_payload(payload: Dictionary, config: Config, evaluator: Evaluator) -> Dictionary:
	if not config.ready or not evaluator.get_rules().ready: return Result.failure("rules_unavailable", "迁移规则尚未正确载入。")
	var version: Variant = payload.get("domain_version", 1)
	if not Rules.is_count(version, 1, Repository.MAX_SAFE_INTEGER): return Result.failure("invalid_domain", "进度领域版本无效。")
	if int(version) > DOMAIN_VERSION: return Result.failure("future_schema", "进度由较新领域版本创建，当前版本不会覆盖它。")
	var fields := LEGACY_FIELDS.duplicate()
	if payload.has("domain_version"): fields.append("domain_version")
	if int(version) == DOMAIN_VERSION: fields.append_array(["character_builds", "combat_state"])
	if not _keys(payload, fields): return Result.failure("payload_schema_invalid", "进度领域字段缺少、多余或新旧格式不配对。")
	if not _json_safe(payload, 0, {"count": 0}) or JSON.stringify(payload).to_utf8_buffer().size() > Repository.MAX_FILE_BYTES:
		return Result.failure("payload_invalid", "进度超出安全容量或包含非JSON数据。")
	if not _keys(payload.get("world"), ["level", "realm", "experience", "banked_experience", "earned_talent_points", "ascension_records", "applied_operations"]) or not _keys(payload.get("inventory"), ["resources", "equipment", "applied_operations"]):
		return Result.failure("payload_schema_invalid", "世界或库存字段不完整。")
	var rules: Rules = evaluator.get_rules()
	var progress := Progress.new(rules)
	var inventory := Inventory.new(rules)
	var world_result := progress.restore(payload.world)
	if not world_result.ok: return world_result
	var inventory_result := inventory.restore(payload.inventory)
	if not inventory_result.ok: return inventory_result
	if not payload.get("active_weapon_id") is String or str(payload.active_weapon_id).is_empty() or str(payload.active_weapon_id).length() > int(config.data.limits.weapon_id_length):
		return Result.failure("equipment_missing", "当前装备引用无效。")
	for field: String in ["run_counter", "operation_counter"]:
		if not Rules.is_count(payload[field]): return Result.failure("payload_counter_invalid", "进度操作计数无效。")
	for field: String in ["bench_built", "interrupted_expedition"]:
		if not payload[field] is bool: return Result.failure("payload_flag_invalid", "营地状态必须是布尔值。")
	if not payload.settings is Dictionary or not payload.input_bindings is Dictionary: return Result.failure("payload_schema_invalid", "设置或键位结构无效。")
	var settings := Settings.normalize(payload.settings) if int(version) == 1 else Settings.validate(payload.settings)
	if not settings.ok: return settings
	var bindings := Bindings.normalize_snapshot(payload.input_bindings)
	if not bindings.ok: return bindings
	var roster := Roster.new(config, evaluator)
	var combat := Combat.new(config)
	var roster_result: Dictionary
	var combat_result: Dictionary
	if int(version) == 1:
		roster_result = roster.initialize(payload.active_weapon_id, progress, inventory)
		combat_result = Result.success(combat.snapshot())
	else:
		if not payload.character_builds is Dictionary or not payload.combat_state is Dictionary: return Result.failure("payload_schema_invalid", "角色与共享战斗领域必须完整配对。")
		roster_result = roster.restore(payload.character_builds, progress, inventory)
		combat_result = combat.restore(payload.combat_state)
	if not roster_result.ok: return roster_result
	if not combat_result.ok: return combat_result
	# Shared cooldowns/effects can outlive loadout and weapon changes, never their world unlock.
	var shared_state := combat.snapshot()
	if progress.realm < int(config.skill("focus").required_realm) and (float(shared_state.cooldowns.focus) > 0.0 or float(shared_state.effects.focus_remaining) > 0.0):
		return Result.failure("skill_locked", "当前世界尚未解锁聚焦，不能恢复其冷却或持续增益。")
	if progress.realm < int(rules.data.combat.anchor_required_realm) and float(shared_state.cooldowns.anchor) > 0.0:
		return Result.failure("realm_required", "当前世界尚未解锁锚点，不能恢复其持续冷却。")
	if roster.active_build().weapon_id != payload.active_weapon_id: return Result.failure("active_weapon_conflict", "活动角色与当前装备引用冲突，未静默替换。")
	var evaluation := evaluator.evaluate(roster.active_build(), progress, inventory)
	if not evaluation.ok: return evaluation
	var stats: Dictionary = evaluation.data.stats
	if not _number(payload.health, 0.0, float(stats.max_health)) or not _number(payload.stamina, 0.0, float(stats.max_stamina)):
		return Result.failure("payload_vitals_invalid", "进度生命或体力超出已生效上限，未补给或截断。")
	var normalized := payload.duplicate(true)
	normalized["domain_version"] = DOMAIN_VERSION
	normalized["world"] = progress.snapshot()
	normalized["inventory"] = inventory.snapshot()
	var equip_changed := false
	for item_id: String in normalized.inventory.equipment:
		var active := item_id == str(payload.active_weapon_id)
		if bool(normalized.inventory.equipment[item_id].get("equipped", false)) != active or not normalized.inventory.equipment[item_id].has("equipped"): equip_changed = true
		normalized["inventory"]["equipment"][item_id]["equipped"] = active
	normalized["settings"] = settings.data
	normalized["input_bindings"] = bindings.data
	normalized["character_builds"] = roster.snapshot()
	normalized["combat_state"] = combat.snapshot()
	normalized["run_counter"] = int(payload.run_counter)
	normalized["operation_counter"] = int(payload.operation_counter)
	normalized["health"] = float(payload.health)
	normalized["stamina"] = float(payload.stamina)
	var result := Result.success(normalized)
	result["migrated"] = int(version) == 1 or bool(bindings.get("migrated", false)) or equip_changed
	return result

static func _keys(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size(): return false
	for key: Variant in value:
		if not key is String or key not in fields: return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _json_safe(value: Variant, depth: int, budget: Dictionary) -> bool:
	budget["count"] += 1
	if depth > Repository.MAX_DEPTH or int(budget.count) > Repository.MAX_VALUES: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL: return true
		TYPE_INT, TYPE_FLOAT: return _number(value, -Repository.MAX_SAFE_INTEGER, Repository.MAX_SAFE_INTEGER)
		TYPE_STRING: return value.to_utf8_buffer().size() <= Repository.MAX_FILE_BYTES
		TYPE_ARRAY:
			for child: Variant in value:
				if not _json_safe(child, depth + 1, budget): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or key.to_utf8_buffer().size() > Repository.MAX_FILE_BYTES or not _json_safe(value[key], depth + 1, budget): return false
			return true
	return false
