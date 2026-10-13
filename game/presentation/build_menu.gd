class_name AWBuildMenu
extends RefCounted
## The view emits editing intents; the session owns domain validation and commits.

signal requested(action: String, data: Dictionary)

const SECTIONS := {"overview": "身份与装备", "talents": "天赋", "skills": "技能", "presets": "预设"}
var hud: AWGameHUD
var section := "overview"
var _model: Dictionary = {}
var _feedback: Label
var _comparison: Label
var _apply_button: Button
var _talent_controls: Dictionary = {}
var _skill_controls: Array[OptionButton] = []
var _weapon_control: OptionButton
var _cooldown_label: Label

func _init(game_hud: AWGameHUD) -> void:
	hud = game_hud

func show(model: Dictionary, destination: String = "overview") -> Dictionary:
	if not SECTIONS.has(destination):
		return {"ok": false, "code": "screen_unknown", "message": "构筑页面无效。"}
	section = destination
	_model = model.duplicate(true)
	_talent_controls.clear()
	_skill_controls.clear()
	_weapon_control = null
	_cooldown_label = null
	hud.show_menu(str(model["title"]), "编辑草稿，回营确认应用。技能冷却与剩余资源随当前状态保留。", [])
	var tabs := HBoxContainer.new()
	for key: String in SECTIONS:
		var tab := _button(str(SECTIONS[key]), "section", {"section": key})
		tab.name = "BuildTab_" + key
		tab.toggle_mode = true
		tab.button_pressed = key == section
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	hud.append_menu_control(tabs)
	_feedback = _label("")
	_feedback.name = "BuildQualification"
	hud.append_menu_control(_feedback)
	match section:
		"overview": _overview()
		"talents": _talents()
		"skills": _skills()
		"presets": _presets()
	_comparison = _label("")
	_comparison.name = "BuildComparison"
	hud.append_menu_control(_comparison)
	_apply_button = _button("确认应用草稿", "apply", {"character_id": str(model["character_id"])})
	_apply_button.name = "ApplyBuild"
	hud.append_menu_control(_apply_button)
	hud.append_menu_control(_button("返回", "back", {}))
	refresh_feedback(model)
	(tabs.get_child(0) as Control).grab_focus()
	return {"ok": true, "code": "ok", "message": ""}

func refresh_feedback(model: Dictionary) -> void:
	_model = model.duplicate(true)
	if is_instance_valid(_feedback):
		_feedback.text = str(model["qualification_text"])
	if is_instance_valid(_comparison):
		_comparison.text = str(model["comparison_text"])
	if is_instance_valid(_apply_button):
		_apply_button.disabled = not bool(model["apply_allowed"])
		_apply_button.tooltip_text = str(model["apply_reason"])
	for id: String in _talent_controls:
		var rank: SpinBox = _talent_controls[id]
		if is_instance_valid(rank):
			rank.set_value_no_signal(int(_model["draft"]["talents"][id]))
	for slot in range(_skill_controls.size()):
		var selector := _skill_controls[slot]
		if is_instance_valid(selector):
			_select_id(selector, _model["skill_options"], str(_model["draft"]["skill_loadout"][slot]))
	if is_instance_valid(_weapon_control):
		_select_id(_weapon_control, _model["weapon_options"], str(_model["draft"]["weapon_id"]))
	if is_instance_valid(_cooldown_label):
		_cooldown_label.text = str(_model["cooldown_text"])

func refresh_cooldowns(text: String) -> void:
	_model["cooldown_text"] = text
	if is_instance_valid(_cooldown_label):
		_cooldown_label.text = text

func _overview() -> void:
	for character: Dictionary in _model["characters"]:
		var marker := " · 当前活动" if character["id"] == _model["active_character_id"] else ""
		var button := _button(str(character["label"]) + marker, "select_character", {"character_id": str(character["id"])})
		button.name = "Character_" + str(character["id"])
		button.tooltip_text = str(character["description"])
		hud.append_menu_control(button)
	hud.append_menu_control(_label(str(_model["character_description"])))
	var weapon := OptionButton.new()
	_weapon_control = weapon
	weapon.name = "DraftWeapon"
	weapon.custom_minimum_size.y = 48
	var selected := -1
	var options: Array = _model["weapon_options"]
	for index in range(options.size()):
		var option: Dictionary = options[index]
		weapon.add_item(str(option["label"]))
		weapon.set_item_tooltip(index, str(option.get("description", "")))
		if option["id"] == _model["draft"]["weapon_id"]:
			selected = index
	weapon.select(selected)
	weapon.item_selected.connect(func(index: int) -> void:
		requested.emit("weapon", {"character_id": str(_model["character_id"]), "weapon_id": str(options[index]["id"])}))
	hud.append_menu_control(_label("草稿武器 · 实例和首次获得经历随装备保留"))
	hud.append_menu_control(weapon)
	for text: String in _model["resonance_texts"]:
		hud.append_menu_control(_label(text))

