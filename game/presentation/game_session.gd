class_name AWGameSession
extends Node3D

const PresentationConfig = preload("res://config/presentation_config.gd")
const Preferences = preload("res://persistence/user_preferences.gd")
const DOMAIN_VERSION := AWBuildMigration.DOMAIN_VERSION

@export var save_directory := "user://saves"

var rules: AWGameRules
var progress: AWWorldProgress
var inventory: AWInventoryLedger
var expedition: AWExpeditionState
var equipment: AWEquipmentService
var character_config: AWCharacterBuildsConfig
var build_evaluator: AWBuildEvaluator
var roster: AWCharacterRoster
var combat: AWCombatState
var build_controller: AWBuildController
var repository: SaveRepository
var settings: Dictionary = {}
var parameters: Dictionary = {}
var player: AWPlayerController
var camera_rig: AWCameraRig
var world: AWWorldBuilder
var hud: AWGameHUD
var input_adapter: AWInputAdapter
var enemy_root: Node3D
var effects: Node3D
var audio: Node
var active_weapon_id := "starter-lightning"
var run_counter := 0
var in_camp := true
var bench_built := false
var session_started := false
var save_available := false
var save_blocked := false
var _modal_mode := "title"
var _save_clock := 0.0
var _hud_clock := 0.0
var _pending_equipment: Array[Dictionary] = []
var _anchors: Array[Node3D] = []
var _stats: Dictionary = {}
var _derived_build: Dictionary = {}
var _build_return_mode := "camp"
var _operation_counter := 0
var _selected_material := ""
var _locked_affixes: Array[String] = []
var _fusion_materials: Array[String] = []
var _quitting := false
var _binding_action := ""
var preferences: RefCounted
var _preferences_blocked := false
var _preferences_dirty := false
var _preferences_delay := 0.0
var _preferences_write_failed := false
var _pending_persistence_action := ""
var _persistence_return_mode := ""
var _persistence_return_paused := false
var _persistence_return_blocked := false
var _persistence_return_player_active := false
var _environment: Environment
var _sun: DirectionalLight3D
var _future_domain := false
var _fatal_failure := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	input_adapter = AWInputAdapter.new()
	input_adapter.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(input_adapter)
	hud = AWGameHUD.new()
	add_child(hud)
	hud.input_adapter = input_adapter
	hud.command.connect(_on_command)
	hud.setting_changed.connect(_on_setting)
	rules = AWGameRules.new()
	var loaded := rules.load_file("res://config/rules.json")
	if not loaded.ok:
		_fatal(str(loaded.message))
		return
	var presentation := PresentationConfig.load_file()
	if not presentation.ok:
		_fatal(str(presentation.message))
		return
	parameters = presentation.data
	character_config = AWCharacterBuildsConfig.new()
	var character_rules := character_config.load_file("res://config/character_builds.json", parameters)
	if not character_rules.ok:
		_fatal(str(character_rules.message))
		return
	build_evaluator = AWBuildEvaluator.new(character_config, rules, parameters)
	combat = AWCombatState.new(character_config)
	roster = AWCharacterRoster.new(character_config, build_evaluator)
	if not input_adapter.initialization_result.ok:
		_fatal(str(input_adapter.initialization_result.message))
		return
	var input_configured := input_adapter.configure(parameters.input)
	if not input_configured.ok:
		_fatal(str(input_configured.message))
		return
	progress = AWWorldProgress.new(rules)
	inventory = AWInventoryLedger.new(rules)
	expedition = AWExpeditionState.new(rules, character_config)
	equipment = AWEquipmentService.new(rules)
	repository = SaveRepository.new()
	var configured := repository.configure(save_directory)
	if not configured.ok:
		_fatal(str(configured.message))
		return
	settings = AWGameSettings.default_settings()
	var saved := repository.load()
	if saved.ok:
		var restored := _restore_payload(saved.data)
		if not restored.ok:
			save_blocked = true
			_future_domain = restored.get("code", "") == "future_schema"
			hud.notify(str(restored.message), 12.0)
		else:
			save_available = true
			if saved.recovered:
				hud.notify("已从有效备份恢复进度。", 7.0)
	elif saved.code != "not_found":
		save_blocked = true
		_future_domain = saved.code == "future_schema"
		hud.notify(str(saved.message) + " 原始存档已保留。", 12.0)
	preferences = Preferences.new()
	var preferences_configured: Dictionary = preferences.configure(save_directory.path_join("preferences"))
	if not preferences_configured.ok:
		_preferences_blocked = true
		hud.notify(str(preferences_configured.message), 9.0)
	else:
		var preferred: Dictionary = preferences.load()
		if preferred.ok:
			settings = preferred.data.settings
			input_adapter.restore_bindings(preferred.data.input_bindings)
		elif preferred.code != "not_found":
			_preferences_blocked = true
			hud.notify("全局偏好无法读取，原文件已保留。 " + str(preferred.message), 9.0)
	if inventory.get_equipment(active_weapon_id).is_empty():
		_create_starter_weapon()
	if roster.active_character_id.is_empty():
		var initialized := roster.initialize(active_weapon_id, progress, inventory)
		if not initialized.ok:
			_fatal(str(initialized.message))
			return
	if not _build_scene("rain_court"):
		return
	_apply_settings()
	if not _apply_equipment_stats():
		return
	_restore_vitals()
	if not _configure_build_controller():
		return
	_show_title()

func _build_scene(region: String) -> bool:
	if world:
		remove_child(world)
		if is_instance_valid(camera_rig):
			camera_rig.occlusion_fader.release_world()
		world.queue_free()
	if enemy_root:
		remove_child(enemy_root)
		enemy_root.queue_free()
	world = AWWorldBuilder.new()
	world.name = "Region"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	if not world.build(region):
		_fatal("区域配置或资产无法加载。 " + "; ".join(world.configuration_errors))
		return false
	enemy_root = Node3D.new()
	enemy_root.name = "Enemies"
	enemy_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy_root)
	if player == null:
		player = AWPlayerController.new()
		player.name = "Player"
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(player)
		player.configure(parameters.player)
		if not player.visual_ready:
			_fatal(str(player.visual_error.get("message", "角色资产验证失败。")))
			return false
		player.input_adapter = input_adapter
		player.died.connect(_on_death)
		player.hurt.connect(func(_amount: float) -> void:
			camera_rig.shake_strength = 0.45
			_sound("hurt"))
		player.dodge_started.connect(func() -> void: _sound("dodge"))
		player.shield_absorbed.connect(func(_amount: float) -> void:
			_burst(player.global_position + Vector3.UP, Color("86b5ef"), 0.6)
			_sound("impact"))
		camera_rig = AWCameraRig.new()
		camera_rig.name = "CameraRig"
		camera_rig.process_mode = Node.PROCESS_MODE_PAUSABLE
		camera_rig.target = player
		add_child(camera_rig)
		camera_rig.configure(parameters.camera)
		player.camera = camera_rig.camera
		effects = Node3D.new()
		effects.name = "Effects"
		effects.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(effects)
		_create_lighting()
		if ResourceLoader.exists("res://presentation/game_audio.gd"):
			audio = (load("res://presentation/game_audio.gd") as Script).new() as Node
			audio.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(audio)
			audio.call("configure", settings)
			audio.call("start_environment")
	player.global_position = Vector3(0, 0.2, 11)
	player.combat_state = combat
	camera_rig.global_position = player.global_position
	camera_rig.occlusion_fader.bind_world(world)
	_apply_world_lighting()
	return true

