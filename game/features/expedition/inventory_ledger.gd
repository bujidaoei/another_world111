extends RefCounted
class_name AWInventoryLedger

const Result = preload("res://config/rule_result.gd")
const Equipment = preload("res://features/equipment/equipment_instance.gd")
var _rules: RefCounted
var _resources: Dictionary = {}
var _equipment: Dictionary = {}
var _applied_operations: Dictionary = {}

func _init(rules: RefCounted) -> void:
	_rules = rules
	if _rules.ready:
		for resource: String in _rules.data.resources:
			_resources[resource] = int(_rules.data.inventory.starting_resources.get(resource, 0))

func count(resource: String) -> int:
	return int(_resources.get(resource, 0))

func can_apply_operation(operation_id: String, cost: Dictionary, grant_resources: Dictionary = {}, updates: Dictionary = {}, remove_ids: Array[String] = []) -> Dictionary:
	if not _rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	if operation_id.is_empty() or _applied_operations.has(operation_id):
		return Result.failure("duplicate_operation", "操作已完成或标识无效。")
	for amounts: Dictionary in [cost, grant_resources]:
		var validation: Dictionary = _rules.validate_resources(amounts)
		if not validation.ok:
			return validation
	for resource: String in _rules.data.resources:
		var needed := int(cost.get(resource, 0))
		var resulting := count(resource) - needed + int(grant_resources.get(resource, 0))
		if count(resource) < needed:
			return Result.failure("insufficient_resources", "资源不足：%s。" % resource)
		if resulting > int(_rules.data.inventory.maximum_quantity):
			return Result.failure("inventory_overflow", "资源数量超过库存上限。")
	var seen: Dictionary = {}
	for id: String in remove_ids:
		if not _equipment.has(id) or seen.has(id) or updates.has(id):
			return Result.failure("equipment_transaction_invalid", "材料装备不存在、重复或同时被更新。")
		seen[id] = true
		if _equipment[id].get("equipped", false):
			return Result.failure("material_equipped", "已装备的物品不能作为材料。")
	for id: Variant in updates:
		if not id is String or not _equipment.has(id) or not updates[id] is Dictionary or updates[id].get("instance_id") != id:
			return Result.failure("equipment_transaction_invalid", "更新装备身份无效。")
		var validation := Equipment.validate(updates[id], _rules)
		if not validation.ok:
			return validation
	return Result.success()

func apply_operation(operation_id: String, cost: Dictionary, grant_resources: Dictionary = {}, updates: Dictionary = {}, remove_ids: Array[String] = []) -> Dictionary:
	var validation := can_apply_operation(operation_id, cost, grant_resources, updates, remove_ids)
	if not validation.ok:
		return validation
	for resource: String in _rules.data.resources:
		_resources[resource] = count(resource) - int(cost.get(resource, 0)) + int(grant_resources.get(resource, 0))
	for id: String in remove_ids:
		_equipment.erase(id)
	for id: String in updates:
		_equipment[id] = updates[id].duplicate(true)
	_applied_operations[operation_id] = true
	return Result.success({"resources": _resources.duplicate(true), "equipment_updates": updates.duplicate(true)})

func grant(resources: Dictionary, operation_id: String) -> Dictionary:
	return apply_operation(operation_id, {}, resources)

func add_equipment(equipment: Dictionary) -> Dictionary:
	var validation := Equipment.validate(equipment, _rules)
	if not validation.ok:
		return validation
	if _equipment.has(equipment.instance_id):
		return Result.failure("equipment_duplicate", "装备实例已存在。")
	_equipment[equipment.instance_id] = equipment.duplicate(true)
	return Result.success({"instance_id": equipment.instance_id})

func equipment_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _equipment:
		ids.append(id)
	ids.sort()
	return ids

func get_equipment(id: String) -> Dictionary:
	return _equipment.get(id, {}).duplicate(true)

func snapshot() -> Dictionary:
	return {"resources": _resources.duplicate(true), "equipment": _equipment.duplicate(true), "applied_operations": _applied_operations.duplicate(true)}

func restore(state: Dictionary) -> Dictionary:
	if not _rules.ready or not state.get("resources") is Dictionary or not state.get("equipment") is Dictionary or not state.get("applied_operations") is Dictionary:
		return Result.failure("inventory_invalid", "库存存档结构无效。")
	var validation: Dictionary = _rules.validate_resources(state.resources)
	if not validation.ok:
		return validation
	for resource: String in _rules.data.resources:
		if not state.resources.has(resource) or not _rules.is_count(state.resources[resource], 0, int(_rules.data.inventory.maximum_quantity)):
			return Result.failure("inventory_invalid", "库存存档资源缺失或溢出。")
	for id: Variant in state.equipment:
		if not id is String or not state.equipment[id] is Dictionary or state.equipment[id].get("instance_id") != id:
			return Result.failure("inventory_invalid", "库存装备身份无效。")
		validation = Equipment.validate(state.equipment[id], _rules)
		if not validation.ok:
			return validation
	for operation: Variant in state.applied_operations:
		if not operation is String or operation.is_empty() or state.applied_operations[operation] != true:
			return Result.failure("inventory_invalid", "库存操作记录无效。")
	_resources = state.resources.duplicate(true)
	_equipment = state.equipment.duplicate(true)
	_applied_operations = state.applied_operations.duplicate(true)
	return Result.success()
