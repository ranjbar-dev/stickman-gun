extends Node2D

@onready var _player: StickmanController = $Player
@onready var _left_joystick: VirtualJoystick = $HUD/LeftJoystick
@onready var _right_joystick: VirtualJoystick = $HUD/RightJoystick
@onready var _jump_button: Button = $HUD/JumpButton


func _ready() -> void:
	_player.connect_joystick(_left_joystick)
	_player.connect_aim_joystick(_right_joystick)
	_jump_button.button_down.connect(_player.request_jump)
	# Constrain camera to this level's world bounds (4800 px wide).
	_player.set_camera_limits(0.0, 4800.0, -200.0, 900.0)
