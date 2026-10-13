extends Node
class_name AWBuildController
## Menu intent adapter. Domain state remains in Roster; the scene owns vitals and IO.

signal build_applied(data: Dictionary)
signal edited()
signal closed()

const Result = preload("res://config/rule_result.gd")
const Config = preload("res://config/character_builds_config.gd")
const Rules = preload("res://config/rules_config.gd")
const Evaluator = preload("res://features/characters/build_evaluator.gd")
const Roster = preload("res://features/characters/character_roster.gd")
const Progress = preload("res://features/progression/world_progress.gd")
const Inventory = preload("res://features/expedition/inventory_ledger.gd")
const Combat = preload("res://features/combat/combat_state.gd")
const HUD = preload("res://presentation/game_hud.gd")
const Menu = preload("res://presentation/build_menu.gd")
const BRANCH_LABELS := {"attack": "进攻", "guard": "守护", "utility": "机动"}
const QUALITY_LABELS := {"common": "普通", "rare": "稀有"}
const REASON_LABELS := {"branch_points": "分支点数不足", "weapon_tier": "需要对应阶级的电枪", "skill_stage": "技能阶段尚未解锁", "skill_loadout": "需要装配对应通用技能"}
const COMPARISONS := {"max_health": "生命上限", "max_stamina": "体力上限", "attack_damage": "武器伤害", "move_speed": "移速", "stamina_recovery": "自然体力恢复", "pulse_damage": "脉冲伤害", "anchor_range": "锚点连接距离", "barrier_capacity": "屏障施放容量"}
const INTENT_FIELDS := {"section": ["section"], "select_character": ["character_id"], "weapon": ["character_id", "weapon_id"], "talent_rank": ["character_id", "node_id", "rank"], "skill": ["character_id", "slot", "skill_id"], "save_preset": ["character_id", "slot", "name"], "load_preset": ["character_id", "slot"], "apply": ["character_id"], "back": []}
var _hud: HUD
var _config: Config
var _evaluator: Evaluator
var _roster: Roster
var _progress: Progress
var _inventory: Inventory
var _combat: Combat
var _context_provider: Callable
var _vitals_provider: Callable
var _operation_provider: Callable
var _view: Menu
var _selected_character_id: String = ""
var _configured: bool = false
var _open: bool = false
var _model: Dictionary = {}
var view: Menu:
	get: return _view
var selected_character_id: String:
	get: return _selected_character_id

func configure(hud: HUD, config: Config, evaluator: Evaluator, roster: Roster, progress: Progress, inventory: Inventory, combat: Combat, context_provider: Callable, vitals_provider: Callable, operation_id_provider: Callable) -> Dictionary:
	if not is_instance_valid(hud) or not is_instance_valid(hud.root) or config == null or not config.ready or evaluator == null or roster == null or progress == null or inventory == null or combat == null or not combat.ready or not context_provider.is_valid() or not vitals_provider.is_valid() or not operation_id_provider.is_valid():
		return Result.failure("build_controller_invalid", "构筑界面依赖或回调尚未就绪。")
	var active := evaluator.evaluate(roster.active_build(), progress, inventory)
	if not active.ok: return active
	_disconnect_view()
	_hud = hud
	_config = config
	_evaluator = evaluator
	_roster = roster
	_progress = progress
	_inventory = inventory
	_combat = combat
	_context_provider = context_provider
	_vitals_provider = vitals_provider
	_operation_provider = operation_id_provider
	_selected_character_id = roster.active_character_id
	_view = Menu.new(hud)
	_view.requested.connect(_on_requested)
	_configured = true
	_open = false
	_model.clear()
	return Result.success()

func show(section: String = "overview") -> Dictionary:
	if not _usable(): return _unavailable()
	if not Menu.SECTIONS.has(section): return Result.failure("screen_unknown", "构筑页面无效。")
	var model := _build_model()
	if not model.ok: return _report(model)
	var shown := _view.show(model.data, section)
	if not shown.ok: return _report(shown)
	_model = model.data.duplicate(true)
	_open = true
	var tab := _hud.find_child("BuildTab_" + section, true, false) as Control
	if tab != null: tab.grab_focus()
	return Result.success({"model": _model.duplicate(true)})

