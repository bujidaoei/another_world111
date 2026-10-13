extends Node
## Developer-only gameplay QA. All commands enter through InputEvents/UI hit testing.
## Observes domain state for assertions; never awards XP, grants loot or deals damage.

var session: AWGameSession
var stage := "idle"
var completed_runs := 0
var target_runs := 1
var results: Array[Dictionary] = []
var elapsed := 0.0
var _clock := 0.0
var _held_keys: Dictionary = {}
var _held_mouse: Dictionary = {}
var _route: Array[Vector3] = []
var _gather_index := 0
var _stage_clock := 0.0
var _last_click := -1.0
var _interact_clock := 0.0
var _last_position := Vector3.ZERO
var _stuck_time := 0.0
var _route_goal := Vector3.INF

func start(game: AWGameSession, run_count: int = 1, fresh: bool = false) -> void:
	session = game
	target_runs = run_count
	process_mode = Node.PROCESS_MODE_ALWAYS
	stage = "new" if fresh else "continue"
	_log("start", {"fresh": fresh, "requested_runs": target_runs})

func _process(delta: float) -> void:
	if stage in ["idle", "done", "error"] or session == null:
		return
	elapsed += delta
	_stage_clock += delta
	_clock += delta
	if _clock < 0.1:
		return
	_clock = 0.0
	if get_tree().paused and session.session_started:
		_release()
		_click("继续")
		return
	if elapsed > 900 or _stage_clock > 120:
		_fail("Stage timeout")
		return
	match stage:
		"new":
			if _click("开始新旅程"):
				_next("confirm_new")
		"confirm_new":
			if _click("明确开始新旅程"):
				_next("camp")
			elif session.session_started:
				_next("camp")
		"continue":
			if _click("继续旅程"):
				_next("camp")
			elif session.session_started:
				_next("camp")
		"settings_enter":
			if _click("设置"):
				_next("bindings_enter")
		"bindings_enter":
			if _click("键盘按键设置"):
				_next("bind_dodge")
		"bind_dodge":
			if _click("闪避"):
				_next("capture_dodge")
		"capture_dodge":
			_press(KEY_G)
			_next("binding_observe")
		"binding_observe":
			if session.input_adapter.bindings.key_for("dodge") == KEY_G:
				_log("title_binding_saved", {"started":session.session_started,"dodge_key":session.input_adapter.bindings.key_for("dodge"),"preferences":session.preferences.load()})
				stage = "done"
		"bindings_reset":
			if _click("恢复默认按键"):
				_next("binding_reset_observe")
		"binding_reset_observe":
			if session.input_adapter.bindings.key_for("dodge") == KEY_SPACE:
				_log("binding_defaults_restored", {"dodge_key":session.input_adapter.bindings.key_for("dodge")})
				stage="done"
		"failure_enter":
			if _click("出发：雨庭"):
				_next("failure_position")
		"failure_position":
			if _move_to(Vector3(-4,0,1), 1.5):
				_release()
				_next("failure_wait")
		"failure_wait":
			_release()
			if session.in_camp:
				_log("failure_return", _snapshot())
				stage="done"
		"camp":
			_release()
			if completed_runs >= target_runs:
				stage = "done"
				_log("done", _snapshot())
				return
			if _click("出发：雨庭"):
				_next("combat")
		"combat": _combat()
		"bench_open":
			_release()
			if _click("维护台："):
				_next("bench_build")
		"bench_build":
			if session.bench_built:
				_log("bench_built", _snapshot())
				_next("fusion_open")
			else:
				_click("建设维护台")
		"fusion_open":
			if _click("融合熔炉"):
				_next("fusion_lock")
		"fusion_lock":
			_log("fusion_preview", {"body":session.hud._modal_content.get_child(1).text})
			if _click("锁定 武器功率"):
				_next("fusion_confirm")
		"fusion_confirm":
			if _click("确认融合"):
				_next("expand")
		"expand":
			if int(session.inventory.get_equipment(session.active_weapon_id).slot_count) == 5:
				_log("fusion_and_expansion", _snapshot())
				_next("challenge_camp")
			else:
				_click("确定扩槽")
		"challenge_camp":
			if _click("返回营地"):
				_next("challenge_enter")
		"challenge_enter":
			if _click("个人晋阶挑战"):
				_next("challenge_combat")
		"challenge_combat":
			if session.in_camp:
				_release()
				if session.progress.realm != 2:
					_fail("Real input personal challenge failed")
				else:
					_log("ascension_victory", _snapshot())
					_next("advance_open")
			else:
				_combat()
		"advance_open":
			if _click("维护台："):
				_next("advance")
		"advance":
			if session._weapon_tier() == 2:
				_log("same_weapon_advanced", _snapshot())
				_next("conduit_camp")
			else:
				_click("装备进阶")
		"conduit_camp":
			if _click("返回营地"):
				_next("conduit_enter")
		"conduit_enter":
			if _click("出发：导体工场"):
				_next("anchor")
		"anchor":
			_press(KEY_F)
			_next("anchor_observe")
		"anchor_observe":
			if not session._anchors.is_empty():
				_log("anchor_placed", {"count":session._anchors.size(),"stamina":session.player.stamina,"realm":session.progress.realm,"weapon_tier":session._weapon_tier()})
				_next("combat")
		"gather": _gather()
		"return":
			if session.in_camp:
				completed_runs += 1
				_log("settled", _snapshot())
				_next("camp")
			elif _move_to(session.world.exit_position, 1.6):
				_press(KEY_E)