func _create_lighting() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var env := Environment.new()
	_environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("17292e")
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("354c58")
	atmosphere.sky_horizon_color = Color("95a29c")
	atmosphere.ground_bottom_color = Color("17292e")
	atmosphere.ground_horizon_color = Color("73817a")
	sky.sky_material = atmosphere
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("728c91")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.009
	env.fog_light_color = Color("628184")
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -25, 0)
	sun.light_color = Color("eee0b4")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55
	add_child(sun)

func _apply_world_lighting() -> void:
	if _environment == null or _sun == null:
		return
	var profile := world.lighting_profile
	_environment.ambient_light_color = Color(str(profile.get("ambient_color", "728c91")))
	_environment.ambient_light_energy = float(profile.get("ambient_energy", 0.3))
	_environment.fog_light_color = Color(str(profile.get("fog_color", "628184")))
	_environment.fog_density = float(profile.get("fog_density", 0.006))
	_sun.light_color = Color(str(profile.get("sun_color", "eee0b4")))
	_sun.light_energy = float(profile.get("sun_energy", 1.15))

func _process(delta: float) -> void:
	if _quitting:
		return
	if _preferences_dirty and not _preferences_write_failed:
		_preferences_delay -= delta
		if _preferences_delay <= 0.0:
			_save_preferences()
	for action: String in input_adapter.consume_actions():
		_handle_action(action)
	if not session_started:
		return
	_hud_clock += delta
	if _hud_clock > 0.12:
		_hud_clock = 0.0
		_update_hud()
		if _modal_mode == "build" and hud.modal.visible:
			build_controller.refresh_cooldowns()
	if get_tree().paused:
		return
	combat.tick(delta, true)
	_save_clock += delta
	if _save_clock >= float(parameters.save.checkpoint_interval):
		_save_clock = 0.0
		_save_progress(false)
	if player.active and not input_adapter.blocked and input_adapter.attack_held and not in_camp:
		_attack()

func _handle_action(action: String) -> void:
	if action == "pause":
		if not _pending_persistence_action.is_empty():
			_cancel_pending_persistence()
			return
		if not session_started:
			return
		if hud.modal.visible:
			_close_menu()
		else:
			_show_pause()
		return
	if input_adapter.blocked:
		return
	match action:
		"dodge": _dodge()
		"pulse": _common_skill(0)
		"skill_secondary": _common_skill(1)
		"character_ability": _cast_skill("self_heal")
		"anchor": _place_anchor()
		"interact": _interact()
		"heal": _use_consumable("medkit")
		"camera_lock":
			settings.camera_locked = not settings.camera_locked
			_apply_settings()
			hud.notify("镜头已锁定，仍跟随角色。" if camera_rig.locked else "自由镜头：中键旋转，滚轮缩放。")
		"camera_reset": camera_rig.reset_view()

func _show_title() -> void:
	_modal_mode = "title"
	get_tree().paused = true
	_set_menu_block(true)
	hud.show_menu("另一个世界", "在雨后的废弃泵站搜集资源、判断撤离时机。\n珍爱的闪电枪随你的世界晋阶，获得新的打法。\n单人可玩原型 · 最终品质与完整内容制作中", [
		{"label": "继续旅程", "action": "continue", "disabled": not save_available or save_blocked},
		{"label": "开始新旅程", "action": "new_game", "disabled": _future_domain, "tooltip": "已有更新版本进度，请使用兼容版本。" if _future_domain else ""}, {"label": "设置", "action": "settings"}, {"label": "退出", "action": "quit"}])

func _show_camp() -> void:
	_modal_mode = "camp"
	get_tree().paused = false
	_set_menu_block(true)
	var challenge_ready := progress.realm == 1 and progress.level == 30
	var description := "金币 %d  ·  废铁 %d  ·  合金 %d  ·  晶片 %d\n生命 %d/%d · 口粮%d / 药包%d\n%s" % [inventory.count("currency"), inventory.count("scrap"), inventory.count("alloy"), inventory.count("crystal"), int(player.health), int(player.maximum_health), inventory.count("rations"), inventory.count("medkit"), "维护台已建成，可培养装备。" if bench_built else "建成维护台后解锁制作与装备培养。"]
	hud.show_menu("回收营地", description, [
		{"label": "出发：雨庭 / 一阶", "action": "explore_rain"},
		{"label": "出发：导体工场 / 二阶", "action": "explore_conduit", "disabled": progress.realm < 2},
		{"label": "个人晋阶挑战：雨庭守卫", "action": "challenge", "disabled": not challenge_ready},
		{"label": "维护台：装备培养与补给", "action": "workbench"},
		{"label": "角色构筑 · 天赋 / 技能 / 预设", "action": "builds"},
		{"label": "食用口粮 · 恢复25生命", "action": "use_rations", "disabled": inventory.count("rations") <= 0 or player.health >= player.maximum_health},
		{"label": "回到营地活动", "action": "resume"}])

func _show_workbench() -> void:
	_modal_mode = "workbench"
	_set_menu_block(true)
	var current := inventory.get_equipment(active_weapon_id)
	var affix_lines: Array[String] = []
	for affix: Dictionary in current.get("affixes", []):
		affix_lines.append("%s %d" % [str(rules.data.equipment.affixes[affix.id].label), int(affix.value)])
	var body := "%s · %s · %d阶 / %d槽\n%s\n金币%d  废铁%d  合金%d  晶片%d" % [str(current.get("name", "闪电枪")), "稀有" if current.get("quality") == "rare" else "普通", int(current.get("tier", 1)), int(current.get("slot_count", 4)), " / ".join(affix_lines), inventory.count("currency"), inventory.count("scrap"), inventory.count("alloy"), inventory.count("crystal")]
	var options: Array = []
	if not bench_built:
		options.append({"label": "建设维护台 · 金币6 + 废铁6", "action": "build_bench"})
	else:
		options.append({"label": "融合熔炉 · 查看候选/概率/成本", "action": "fusion"})
		options.append({"label": "确定扩槽：4→5 · 对应阶级材料8", "action": "expand", "disabled": int(current.slot_count) != 4})
		options.append({"label": "装备进阶：1→2 · 废铁10 + 合金5", "action": "advance", "disabled": int(current.tier) >= 2 or progress.realm < 2})
		options.append({"label": "制作药包 · 废铁2 + 晶片1", "action": "craft_medkit"})
		options.append({"label": "购买口粮 · 金币4", "action": "buy_rations"})
	options.append({"label": "返回营地", "action": "camp"})
	hud.show_menu("维护台", body, options)

