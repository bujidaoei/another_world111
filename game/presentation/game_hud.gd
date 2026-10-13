class_name AWGameHUD
extends CanvasLayer

signal command(action: String)
signal setting_changed(key: String, value: Variant)
var root: Control
var modal: PanelContainer
var status: Label
var mission: Label
var inventory_label: Label
var health_bar: ProgressBar
var stamina_bar: ProgressBar
var health_text: Label
var notice: Label
var _notice_time := 0.0
var _modal_content: VBoxContainer
var _controls: Control
var _touch_controls: Control
var input_adapter: AWInputAdapter
var settings: Dictionary = {}
var _sticks: Array[AWVirtualStick] = []
var _modal_scroll: ScrollContainer
var _vitals: VBoxContainer
var _text_scale := 1.0

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	var title := VBoxContainer.new()
	title.position = Vector2(34, 28)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)
	var heading := Label.new()
	heading.text = "A N O T H E R  W O R L D"
	heading.add_theme_font_size_override("font_size", 29)
	heading.add_theme_color_override("font_color", Color("dfdbc5"))
	title.add_child(heading)
	status = Label.new()
	status.text = "另一个世界  /  回收营地"
	status.add_theme_font_size_override("font_size", 18)
	title.add_child(status)
	mission = Label.new()
	mission.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mission.offset_left = -380
	mission.offset_top = 36
	mission.offset_right = -36
	mission.offset_bottom = 186
	mission.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mission.add_theme_font_size_override("font_size", 20)
	mission.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(mission)
	var vitals := VBoxContainer.new()
	_vitals = vitals
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 34
	vitals.offset_top = -132
	vitals.offset_right = 334
	vitals.offset_bottom = -36
	vitals.custom_minimum_size = Vector2(300, 96)
	root.add_child(vitals)
	health_text = Label.new()
	vitals.add_child(health_text)
	health_bar = ProgressBar.new()
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(300, 12)
	vitals.add_child(health_bar)
	stamina_bar = ProgressBar.new()
	stamina_bar.show_percentage = false
	stamina_bar.custom_minimum_size = Vector2(300, 7)
	stamina_bar.add_theme_stylebox_override("fill", _style(Color("74cfdd")))
	vitals.add_child(stamina_bar)
	inventory_label = Label.new()
	inventory_label.add_theme_font_size_override("font_size", 16)
	vitals.add_child(inventory_label)
	_controls = Label.new()
	_controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_controls.offset_left = -670
	_controls.offset_top = -80
	_controls.offset_right = -40
	_controls.offset_bottom = -30
	(_controls as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	(_controls as Label).text = "左键 电链   右键 防御   SPACE 闪避\nQ 冲击   F 锚点   E 交互   H 药包   ESC 暂停"
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_controls)
	notice = Label.new()
	notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	notice.offset_left = -330
	notice.offset_top = -148
	notice.offset_right = 330
	notice.offset_bottom = -84
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_theme_font_size_override("font_size", 20)
	notice.add_theme_color_override("font_color", Color("ffd098"))
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notice)
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.visible = false
	root.add_child(modal)
	root.resized.connect(_layout_modal)
	root.resized.connect(_layout_hud)
	var margin := MarginContainer.new()
	for key: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(key, 26)
	modal.add_child(margin)
	_modal_scroll = ScrollContainer.new()
	_modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_modal_scroll.follow_focus = true
	margin.add_child(_modal_scroll)
	_modal_content = VBoxContainer.new()
	_modal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_modal_content.add_theme_constant_override("separation", 12)
	_modal_scroll.add_child(_modal_content)
	_build_touch()
	_layout_modal.call_deferred()
	_layout_hud.call_deferred()

func set_text_scale(value: float) -> void:
	_text_scale = value
	root.theme.default_font_size = int(18.0 * value)
	_scale_overrides(root)