func _combat() -> void:
	if session.in_camp:
		_fail("Expedition failed during real-input combat")
		return
	var nearest: AWEnemyController
	var best := INF
	for child: Node in session.enemy_root.get_children():
		if child is AWEnemyController and child.active:
			var distance := session.player.global_position.distance_to(child.global_position)
			if distance < best:
				best = distance
				nearest = child
	if nearest == null:
		_release()
		_log("all_enemies_defeated", _snapshot())
		_gather_index = 0
		_next("gather")
		return
	_aim_at(nearest.global_position + Vector3.UP * 0.8)
	_mouse(MOUSE_BUTTON_LEFT, true)
	var away := session.player.global_position - nearest.global_position
	away.y = 0
	if best < 4.5:
		var goal := session.player.global_position + away.normalized() * 3
		goal.x = clampf(goal.x, -12, 12)
		goal.z = clampf(goal.z, -12, 12)
		_move_direction(goal - session.player.global_position)
	elif best > 7.2:
		_move_direction(-away)
	else:
		# Strafe the stationary ranged tell while remaining in weapon range.
		var tangent := Vector3(-away.z, 0, away.x).normalized()
		_move_direction(tangent)
	var primary_skill := str(session.roster.active_build().skill_loadout[0])
	if best < 3.8 and session.combat.cooldown_remaining(primary_skill) <= 0.0 and session.player.stamina >= float(session.character_config.skill(primary_skill).cost):
		_press(KEY_Q)
	if session.player.health < session.player.maximum_health * 0.6 and session.inventory.count("medkit") > 0:
		_press(KEY_H)

func _gather() -> void:
	var prefix := "conduit" if session.expedition.region_id == "conduit_yard" else "rain"
	var material := "alloy" if prefix == "conduit" else "scrap"
	var ids := [prefix + "_" + material + "_01", prefix + "_" + material + "_03", prefix + "_crystal_01"]
	if _gather_index >= ids.size():
		_log("objective_and_cargo", _snapshot())
		if not session.expedition.objective_completed:
			_fail("Objective missing after three real gathers and real kills")
			return
		_next("return")
		return
	var id: String = ids[_gather_index]
	if id in session.expedition.gathered_node_ids:
		_gather_index += 1
		_route.clear()
		return
	if _move_to(session.world.resource_positions[id], 1.65) and elapsed > _interact_clock:
		_press(KEY_E)
		_interact_clock = elapsed + 0.4

func _move_to(goal: Vector3, stop_distance: float) -> bool:
	var current := session.player.global_position
	var offset := goal - current
	offset.y = 0
	if offset.length() <= stop_distance:
		_move_direction(Vector3.ZERO)
		return true
	if _route.is_empty() or _route_goal != goal:
		_route = _find_path(current, goal)
		_route_goal = goal
		if _route.is_empty():
			_fail("No physics-clear route to resource/exit")
			return false
	if current.distance_to(_last_position) < 0.025:
		_stuck_time += 0.1
	else:
		_stuck_time = 0
	_last_position = current
	if _stuck_time > 4:
		_fail("Input movement blocked by collision")
		return false
	var waypoint := _route[0]
	var direction := waypoint - current
	direction.y = 0
	if direction.length() < 0.7:
		_route.pop_front()
	else:
		_move_direction(direction)
	return false

