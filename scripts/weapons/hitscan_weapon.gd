class_name HitscanWeapon
extends Node2D

# Fired from weapon tip in the aim direction. Range ~600 px = ~60% of 1080-wide canvas.
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.1 / §5.5, Implementation Plan §1.5.

signal head_hit(hit_position: Vector2)
signal body_hit(hit_position: Vector2)

const FIRE_RATE: float = 3.0        # shots / second
const RANGE: float = 600.0          # pixels
const TRACER_DURATION: float = 0.05 # seconds

@onready var _tracer_line: Line2D = $TracerLine
@onready var _tracer_timer: Timer = $TracerTimer

var _renderer: StickmanRenderer = null
var _is_firing: bool = false
var _cooldown: float = 0.0


func _ready() -> void:
	_tracer_timer.timeout.connect(_on_tracer_timeout)


# Called by StickmanController after both nodes are ready.
func set_renderer(r: StickmanRenderer) -> void:
	_renderer = r


func start_firing() -> void:
	_is_firing = true


func stop_firing() -> void:
	_is_firing = false


func _process(delta: float) -> void:
	_cooldown -= delta
	if _is_firing and _cooldown <= 0.0:
		_fire()
		_cooldown = 1.0 / FIRE_RATE


func _fire() -> void:
	if _renderer == null:
		return

	var from: Vector2 = _renderer.get_weapon_tip_world()
	var aim_dir: Vector2 = _renderer.get_aim_dir_world()
	var to: Vector2 = from + aim_dir * RANGE

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	# Layer 1 = terrain, layer 2 = head_hitbox, layer 3 = body_hitbox (bits 0–2 → mask 7).
	query.collision_mask = 7
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# Prevent the owning CharacterBody2D from blocking its own shot.
	var owner_body := get_parent()
	if owner_body is CollisionObject2D:
		query.exclude = [owner_body.get_rid()]

	var result := space_state.intersect_ray(query)
	var hit_point: Vector2 = to

	if result:
		hit_point = result.position
		var collider: Object = result.collider
		# Only Area2D nodes carry hitbox groups; bodies are terrain.
		if collider is Area2D:
			var target_node := collider.get_parent()
			if collider.is_in_group("head_hitbox"):
				head_hit.emit(hit_point)
				if target_node.has_method("take_head_hit"):
					target_node.take_head_hit(hit_point)
			elif collider.is_in_group("body_hitbox"):
				body_hit.emit(hit_point)
				if target_node.has_method("take_body_hit"):
					target_node.take_body_hit(hit_point)

	_show_tracer(from, hit_point)


func _show_tracer(from: Vector2, to: Vector2) -> void:
	# Line2D draws in HitscanWeapon's local space, which shares the parent's origin.
	var parent_global: Vector2 = get_parent().global_position
	_tracer_line.points = PackedVector2Array([
		from - parent_global,
		to - parent_global,
	])
	_tracer_line.visible = true
	_tracer_timer.start()


func _on_tracer_timeout() -> void:
	_tracer_line.visible = false