func _show_fusion() -> void:
	_modal_mode = "fusion"
	var primary := inventory.get_equipment(active_weapon_id)
	var materials: Array[String] = []
	for id: String in inventory.equipment_ids():
		var item := inventory.get_equipment(id)
		if id != active_weapon_id and item.tier == primary.tier and item.quality == primary.quality and not item.get("equipped", false):
			materials.append(id)
	if materials.is_empty():
		hud.show_menu("融合熔炉", "没有同阶级、同品质的材料闪电枪。\n完成远征可获得材料装备；本操作不转移材料的特殊能力。", [{"label": "返回", "action": "workbench"}])
		return
	_fusion_materials = materials
	if not _selected_material in materials:
		_selected_material = materials[0]
	var preview := equipment.preview_fusion(inventory, active_weapon_id, _selected_material, _locked_affixes, progress.realm, in_camp, _ended())
	var body := "未锁位置从双方合格普通词条重新抽取；结果不保证更强。\n主装备身份、阶级、品质、槽数、特效与经历保留。\n"
	var referenced := roster.references_to(_selected_material)
	if not referenced.is_empty():
		body += "材料消耗后，下列引用会失效，需重新选择已有装备：\n"
		for reference: Dictionary in referenced:
			var character_label := str(character_config.data.characters[reference.character_id].label)
			var destination := "预设%d「%s」" % [int(reference.slot) + 1, str(reference.name)] if reference.kind == "preset" else ("草稿" if reference.kind == "draft" else "非活动生效构筑")
			body += character_label + " · " + destination + "\n"
	if preview.ok:
		body += "成本 %s\n合法成品组合 %d，每组合 %.2f%%\n候选进入成品的概率：" % [_cost_text(preview.data.cost), preview.data.outcomes.size(), float(preview.data.outcome_probability) * 100.0]
		for id: String in preview.data.candidate_inclusion_probability:
			body += "%s %.0f%%  " % [str(rules.data.equipment.affixes[id].label), float(preview.data.candidate_inclusion_probability[id]) * 100.0]
	else:
		body += str(preview.message)
	var options: Array = []
	for affix: Dictionary in primary.affixes:
		options.append({"label": "%s %s %d" % ["已锁" if affix.id in _locked_affixes else "锁定", str(rules.data.equipment.affixes[affix.id].label), int(affix.value)], "action": "lock:" + str(affix.id)})
	options.append({"label": "更换材料装备 (%d件可选)" % materials.size(), "action": "cycle_material"})
	options.append({"label": "确认融合并消耗材料", "action": "confirm_fusion", "disabled": not preview.ok})
	options.append({"label": "取消 / 返回", "action": "workbench"})
	hud.show_menu("融合熔炉", body, options)

func _show_pause() -> void:
	_modal_mode = "pause"
	get_tree().paused = true
	_set_menu_block(true)
	hud.show_menu("暂停", "世界与战斗冷却暂停。离开当前远征会丢弃本次未入库战利品。", [{"label": "继续", "action": "resume"}, {"label": "查看构筑 / 编辑草稿", "action": "builds"}, {"label": "设置", "action": "settings"}, {"label": "保存并回到标题", "action": "title"}, {"label": "保存并退出", "action": "quit"}])

func _on_command(action: String) -> void:
	if _quitting:
		return
	if _fatal_failure and action not in ["quit", "retry_quit", "discard_quit", "cancel_quit"]:
		return
	if _future_domain and action in ["new_game", "confirm_new", "continue"]:
		hud.notify("已有更新版本进度，本版本不会覆盖它。", 9.0)
		return
	var camp_action := action in ["camp", "workbench", "fusion", "cycle_material", "confirm_fusion", "expand", "advance", "build_bench", "craft_medkit", "buy_rations", "use_rations"] or action.begins_with("lock:")
	if camp_action and (not session_started or not in_camp or not _ended()):
		hud.notify("本操作只在营地且遭遇结束后可用。")
		return
	if (action in ["fusion", "cycle_material", "confirm_fusion", "expand", "advance", "craft_medkit", "buy_rations"] or action.begins_with("lock:")) and not bench_built:
		hud.notify("需要先建设维护台。")
		return
	if action.begins_with("bind:"):
		_binding_action = action.trim_prefix("bind:")
		hud.show_menu("设置按键", "按下要分配的键。冲突和菜单导航键会被拒绝；ESC取消。", [{"label": "取消", "action": "bindings"}])
		return
	if action.begins_with("lock:"):
		var id := action.trim_prefix("lock:")
		if id in _locked_affixes:
			_locked_affixes.erase(id)
		elif _locked_affixes.size() < 2:
			_locked_affixes.append(id)
		else:
			hud.notify("每次最多锁定两条普通词条。")
		_show_fusion()
		return
	match action:
		"retry_quit":
			if _pending_persistence_action == "quit": _request_quit()
		"discard_quit":
			if _pending_persistence_action == "quit": _finish_quit()
		"cancel_quit", "cancel_title":
			if not _pending_persistence_action.is_empty(): _cancel_pending_persistence()
		"retry_title":
			if _pending_persistence_action == "title": _return_to_title()
		"retry_settlement":
			if session_started and not in_camp and expedition.state == AWExpeditionState.State.ENDED and not expedition.rewards_committed:
				_finish_run(expedition.outcome)
		"abandon_settlement":
			if session_started and not in_camp and expedition.state == AWExpeditionState.State.ENDED and not expedition.rewards_committed:
				expedition = AWExpeditionState.new(rules, character_config)
				_return_to_camp("discarded")
		"continue":
			var saved := repository.load()
			if not saved.ok or not _restore_payload(saved.data).ok:
				hud.notify("存档恢复失败，原文件已保留。", 8.0)
				return
			expedition = AWExpeditionState.new(rules, character_config)
			_pending_equipment.clear()
			if not _build_scene("rain_court"):
				return
			if not _apply_equipment_stats():
				return
			_restore_vitals(true)
			if not _configure_build_controller():
				return
			if not _preferences_blocked:
				var preferred: Dictionary = preferences.load()
				if preferred.ok:
					settings = preferred.data.settings
					input_adapter.restore_bindings(preferred.data.input_bindings)
			_apply_settings()
			session_started = true
			in_camp = true
			player.active = true
			if has_meta("failure_checkpoint_recovered"):
				remove_meta("failure_checkpoint_recovered")
				_save_progress(false)
			_close_menu()
			_show_camp()
		"new_game":
			if save_available or save_blocked:
				hud.show_menu("新旅程", "开始新旅程将替代本机当前进度。原损坏文件保持，不自动清档。", [{"label": "明确开始新旅程", "action": "confirm_new"}, {"label": "取消", "action": "title"}])
			else:
				_new_game()
		"confirm_new": _new_game()
		"resume": _close_menu()
		"camp": _show_camp()
		"workbench": _show_workbench()
		"builds": _show_builds()
		"fusion":
			_locked_affixes.clear()
			_selected_material = ""
			_show_fusion()
		"cycle_material":
			if _fusion_materials.is_empty():
				return
			var index := _fusion_materials.find(_selected_material)
			_selected_material = _fusion_materials[(index + 1) % _fusion_materials.size()]
			_show_fusion()
		"confirm_fusion":
			_result(equipment.fuse(inventory, active_weapon_id, _selected_material, _locked_affixes, progress.realm, in_camp, _ended(), _operation_id("fusion"), run_counter * 93 + _operation_counter))
			_selected_material = ""
			_locked_affixes.clear()
			if not _apply_equipment_stats():
				return
			_save_progress()
			_show_workbench()
		"expand":
			_result(equipment.expand_slot(inventory, active_weapon_id, progress.realm, in_camp, _ended(), _operation_id("expansion"), run_counter + _operation_counter))
			if not _apply_equipment_stats():
				return
			_save_progress()
			_show_workbench()
		"advance":
			_result(equipment.ascend(inventory, active_weapon_id, progress.realm, in_camp, _ended(), _operation_id("advance"), {"location": "回收营地", "at": Time.get_datetime_string_from_system(true)}))
			if not _apply_equipment_stats():
				return
			_save_progress()
			_show_workbench()
		"build_bench":
			if in_camp and _ended() and not bench_built:
				var result := inventory.apply_operation(_operation_id("bench"), rules.data.camp.bench_cost)
				if result.ok:
					bench_built = true
				_result(result)
				_save_progress()
			_show_workbench()
		"craft_medkit":
			_result(inventory.apply_operation(_operation_id("craft"), rules.data.camp.medkit_cost, {"medkit": 1}))
			_save_progress()
			_show_workbench()
		"buy_rations":
			_result(inventory.apply_operation(_operation_id("food"), rules.data.camp.rations_cost, {"rations": 1}))
			_save_progress()
			_show_workbench()
		"use_rations":
			_use_consumable("rations")
			_show_camp()
		"explore_rain": _begin_run("rain_court", false)
		"explore_conduit": _begin_run("conduit_yard", false)
		"challenge": _begin_run("rain_court", true)
		"settings":
			_modal_mode = "settings"
			_set_menu_block(true)
			hud.show_settings(settings)
		"bindings": _show_bindings()
		"bindings_reset":
			_result(input_adapter.bindings.reset_defaults())
			_apply_settings()
			_save_preferences()
			_save_progress(false)
			_show_bindings()
		"settings_back":
			if _preferences_dirty:
				_save_preferences()
			_save_progress(false)
			if not session_started:
				_show_title()
			elif in_camp:
				_show_camp()
			else:
				_show_pause()
		"title":
			_return_to_title()
		"quit":
			_request_quit()