func _scale_overrides(node: Node) -> void:
	if node is Control and node.has_theme_font_size_override("font_size"):
		if not node.has_meta("base_font_size"):
			node.set_meta("base_font_size", node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size", int(float(node.get_meta("base_font_size")) * _text_scale))
	for child: Node in node.get_children():
		_scale_overrides(child)

func _safe_insets() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	if safe.size.x <= 0 or safe.size.y <= 0 or window_size.x <= 0 or window_size.y <= 0:
		return Vector4.ZERO
	var multiplier := root.size / Vector2(window_size)
	return Vector4(maxf(0, safe.position.x) * multiplier.x, maxf(0, safe.position.y) * multiplier.y, maxf(0, window_size.x - safe.end.x) * multiplier.x, maxf(0, window_size.y - safe.end.y) * multiplier.y)

func _layout_hud() -> void:
	if _vitals == null or _touch_controls == null:
		return
	var safe := _safe_insets()
	_vitals.offset_left = 34 + safe.x
	_vitals.offset_right = 334 + safe.x
	_vitals.offset_top = (-350 if _touch_controls.visible else -132) - safe.w
	_vitals.offset_bottom = (-254 if _touch_controls.visible else -36) - safe.w
	mission.offset_right = -36 - safe.z
	mission.offset_left = -380 - safe.z
	mission.offset_top = 36 + safe.y
	mission.offset_bottom = 186 + safe.y
	notice.offset_top = (-290 if _touch_controls.visible else -148) - safe.w
	notice.offset_bottom = notice.offset_top + 64
	for child: Node in _touch_controls.get_children():
		if child is Control:
			if not child.has_meta("base_offsets"):
				child.set_meta("base_offsets", Vector4(child.offset_left, child.offset_top, child.offset_right, child.offset_bottom))
			var base: Vector4 = child.get_meta("base_offsets")
			var side := safe.x if child.anchor_left < 0.5 else -safe.z
			child.offset_left = base.x + side
			child.offset_right = base.z + side
			child.offset_top = base.y - safe.w
			child.offset_bottom = base.w - safe.w

func _layout_modal() -> void:
	if modal == null or root == null:
		return
	var viewport_size := root.size
	var safe := _safe_insets()
	var dimensions := Vector2(minf(720, viewport_size.x - 48 - safe.x - safe.z), minf(680, viewport_size.y - 80 - safe.y - safe.w))
	var shift := Vector2(safe.x - safe.z, safe.y - safe.w) * 0.5
	modal.custom_minimum_size = Vector2.ZERO
	modal.size = dimensions
	modal.offset_left = -dimensions.x * 0.5 + shift.x
	modal.offset_top = -dimensions.y * 0.5 + shift.y
	modal.offset_right = dimensions.x * 0.5 + shift.x
	modal.offset_bottom = dimensions.y * 0.5 + shift.y

func _process(delta: float) -> void:
	_notice_time -= delta
	notice.visible = _notice_time > 0.0

func update_state(data: Dictionary) -> void:
	status.text = "%s  ·  世界 %d  /  %s  ·  天赋点 %d" % [str(data.get("region", "回收营地")), int(data.get("level", 1)), "一阶" if int(data.get("realm", 1)) == 1 else "二阶", int(data.get("talent", 0))]
	mission.text = str(data.get("objective", "在维护台制备补给\n准备一次远征"))
	health_bar.max_value = float(data.get("max_health", 100.0))
	health_bar.value = float(data.get("health", 100.0))
	stamina_bar.max_value = float(data.get("max_stamina", 100.0))
	stamina_bar.value = float(data.get("stamina", 100.0))
	health_text.text = "生命 %d/%d     体力 %d" % [int(health_bar.value), int(health_bar.max_value), int(stamina_bar.value)]
	inventory_label.text = str(data.get("inventory", ""))

func notify(text: String, duration: float = 3.8) -> void:
	notice.text = text
	_notice_time = duration
	notice.visible = true

func show_menu(title: String, description: String, options: Array) -> void:
	_clear_modal()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 30)
	_modal_content.add_child(heading)
	var body := Label.new()
	body.text = description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 40)
	_modal_content.add_child(body)
	for option: Dictionary in options:
		var button := Button.new()
		button.text = str(option.label)
		button.custom_minimum_size.y = 43
		button.disabled = bool(option.get("disabled", false))
		button.tooltip_text = str(option.get("tooltip", ""))
		button.pressed.connect(func() -> void: command.emit(str(option.action)))
		_modal_content.add_child(button)
	modal.visible = true
	_scale_overrides(_modal_content)
	_layout_modal.call_deferred()
	for child: Node in _modal_content.get_children():
		if child is Button and not child.disabled:
			child.grab_focus()
			break

func show_settings(values: Dictionary) -> void:
	show_menu("设置 / SETTINGS", "音量、镜头与可读性即时应用并保存。", [])
	var labels := {"master_volume": "总音量", "music_volume": "音乐", "sfx_volume": "动作音效", "ambience_volume": "环境声", "text_scale": "字号倍率", "camera_shake": "镜头震动"}
	for key: String in labels:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = labels[key]
		label.custom_minimum_size.x = 135
		row.add_child(label)
		var slider := HSlider.new()
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = 0.85 if key == "text_scale" else 0.0
		slider.max_value = 1.5 if key == "text_scale" else 1.0
		slider.step = 0.05
		slider.value = float(values[key])
		slider.value_changed.connect(func(value: float) -> void: setting_changed.emit(key, value))
		row.add_child(slider)
		_modal_content.add_child(row)
	var flashing := CheckButton.new()
	flashing.text = "减少闪烁"
	flashing.button_pressed = bool(values.reduced_flashing)
	flashing.toggled.connect(func(on: bool) -> void: setting_changed.emit("reduced_flashing", on))
	_modal_content.add_child(flashing)
	var camera_lock := CheckButton.new()
	camera_lock.text = "固定镜头（仍跟随角色）"
	camera_lock.button_pressed = bool(values.camera_locked)
	camera_lock.toggled.connect(func(on: bool) -> void: setting_changed.emit("camera_locked", on))
	_modal_content.add_child(camera_lock)
	var bindings_button := Button.new()
	bindings_button.text = "键盘按键设置"
	bindings_button.pressed.connect(func() -> void: command.emit("bindings"))
	_modal_content.add_child(bindings_button)
	var close := Button.new()
	close.text = "返回"
	close.pressed.connect(func() -> void: command.emit("settings_back"))
	_modal_content.add_child(close)
	close.grab_focus()
	_scale_overrides(_modal_content)

