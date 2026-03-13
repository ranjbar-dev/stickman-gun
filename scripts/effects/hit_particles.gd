class_name HitParticles
extends Node2D

# Short line fragments burst outward from a hit point.
# Spawned by game.gd on handle_player_hit(); returned to pool after LIFETIME seconds.

const LIFETIME: float = 0.2
const FRAGMENT_COUNT: int = 6
const MIN_SPEED: float = 100.0
const MAX_SPEED: float = 260.0
const FRAGMENT_LENGTH: float = 13.0
const LINE_WIDTH: float = 1.8

# Each fragment: [position: Vector2, velocity: Vector2, angle: float]
var _fragments: Array = []
var _elapsed: float = 0.0
# Set by ProjectilePool so reset() can return to pool after lifetime.
var _pool: ProjectilePool = null
var _active_tween: Tween = null


func _ready() -> void:
	# Only initialise fragments; fade is started by reset() when the effect is activated.
	# This prevents pre-warmed pool instances from self-destructing on _ready().
	_init_fragments()


## Re-arms this effect for pooled reuse at a new world position.
func reset(world_pos: Vector2) -> void:
	global_position = world_pos
	_elapsed = 0.0
	modulate.a = 1.0
	_init_fragments()
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_start_fade()


func _init_fragments() -> void:
	_fragments.clear()
	for i in FRAGMENT_COUNT:
		var angle: float = (TAU / FRAGMENT_COUNT) * i + randf_range(-0.3, 0.3)
		var speed: float = randf_range(MIN_SPEED, MAX_SPEED)
		_fragments.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(angle), sin(angle)) * speed,
			"angle": angle,
		})


func _start_fade() -> void:
	_active_tween = create_tween()
	_active_tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	if _pool != null:
		_active_tween.tween_callback(func() -> void: _pool.release(self))
	else:
		_active_tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_elapsed += delta
	for frag in _fragments:
		frag["pos"] += frag["vel"] * delta
	queue_redraw()


func _draw() -> void:
	for frag in _fragments:
		var pos: Vector2 = frag["pos"]
		var angle: float = frag["angle"]
		var tip: Vector2 = pos + Vector2(cos(angle), sin(angle)) * FRAGMENT_LENGTH
		draw_line(pos, tip, Color.WHITE, LINE_WIDTH)