func _new_game() -> void:
	get_tree().paused = false
	progress = AWWorldProgress.new(rules)
	inventory = AWInventoryLedger.new(rules)
	expedition = AWExpeditionState.new(rules, character_config)
	combat = AWCombatState.new(character_config)
	roster = AWCharacterRoster.new(character_config, build_evaluator)
	run_counter = 0
	_operation_counter = 0
	bench_built = false
	save_blocked = false
	active_weapon_id = "starter-lightning"
	_create_starter_weapon()
	var initialized := roster.initialize(active_weapon_id, progress, inventory)
	if not initialized.ok:
		_fatal(str(initialized.message))
		return
	if not _apply_equipment_stats():
		return
	player.health = player.maximum_health
	player.stamina = player.maximum_stamina
	player.active = true
	session_started = true
	in_camp = true
	if not _build_scene("rain_court"):
		return
	if not _configure_build_controller():
		return
	_save_progress()
	_show_camp()

func _create_starter_weapon() -> void:
	var result := equipment.create_drop(active_weapon_id, 1, "rare", 4, {"location": "回收营地 · 初始工具", "level": 1, "acquired_at": Time.get_datetime_string_from_system(true)}, 27191)
	if result.ok:
		var starter: Dictionary = result.data.equipment.duplicate(true)
		starter["equipped"] = true
		inventory.add_equipment(starter)

func _begin_run(region: String, challenge: bool) -> void:
	if not in_camp or not _ended():
		hud.notify("必须在营地且上一遭遇已经结束。")
		return
	run_counter += 1
	var result := expedition.begin("run-%d" % run_counter, region, challenge, progress.realm, progress.level, roster.active_character_id, roster.thief_coin_remainder)
	if not result.ok:
		_result(result)
		return
	_pending_equipment.clear()
	in_camp = false
	if not _build_scene(region):
		return
	player.global_position = Vector3(0, 0.2, 6.0)
	player.active = true
	var positions := [Vector3(-5, 0.1, 3), Vector3(-3, 0.1, 1), Vector3(-5, 0.1, -2), Vector3(6, 0.1, -4), Vector3(4, 0.1, -7), Vector3(8, 0.1, -9)]
	var ids := expedition.enemy_ids()
	for index: int in range(ids.size()):
		var enemy := AWEnemyController.new()
		enemy.name = ids[index]
		enemy.setup(ids[index], "guardian" if challenge else ("spitter" if index % 3 == 2 else "scavenger"), parameters.enemy, player)
		enemy_root.add_child(enemy)
		enemy.global_position = Vector3(0, 0.1, -4) if challenge else positions[index]
		enemy.defeated.connect(_on_enemy_defeated)
		enemy.attack_telegraphed.connect(_telegraph)
	_close_menu()
	if audio:
		audio.call("set_encounter", true)
	hud.notify("挑战守卫，胜利才会晋阶。" if challenge else "目标：击败3个异变体，搜集2处资源。可随时回撤离点交互。", 6.0)
	_save_progress(false)

func _interact() -> void:
	if in_camp:
		if player.global_position.distance_to(world.bench_position) < 3.0:
			_show_workbench()
		else:
			_show_camp()
		return
	if player.global_position.distance_to(world.exit_position) < 2.6:
		_finish_run("evacuated")
		return
	for id: String in world.resource_positions:
		if player.global_position.distance_to(world.resource_positions[id]) < float(parameters.world.interaction_range):
			var result := expedition.gather(id)
			if result.ok:
				(world.pickup_nodes[id] as Node3D).visible = false
				_sound("collect")
				_check_objective()
			_result(result)
			return
	hud.notify("靠近资源箱后按E。回到绿色圆环可撤离。")

func _on_enemy_defeated(id: String, location: Vector3) -> void:
	var result := expedition.record_kill(id, progress)
	if not result.ok:
		_result(result)
		return
	_sound("impact")
	if expedition.challenge:
		_finish_run("victory")
		return
	if expedition.defeated_enemy_ids.size() % 3 == 0:
		var drop_id := "%s-%s" % [expedition.run_id, id]
		var quality := "rare" if expedition.defeated_enemy_ids.size() == 3 else "common"
		var drop := equipment.create_drop(drop_id, progress.realm, quality, 4, {"location": expedition.region_id, "level": progress.level, "acquired_at": Time.get_datetime_string_from_system(true)}, run_counter * 173 + expedition.defeated_enemy_ids.size())
		if drop.ok:
			_pending_equipment.append(drop.data.equipment)
			hud.notify("发现一把%s闪电枪，成功撤离后入库。" % ("稀有" if quality == "rare" else "普通"))
	_check_objective()
	_save_progress(false)
	_burst(location + Vector3.UP, Color("ffd28d"), 0.5)

