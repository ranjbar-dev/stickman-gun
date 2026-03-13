class_name SniperWeapon
extends WeaponBase

# Full-map hitscan, 2 damage, 5 ammo, thick tracer that fades over 0.3 s.
# Fires once per trigger pull (calls stop_firing() after each shot).
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.1, Implementation Plan §2.4.

signal head_hit(hit_position: Vector2)
signal body_hit(hit_position: Vector2)

const RANGE: float = 4000.0          # pixels — spans full map width
const TRACER_FADE_DURATION: float = 0.3

@onready var _tracer_line: Line2D = $TracerLine


func _ready() -> void:
	super()
	fire_rate = 0.8
	damage = 2
	max_ammo = 5
	current_ammo = 5


func _fire() -> void:
	if _renderer == null:
		return

	# Sniper fires once per trigger pull; base loop would keep firing while held.
	stop_firing()

	var from: Vector2 = _renderer.get_weapon_tip_world()
	var aim_dir: Vector2 = _renderer.get_aim_dir_world()
	var to: Vector2 = from + aim_dir * RANGE

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = 7
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = _get_owner_exclusions()

	var result := space_state.intersect_ray(query)
	var hit_point: Vector2 = to

	if result:
		hit_point = result.position
		var collider: Object = result.collider
		if collider is Area2D:
			var target_node := collider.get_parent()
			if collider.is_in_group("head_hitbox"):
				head_hit.emit(hit_point)
				if target_node.has_method("take_head_hit"):
					target_node.take_head_hit(hit_point, aim_dir)
			elif collider.is_in_group("body_hitbox"):
				body_hit.emit(hit_point)
				if target_node.has_method("take_body_hit"):
					target_node.take_body_hit(hit_point, aim_dir, damage)

	_show_tracer(from, hit_point)


func _show_tracer(from: Vector2, to: Vector2) -> void:
	var parent_global: Vector2 = get_parent().global_position
	_tracer_line.points = PackedVector2Array([
		from - parent_global,
		to - parent_global,
	])
	_tracer_line.modulate.a = 1.0
	_tracer_line.visible = true

	# Fade out via Tween rather than a hard-cut timer.
	var tween := create_tween()
	tween.tween_property(_tracer_line, "modulate:a", 0.0, TRACER_FADE_DURATION)
	tween.tween_callback(func() -> void: _tracer_line.visible = false)
