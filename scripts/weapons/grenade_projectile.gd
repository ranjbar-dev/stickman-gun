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
const FUSE_LINE_LENGTH: float = 10.0

var _exploded: bool = false
var _color: Color = Color.YELLOW_GREEN


func _ready() -> void:
	body_entered.connect(_on_body_entered)

	var fuse := Timer.new()
	fuse.wait_time = FUSE_TIME
	fuse.one_shot = true
	fuse.timeout.connect(_explode)
	add_child(fuse)
	fuse.start()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Small filled circle body.
	draw_circle(Vector2.ZERO, DRAW_RADIUS, _color)
	# Fuse line: short stub pointing upward in local space.
	var fuse_end := Vector2(0.0, -(DRAW_RADIUS + FUSE_LINE_LENGTH))
	draw_line(Vector2(0.0, -DRAW_RADIUS), fuse_end, Color.ORANGE_RED, 2.0)


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

	# Query all physics bodies inside the blast radius.
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
			hbm.take_body_hit(blast_center, hit_dir, BLAST_DAMAGE)

	exploded.emit(blast_center)
	queue_free()
