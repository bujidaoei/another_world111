extends RefCounted
class_name AWWorldProgress

const Result = preload("res://config/rule_result.gd")
var _rules: RefCounted
var level: int = 1
var realm: int = 1
var experience: int = 0
var banked_experience: int = 0
var earned_talent_points: int = 0
var _ascension_records: Dictionary = {}
var _applied_operations: Dictionary = {}

func _init(rules: RefCounted) -> void:
	_rules = rules

func can_award_experience(amount: int, operation_id: String) -> Dictionary:
	if not _rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	if operation_id.is_empty() or _applied_operations.has(operation_id):
		return Result.failure("duplicate_operation", "经验事件已处理或标识无效。")
	if amount < 0 or amount > int(_rules.data.progression.maximum_award) or banked_experience > 1000000000 - amount:
		return Result.failure("experience_invalid", "经验数量无效或超过上限。")
	return Result.success()

func award_experience(amount: int, operation_id: String) -> Dictionary:
	var validation := can_award_experience(amount, operation_id)
	if not validation.ok:
		return validation
	var old_level := level
	_distribute_experience(amount)
	_applied_operations[operation_id] = true
	return Result.success({"levels_gained": level - old_level, "level": level, "realm": realm, "banked_experience": banked_experience})

func _distribute_experience(amount: int) -> void:
	var threshold := int(_rules.data.progression.experience_per_level)
	var cap := realm * int(_rules.data.progression.levels_per_realm)
	if level >= cap:
		banked_experience += amount
		return
	experience += amount
	while experience >= threshold and level < cap:
		experience -= threshold
		level += 1
		earned_talent_points += 1
	if level == cap:
		banked_experience += experience
		experience = 0

func complete_ascension(challenge_id: String, operation_id: String, victory: Dictionary) -> Dictionary:
	if not _rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	if operation_id.is_empty() or _applied_operations.has(operation_id) or _ascension_records.has(challenge_id):
		return Result.failure("duplicate_operation", "晋阶事件已处理。")
	if realm >= int(_rules.data.progression.maximum_realm) or level != realm * int(_rules.data.progression.levels_per_realm):
		return Result.failure("ascension_ineligible", "尚未达到个人晋阶门槛。")
	if challenge_id != str(_rules.data.progression.ascension_challenge) or victory.get("challenge_id") != challenge_id or victory.get("outcome") != "victory" or not victory.get("run_id") is String or str(victory.run_id).is_empty() or not victory.get("defeated_enemy_ids") is Array or not challenge_id in victory.defeated_enemy_ids:
		return Result.failure("challenge_not_won", "个人挑战尚未真实胜利。")
	realm += 1
	_ascension_records[challenge_id] = {"run_id": victory.run_id, "operation_id": operation_id, "realm": realm}
	_applied_operations[operation_id] = true
	var released := banked_experience
	banked_experience = 0
	_distribute_experience(released)
	return Result.success({"realm": realm, "level": level, "released_experience": released})

func snapshot() -> Dictionary:
	return {"level": level, "realm": realm, "experience": experience, "banked_experience": banked_experience, "earned_talent_points": earned_talent_points, "ascension_records": _ascension_records.duplicate(true), "applied_operations": _applied_operations.duplicate(true)}

func restore(state: Dictionary) -> Dictionary:
	if not _rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	for key: String in ["level", "realm", "experience", "banked_experience", "earned_talent_points"]:
		if not _rules.is_count(state.get(key), 0, 1000000000):
			return Result.failure("progress_invalid", "存档成长字段无效。")
	var incoming_level := int(state.level)
	var incoming_realm := int(state.realm)
	var incoming_experience := int(state.experience)
	var cap := incoming_realm * int(_rules.data.progression.levels_per_realm)
	var minimum_level := maxi(1, (incoming_realm - 1) * int(_rules.data.progression.levels_per_realm))
	if incoming_realm < 1 or incoming_realm > int(_rules.data.progression.maximum_realm) or incoming_level < minimum_level or incoming_level > cap or incoming_experience >= int(_rules.data.progression.experience_per_level) or int(state.earned_talent_points) != incoming_level - 1 or (incoming_level == cap and incoming_experience != 0) or (incoming_level < cap and int(state.banked_experience) != 0):
		return Result.failure("progress_invalid", "成长字段违反境界、经验或天赋不变量。")
	if not state.get("ascension_records") is Dictionary or not state.get("applied_operations") is Dictionary:
		return Result.failure("progress_invalid", "成长事件记录无效。")
	if incoming_realm == 2 and not state.ascension_records.has(str(_rules.data.progression.ascension_challenge)):
		return Result.failure("progress_invalid", "二阶存档缺少晋阶记录。")
	if state.ascension_records.size() != incoming_realm - 1:
		return Result.failure("progress_invalid", "境界与晋阶记录数量不一致。")
	for challenge_id: Variant in state.ascension_records:
		var record: Variant = state.ascension_records[challenge_id]
		if challenge_id != str(_rules.data.progression.ascension_challenge) or not record is Dictionary or not record.get("run_id") is String or record.run_id.is_empty() or not record.get("operation_id") is String or record.operation_id.is_empty() or not state.applied_operations.has(record.operation_id) or not _rules.is_count(record.get("realm"), 2, 2):
			return Result.failure("progress_invalid", "晋阶事件缺少有效来源或对应操作记录。")
	for operation: Variant in state.applied_operations:
		if not operation is String or operation.is_empty() or state.applied_operations[operation] != true:
			return Result.failure("progress_invalid", "成长操作记录无效。")
	level = incoming_level
	realm = incoming_realm
	experience = incoming_experience
	banked_experience = int(state.banked_experience)
	earned_talent_points = int(state.earned_talent_points)
	_ascension_records = state.ascension_records.duplicate(true)
	_applied_operations = state.applied_operations.duplicate(true)
	return Result.success()