func refresh() -> Dictionary:
	if not _usable() or not _open: return _unavailable()
	var model := _build_model()
	if not model.ok: return _report(model)
	_model = model.data.duplicate(true)
	_view.refresh_feedback(model.data)
	return Result.success({"model": _model.duplicate(true)})

func refresh_cooldowns() -> Dictionary:
	if not _usable() or not _open: return _unavailable()
	var text := _cooldown_text()
	_model["cooldown_text"] = text
	_view.refresh_cooldowns(text)
	return Result.success({"cooldown_text": text})

func view_model() -> Dictionary:
	return _model.duplicate(true)

func handle_intent(action: String, payload: Dictionary) -> Dictionary:
	if not _usable() or not _open: return _unavailable()
	if not INTENT_FIELDS.has(action) or not Config._keys(payload, INTENT_FIELDS[action]): return _reject("build_intent_invalid", "构筑操作字段无效。")
	if action == "back":
		_open = false
		closed.emit()
		return Result.success()
	if action == "section":
		if not payload.section is String: return _reject("screen_unknown", "构筑页面无效。")
		return show(payload.section)
	if not payload.get("character_id") is String or not _config.data.characters.has(payload.character_id): return _reject("character_unknown", "角色尚未注册。")
	if action == "select_character":
		_selected_character_id = payload.character_id
		return show(_view.section)
	if payload.character_id != _selected_character_id: return _reject("build_intent_invalid", "该操作不属于当前查看的角色。")
	if action == "apply": return _apply()
	var draft: Dictionary = _roster.profile(_selected_character_id).draft
	var result: Dictionary
	var rebuild := false
	match action:
		"talent_rank":
			if not payload.node_id is String or not _config.data.talents.has(payload.node_id): return _reject("build_schema_invalid", "天赋节点尚未注册。")
			if not Rules.is_count(payload.rank, 0, int(_config.data.talents[payload.node_id].rank_limit)): return _reject("talent_rank", "天赋等级必须是范围内的整数。")
			draft["talents"][str(payload.node_id)] = int(payload.rank)
			result = _roster.set_draft(_selected_character_id, draft)
		"skill":
			if not Rules.is_count(payload.slot, 0, 1) or not payload.skill_id is String: return _reject("build_intent_invalid", "技能槽或选择无效。")
			draft["skill_loadout"][int(payload.slot)] = payload.skill_id
			result = _roster.set_draft(_selected_character_id, draft)
		"weapon":
			if not payload.weapon_id is String: return _reject("build_intent_invalid", "装备引用无效。")
			draft["weapon_id"] = payload.weapon_id
			result = _roster.set_draft(_selected_character_id, draft)
			rebuild = true
		"save_preset":
			if not Rules.is_count(payload.slot, 0, 2) or not payload.name is String: return _reject("preset_invalid", "预设槽或名称无效。")
			result = _roster.save_preset(_selected_character_id, int(payload.slot), payload.name, _progress, _inventory)
			rebuild = true
		"load_preset":
			if not Rules.is_count(payload.slot, 0, 2): return _reject("preset_invalid", "预设槽无效。")
			result = _roster.load_preset_draft(_selected_character_id, int(payload.slot))
			rebuild = true
		_: return _reject("build_intent_invalid", "构筑操作尚未注册。")
	if not result.ok: return _report(result, true)
	if rebuild: show(_view.section)
	else: refresh()
	edited.emit()
	return result

func _apply() -> Dictionary:
	var environment := _read_environment()
	if not environment.ok: return _report(environment, true)
	var draft: Dictionary = _roster.profile(_selected_character_id).draft
	var preview := _roster.preview_apply(_selected_character_id, draft, _progress, _inventory, environment.data.context, environment.data.vitals, _combat)
	if not preview.ok: return _report(preview, true)
	if not _operation_provider.is_valid(): return _reject("build_provider_invalid", "操作回调已失效，未应用构筑。")
	var operation: Variant = _operation_provider.call()
	if not operation is String or not Config._text(operation, 128): return _reject("build_operation_invalid", "操作标识无效，未应用构筑。")
	# Providers are live: allocation may coincide with a scene/context transition.
	environment = _read_environment()
	if not environment.ok: return _report(environment, true)
	var result := _roster.apply(_selected_character_id, draft, _progress, _inventory, environment.data.context, environment.data.vitals, _combat, operation)
	if not result.ok: return _report(result, true)
	build_applied.emit(result.data.duplicate(true))
	if _usable() and _open: show(_view.section)
	return result

