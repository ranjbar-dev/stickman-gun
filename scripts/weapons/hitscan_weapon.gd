class_name HitscanWeapon
extends WeaponBase

# Pistol hitscan. Fired from weapon tip in the aim direction.
# Extends WeaponBase — cooldown and ammo are managed by the base class.
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.1 / §5.5, Implementation Plan §1.5 / §2.3.

signal head_hit(hit_position: Vector2)
signal body_hit(hit_position: Vector2)

const RANGE: float = 600.0           # pixels (~60% of 1080-wide canvas)
const TRACER_DURATION: float = 0.05  # seconds

@onready var _tracer_line: Line2D = $TracerLine
@onready var _tracer_timer: Timer = $TracerTimer


func _ready() -> void:
	super()
	fire_rate = 3.0
	damage = 1
	max_ammo = -1
	current_ammo = -1
	_tracer_timer.timeout.connect(_on_tracer_timeout)


func _fire() -> void:
	if _renderer == null:
		return

	var from: Vector2 = _renderer.get_weapon_tip_world()
	var aim_dir: Vector2 = _renderer.get_aim_dir_world()
	var to: Vector2 = from + aim_dir * RANGE
	var hit_point: Vector2 = to

	# Damage is computed only on the authoritative host. Clients still run _fire()
	# for immediate tracer feedback but must not touch health state locally.
	if NetworkManager.is_host:
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsRayQueryParameters2D.create(from, to)
		# Layer 1 = terrain, layer 2 = head_hitbox, layer 3 = body_hitbox (bits 0–2 → mask 7).
		query.collision_mask = 7
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = _get_owner_exclusions()

		var result := space_state.intersect_ray(query)

		if result:
			hit_point = result.position
			var collider: Object = result.collider
			# Only Area2D nodes carry hitbox groups; bodies are terrain.
			if collider is Area2D:
				var target_node := collider.get_parent()
				if collider.is_in_group("head_hitbox"):
					head_hit.emit(hit_point)
					if target_node.has_method("take_head_hit"):
						target_node.take_head_hit(hit_point, aim_dir, _get_owner_peer_id())
				elif collider.is_in_group("body_hitbox"):
					body_hit.emit(hit_point)
					if target_node.has_method("take_body_hit"):
						target_node.take_body_hit(hit_point, aim_dir, damage, _get_owner_peer_id())

	_show_tracer(from, hit_point)
	AudioManager.play_sfx("pistol_shot", global_position)
	_spawn_muzzle_flash()


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
