class_name Ragdoll
extends Node2D

# Proportions matching StickmanRenderer constants exactly.
const HEAD_RADIUS := 12.0
const LINE_WIDTH := 2.5
const ARM_UPPER := 22.0
const ARM_LOWER := 20.0
const LEFT_ARM_ANGLE := PI * 0.55
const LEFT_FOREARM_ANGLE := PI * 0.65

# Physics tuning.
const IMPULSE_SCALE := 200.0
const GRAVITY_SCALE := 1.0
const LINEAR_DAMP := 0.5

# Fade timing (seconds).
const FADE_DELAY := 5.0
const FADE_DURATION := 1.5

# Collision: layer bit 3 (value 8) = ragdoll; mask bit 0 (value 1) = terrain only.
const RAGDOLL_LAYER := 8
const RAGDOLL_MASK := 1

var _color: Color = Color.WHITE
var _spawn_pos: Vector2 = Vector2.ZERO
var _kill_force: Vector2 = Vector2.ZERO

# Body references for rendering.
var _head: RigidBody2D
var _torso: RigidBody2D
var _upper_leg_l: RigidBody2D
var _lower_leg_l: RigidBody2D
var _upper_leg_r: RigidBody2D
var _lower_leg_r: RigidBody2D
var _upper_arm_l: RigidBody2D
var _lower_arm_l: RigidBody2D
var _upper_arm_r: RigidBody2D
var _lower_arm_r: RigidBody2D

# Maps each segment body → half-length along its local Y axis (for _draw_segment).
var _half_lengths: Dictionary = {}


## Call this BEFORE add_child so _ready() has the correct position, colour, and impulse.
func initialize(spawn_pos: Vector2, color: Color, kill_force: Vector2) -> void:
	_spawn_pos = spawn_pos
	_color = color
	# Guarantee a non-zero impulse direction so the ragdoll always moves.
	_kill_force = kill_force if kill_force.length() > 0.05 \
			else Vector2(randf_range(-1.0, 1.0), -0.5).normalized()


func _ready() -> void:
	global_position = _spawn_pos
	_build_ragdoll()
	_torso.apply_central_impulse(_kill_force * IMPULSE_SCALE)
	_start_fade_timer()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_torso):
		return

	# Head drawn as a circle at the head body's current world position.
	draw_arc(to_local(_head.global_position), HEAD_RADIUS, 0.0, TAU, 24, _color, LINE_WIDTH)

	# Each limb drawn as a line spanning the capsule body's two endpoints.
	_draw_segment(_torso)
	_draw_segment(_upper_leg_l)
	_draw_segment(_lower_leg_l)
	_draw_segment(_upper_leg_r)
	_draw_segment(_lower_leg_r)
	_draw_segment(_upper_arm_l)
	_draw_segment(_lower_arm_l)
	_draw_segment(_upper_arm_r)
	_draw_segment(_lower_arm_r)


## Draws a single physics segment as a line between its two capsule endpoints.
## Offset = half-length along local +Y after applying body rotation.
## Derivation: Vector2(0, half).rotated(θ) → (−half·sinθ, half·cosθ)
## which equals half · local_Y_axis in world space (since parent has no rotation).
func _draw_segment(body: RigidBody2D) -> void:
	var half: float = _half_lengths[body]
	var center := to_local(body.global_position)
	var offset := Vector2(0.0, half).rotated(body.rotation)
	draw_line(center - offset, center + offset, _color, LINE_WIDTH)


# ------------------------------------------------------------------
# Ragdoll construction
# ------------------------------------------------------------------