func _build_model() -> Dictionary:
	var profile := _roster.profile(_selected_character_id)
	if profile.is_empty(): return Result.failure("character_unknown", "当前查看角色的档案不存在。")
	var draft: Dictionary = profile.draft
	var qualification := _evaluator.reference_status(draft, _progress, _inventory)
	if not qualification.ok: return qualification
	var candidate := _evaluator.evaluate(draft, _progress, _inventory)
	var active := _evaluator.evaluate(_roster.active_build(), _progress, _inventory)
	if not active.ok: return active
	var environment := _read_environment()
	var preview: Dictionary = environment
	if environment.ok: preview = _roster.preview_apply(_selected_character_id, draft, _progress, _inventory, environment.data.context, environment.data.vitals, _combat)
	var characters: Array[Dictionary] = []
	for id: String in _config.data.characters:
		var definition: Dictionary = _config.data.characters[id]
		characters.append({"id": id, "label": definition.label, "description": definition.description})
	var talent_nodes: Array[Dictionary] = []
	for id: String in _config.data.talents:
		var definition: Dictionary = _config.data.talents[id]
		talent_nodes.append({"id": id, "label": definition.label, "description": definition.description, "branch_label": BRANCH_LABELS[definition.branch], "rank_limit": int(definition.rank_limit)})
	var skill_options: Array[Dictionary] = []
	for id: String in ["pulse", "barrier", "focus"]:
		var definition := _config.skill(id)
		skill_options.append({"id": id, "label": definition.label, "description": definition.description, "availability_text": "已解锁" if _progress.realm >= int(definition.required_realm) else "%d阶解锁" % int(definition.required_realm)})
	var presets: Array[Dictionary] = []
	for saved: Dictionary in profile.presets:
		if saved.build == null:
			presets.append({"name": "", "empty": true, "status_text": "未保存", "qualification": {}})
		else:
			var status := _evaluator.reference_status(saved.build, _progress, _inventory)
			presets.append({"name": saved.name, "empty": false, "status_text": "资格满足" if status.ok and bool(status.data.qualified) else _qualification_reason(status), "qualification": status.data.duplicate(true)})
	var qualification_text := "草稿 %d / 世界总量 %d 点 · %s" % [int(qualification.data.spent_points), int(qualification.data.available_points), "资格满足" if qualification.data.qualified else _qualification_reason(qualification)]
	return Result.success({"title": "构筑 · " + str(_config.data.characters[_selected_character_id].label), "character_id": _selected_character_id, "active_character_id": _roster.active_character_id, "character_description": _config.data.characters[_selected_character_id].description, "characters": characters, "draft": draft.duplicate(true), "talent_nodes": talent_nodes, "skill_options": skill_options, "weapon_options": _weapon_options(str(draft.weapon_id)), "presets": presets, "qualification_text": qualification_text, "comparison_text": _comparison_text(active.data.stats, candidate), "apply_allowed": bool(preview.ok), "apply_reason": "" if preview.ok else str(preview.message), "resonance_texts": _resonance_texts(draft, candidate, qualification), "exclusive_skill_text": "专属身份 · " + str(_config.data.characters[_selected_character_id].description), "cooldown_text": _cooldown_text()})

func _cooldown_text() -> String:
	var lines: Array[String] = []
	for id: String in _config.data.skills: lines.append("%s %.1f秒" % [_config.data.skills[id].label, _combat.cooldown_remaining(id)])
	lines.append("共享恢复 %.1f秒" % _combat.cooldown_remaining("recovery_family"))
	return "共享冷却 · " + " / ".join(lines)

