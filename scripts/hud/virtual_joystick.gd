class_name VirtualJoystick
extends Control

signal joystick_input(direction: Vector2)
signal joystick_released()

@export var joystick_radius: float = 120.0
@export var knob_radius: float = 40.0
@export var dead_zone: float = 0.15
@export var outer_color: Color = Color(1.0, 1.0, 1.0, 0.25)
@export var knob_color: Color = Color(1.0, 1.0, 1.0, 0.55)

var _active: bool = false
var _finger_index: int = -1
var _joystick_center: Vector2 = Vector2.ZERO
var _knob_offset: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Only claim the first touch that lands within this control's rect.
		if _active:
			return
		var local_pos: Vector2 = to_local(event.position)
		if not Rect2(Vector2.ZERO, size).has_point(local_pos):
			return
		_active = true
		_finger_index = event.index
		_joystick_center = local_pos
		_knob_offset = Vector2.ZERO
		_direction = Vector2.ZERO
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif event.index == _finger_index:
		_active = false
		_finger_index = -1
		_joystick_center = Vector2.ZERO
		_knob_offset = Vector2.ZERO
		_direction = Vector2.ZERO
		get_viewport().set_input_as_handled()
		queue_redraw()
		joystick_released.emit()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if not _active or event.index != _finger_index:
		return
	var local_pos: Vector2 = to_local(event.position)
	var offset: Vector2 = local_pos - _joystick_center
	# Clamp knob within the outer circle.
	if offset.length() > joystick_radius:
		offset = offset.normalized() * joystick_radius
	_knob_offset = offset
	# Apply dead zone: suppress tiny unintentional movements.
	if _knob_offset.length() < dead_zone * joystick_radius:
		_direction = Vector2.ZERO
	else:
		_direction = _knob_offset / joystick_radius
	get_viewport().set_input_as_handled()
	queue_redraw()


func _process(_delta: float) -> void:
	if _active:
		joystick_input.emit(_direction)


func _draw() -> void:
	if not _active:
		return
	draw_arc(_joystick_center, joystick_radius, 0.0, TAU, 64, outer_color, 3.0)
	draw_circle(_joystick_center + _knob_offset, knob_radius, knob_color)