func _find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var origin := Vector2i(roundi(from.x), roundi(from.z))
	var end := Vector2i(roundi(to.x), roundi(to.z))
	var open: Array[Vector2i] = [origin]
	var came_from: Dictionary = {}
	var costs := {origin: 0.0}
	var closed: Dictionary = {}
	var walkable: Dictionary = {}
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var space := session.get_world_3d().direct_space_state
	while not open.is_empty():
		var current := open[0]
		var score := INF
		for candidate: Vector2i in open:
			var priority := float(costs[candidate]) + Vector2(candidate).distance_to(Vector2(end))
			if priority < score:
				score = priority
				current = candidate
		open.erase(current)
		if current == end:
			var path: Array[Vector3] = [to]
			while came_from.has(current):
				path.push_front(Vector3(current.x, 0, current.y))
				current = came_from[current]
			return path
		closed[current] = true
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := current + direction
			if absi(next.x) > 14 or absi(next.y) > 14 or closed.has(next):
				continue
			if not walkable.has(next):
				query.transform = Transform3D(Basis.IDENTITY, Vector3(next.x, 0.85, next.y))
				walkable[next] = space.intersect_shape(query, 1).is_empty()
			if not walkable[next]:
				continue
			var cost := float(costs[current]) + 1
			if not costs.has(next) or cost < float(costs[next]):
				costs[next] = cost
				came_from[next] = current
				if next not in open:
					open.append(next)
	return []

func _move_direction(direction: Vector3) -> void:
	var right := session.player.camera.global_basis.x
	var forward := -session.player.camera.global_basis.z
	right.y = 0
	forward.y = 0
	var unit := direction.normalized() if direction.length() > 0.15 else Vector3.ZERO
	var x := unit.dot(right.normalized())
	var y := unit.dot(forward.normalized())
	_key(KEY_A, x < -0.25)
	_key(KEY_D, x > 0.25)
	_key(KEY_W, y > 0.25)
	_key(KEY_S, y < -0.25)

func _aim_at(position: Vector3) -> void:
	var screen := get_viewport().get_final_transform() * session.player.camera.unproject_position(position)
	Input.warp_mouse(screen)
	var event := InputEventMouseMotion.new()
	event.position = screen
	event.global_position = screen
	Input.parse_input_event(event)

func _key(code: int, down: bool) -> void:
	if bool(_held_keys.get(code, false)) == down:
		return
	_held_keys[code] = down
	var event := InputEventKey.new()
	event.physical_keycode = code as Key
	event.keycode = code as Key
	event.pressed = down
	Input.parse_input_event(event)

func _press(code: int) -> void:
	_key(code, true)
	_key(code, false)

func _mouse(button: int, down: bool) -> void:
	if bool(_held_mouse.get(button, false)) == down:
		return
	_held_mouse[button] = down
	var event := InputEventMouseButton.new()
	event.button_index = button as MouseButton
	event.position = get_viewport().get_final_transform() * get_viewport().get_mouse_position()
	event.global_position = event.position
	event.pressed = down
	Input.parse_input_event(event)

func _click(text: String) -> bool:
	if elapsed - _last_click < 0.5 or not session.hud.modal.visible:
		return false
	for node: Node in session.hud._modal_content.get_children():
		if node is Button and text in node.text and not node.disabled:
			var rect: Rect2 = node.get_global_rect()
			if not session.hud.modal.get_global_rect().encloses(rect):
				session.hud._modal_scroll.ensure_control_visible(node)
				return false
			var point := get_viewport().get_final_transform() * rect.get_center()
			Input.warp_mouse(point)
			var motion := InputEventMouseMotion.new()
			motion.position = point
			motion.global_position = motion.position
			Input.parse_input_event(motion)
			_mouse(MOUSE_BUTTON_LEFT, true)
			_mouse(MOUSE_BUTTON_LEFT, false)
			_last_click = elapsed
			return true
	return false

func _release() -> void:
	for code: int in _held_keys.keys():
		_key(code, false)
	for button: int in _held_mouse.keys():
		_mouse(button, false)

func _next(next_stage: String) -> void:
	stage = next_stage
	_stage_clock = 0
	_route.clear()
	_stuck_time = 0
	_log("stage", {"stage": stage})

func _snapshot() -> Dictionary:
	return {"level": session.progress.level, "realm": session.progress.realm, "xp": session.progress.experience, "banked_xp": session.progress.banked_experience, "health": session.player.health, "inventory": session.inventory.snapshot(), "kills": session.expedition.defeated_enemy_ids.size(), "gathers": session.expedition.gathered_node_ids.size(), "objective": session.expedition.objective_completed, "cargo": session.expedition.pending_loot, "position": str(session.player.global_position), "camp": session.in_camp, "run": session.run_counter}

func _log(event: String, data: Dictionary) -> void:
	results.append({"at_seconds": elapsed, "event": event, "data": data})
	var output := FileAccess.open("res://../artifacts/input-playtest.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify({"driver": "InputEventKey/MouseMotion/MouseButton through engine input", "stage": stage, "completed_runs": completed_runs, "results": results}, "  "))

func _fail(message: String) -> void:
	_release()
	stage = "error"
	_log("failure", {"message": message, "state": _snapshot()})
