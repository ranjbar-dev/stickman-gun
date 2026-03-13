extends Camera2D

@export var smoothing_speed: float = 5.0

# Map boundary limits in world-space pixels.
@export var map_left: float = 0.0
@export var map_right: float = 1920.0
@export var map_top: float = -200.0
@export var map_bottom: float = 900.0


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	_apply_limits()


func set_limits(left: float, right: float, top: float, bottom: float) -> void:
	map_left = left
	map_right = right
	map_top = top
	map_bottom = bottom
	_apply_limits()


func _apply_limits() -> void:
	limit_left = int(map_left)
	limit_right = int(map_right)
	limit_top = int(map_top)
	limit_bottom = int(map_bottom)
