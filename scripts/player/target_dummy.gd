class_name TargetDummy
extends Node2D

# Static shooting target with head_hitbox and body_hitbox Area2D children.
# Visual mirrors StickmanRenderer proportions in a neutral T-pose.

@export var dummy_color: Color = Color(0.8, 0.3, 0.3, 1.0)

# Proportions matching StickmanRenderer constants.
const HEAD_RADIUS := 12.0
const LINE_WIDTH := 2.5
const STANDING_BODY := 50.0
const ARM_UPPER := 22.0
const ARM_LOWER := 20.0
const LEG_UPPER := 22.0
const LEG_LOWER := 22.0
const HIP_HALF_WIDTH := 8.0
const SHOULDER_HALF_WIDTH := 10.0

var _draw_color: Color


func _ready() -> void:
	_draw_color = dummy_color
	# Register hitbox Area2D nodes into their respective groups.
	$HeadHitbox.add_to_group("head_hitbox")
	$BodyHitbox.add_to_group("body_hitbox")


func take_head_hit(hit_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO, _attacker_id: int = 0) -> void:
	print("HEADSHOT on %s at %s" % [name, hit_pos])
	_flash(Color(1.0, 0.15, 0.15, 1.0))


func take_body_hit(hit_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO, _amount: int = 1, _attacker_id: int = 0) -> void:
	print("Body hit on %s at %s" % [name, hit_pos])
	_flash(Color(1.0, 0.8, 0.1, 1.0))


func _flash(c: Color) -> void:
	_draw_color = c
	queue_redraw()
	var t := create_tween()
	t.tween_interval(0.12)
	t.tween_callback(func() -> void:
		_draw_color = dummy_color
		queue_redraw()
	)


func _draw() -> void:
	var hip := Vector2(0.0, -(LEG_UPPER + LEG_LOWER))
	var knee_l := Vector2(-HIP_HALF_WIDTH, -LEG_LOWER)
	var knee_r := Vector2(HIP_HALF_WIDTH, -LEG_LOWER)
	var foot_l := Vector2(-5.0, 0.0)
	var foot_r := Vector2(5.0, 0.0)
	var neck := hip + Vector2(0.0, -STANDING_BODY)
	var head_center := neck + Vector2(0.0, -HEAD_RADIUS)
	var shoulder_l := neck + Vector2(-SHOULDER_HALF_WIDTH, 0.0)
	var shoulder_r := neck + Vector2(SHOULDER_HALF_WIDTH, 0.0)
	# Arms in a T-pose for clear target silhouette.
	var elbow_l := shoulder_l + Vector2(-ARM_UPPER, 0.0)
	var hand_l := elbow_l + Vector2(-ARM_LOWER, 0.0)
	var elbow_r := shoulder_r + Vector2(ARM_UPPER, 0.0)
	var hand_r := elbow_r + Vector2(ARM_LOWER, 0.0)

	draw_arc(head_center, HEAD_RADIUS, 0.0, TAU, 32, _draw_color, LINE_WIDTH)
	draw_line(neck, hip, _draw_color, LINE_WIDTH)
	draw_line(hip, knee_l, _draw_color, LINE_WIDTH)
	draw_line(knee_l, foot_l, _draw_color, LINE_WIDTH)
	draw_line(hip, knee_r, _draw_color, LINE_WIDTH)
	draw_line(knee_r, foot_r, _draw_color, LINE_WIDTH)
	draw_line(shoulder_l, elbow_l, _draw_color, LINE_WIDTH)
	draw_line(elbow_l, hand_l, _draw_color, LINE_WIDTH)
	draw_line(shoulder_r, elbow_r, _draw_color, LINE_WIDTH)
	draw_line(elbow_r, hand_r, _draw_color, LINE_WIDTH)
