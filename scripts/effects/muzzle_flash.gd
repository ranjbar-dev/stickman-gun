class_name MuzzleFlash
extends Node2D

# Brief white circle + rays drawn at the weapon tip for one frame on fire.
# Spawned by WeaponBase._spawn_muzzle_flash(); self-frees after LIFETIME seconds.

const LIFETIME: float = 0.05
const CIRCLE_RADIUS: float = 7.0
const RAY_LENGTH: float = 9.0
const LINE_WIDTH: float = 2.0
const RAY_COUNT: int = 4

var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var alpha: float = 1.0 - (_elapsed / LIFETIME)
	var c := Color(1.0, 1.0, 1.0, alpha)
	draw_circle(Vector2.ZERO, CIRCLE_RADIUS, c)
	for i in RAY_COUNT:
		var angle: float = (TAU / RAY_COUNT) * i
		var ray_dir := Vector2(cos(angle), sin(angle))
		draw_line(ray_dir * CIRCLE_RADIUS, ray_dir * (CIRCLE_RADIUS + RAY_LENGTH), c, LINE_WIDTH)