func _check_objective() -> void:
	if not expedition.objective_completed and not expedition.challenge:
		var result := expedition.complete_objective(progress)
		if result.ok:
			hud.notify("远征目标完成：经验+60，奖励随战利品撤离入库。", 5.0)
			_sound("confirm")

func _finish_run(outcome: String) -> void:
	for node: Node in enemy_root.get_children():
		if node is AWEnemyController:
			node.active = false
	if expedition.state != AWExpeditionState.State.ENDED:
		var resolved := expedition.resolve(outcome, progress)
		if not resolved.ok:
			_result(resolved)
			return
		var reset := expedition.reset()
		if not reset.ok:
			_result(reset)
			return
	elif expedition.outcome != outcome or expedition.rewards_committed:
		return
	if outcome != "failed":
		var settled := expedition.commit_rewards(inventory, roster, _pending_equipment)
		if not settled.ok:
			if settled.code == "settlement_invariant":
				_fatal(str(settled.message))
				return
			_modal_mode = "settlement"
			_set_menu_block(true)
			player.active = false
			hud.show_menu("战利品尚未入库", str(settled.message) + "\n本次资源、装备和金币余数均未入库，可重试或放弃未入库战利品回营。", [{"label": "重试入库", "action": "retry_settlement"}, {"label": "放弃未入库战利品并回营", "action": "abandon_settlement"}])
			return
	_return_to_camp(outcome)

func _return_to_camp(outcome: String) -> void:
	_pending_equipment.clear()
	for anchor: Node3D in _anchors:
		if is_instance_valid(anchor):
			anchor.queue_free()
	_anchors.clear()
	in_camp = true
	if not _build_scene("rain_court"):
		return
	if outcome == "failed":
		_recover_after_failure()
	player.active = true
	_sound("failure" if outcome in ["failed", "discarded"] else "victory")
	if audio:
		audio.call("set_encounter", false)
	_save_progress(false)
	_show_camp()
	hud.notify("本次未入库战利品已丢失；已入库装备和经验保留。" if outcome in ["failed", "discarded"] else ("晋阶成功：导体工场开放！可在维护台进阶原电枪。" if outcome == "victory" else "安全撤离，战利品已入库。"), 7.0)

func _on_death() -> void:
	_finish_run("failed")

func _attack() -> void:
	if combat.cooldown_remaining("attack") > 0.0:
		return
	var target := _find_target(player.global_position, player.aim_direction, float(_stats.attack_range), true, [])
	if target == null:
		return
	var cast_result := _perform_cast("attack")
	if not cast_result.ok:
		return
	var previous := player.global_position + Vector3.UP * 1.2
	var damage: float = cast_result.data.effect_spec.damage
	var visited: Array[AWEnemyController] = []
	var current := target
	for _index: int in range(int(_stats.chain_targets)):
		if current == null:
			break
		visited.append(current)
		var destination := current.global_position + Vector3.UP
		_lightning(previous, destination)
		current.take_damage(damage)
		damage *= float(_stats.chain_falloff)
		previous = destination
		var range_value := float(_stats.chain_range)
		current = _find_target(previous, Vector3.ZERO, range_value, false, visited)
		if current == null and _weapon_tier() >= 2:
			for anchor: Node3D in _anchors:
				if is_instance_valid(anchor) and previous.distance_to(anchor.global_position) <= float(_stats.anchor_range):
					var across := _find_target(anchor.global_position, Vector3.ZERO, float(_stats.anchor_range), false, visited)
					if across:
						_lightning(previous, anchor.global_position + Vector3.UP)
						previous = anchor.global_position + Vector3.UP
						current = across
						break
	_sound("electric")
	camera_rig.shake_strength = maxf(camera_rig.shake_strength, 0.12)

func _find_target(origin: Vector3, direction: Vector3, range_value: float, aimed: bool, excluded: Array) -> AWEnemyController:
	var best: AWEnemyController
	var best_score := -INF
	for node: Node in enemy_root.get_children():
		if not node is AWEnemyController or not node.active or node in excluded:
			continue
		var enemy := node as AWEnemyController
		var offset := enemy.global_position - origin
		offset.y = 0.0
		var distance := offset.length()
		if distance > range_value:
			continue
		var alignment := offset.normalized().dot(direction)
		if aimed and alignment < 0.87:
			continue
		var from := Vector3(origin.x, 1.0, origin.z)
		var to := enemy.global_position + Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var score := alignment * 10.0 - distance if aimed else -distance
		if score > best_score:
			best_score = score
			best = enemy
	return best

func _pulse() -> void:
	_cast_skill("pulse")

func _common_skill(slot: int) -> void:
	var loadout: Array = roster.active_build().skill_loadout
	_cast_skill(str(loadout[slot]))

func _perform_cast(skill_id: String) -> Dictionary:
	var preview := combat.preview_cast(skill_id, _combat_context(), _vitals(), _derived_build)
	if not preview.ok:
		return preview
	var cast_result := combat.cast(skill_id, _combat_context(), _vitals(), _derived_build, _operation_id("cast-" + skill_id))
	if cast_result.ok:
		_apply_vitals(cast_result.data.new_vitals)
	return cast_result

func _cast_skill(skill_id: String) -> void:
	var cast_result := _perform_cast(skill_id)
	if not cast_result.ok:
		hud.notify(str(cast_result.message))
		return
	var effect_spec: Dictionary = cast_result.data.effect_spec
	match skill_id:
		"pulse": _resolve_pulse(effect_spec)
		"barrier":
			_burst(player.global_position + Vector3.UP * 0.1, Color("86b5ef"), 1.0)
			_sound("confirm")
		"focus":
			_burst(player.global_position + Vector3.UP * 0.1, Color("f3ca89"), 0.8)
			_sound("confirm")
		"self_heal":
			var animated := player.play_self_heal()
			if not animated.ok:
				_fatal(str(animated.message))
				return
			_burst(player.global_position + Vector3.UP * 0.1, Color("83f7b0"), 0.8)
			_sound("confirm")
	_save_progress(false)
	_update_hud()

func _resolve_pulse(effect_spec: Dictionary) -> void:
	var radius := float(effect_spec.radius)
	for node: Node in enemy_root.get_children():
		if node is AWEnemyController and node.active and node.global_position.distance_to(player.global_position) <= radius:
			var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP, node.global_position + Vector3.UP, 1)
			if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
				node.take_damage(float(effect_spec.damage))
	_burst(player.global_position + Vector3.UP * 0.1, Color("83f7df"), radius)
	_sound("pulse")

