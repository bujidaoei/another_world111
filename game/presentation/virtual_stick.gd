class_name AWVirtualStick
extends Control

signal changed(value: Vector2, pressed: bool)
var finger := -1
var mouse_drag := false
var value := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(148, 148)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and finger < 0:
			finger = event.index
			_update(event.position)
		elif not event.pressed and event.index == finger:
			finger = -1
			_clear()
		accept_event()
	elif event is InputEventScreenDrag and event.index == finger:
		_update(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_drag = event.pressed
		if mouse_drag:
			_update(event.position)
		else:
			_clear()
		accept_event()
	elif event is InputEventMouseMotion and mouse_drag:
		_update(event.position)
		accept_event()

func _update(at: Vector2) -> void:
	value = ((at - size * 0.5) / (size.x * 0.36)).limit_length(1.0)
	if value.length() < 0.12:
		value = Vector2.ZERO
	changed.emit(value, true)
	queue_redraw()

func _clear() -> void:
	value = Vector2.ZERO
	changed.emit(value, false)
	queue_redraw()

func reset_stick() -> void:
	finger = -1
	mouse_drag = false
	_clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_stick()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
		reset_stick()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, size.x * 0.46, Color(0.04, 0.1, 0.12, 0.7))
	draw_arc(center, size.x * 0.46, 0, TAU, 64, Color(0.4, 0.8, 0.8, 0.5), 2)
	draw_circle(center + value * size.x * 0.3, size.x * 0.17, Color(0.65, 0.86, 0.8, 0.75))