func _weapon_options(draft_weapon_id: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for id: String in _inventory.equipment_ids():
		var item := _inventory.get_equipment(id)
		var history: Dictionary = item.history
		var location := _location_name(str(history.location))
		var label := "%s · %s · %d阶%d槽 · 初获%sLv%d · %s" % [item.name, QUALITY_LABELS.get(item.quality, item.quality), int(item.tier), int(item.slot_count), location, int(history.level), id.sha256_text().left(8)]
		var description := "首次获得：%s，世界%d级，%s。\n装备实例：%s。进阶经历%d次。" % [location, int(history.level), history.acquired_at, id, history.ascensions.size()]
		for event: Dictionary in history.ascensions: description += "\n%d阶：%s，%s。" % [int(event.tier), _location_name(str(event.location)), event.at]
		options.append({"id": id, "label": label, "description": description})
	if _inventory.get_equipment(draft_weapon_id).is_empty(): options.append({"id": draft_weapon_id, "label": "装备已消耗 · 失效引用 " + draft_weapon_id.sha256_text().left(8), "description": "该装备实例已不存在。引用保留供查看，选择现有装备后才能应用；不会重建或复制原经历。"})
	return options

func _comparison_text(current: Dictionary, candidate: Dictionary) -> String:
	var lines: Array[String] = ["当前生效 → 草稿"]
	for id: String in COMPARISONS:
		lines.append("%s %.2f → %s" % [COMPARISONS[id], float(current[id]), "%.2f" % float(candidate.data.stats[id]) if candidate.ok else "资格未满足"])
	return "\n".join(lines)

func _resonance_texts(draft: Dictionary, candidate: Dictionary, qualification: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for id: String in _config.data.resonances:
		var definition: Dictionary = _config.data.resonances[id]
		if candidate.ok and id in candidate.data.active_resonances:
			lines.append(str(definition.label) + " · 已激活：" + str(definition.description))
		else:
			var reasons: Array[String] = []
			if candidate.ok:
				for reason: String in candidate.data.inactive_resonance_reasons[id]: reasons.append(str(REASON_LABELS[reason]))
			else:
				reasons.append(_qualification_reason(qualification))
				if int(qualification.data.branch_points[definition.branch]) < int(definition.points): reasons.append("%s分支需%d点" % [BRANCH_LABELS[definition.branch], int(definition.points)])
				var item := _inventory.get_equipment(str(draft.weapon_id))
				if item.is_empty() or int(item.tier) < int(definition.weapon_tier): reasons.append("需要%d阶电枪" % int(definition.weapon_tier))
				if definition.required_skill == "anchor":
					if _progress.realm < 2: reasons.append("锚点需二阶解锁")
				elif not definition.required_skill in draft.skill_loadout: reasons.append("需要装配" + str(_config.skill(str(definition.required_skill)).label))
			lines.append(str(definition.label) + " · 未激活：" + "；".join(reasons))
	return lines

func _read_environment() -> Dictionary:
	if not _context_provider.is_valid() or not _vitals_provider.is_valid(): return Result.failure("build_provider_invalid", "场所或生命回调已失效。")
	var context: Variant = _context_provider.call()
	var vitals: Variant = _vitals_provider.call()
	if not context is Dictionary or not vitals is Dictionary: return Result.failure("build_provider_invalid", "当前场所或生命状态无效，未应用构筑。")
	for key: String in ["camp", "encounter_ended", "session_started"]:
		if not context.get(key) is bool: return Result.failure("build_provider_invalid", "当前场所状态字段无效。")
	if not Config._keys(vitals, ["health", "stamina", "max_health", "max_stamina"]): return Result.failure("build_provider_invalid", "当前生命与体力字段无效。")
	return Result.success({"context": context.duplicate(true), "vitals": vitals.duplicate(true)})

func _on_requested(action: String, payload: Dictionary) -> void:
	handle_intent(action, payload)

func _report(result: Dictionary, synchronize: bool = false) -> Dictionary:
	if is_instance_valid(_hud): _hud.notify(str(result.message))
	if synchronize and _usable() and _open: refresh()
	return result

func _reject(code: String, message: String) -> Dictionary:
	return _report(Result.failure(code, message), true)

func _usable() -> bool:
	return _configured and is_instance_valid(_hud) and is_instance_valid(_hud.root) and _view != null

func _disconnect_view() -> void:
	if _view != null and _view.requested.is_connected(_on_requested): _view.requested.disconnect(_on_requested)

func _exit_tree() -> void:
	_disconnect_view()
	_configured = false
	_open = false

static func _qualification_reason(result: Dictionary) -> String:
	if not result.ok: return str(result.message)
	var reasons: Array[String] = []
	for reason: Dictionary in result.data.reasons: reasons.append(str(reason.message))
	return "；".join(reasons)

static func _location_name(id: String) -> String:
	return {"rain_court": "雨庭", "conduit_yard": "导体工场", "camp": "回收营地"}.get(id, id)

static func _unavailable() -> Dictionary:
	return Result.failure("build_controller_unavailable", "构筑菜单尚未就绪或已经关闭。")