func _dodge() -> void:
	var cast_result := _perform_cast("dodge")
	if cast_result.ok:
		var moved := player.begin_dodge(cast_result.data.effect_spec)
		if not moved.ok:
			_fatal(str(moved.message))
	else:
		hud.notify(str(cast_result.message))

func _place_anchor() -> void:
	if in_camp or _weapon_tier() < 2 or progress.realm < 2:
		hud.notify("电枪进阶到二阶后解锁导电锚点。")
		return
	var cast_result := _perform_cast("anchor")
	if not cast_result.ok:
		hud.notify(str(cast_result.message))
		return
	var anchor := Node3D.new()
	effects.add_child(anchor)
	anchor.global_position = player.global_position + player.aim_direction * 2.5
	var model := (load("res://assets/models/conductive_anchor.glb") as PackedScene).instantiate() as Node3D
	anchor.add_child(model)
	_anchors.append(anchor)
	var timer := get_tree().create_timer(float(cast_result.data.effect_spec.lifetime), false)
	timer.timeout.connect(_expire_anchor.bind(weakref(anchor)))
	_sound("anchor")

func _expire_anchor(reference: WeakRef) -> void:
	var anchor: Node3D = reference.get_ref() as Node3D
	if is_instance_valid(anchor):
		_anchors.erase(anchor)
		anchor.queue_free()

func _use_consumable(id: String) -> void:
	var preview := combat.preview_recovery(id, _combat_context(), _vitals())
	if not preview.ok:
		_result(preview)
		return
	var operation := _operation_id("consume")
	var context := _combat_context()
	var vitals := _vitals()
	var cooldown_ready := combat.can_commit_recovery(id, context, vitals, operation)
	var inventory_ready := inventory.can_apply_operation(operation, preview.data.cost)
	if not cooldown_ready.ok or not inventory_ready.ok:
		_result(cooldown_ready if not cooldown_ready.ok else inventory_ready)
		return
	# Both pure domains have passed preflight. No signal, callback or await occurs
	# between their commits; they are saved together in the same validated envelope.
	var consumed := inventory.apply_operation(operation, preview.data.cost)
	if not consumed.ok:
		_result(consumed)
		return
	var committed := combat.commit_recovery(id, context, vitals, operation)
	if not committed.ok:
		_fatal("恢复事务状态发生冲突，已停止写档。 " + str(committed.message))
		return
	player.health = minf(player.maximum_health, player.health + float(rules.data.camp.medkit_healing if id == "medkit" else rules.data.camp.ration_healing))
	_sound("confirm")
	hud.notify("已恢复生命；同类恢复进入共享冷却。")
	_save_progress(false)

func _apply_equipment_stats() -> bool:
	var evaluation := build_evaluator.evaluate(roster.active_build(), progress, inventory)
	if not evaluation.ok:
		_fatal(str(evaluation.message))
		return false
	var ratio := player.health / player.maximum_health
	var new_vitals := {"health": ratio * float(evaluation.data.stats.max_health), "stamina": minf(player.stamina, float(evaluation.data.stats.max_stamina)), "max_health": float(evaluation.data.stats.max_health), "max_stamina": float(evaluation.data.stats.max_stamina)}
	return _apply_derived_build(evaluation.data, new_vitals)

func _apply_derived_build(derived: Dictionary, vitals: Dictionary) -> bool:
	_derived_build = derived.duplicate(true)
	_stats = derived.stats.duplicate(true)
	active_weapon_id = str(roster.active_build().weapon_id)
	_apply_vitals(vitals)
	for key: String in ["move_speed", "stamina_recovery", "defense_drain", "passive_damage_reduction"]:
		player.config[key] = _stats[key]
	player.combat_state = combat
	var identity := player.set_character(roster.active_character_id)
	var weapon := player.set_weapon_tier(_weapon_tier())
	if not identity.ok or not weapon.ok:
		_fatal(str(identity.message if not identity.ok else weapon.message))
		return false
	_update_hud()
	return true

func _apply_vitals(vitals: Dictionary) -> void:
	player.maximum_health = float(vitals.max_health)
	player.maximum_stamina = float(vitals.max_stamina)
	player.health = float(vitals.health)
	player.stamina = float(vitals.stamina)

func _vitals() -> Dictionary:
	return {"health": player.health, "stamina": player.stamina, "max_health": player.maximum_health, "max_stamina": player.maximum_stamina}

func _combat_context() -> Dictionary:
	return {"active_character_id": roster.active_character_id, "realm": progress.realm, "skill_loadout": roster.active_build().skill_loadout, "weapon_tier": _weapon_tier(), "gameplay_running": session_started and not _quitting and not get_tree().paused}

func _weapon_tier() -> int:
	return int(inventory.get_equipment(active_weapon_id).get("tier", 1))

func _save_progress(show_notice: bool = true) -> Dictionary:
	if not session_started or player == null:
		return {"ok": true, "code": "save_not_required", "message": "尚未开始旅程。"}
	if save_blocked:
		return {"ok": false, "code": "future_schema" if _future_domain else "save_blocked", "message": "保存保护已启用，已有存档保持原样。"}
	var payload := {"domain_version": DOMAIN_VERSION, "world": progress.snapshot(), "inventory": inventory.snapshot(), "active_weapon_id": active_weapon_id, "run_counter": run_counter, "operation_counter": _operation_counter, "bench_built": bench_built, "health": player.health, "stamina": player.stamina, "settings": settings.duplicate(true), "input_bindings": input_adapter.snapshot_bindings(), "interrupted_expedition": not in_camp, "character_builds": roster.snapshot(), "combat_state": combat.snapshot()}
	var validated := AWBuildMigration.migrate_payload(payload, character_config, build_evaluator)
	if not validated.ok:
		hud.notify("当前进度校验失败，已有文件已保留。 " + str(validated.message), 9.0)
		push_error(JSON.stringify({"module": "save", "operation": "validate", "code": validated.code}))
		return validated
	var result := repository.save(validated.data, _validate_existing_progress)
	if result.ok:
		save_available = true
		if show_notice:
			hud.notify("进度已验证保存。")
	else:
		if result.code == "future_schema":
			save_blocked = true
			_future_domain = true
		hud.notify("保存失败：" + str(result.message), 9.0)
		push_error(JSON.stringify({"module": "save", "operation": "save", "code": result.code, "version": "0.1.0"}))
	return result

func _validate_existing_progress(payload: Dictionary) -> Dictionary:
	return AWBuildMigration.migrate_payload(payload, character_config, build_evaluator)

