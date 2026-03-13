class_name HealthDisplay
extends Control

# Draws 3 filled/hollow circles representing the player's current health.
# Call setup() to bind to a HitboxManager instance.
# Design ref: STICKFIGHT_GAME_DESIGN.md §8

const DOT_RADIUS: float = 14.0
const DOT_STEP: float = 48.0          # center-to-center distance
const PADDING: float = 14.0
const COLOR_ALIVE: Color = Color(1.0, 1.0, 1.0, 0.90)
const COLOR_DEAD: Color = Color(1.0, 1.0, 1.0, 0.22)
const BORDER_WIDTH: float = 2.5

var _current_health: int = 3


func setup(hitbox_manager: HitboxManager) -> void:
	_current_health = hitbox_manager.health
	hitbox_manager.health_changed.connect(_on_health_changed)
	queue_redraw()


func _on_health_changed(new_health: int) -> void:
	_current_health = new_health
	queue_redraw()


func _draw() -> void:
	for i: int in 3:
		var center := Vector2(PADDING + DOT_RADIUS + i * DOT_STEP, PADDING + DOT_RADIUS)
		if i < _current_health:
			draw_circle(center, DOT_RADIUS, COLOR_ALIVE)
		else:
			draw_arc(center, DOT_RADIUS, 0.0, TAU, 32, COLOR_DEAD, BORDER_WIDTH)