func _talents() -> void:
	for definition: Dictionary in _model["talent_nodes"]:
		var row := HBoxContainer.new()
		var description := VBoxContainer.new()
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.add_child(_label(str(definition["label"]) + " · " + str(definition["branch_label"])))
		description.add_child(_label(str(definition["description"])))
		row.add_child(description)
		var rank := SpinBox.new()
		_talent_controls[str(definition["id"])] = rank
		rank.name = "Talent_" + str(definition["id"])
		rank.min_value = 0
		rank.max_value = int(definition["rank_limit"])
		rank.step = 1
		rank.custom_minimum_size = Vector2(120, 48)
		rank.value = int(_model["draft"]["talents"][definition["id"]])
		rank.value_changed.connect(func(value: float) -> void:
			requested.emit("talent_rank", {"character_id": str(_model["character_id"]), "node_id": str(definition["id"]), "rank": int(value)}))
		row.add_child(rank)
		hud.append_menu_control(row)

func _skills() -> void:
	var options: Array = _model["skill_options"]
	for slot in range(2):
		hud.append_menu_control(_label("主通用技能" if slot == 0 else "次通用技能"))
		var selector := OptionButton.new()
		_skill_controls.append(selector)
		selector.name = "CommonSkill_" + str(slot)
		selector.custom_minimum_size.y = 48
		var selected := -1
		for index in range(options.size()):
			var option: Dictionary = options[index]
			selector.add_item(str(option["label"]) + " · " + str(option["availability_text"]))
			selector.set_item_tooltip(index, str(option["description"]))
			if option["id"] == _model["draft"]["skill_loadout"][slot]:
				selected = index
		selector.select(selected)
		selector.item_selected.connect(func(index: int) -> void:
			requested.emit("skill", {"character_id": str(_model["character_id"]), "slot": slot, "skill_id": str(options[index]["id"])}))
		hud.append_menu_control(selector)
	hud.append_menu_control(_label(str(_model["exclusive_skill_text"])))
	_cooldown_label = _label(str(_model["cooldown_text"]))
	_cooldown_label.name = "BuildCooldowns"
	hud.append_menu_control(_cooldown_label)

func _presets() -> void:
	var presets: Array = _model["presets"]
	for slot in range(presets.size()):
		var preset: Dictionary = presets[slot]
		hud.append_menu_control(_label("预设 %d · %s" % [slot + 1, str(preset["status_text"])]))
		var name_edit := LineEdit.new()
		name_edit.name = "PresetName_" + str(slot)
		name_edit.text = str(preset["name"])
		name_edit.placeholder_text = "输入预设名称（1—24字）"
		name_edit.max_length = 24
		name_edit.custom_minimum_size.y = 48
		hud.append_menu_control(name_edit)
		var actions := HBoxContainer.new()
		var save := Button.new()
		save.text = "保存当前草稿"
		save.custom_minimum_size.y = 48
		save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		save.pressed.connect(func() -> void:
			requested.emit("save_preset", {"character_id": str(_model["character_id"]), "slot": slot, "name": name_edit.text}))
		actions.add_child(save)
		var load_button := _button("载入草稿", "load_preset", {"character_id": str(_model["character_id"]), "slot": slot})
		load_button.disabled = bool(preset["empty"])
		load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(load_button)
		hud.append_menu_control(actions)

func _button(label: String, action: String, payload: Dictionary) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 48
	button.pressed.connect(func() -> void: requested.emit(action, payload.duplicate(true)))
	return button

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func _select_id(control: OptionButton, options: Array, selected_id: String) -> void:
	var selected := -1
	for index in range(options.size()):
		if str(options[index]["id"]) == selected_id:
			selected = index
			break
	control.set_block_signals(true)
	control.select(selected)
	control.set_block_signals(false)