func _restore_payload(payload: Dictionary) -> Dictionary:
	var migrated := AWBuildMigration.migrate_payload(payload, character_config, build_evaluator)
	if not migrated.ok:
		return migrated
	var candidate: Dictionary = migrated.data
	var candidate_progress := AWWorldProgress.new(rules)
	var candidate_inventory := AWInventoryLedger.new(rules)
	var candidate_roster := AWCharacterRoster.new(character_config, build_evaluator)
	var candidate_combat := AWCombatState.new(character_config)
	for restored: Dictionary in [candidate_progress.restore(candidate.world), candidate_inventory.restore(candidate.inventory), candidate_combat.restore(candidate.combat_state)]:
		if not restored.ok:
			return restored
	var restored_roster := candidate_roster.restore(candidate.character_builds, candidate_progress, candidate_inventory)
	if not restored_roster.ok:
		return restored_roster
	var restored_bindings := input_adapter.restore_bindings(candidate.input_bindings)
	if not restored_bindings.ok:
		return restored_bindings
	# All candidate domains and InputMap are validated before the live references move.
	progress = candidate_progress
	inventory = candidate_inventory
	roster = candidate_roster
	combat = candidate_combat
	active_weapon_id = str(candidate.active_weapon_id)
	run_counter = int(candidate.run_counter)
	_operation_counter = int(candidate.operation_counter)
	bench_built = bool(candidate.bench_built)
	settings = candidate.settings.duplicate(true)
	set_meta("restore_health", float(candidate.health))
	set_meta("restore_stamina", float(candidate.stamina))
	if bool(candidate.interrupted_expedition):
		hud.notify("从营地检查点恢复；中断远征的未入库战利品未保留。", 9.0)
	return {"ok": true, "code": "ok", "message": "", "migrated": bool(migrated.migrated)}

func _configure_build_controller() -> bool:
	if build_controller == null:
		build_controller = AWBuildController.new()
		build_controller.name = "BuildController"
		build_controller.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(build_controller)
		build_controller.edited.connect(func() -> void: _save_progress(false))
		build_controller.build_applied.connect(_on_build_applied)
		build_controller.closed.connect(_on_build_closed)
	var configured := build_controller.configure(hud, character_config, build_evaluator, roster, progress, inventory, combat, _build_context, _vitals, func() -> String: return _operation_id("build"))
	if not configured.ok:
		_fatal(str(configured.message))
		return false
	return true

func _build_context() -> Dictionary:
	return {"session_started": session_started, "camp": in_camp, "encounter_ended": _ended()}

func _show_builds() -> void:
	if not session_started:
		return
	_build_return_mode = "pause" if get_tree().paused or not in_camp else "camp"
	if not in_camp:
		get_tree().paused = true
	_modal_mode = "build"
	_set_menu_block(true)
	var shown := build_controller.show()
	if not shown.ok:
		_result(shown)

func _on_build_applied(data: Dictionary) -> void:
	if not _apply_derived_build(data.derived_build, data.new_vitals):
		return
	_save_progress(false)
	_sound("confirm")

func _on_build_closed() -> void:
	if _build_return_mode == "pause":
		_show_pause()
	else:
		_show_camp()

func _apply_settings() -> void:
	if camera_rig:
		camera_rig.locked = bool(settings.camera_locked)
		camera_rig.shake_multiplier = float(settings.camera_shake)
	if audio:
		audio.call("configure", settings)
	if hud.root:
		hud.set_text_scale(float(settings.text_scale))
	input_adapter.touch_mode = OS.has_feature("mobile")
	hud.set_touch_visible(input_adapter.touch_mode)
	hud.update_bindings(input_adapter.bindings)

func _show_bindings() -> void:
	_binding_action = ""
	var options: Array = []
	for action: String in AWInputBindings.ACTIONS:
		if action == "pause":
			continue
		options.append({"label": "%s  ·  %s" % [str(input_adapter.bindings.label_for(action)), str(input_adapter.bindings.key_label(action))], "action": "bind:" + action})
	options.append({"label": "恢复默认按键", "action": "bindings_reset"})
	options.append({"label": "返回设置", "action": "settings"})
	hud.show_menu("键盘按键", "鼠标、触控与手柄保留独立绑定。ESC、确认和方向键保留菜单导航。", options)

func _input(event: InputEvent) -> void:
	if _quitting or not _pending_persistence_action.is_empty() or _binding_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode == KEY_ESCAPE:
		_show_bindings()
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		hud.notify("请选择单个物理按键。")
		return
	var result := input_adapter.set_binding(_binding_action, event.physical_keycode)
	if result.ok:
		_binding_action = ""
		_apply_settings()
		_save_preferences()
		_save_progress(false)
		_show_bindings()
	else:
		hud.notify(str(result.message))

func _on_setting(key: String, value: Variant) -> void:
	var candidate := settings.duplicate(true)
	candidate[key] = value
	var validation := AWGameSettings.validate(candidate)
	if validation.ok:
		settings = validation.data
		_apply_settings()
		_preferences_dirty = true
		_preferences_write_failed = false
		_preferences_delay = 0.35

func _save_preferences() -> Dictionary:
	_preferences_dirty = true
	if _preferences_blocked or preferences == null:
		_preferences_write_failed = true
		return {"ok": false, "code": "preferences_blocked", "message": "偏好保存保护已启用，已有文件保持原样。"}
	var result: Dictionary = preferences.save(settings, input_adapter.snapshot_bindings())
	if result.ok:
		_preferences_dirty = false
		_preferences_write_failed = false
	else:
		_preferences_write_failed = true
		hud.notify("偏好保存失败：" + str(result.message), 9.0)
		push_error(JSON.stringify({"module": "preferences", "code": result.code, "operation": "save"}))
	return result

func _close_menu() -> void:
	_binding_action = ""
	get_tree().paused = false
	hud.hide_menu()
	_set_menu_block(false)
	player.active = session_started

func _set_menu_block(blocked: bool) -> void:
	input_adapter.blocked = blocked
	hud.clear_touch()
	input_adapter.release_all()
	if camera_rig:
		camera_rig.allow_input = not blocked

func _restore_vitals(recover_failed_checkpoint: bool = false) -> void:
	if has_meta("restore_health"):
		player.health = float(get_meta("restore_health"))
		player.stamina = float(get_meta("restore_stamina"))
		remove_meta("restore_health")
		remove_meta("restore_stamina")
		if recover_failed_checkpoint and player.health == 0.0:
			_recover_after_failure()
			set_meta("failure_checkpoint_recovered", true)
			hud.notify("已从死亡检查点按失败规则回营，恢复35%生命；冷却和已入库进度保留。", 9.0)

func _recover_after_failure() -> void:
	combat.clear_effects()
	_pending_equipment.clear()
	player.health = maxf(1.0, player.maximum_health * 0.35)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _quitting and session_started and is_instance_valid(hud):
		input_adapter.release_all()
		hud.clear_touch()
		_save_progress(false)
		if not hud.modal.visible:
			_show_pause()

func _request_quit() -> void:
	if _quitting:
		return
	var results := _save_before_transition()
	if not results.is_empty():
		_show_persistence_failure("quit", results)
		return
	_finish_quit()

func _save_before_transition() -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	if _preferences_dirty:
		var preferred := _save_preferences()
		if not preferred.ok: failures.append({"label": "偏好", "result": preferred})
	if session_started:
		var saved := _save_progress(false)
		if not saved.ok: failures.append({"label": "进度", "result": saved})
	return failures

