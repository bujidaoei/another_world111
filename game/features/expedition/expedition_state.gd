extends RefCounted
class_name AWExpeditionState

const Result = preload("res://config/rule_result.gd")
const SNAPSHOT_FIELDS: Array[String] = ["state", "run_id", "region_id", "challenge", "outcome", "pending_loot", "defeated_enemy_ids", "gathered_node_ids", "objective_completed", "rewards_committed", "used_run_ids", "character_id", "starting_coin_remainder", "pending_coin_remainder"]
enum State { DORMANT, ACTIVE, VICTORY, FAILURE, EVACUATION_PENDING, ENDED }
var _rules: RefCounted
var state: State = State.DORMANT
var run_id: String = ""
var region_id: String = ""
var challenge: bool = false
var outcome: String = ""
var pending_loot: Dictionary = {}
var defeated_enemy_ids: Array[String] = []
var gathered_node_ids: Array[String] = []
var objective_completed: bool = false
var rewards_committed: bool = false
var _used_run_ids: Dictionary = {}
var _characters: RefCounted
var _character_id := ""
var _starting_coin_remainder := 0
var _pending_coin_remainder := 0

func _init(rules: RefCounted, characters: RefCounted = null) -> void:
	_rules = rules
	_characters = characters

func begin(new_run_id: String, new_region_id: String, is_challenge: bool = false, realm: int = 1, world_level: int = 1, character_id: String = "", starting_coin_remainder: int = 0) -> Dictionary:
	if not _rules.ready:
		return Result.failure("rules_unavailable", "规则尚未载入。")
	if not _valid_bonus_context(character_id, starting_coin_remainder, false):
		return Result.failure("character_reward_invalid", "远征身份或金币余数无效。")
	if state != State.DORMANT and state != State.ENDED:
		return Result.failure("encounter_active", "上一遭遇尚未结束。")
	if state == State.ENDED and outcome != "failed" and not rewards_committed:
		return Result.failure("settlement_pending", "上一远征还未结算。")
	if new_run_id.is_empty() or _used_run_ids.has(new_run_id):
		return Result.failure("run_duplicate", "远征标识无效或已经使用。")
	if not _rules.data.regions.has(new_region_id):
		return Result.failure("region_unknown", "探索区域不存在。")
	if realm < int(_rules.data.regions[new_region_id].required_realm):
		return Result.failure("realm_required", "当前个人境界无法进入此区域。")
	if is_challenge and (new_region_id != "rain_court" or realm != 1 or world_level != int(_rules.data.challenge.minimum_level)):
		return Result.failure("challenge_ineligible", "个人晋阶挑战需要一阶30级。")
	run_id = new_run_id
	region_id = new_region_id
	challenge = is_challenge
	outcome = ""
	pending_loot = {}
	defeated_enemy_ids.clear()
	gathered_node_ids.clear()
	objective_completed = false
	rewards_committed = false
	_character_id = character_id
	_starting_coin_remainder = starting_coin_remainder
	_pending_coin_remainder = starting_coin_remainder
	_used_run_ids[run_id] = true
	state = State.ACTIVE
	return Result.success({"enemy_ids": enemy_ids(), "nodes": node_definitions()})

func enemy_ids() -> Array[String]:
	var ids: Array[String] = []
	if region_id.is_empty():
		return ids
	if challenge:
		ids.append(str(_rules.data.challenge.enemy_id))
	else:
		for id: String in _rules.data.regions[region_id].enemy_ids:
			ids.append(id)
	return ids

func node_definitions() -> Dictionary:
	if region_id.is_empty() or challenge:
		return {}
	return _rules.data.regions[region_id].nodes.duplicate(true)

