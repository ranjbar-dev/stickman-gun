class_name GrenadeProjectile
extends RigidBody2D

# Physics grenade: bounces, 2 s fuse, 80 px blast radius.
# Self-damage is intentional — the thrower is not excluded.
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.1 / §5.4, Implementation Plan §2.6.

signal exploded(position: Vector2)

const FUSE_TIME: float = 2.0
const BLAST_RADIUS: float = 80.0
const BLAST_DAMAGE: int = 2
const DRAW_RADIUS: float = 8.0

var _exploded: bool = false
var _color: Color = Color.YELLOW_GREEN
var thrower_id: int = 0  # set by GrenadeWeapon after instantiation
var _fuse_timer: Timer = null
# Set by ProjectilePool so _explode() can return to the pool instead of queue_free.
var _pool: ProjectilePool = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	_fuse_timer = Timer.new()
	_fuse_timer.wait_time = FUSE_TIME
	_fuse_timer.one_shot = true
	_fuse_timer.timeout.connect(_explode)
	add_child(_fuse_timer)
	# Don't auto-start: pool pre-warms instances before they are used.
	# reset() starts the timer when the grenade is actually thrown.


## Re-arms this grenade for pooled reuse. Called by ProjectilePool users instead of
## instantiating a new scene.
func reset(pos: Vector2, vel: Vector2, thrower: int) -> void:
	_exploded = false
	thrower_id = thrower
	global_position = pos
	linear_velocity = vel
	modulate.a = 1.0
	if _fuse_timer != null:
		_fuse_timer.stop()
		_fuse_timer.start()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Small filled circle body.
	draw_circle(Vector2.ZERO, DRAW_RADIUS, _color)

	# Fuse indicator: arc shrinks from full circle to nothing as fuse burns down.
	# Color shifts from orange-red toward pure red as time runs out.
	if _fuse_timer != null and not _exploded:
		var fuse_ratio: float = clampf(_fuse_timer.time_left / FUSE_TIME, 0.0, 1.0)
		var arc_color := Color(1.0, fuse_ratio * 0.4, 0.0, 1.0)
		var arc_end: float = -PI * 0.5 + TAU * fuse_ratio
		draw_arc(Vector2.ZERO, DRAW_RADIUS + 3.0, -PI * 0.5, arc_end, 24, arc_color, 2.0)


func _on_body_entered(body: Node) -> void:
	if _exploded:
		return
	# Direct player contact triggers instant explosion.
	if body.has_node("HitboxManager"):
		_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true

	var blast_center: Vector2 = global_position

	# Blast damage is authoritative — only the host applies it.
	# On clients, the grenade physics still runs (for visual fidelity), but
	# damage is skipped; the host will broadcast hit RPCs to all peers.
	if NetworkManager.is_host:
		var space_state := get_world_2d().direct_space_state
		var query := PhysicsShapeQueryParameters2D.new()
		var shape := CircleShape2D.new()
		shape.radius = BLAST_RADIUS
		query.shape = shape
		query.transform = Transform2D(0.0, blast_center)
		# Layer mask: terrain (1) + body hitboxes (4) + player bodies (any layer they use).
		query.collision_mask = 0xFFFF
		query.collide_with_bodies = true
		query.collide_with_areas = false

		var results := space_state.intersect_shape(query, 16)
		var already_hit: Array[Node] = []

		for info in results:
			var body: Object = info.collider
			if not (body is Node):
				continue
			# Resolve HitboxManager from CharacterBody2D or its children.
			var hbm: Node = null
			if body.has_node("HitboxManager"):
				hbm = body.get_node("HitboxManager")
			if hbm == null or already_hit.has(hbm):
				continue
			already_hit.append(hbm)

			var hit_dir: Vector2 = (body.global_position - blast_center).normalized()
			if hbm.has_method("take_body_hit"):
				hbm.take_body_hit(blast_center, hit_dir, BLAST_DAMAGE, thrower_id)

	AudioManager.play_sfx("explosion", blast_center)
	exploded.emit(blast_center)
	if _pool != null:
		_pool.release(self)
	else:
		queue_free()
