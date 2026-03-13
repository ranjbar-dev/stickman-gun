class_name ShotgunWeapon
extends WeaponBase

# Fires 5 independent hitscan pellets per shot in a 30° spread cone.
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.1 / §5.5, Implementation Plan §2.5.

const RANGE: float = 300.0           # pixels (short range ~25% screen)
const PELLET_COUNT: int = 5
const SPREAD_HALF: float = PI / 12.0 # 15° in radians (total cone = 30°)
const TRACER_DURATION: float = 0.05

# Tracer lines recycled each shot — one per pellet.
var _tracer_lines: Array[Line2D] = []
var _tracer_timer: Timer


func _ready() -> void:
	super()
	fire_rate = 1.5
	damage = 1
	max_ammo = 8
	current_ammo = 8
	_build_tracers()


func _build_tracers() -> void:
	for i in PELLET_COUNT:
		var line := Line2D.new()
		line.default_color = Color(1.0, 0.7, 0.2, 0.8)
		line.width = 1.2
		line.z_index = 5
		line.visible = false
		add_child(line)
		_tracer_lines.append(line)

	_tracer_timer = Timer.new()
	_tracer_timer.wait_time = TRACER_DURATION
	_tracer_timer.one_shot = true
	_tracer_timer.timeout.connect(_on_tracer_timeout)
	add_child(_tracer_timer)


func _fire() -> void:
	if _renderer == null:
		return

	var from: Vector2 = _renderer.get_weapon_tip_world()
	var aim_dir: Vector2 = _renderer.get_aim_dir_world()
	var base_angle: float = aim_dir.angle()
	var parent_global: Vector2 = get_parent().global_position

	# Damage and raycasts run only on the authoritative host. Clients still run
	# _fire() so tracer lines appear immediately for local visual feedback.
	if NetworkManager.is_host:
		var space_state := get_world_2d().direct_space_state
		var exclusions: Array[RID] = _get_owner_exclusions()

		for i in PELLET_COUNT:
			var spread: float = randf_range(-SPREAD_HALF, SPREAD_HALF)
			var pellet_dir: Vector2 = Vector2.from_angle(base_angle + spread)
			var to: Vector2 = from + pellet_dir * RANGE

			var query := PhysicsRayQueryParameters2D.create(from, to)
			query.collision_mask = 7
			query.collide_with_areas = true
			query.collide_with_bodies = true
			query.exclude = exclusions

			var result := space_state.intersect_ray(query)
			var hit_point: Vector2 = to

			if result:
				hit_point = result.position
				var collider: Object = result.collider
				if collider is Area2D:
					var target_node := collider.get_parent()
					if collider.is_in_group("head_hitbox"):
						if target_node.has_method("take_head_hit"):
							target_node.take_head_hit(hit_point, pellet_dir, _get_owner_peer_id())
					elif collider.is_in_group("body_hitbox"):
						if target_node.has_method("take_body_hit"):
							target_node.take_body_hit(hit_point, pellet_dir, damage, _get_owner_peer_id())

			# Show tracer for this pellet.
			var line: Line2D = _tracer_lines[i]
			line.points = PackedVector2Array([from - parent_global, hit_point - parent_global])
			line.visible = true
	else:
		# Client: show tracer lines without raycasting (cosmetic only).
		for i in PELLET_COUNT:
			var spread: float = randf_range(-SPREAD_HALF, SPREAD_HALF)
			var pellet_dir: Vector2 = Vector2.from_angle(base_angle + spread)
			var to: Vector2 = from + pellet_dir * RANGE
			var line: Line2D = _tracer_lines[i]
			line.points = PackedVector2Array([from - parent_global, to - parent_global])
			line.visible = true

	_tracer_timer.start()
	AudioManager.play_sfx("shotgun_blast", global_position)
	_spawn_muzzle_flash()


func _on_tracer_timeout() -> void:
	for line in _tracer_lines:
		line.visible = false