func record_kill(enemy_id: String, progress: RefCounted) -> Dictionary:
	if state != State.ACTIVE:
		return Result.failure("encounter_not_active", "当前没有进行中的遭遇。")
	if not enemy_id in enemy_ids() or enemy_id in defeated_enemy_ids:
		return Result.failure("enemy_reward_invalid", "敌人未登记或奖励已记录。")
	var region: Dictionary = _rules.data.regions[region_id]
	var xp := int(_rules.data.challenge.experience if challenge else region.kill_experience)
	var reward: Dictionary = {} if challenge else region.kill_reward.duplicate(true)
	var next_remainder := _pending_coin_remainder
	var extra_coins := 0
	if not challenge and _characters != null:
		var character: Dictionary = _characters.data.characters[_character_id]
		var accumulated := _pending_coin_remainder + int(reward.get("currency", 0)) * int(character.monster_coin_numerator)
		var denominator := int(character.monster_coin_denominator)
		extra_coins = floori(float(accumulated) / float(denominator))
		next_remainder = accumulated % denominator
		if extra_coins > 0:
			reward["currency"] = int(reward.get("currency", 0)) + extra_coins
	var cargo_check := _can_add_loot(reward)
	if not cargo_check.ok:
		return cargo_check
	var award: Dictionary = progress.award_experience(xp, "%s:kill:%s" % [run_id, enemy_id])
	if not award.ok:
		return award
	defeated_enemy_ids.append(enemy_id)
	_add_loot(reward)
	_pending_coin_remainder = next_remainder
	return Result.success({"experience": xp, "pending_loot": pending_loot.duplicate(true), "enemy_id": enemy_id, "extra_monster_coins": extra_coins, "pending_coin_remainder": _pending_coin_remainder})

func gather(node_id: String) -> Dictionary:
	if state != State.ACTIVE:
		return Result.failure("encounter_not_active", "当前没有进行中的遭遇。")
	var nodes := node_definitions()
	if not nodes.has(node_id) or node_id in gathered_node_ids:
		return Result.failure("node_reward_invalid", "采集节点未登记或已经采集。")
	var validation := _can_add_loot(nodes[node_id])
	if not validation.ok:
		return validation
	gathered_node_ids.append(node_id)
	_add_loot(nodes[node_id])
	return Result.success({"resources": nodes[node_id].duplicate(true), "cargo_weight": cargo_weight(), "capacity": int(_rules.data.inventory.cargo_capacity)})

func complete_objective(progress: RefCounted) -> Dictionary:
	if state != State.ACTIVE or challenge:
		return Result.failure("objective_unavailable", "当前遭遇没有探索目标任务。")
	if objective_completed:
		return Result.failure("objective_already_completed", "目标任务奖励已记录。")
	var objective: Dictionary = _rules.data.regions[region_id].objective
	if defeated_enemy_ids.size() < int(objective.kills) or gathered_node_ids.size() < int(objective.nodes):
		return Result.failure("objective_incomplete", "需要击败3个敌人并采集2个节点。")
	var validation := _can_add_loot(objective.reward)
	if not validation.ok:
		return validation
	var award: Dictionary = progress.award_experience(int(objective.experience), "%s:objective" % run_id)
	if not award.ok:
		return award
	objective_completed = true
	_add_loot(objective.reward)
	return Result.success({"experience": int(objective.experience), "pending_loot": pending_loot.duplicate(true)})

func aggro_lost() -> Dictionary:
	if state != State.ACTIVE:
		return Result.failure("encounter_not_active", "当前没有进行中的遭遇。")
	return Result.success({"state": state, "encounter_ended": false})

func resolve(result_outcome: String, progress: RefCounted) -> Dictionary:
	if state != State.ACTIVE:
		return Result.failure("encounter_not_active", "遭遇结果已确定或尚未开始。")
	if not result_outcome in ["victory", "failed", "evacuated"]:
		return Result.failure("outcome_invalid", "遭遇结果无效。")
	if result_outcome == "victory":
		if challenge:
			var challenge_id := str(_rules.data.challenge.enemy_id)
			if not challenge_id in defeated_enemy_ids:
				return Result.failure("challenge_not_won", "晋阶守卫仍未击败。")
			var validation := _can_add_loot(_rules.data.challenge.reward)
			if not validation.ok:
				return validation
			var ascension: Dictionary = progress.complete_ascension(challenge_id, "%s:ascension" % run_id, {"challenge_id": challenge_id, "run_id": run_id, "defeated_enemy_ids": defeated_enemy_ids.duplicate(), "outcome": "victory"})
			if not ascension.ok:
				return ascension
			_add_loot(_rules.data.challenge.reward)
		elif not objective_completed:
			return Result.failure("objective_incomplete", "尚未完成探索目标。")
	outcome = result_outcome
	if outcome == "failed":
		pending_loot.clear()
		_pending_coin_remainder = _starting_coin_remainder
		state = State.FAILURE
	elif outcome == "victory":
		state = State.VICTORY
	else:
		state = State.EVACUATION_PENDING
	return Result.success({"outcome": outcome, "pending_loot": pending_loot.duplicate(true)})

