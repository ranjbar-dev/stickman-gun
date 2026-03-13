extends Control

@onready var _left_joystick: VirtualJoystick = $LeftJoystick
@onready var _right_joystick: VirtualJoystick = $RightJoystick
@onready var _debug_label: Label = $DebugLabel

var _move_direction: Vector2 = Vector2.ZERO
var _aim_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	_left_joystick.joystick_input.connect(_on_move_input)
	_left_joystick.joystick_released.connect(_on_move_released)
	_right_joystick.joystick_input.connect(_on_aim_input)
	_right_joystick.joystick_released.connect(_on_aim_released)


func _process(_delta: float) -> void:
	_debug_label.text = (
		"MOVE: (%.2f, %.2f)     AIM: (%.2f, %.2f)" % [
			_move_direction.x, _move_direction.y,
			_aim_direction.x, _aim_direction.y
		]
	)


func _draw() -> void:
	# Vertical divider between the two joystick halves.
	var mid_x: float = size.x * 0.5
	draw_line(Vector2(mid_x, 0.0), Vector2(mid_x, size.y), Color(1.0, 1.0, 1.0, 0.15), 2.0)


func _on_move_input(direction: Vector2) -> void:
	_move_direction = direction


func _on_move_released() -> void:
	_move_direction = Vector2.ZERO


func _on_aim_input(direction: Vector2) -> void:
	_aim_direction = direction


func _on_aim_released() -> void:
	_aim_direction = Vector2.ZERO