func _return_to_title() -> void:
	var failures := _save_before_transition()
	if not failures.is_empty():
		_show_persistence_failure("title", failures)
		return
	if not _pending_persistence_action.is_empty(): hud.pop_menu_layer(false)
	_pending_persistence_action = ""
	_binding_action = ""
	session_started = false
	player.active = false
	input_adapter.release_all()
	if audio: audio.call("set_encounter", false)
	_show_title()

func _show_persistence_failure(action: String, failures: Array[Dictionary]) -> void:
	if _pending_persistence_action.is_empty():
		_persistence_return_mode = _modal_mode
		_persistence_return_paused = get_tree().paused
		_persistence_return_blocked = input_adapter.blocked
		_persistence_return_player_active = player.active
		hud.push_menu_layer()
	_pending_persistence_action = action
	_modal_mode = "save_failure"
	get_tree().paused = true
	_set_menu_block(true)
	var description := "当前旅程仍在内存中，已有文件保持原样。\n"
	for failure: Dictionary in failures:
		description += str(failure.label) + "：" + str(failure.result.message) + "\n"
	var options: Array = [{"label": "重试保存并退出" if action == "quit" else "重试保存并回到标题", "action": "retry_quit" if action == "quit" else "retry_title"}]
	if action == "quit": options.append({"label": "明确放弃未保存内容并退出", "action": "discard_quit"})
	options.append({"label": "取消退出 / 保留当前旅程" if action == "quit" else "取消 / 保留当前旅程", "action": "cancel_quit" if action == "quit" else "cancel_title"})
	hud.show_menu("保存未完成", description, options)

func _cancel_pending_persistence() -> void:
	if _pending_persistence_action.is_empty(): return
	_pending_persistence_action = ""
	hud.pop_menu_layer()
	_modal_mode = _persistence_return_mode
	get_tree().paused = _persistence_return_paused
	_set_menu_block(_persistence_return_blocked)
	player.active = _persistence_return_player_active

func _finish_quit() -> void:
	if _quitting: return
	_quitting = true
	_pending_persistence_action = ""
	if is_instance_valid(input_adapter):
		input_adapter.release_all()
		input_adapter.blocked = true
	if is_instance_valid(player):
		player.active = false
	if is_instance_valid(audio):
		audio.call("stop_all")
	# AudioServer retires playback on its mix thread; let it complete without blocking.
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit()

func _ended() -> bool:
	return expedition.state == AWExpeditionState.State.DORMANT or expedition.is_ended()

func _update_hud() -> void:
	var objective := "在营地准备下一次远征\nE 打开维护/出营菜单"
	if not in_camp:
		objective = "个人晋阶挑战\n击败雨庭守卫" if expedition.challenge else "远征目标\n异变体 %d/3 · 资源点 %d/2\n负载 %d/18 · 回绿色圆环撤离" % [expedition.defeated_enemy_ids.size(), expedition.gathered_node_ids.size(), expedition.cargo_weight()]
		if expedition.objective_completed:
			objective = "目标已完成\n继续搜集或安全撤离\n負载 %d/18" % expedition.cargo_weight()
	hud.update_state({"region": "回收营地" if in_camp else ("雨庭" if expedition.region_id == "rain_court" else "导体工场"), "level": progress.level, "realm": progress.realm, "talent": progress.earned_talent_points, "objective": objective, "health": player.health, "max_health": player.maximum_health, "stamina": player.stamina, "max_stamina": player.maximum_stamina, "inventory": "金币%d  废铁%d  药包%d  |  电枪%d阶" % [inventory.count("currency"), inventory.count("scrap"), inventory.count("medkit"), _weapon_tier()]})
	var loadout: Array = roster.active_build().skill_loadout
	var slots: Array[Dictionary] = []
	for skill_id: String in loadout:
		slots.append({"id": skill_id, "label": str(character_config.data.skills[skill_id].label), "remaining": combat.cooldown_remaining(skill_id)})
	var state := combat.snapshot()
	hud.update_skill_state({"character_label": str(character_config.data.characters[roster.active_character_id].label), "slots": slots, "exclusive_available": roster.active_character_id == "healer", "exclusive_remaining": combat.cooldown_remaining("self_heal"), "recovery_remaining": combat.cooldown_remaining("recovery_family"), "barrier_capacity": state.effects.barrier_capacity, "focus_remaining": state.effects.focus_remaining}, input_adapter.bindings)

func _operation_id(kind: String) -> String:
	_operation_counter += 1
	return "%s-%d-%d" % [kind, run_counter, _operation_counter]

func _cost_text(cost: Dictionary) -> String:
	var names := {"currency": "金币", "scrap": "废铁", "alloy": "合金", "crystal": "晶片"}
	var parts: Array[String] = []
	for id: String in cost:
		parts.append("%s%d" % [str(names.get(id, id)), int(cost[id])])
	return " + ".join(parts)

func _result(result: Dictionary) -> void:
	hud.notify(str(result.get("message", "操作成功。")))
	if result.ok:
		_sound("confirm")

func _sound(event: String) -> void:
	if audio:
		audio.call("play_event", event)

func _fatal(message: String) -> void:
	save_blocked = true
	_fatal_failure = true
	session_started = false
	if is_instance_valid(player):
		player.active = false
	_set_menu_block(true)
	get_tree().paused = true
	hud.show_menu("无法启动", message + "\n请保留诊断与已有存档。", [{"label": "退出", "action": "quit"}])
	push_error(JSON.stringify({"module": "startup", "code": "configuration_error", "message": message}))

func _telegraph(location: Vector3, radius: float, duration: float) -> void:
	var marker := _ring(location + Vector3.UP * 0.1, Color("fa8a52"), radius)
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3.ONE, duration)
	tween.tween_callback(marker.queue_free)

func _ring(location: Vector3, color: Color, radius: float) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.01, radius - 0.09)
	torus.outer_radius = radius
	marker.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	marker.material_override = material
	effects.add_child(marker)
	marker.global_position = location
	marker.scale = Vector3.ONE * 0.3
	return marker

func _burst(location: Vector3, color: Color, radius: float) -> void:
	var marker := _ring(location, color, radius)
	var tween := marker.create_tween()
	tween.tween_property(marker, "scale", Vector3.ONE, 0.28)
	tween.tween_callback(marker.queue_free)

func _lightning(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	if direction.length() < 0.01:
		return
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035 if bool(settings.reduced_flashing) else 0.05
	cylinder.bottom_radius = cylinder.top_radius
	cylinder.height = direction.length()
	mesh.mesh = cylinder
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("7ae4ee")
	material.emission_enabled = true
	material.emission = Color("58c6e6")
	material.emission_energy_multiplier = 0.7 if bool(settings.reduced_flashing) else 1.7
	mesh.material_override = material
	effects.add_child(mesh)
	mesh.global_position = (from + to) * 0.5
	mesh.quaternion = Quaternion(Vector3.UP, direction.normalized())
	var timer := get_tree().create_timer(0.16, false)
	timer.timeout.connect(mesh.queue_free)