func reset() -> Dictionary:
	if not state in [State.VICTORY, State.FAILURE, State.EVACUATION_PENDING]:
		return Result.failure("reset_invalid", "遭遇结果尚未确定，不能通过脱战重置。")
	state = State.ENDED
	return Result.success({"encounter_ended": true})

func is_ended() -> bool:
	return state == State.DORMANT or state == State.ENDED

func settlement_operation_id() -> String:
	return "expedition-settlement:" + run_id

func commit_rewards(inventory: AWInventoryLedger, roster: AWCharacterRoster = null, new_equipment: Array[Dictionary] = []) -> Dictionary:
	if state != State.ENDED or outcome == "failed":
		return Result.failure("settlement_unavailable", "需要成功撤离且完成遭遇重置才能入库。")
	if rewards_committed:
		return Result.failure("rewards_already_committed", "远征战利品已经入库。")
	var operation_id := settlement_operation_id()
	var remove_ids: Array[String] = []
	if _characters != null:
		if roster == null or roster.active_character_id != _character_id:
			return Result.failure("character_reward_invalid", "角色收益需要与库存共同结算。")
		var remainder_check := roster.can_commit_coin_remainder(_starting_coin_remainder, _pending_coin_remainder)
		if not remainder_check.ok:
			return remainder_check
	var inventory_check: Dictionary = inventory.can_apply_operation(operation_id, {}, pending_loot, {}, remove_ids, new_equipment)
	if not inventory_check.ok:
		return inventory_check
	var transaction: Dictionary = inventory.apply_operation(operation_id, {}, pending_loot, {}, remove_ids, new_equipment)
	if not transaction.ok:
		return transaction
	# Both domains are synchronous RefCounted rules without signals or callbacks.
	# The preflighted scalar CAS cannot change between these two assignments.
	if _characters != null:
		var remainder_committed := roster.commit_coin_remainder(_starting_coin_remainder, _pending_coin_remainder)
		if not remainder_committed.ok:
			return Result.failure("settlement_invariant", "角色收益事务验证异常，请保留已有存档和诊断。")
	rewards_committed = true
	return Result.success({"resources": pending_loot.duplicate(true), "coin_remainder": _pending_coin_remainder})

func cargo_weight() -> int:
	var weight: int = 0
	for resource: String in pending_loot:
		weight += int(pending_loot[resource]) * int(_rules.data.resources[resource].weight)
	return weight

func _can_add_loot(resources: Dictionary) -> Dictionary:
	var validation: Dictionary = _rules.validate_resources(resources)
	if not validation.ok:
		return validation
	var extra: int = 0
	for resource: String in resources:
		extra += int(resources[resource]) * int(_rules.data.resources[resource].weight)
	if cargo_weight() + extra > int(_rules.data.inventory.cargo_capacity):
		return Result.failure("cargo_full", "携带重量不足，请先撤离。")
	return Result.success()

func _add_loot(resources: Dictionary) -> void:
	for resource: String in resources:
		pending_loot[resource] = int(pending_loot.get(resource, 0)) + int(resources[resource])

func snapshot() -> Dictionary:
	return {"state": state, "run_id": run_id, "region_id": region_id, "challenge": challenge, "outcome": outcome, "pending_loot": pending_loot.duplicate(true), "defeated_enemy_ids": defeated_enemy_ids.duplicate(), "gathered_node_ids": gathered_node_ids.duplicate(), "objective_completed": objective_completed, "rewards_committed": rewards_committed, "used_run_ids": _used_run_ids.duplicate(true), "character_id": _character_id, "starting_coin_remainder": _starting_coin_remainder, "pending_coin_remainder": _pending_coin_remainder}