func _build_ragdoll() -> void:
	# Key joint positions in Ragdoll local space — feet at origin, Y negative = upward.
	var foot_l    := Vector2(-5.0,   0.0)
	var foot_r    := Vector2( 5.0,   0.0)
	var knee_l    := Vector2(-8.0, -22.0)
	var knee_r    := Vector2( 8.0, -22.0)
	var hip       := Vector2( 0.0, -44.0)
	var neck      := Vector2( 0.0, -94.0)
	var head_ctr  := Vector2( 0.0, -106.0)
	var shld_l    := Vector2(-10.0, -94.0)
	var shld_r    := Vector2( 10.0, -94.0)

	var elbow_l := shld_l + Vector2(cos(LEFT_ARM_ANGLE),    sin(LEFT_ARM_ANGLE))    * ARM_UPPER
	var hand_l  := elbow_l + Vector2(cos(LEFT_FOREARM_ANGLE), sin(LEFT_FOREARM_ANGLE)) * ARM_LOWER
	var elbow_r := shld_r  + Vector2(1.0, 0.0) * ARM_UPPER   # aim_angle = 0 (pointing right)
	var hand_r  := elbow_r + Vector2(1.0, 0.0) * ARM_LOWER

	# --- Bodies ---
	_torso       = _make_capsule("Torso",      _mid(hip,    neck),    5.0, 50.0,          _ang(hip,    neck))
	_head        = _make_circle( "Head",       head_ctr,              HEAD_RADIUS)
	_upper_leg_l = _make_capsule("UpperLegL",  _mid(hip,    knee_l),  3.0, _len(hip,    knee_l),  _ang(hip,    knee_l))
	_lower_leg_l = _make_capsule("LowerLegL",  _mid(knee_l, foot_l),  3.0, _len(knee_l, foot_l),  _ang(knee_l, foot_l))
	_upper_leg_r = _make_capsule("UpperLegR",  _mid(hip,    knee_r),  3.0, _len(hip,    knee_r),  _ang(hip,    knee_r))
	_lower_leg_r = _make_capsule("LowerLegR",  _mid(knee_r, foot_r),  3.0, _len(knee_r, foot_r),  _ang(knee_r, foot_r))
	_upper_arm_l = _make_capsule("UpperArmL",  _mid(shld_l, elbow_l), 3.0, ARM_UPPER,             _ang(shld_l, elbow_l))
	_lower_arm_l = _make_capsule("LowerArmL",  _mid(elbow_l, hand_l), 3.0, ARM_LOWER,             _ang(elbow_l, hand_l))
	_upper_arm_r = _make_capsule("UpperArmR",  _mid(shld_r, elbow_r), 3.0, ARM_UPPER,             _ang(shld_r, elbow_r))
	_lower_arm_r = _make_capsule("LowerArmR",  _mid(elbow_r, hand_r), 3.0, ARM_LOWER,             _ang(elbow_r, hand_r))

	# Register half-lengths for _draw_segment (capsule bodies only; head uses draw_arc).
	_half_lengths[_torso]       = 25.0
	_half_lengths[_upper_leg_l] = _len(hip,    knee_l)  * 0.5
	_half_lengths[_lower_leg_l] = _len(knee_l, foot_l)  * 0.5
	_half_lengths[_upper_leg_r] = _len(hip,    knee_r)  * 0.5
	_half_lengths[_lower_leg_r] = _len(knee_r, foot_r)  * 0.5
	_half_lengths[_upper_arm_l] = ARM_UPPER * 0.5
	_half_lengths[_lower_arm_l] = ARM_LOWER * 0.5
	_half_lengths[_upper_arm_r] = ARM_UPPER * 0.5
	_half_lengths[_lower_arm_r] = ARM_LOWER * 0.5

	# --- PinJoint2D connections (position = anatomical joint point in local space) ---
	_make_joint("JointNeck",      neck,    _torso,       _head)
	_make_joint("JointHipL",      hip,     _torso,       _upper_leg_l)
	_make_joint("JointHipR",      hip,     _torso,       _upper_leg_r)
	_make_joint("JointKneeL",     knee_l,  _upper_leg_l, _lower_leg_l)
	_make_joint("JointKneeR",     knee_r,  _upper_leg_r, _lower_leg_r)
	_make_joint("JointShoulderL", shld_l,  _torso,       _upper_arm_l)
	_make_joint("JointShoulderR", shld_r,  _torso,       _upper_arm_r)
	_make_joint("JointElbowL",    elbow_l, _upper_arm_l, _lower_arm_l)
	_make_joint("JointElbowR",    elbow_r, _upper_arm_r, _lower_arm_r)


func _make_capsule(body_name: String, center: Vector2, radius: float,
		length: float, angle: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.name           = body_name
	body.position       = center
	body.rotation       = angle
	body.gravity_scale  = GRAVITY_SCALE
	body.linear_damp    = LINEAR_DAMP
	body.collision_layer = RAGDOLL_LAYER
	body.collision_mask  = RAGDOLL_MASK

	var col   := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = radius
	shape.height = length
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body


func _make_circle(body_name: String, center: Vector2, radius: float) -> RigidBody2D:
	var body := RigidBody2D.new()
	body.name           = body_name
	body.position       = center
	body.gravity_scale  = GRAVITY_SCALE
	body.linear_damp    = LINEAR_DAMP
	body.collision_layer = RAGDOLL_LAYER
	body.collision_mask  = RAGDOLL_MASK

	var col   := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	add_child(body)
	return body


func _make_joint(joint_name: String, joint_pos: Vector2,
		body_a: RigidBody2D, body_b: RigidBody2D) -> void:
	var joint := PinJoint2D.new()
	joint.name   = joint_name
	joint.position = joint_pos
	# Siblings of the joint share the same parent (Ragdoll), so paths are "../BodyName".
	joint.node_a = NodePath("../" + body_a.name)
	joint.node_b = NodePath("../" + body_b.name)
	add_child(joint)


# ------------------------------------------------------------------
# Utility
# ------------------------------------------------------------------

func _mid(a: Vector2, b: Vector2) -> Vector2:
	return (a + b) * 0.5


func _len(a: Vector2, b: Vector2) -> float:
	return (b - a).length()


## Rotation (radians) so the body's local +Y axis aligns with the from→to direction.
## Proof: Vector2(0,1).rotated(θ) = (−sinθ, cosθ) = diff.normalized()
##        ⟹  θ = atan2(−diff.x, diff.y)
func _ang(from: Vector2, to: Vector2) -> float:
	var diff := to - from
	return atan2(-diff.x, diff.y)


# ------------------------------------------------------------------
# Fade out
# ------------------------------------------------------------------

func _start_fade_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = FADE_DELAY
	timer.one_shot  = true
	add_child(timer)
	timer.timeout.connect(_on_fade_timeout)
	timer.start()


func _on_fade_timeout() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(queue_free)
