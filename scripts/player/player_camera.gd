extends Camera2D

@export var smoothing_speed: float = 5.0

# Map boundary limits in world-space pixels.
@export var map_left: float = 0.0
@export var map_right: float = 1920.0
@export var map_top: float = -200.0
@export var map_bottom: float = 900.0

var _spectate_target: Node2D = null


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	_apply_limits()


func _process(_delta: float) -> void:
	if _spectate_target != null and is_instance_valid(_spectate_target):
		global_position = _spectate_target.global_position


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


func start_spectating(target: Node2D) -> void:
	_spectate_target = target
	enabled = true


func stop_spectating() -> void:
	_spectate_target = null


# Brief camera shake — called on the killer's client only when they score a kill.
func shake(duration: float = 0.1, strength: float = 8.0) -> void:
	var tween := create_tween()
	var steps: int = maxi(int(duration / 0.02), 2)
	for i in steps:
		var off := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(self, "offset", off, duration / steps)
	tween.tween_property(self, "offset", Vector2.ZERO, 0.02)