func restore(saved: Dictionary) -> Dictionary:
	if saved.size() != SNAPSHOT_FIELDS.size():
		return Result.failure("expedition_invalid", "远征状态字段缺失或包含未知字段。")
	for key: Variant in saved:
		if not key is String or not key in SNAPSHOT_FIELDS:
			return Result.failure("expedition_invalid", "远征状态包含未知字段。")
	if not _rules.ready or not _rules.is_count(saved.get("state"), State.DORMANT, State.ENDED) or not saved.get("run_id") is String or not saved.get("region_id") is String or not saved.get("outcome") is String or not saved.get("challenge") is bool or not saved.get("objective_completed") is bool or not saved.get("rewards_committed") is bool or not saved.get("pending_loot") is Dictionary or not saved.get("defeated_enemy_ids") is Array or not saved.get("gathered_node_ids") is Array or not saved.get("used_run_ids") is Dictionary:
		return Result.failure("expedition_invalid", "远征存档结构无效。")
	var saved_state := int(saved.state)
	if not saved.get("character_id") is String or not _rules.is_count(saved.get("starting_coin_remainder"), 0, 19) or not _rules.is_count(saved.get("pending_coin_remainder"), 0, 19) or not _valid_bonus_context(str(saved.character_id), int(saved.starting_coin_remainder), saved_state == State.DORMANT):
		return Result.failure("character_reward_invalid", "远征身份或金币余数无效。")
	if saved_state in [State.DORMANT, State.ACTIVE] and saved.outcome != "":
		return Result.failure("expedition_invalid", "未结束遭遇不能含结算结果。")
	if saved_state == State.DORMANT and (saved.run_id != "" or saved.region_id != "" or saved.challenge or not saved.pending_loot.is_empty() or not saved.defeated_enemy_ids.is_empty() or not saved.gathered_node_ids.is_empty() or saved.objective_completed or saved.rewards_committed):
		return Result.failure("expedition_invalid", "未开始远征含无来源状态。")
	var expected_outcome: Dictionary = {State.VICTORY: "victory", State.FAILURE: "failed", State.EVACUATION_PENDING: "evacuated"}
	if (expected_outcome.has(saved_state) and saved.outcome != expected_outcome[saved_state]) or (saved_state == State.ENDED and not saved.outcome in ["victory", "failed", "evacuated"]):
		return Result.failure("expedition_invalid", "遭遇状态与结果不一致。")
	if saved.challenge and (saved.region_id != "rain_court" or saved.objective_completed or (saved.outcome == "victory" and not str(_rules.data.challenge.enemy_id) in saved.defeated_enemy_ids)):
		return Result.failure("expedition_invalid", "晋阶挑战存档没有真实守卫胜利事件。")
	if saved_state != State.DORMANT and (saved.run_id.is_empty() or not _rules.data.regions.has(saved.region_id) or not saved.used_run_ids.has(saved.run_id)):
		return Result.failure("expedition_invalid", "远征标识或区域无效。")
	var validation: Dictionary = _rules.validate_resources(saved.pending_loot)
	if not validation.ok:
		return validation
	var weight: int = 0
	for resource: String in saved.pending_loot:
		weight += int(saved.pending_loot[resource]) * int(_rules.data.resources[resource].weight)
	if weight > int(_rules.data.inventory.cargo_capacity) or (saved.outcome == "failed" and not saved.pending_loot.is_empty()) or (saved_state == State.ACTIVE and not saved.outcome.is_empty()) or (saved.rewards_committed and (saved_state != State.ENDED or saved.outcome == "failed")):
		return Result.failure("expedition_invalid", "远征状态或战利品违反不变量。")
	var allowed_enemies: Array = [str(_rules.data.challenge.enemy_id)] if saved.challenge else _rules.data.regions.get(saved.region_id, {}).get("enemy_ids", [])
	var nodes: Dictionary = {} if saved.challenge else _rules.data.regions.get(saved.region_id, {}).get("nodes", {})
	if saved.objective_completed:
		var objective: Dictionary = _rules.data.regions[saved.region_id].objective
		if saved.defeated_enemy_ids.size() < int(objective.kills) or saved.gathered_node_ids.size() < int(objective.nodes):
			return Result.failure("expedition_invalid", "目标任务缺少真实击杀或采集事件。")
	if not saved.challenge and saved.outcome == "victory" and not saved.objective_completed:
		return Result.failure("expedition_invalid", "胜利远征缺少目标任务完成记录。")
	for pair: Array in [[saved.defeated_enemy_ids, allowed_enemies], [saved.gathered_node_ids, nodes.keys()]]:
		var seen: Dictionary = {}
		for id: Variant in pair[0]:
			if not id is String or not id in pair[1] or seen.has(id):
				return Result.failure("expedition_invalid", "远征事件未登记或重复。")
			seen[id] = true
	for id: Variant in saved.used_run_ids:
		if not id is String or id.is_empty() or saved.used_run_ids[id] != true:
			return Result.failure("expedition_invalid", "远征操作标识无效。")
	var expected_remainder := int(saved.starting_coin_remainder)
	if saved.outcome != "failed" and not saved.challenge and _characters != null and saved_state != State.DORMANT:
		var character: Dictionary = _characters.data.characters[saved.character_id]
		var base_coins := int(_rules.data.regions[saved.region_id].kill_reward.get("currency", 0))
		expected_remainder = (expected_remainder + saved.defeated_enemy_ids.size() * base_coins * int(character.monster_coin_numerator)) % int(character.monster_coin_denominator)
	if int(saved.pending_coin_remainder) != expected_remainder:
		return Result.failure("character_reward_invalid", "金币余数与真实敌人事件不一致。")
	if saved.pending_loot != _expected_pending_loot(saved):
		return Result.failure("expedition_invalid", "战利品与真实击杀、采集和目标事件不一致。")
	state = saved_state as State
	run_id = saved.run_id
	region_id = saved.region_id
	challenge = saved.challenge
	outcome = saved.outcome
	pending_loot = saved.pending_loot.duplicate(true)
	defeated_enemy_ids.assign(saved.defeated_enemy_ids)
	gathered_node_ids.assign(saved.gathered_node_ids)
	objective_completed = saved.objective_completed
	rewards_committed = saved.rewards_committed
	_used_run_ids = saved.used_run_ids.duplicate(true)
	_character_id = str(saved.character_id)
	_starting_coin_remainder = int(saved.starting_coin_remainder)
	_pending_coin_remainder = int(saved.pending_coin_remainder)
	return Result.success()