func hide_menu() -> void:
	modal.visible = false

func update_bindings(bindings: RefCounted) -> void:
	(_controls as Label).text = "左键 电链   右键 防御   %s 闪避\n%s 冲击   %s 锚点   %s 交互   %s 药包   ESC 暂停" % [bindings.key_label("dodge"), bindings.key_label("pulse"), bindings.key_label("anchor"), bindings.key_label("interact"), bindings.key_label("heal")]

func set_touch_visible(value: bool) -> void:
	clear_touch()
	_touch_controls.visible = value
	_controls.visible = not value
	_layout_hud()

func clear_touch() -> void:
	for stick: AWVirtualStick in _sticks:
		stick.reset_stick()

func _clear_modal() -> void:
	_modal_scroll.scroll_vertical = 0
	for child: Node in _modal_content.get_children():
		_modal_content.remove_child(child)
		child.queue_free()

func _build_touch() -> void:
	_touch_controls = Control.new()
	_touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_touch_controls)
	var move := AWVirtualStick.new()
	move.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	move.offset_left = 34
	move.offset_top = -230
	move.offset_right = 184
	move.offset_bottom = -80
	move.changed.connect(func(value: Vector2, _pressed: bool) -> void:
		if input_adapter:
			input_adapter.set_touch_move(value))
	_touch_controls.add_child(move)
	_sticks.append(move)
	var aim := AWVirtualStick.new()
	aim.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	aim.offset_left = -190
	aim.offset_top = -230
	aim.offset_right = -40
	aim.offset_bottom = -80
	aim.changed.connect(func(value: Vector2, pressed: bool) -> void:
		if input_adapter:
			input_adapter.set_touch_aim(value, pressed and value.length() > 0.2))
	_touch_controls.add_child(aim)
	_sticks.append(aim)
	var actions := {"dodge": "闪避", "pulse": "冲击", "anchor": "锚点", "interact": "交互", "heal": "药包"}
	var index := 0
	for action: String in actions:
		var button := Button.new()
		button.text = actions[action]
		button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		var point := Vector2(-430 + (index % 3) * 76, -200 + floori(float(index) / 3.0) * 68)
		button.offset_left = point.x
		button.offset_top = point.y
		button.offset_right = point.x + 70
		button.offset_bottom = point.y + 60
		button.pressed.connect(func() -> void:
			if input_adapter:
				input_adapter.queue_touch(action))
		_touch_controls.add_child(button)
		index += 1
	var defense := Button.new()
	defense.text = "防御"
	defense.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	defense.offset_left = -278
	defense.offset_top = -132
	defense.offset_right = -208
	defense.offset_bottom = -72
	defense.button_down.connect(func() -> void:
		if input_adapter:
			input_adapter.set_touch_defense(true))
	defense.button_up.connect(func() -> void:
		if input_adapter:
			input_adapter.set_touch_defense(false))
	_touch_controls.add_child(defense)
	_touch_controls.visible = OS.has_feature("mobile")

func _theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", Color("dce4d9"))
	theme.set_color("font_color", "Button", Color("dce4d9"))
	theme.set_stylebox("normal", "Button", _style(Color("223a3e"), Color("4a6868")))
	theme.set_stylebox("hover", "Button", _style(Color("355355"), Color("9db5a1")))
	theme.set_stylebox("pressed", "Button", _style(Color("536863"), Color("dfca8b")))
	theme.set_stylebox("disabled", "Button", _style(Color("263333"), Color("334445")))
	theme.set_stylebox("panel", "PanelContainer", _style(Color(0.06, 0.12, 0.14, 0.97), Color("5d7871")))
	theme.set_stylebox("background", "ProgressBar", _style(Color("172b30")))
	theme.set_stylebox("fill", "ProgressBar", _style(Color("d8b775")))
	return theme

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(3)
	style.content_margin_left = 13
	style.content_margin_right = 13
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