func _valid_bonus_context(character_id: String, remainder: int, dormant: bool) -> bool:
	if _characters == null:
		return character_id.is_empty() and remainder == 0
	if not _characters.ready or remainder < 0 or remainder >= 20:
		return false
	if dormant:
		return character_id.is_empty() and remainder == 0
	return _characters.data.characters.has(character_id)

func _expected_pending_loot(saved: Dictionary) -> Dictionary:
	var expected: Dictionary = {}
	if saved.outcome == "failed" or int(saved.state) == State.DORMANT:
		return expected
	if saved.challenge:
		if saved.outcome == "victory":
			_merge_reward(expected, _rules.data.challenge.reward)
		return expected
	var region: Dictionary = _rules.data.regions[saved.region_id]
	for _id: String in saved.defeated_enemy_ids:
		_merge_reward(expected, region.kill_reward)
	if _characters != null:
		var character: Dictionary = _characters.data.characters[saved.character_id]
		var accumulated: int = int(saved.starting_coin_remainder) + saved.defeated_enemy_ids.size() * int(region.kill_reward.get("currency", 0)) * int(character.monster_coin_numerator)
		var extra_coins := floori(float(accumulated) / float(character.monster_coin_denominator))
		if extra_coins > 0:
			expected["currency"] = int(expected.get("currency", 0)) + extra_coins
	for node_id: String in saved.gathered_node_ids:
		_merge_reward(expected, region.nodes[node_id])
	if saved.objective_completed:
		_merge_reward(expected, region.objective.reward)
	return expected

static func _merge_reward(target: Dictionary, reward: Dictionary) -> void:
	for key: String in reward:
		target[key] = int(target.get(key, 0)) + int(reward[key])
