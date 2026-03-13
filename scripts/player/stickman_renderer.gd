class_name StickmanRenderer
extends Node2D

# Proportions (pixels, local space). Origin is at the stickman's feet.
const HEAD_RADIUS := 12.0
const LINE_WIDTH := 2.5
const WEAPON_LINE_WIDTH := 3.0

const STANDING_BODY := 50.0
const CROUCH_BODY := 28.0

const ARM_UPPER := 22.0
const ARM_LOWER := 20.0
const LEG_UPPER := 22.0
const LEG_LOWER := 22.0
const WEAPON_LENGTH := 24.0

const HIP_HALF_WIDTH := 8.0
const SHOULDER_HALF_WIDTH := 10.0

# Relaxed left-arm angle (pointing down and slightly forward).
const LEFT_ARM_ANGLE := PI * 0.55
const LEFT_FOREARM_ANGLE := PI * 0.65

@export var player_color: Color = Color.WHITE:
	set(value):
		player_color = value
		queue_redraw()

@export var aim_angle: float = 0.0:
	set(value):
		aim_angle = value
		queue_redraw()

@export var is_crouching: bool = false:
	set(value):
		is_crouching = value
		queue_redraw()

# Updated by WeaponHolder whenever the active slot changes.
@export var active_weapon_type: String = "pistol":
	set(value):
		active_weapon_type = value
		queue_redraw()


func _draw() -> void:
	var body_length := CROUCH_BODY if is_crouching else STANDING_BODY

	# --- Key joint positions (Y negative = upward) ---

	var hip: Vector2
	var knee_l: Vector2
	var knee_r: Vector2
	var foot_l: Vector2
	var foot_r: Vector2

	if is_crouching:
		# Knees wider and less raised; hip closer to ground.
		foot_l = Vector2(-5.0, 0.0)
		foot_r = Vector2(5.0, 0.0)
		knee_l = Vector2(-HIP_HALF_WIDTH * 1.8, -(LEG_LOWER * 0.6))
		knee_r = Vector2(HIP_HALF_WIDTH * 1.8, -(LEG_LOWER * 0.6))
		hip = Vector2(0.0, -(LEG_UPPER + LEG_LOWER) * 0.65)
	else:
		foot_l = Vector2(-5.0, 0.0)
		foot_r = Vector2(5.0, 0.0)
		knee_l = Vector2(-HIP_HALF_WIDTH, -LEG_LOWER)
		knee_r = Vector2(HIP_HALF_WIDTH, -LEG_LOWER)
		hip = Vector2(0.0, -(LEG_UPPER + LEG_LOWER))

	var neck: Vector2 = hip + Vector2(0.0, -body_length)
	var head_center: Vector2 = neck + Vector2(0.0, -HEAD_RADIUS)

	var shoulder_l: Vector2 = neck + Vector2(-SHOULDER_HALF_WIDTH, 0.0)
	var shoulder_r: Vector2 = neck + Vector2(SHOULDER_HALF_WIDTH, 0.0)

	# Left arm (non-weapon) — relaxed pose.
	var elbow_l: Vector2 = shoulder_l + Vector2(cos(LEFT_ARM_ANGLE), sin(LEFT_ARM_ANGLE)) * ARM_UPPER
	var hand_l: Vector2 = elbow_l + Vector2(cos(LEFT_FOREARM_ANGLE), sin(LEFT_FOREARM_ANGLE)) * ARM_LOWER

	# Right arm (weapon arm) — follows aim_angle.
	var arm_dir := Vector2(cos(aim_angle), sin(aim_angle))
	var elbow_r: Vector2 = shoulder_r + arm_dir * ARM_UPPER
	var hand_r: Vector2 = elbow_r + arm_dir * ARM_LOWER

	# --- Draw calls ---

	# Head
	draw_arc(head_center, HEAD_RADIUS, 0.0, TAU, 32, player_color, LINE_WIDTH)

	# Body
	draw_line(neck, hip, player_color, LINE_WIDTH)

	# Legs
	draw_line(hip, knee_l, player_color, LINE_WIDTH)
	draw_line(knee_l, foot_l, player_color, LINE_WIDTH)
	draw_line(hip, knee_r, player_color, LINE_WIDTH)
	draw_line(knee_r, foot_r, player_color, LINE_WIDTH)

	# Left arm (non-weapon)
	draw_line(shoulder_l, elbow_l, player_color, LINE_WIDTH)
	draw_line(elbow_l, hand_l, player_color, LINE_WIDTH)

	# Right arm (weapon arm)
	draw_line(shoulder_r, elbow_r, player_color, LINE_WIDTH)
	draw_line(elbow_r, hand_r, player_color, LINE_WIDTH)

	# Weapon — visual varies by active weapon type.
	match active_weapon_type:
		"sniper":
			# Long thin line (40 px).
			var tip: Vector2 = hand_r + arm_dir * 40.0
			draw_line(hand_r, tip, player_color, 1.8)
		"shotgun":
			# Medium barrel (28 px) with a 2-line spread fork at the tip.
			var tip: Vector2 = hand_r + arm_dir * 28.0
			draw_line(hand_r, tip, player_color, WEAPON_LINE_WIDTH)
			var perp := arm_dir.rotated(PI * 0.5) * 4.0
			draw_line(tip - arm_dir * 4.0 + perp, tip + arm_dir * 4.0 + perp, player_color, 1.8)
			draw_line(tip - arm_dir * 4.0 - perp, tip + arm_dir * 4.0 - perp, player_color, 1.8)
		"grenade":
			# Small filled circle at the hand — no barrel line.
			draw_circle(hand_r + arm_dir * 6.0, 5.0, player_color)
		_:
			# "pistol" — default short line (24 px).
			var weapon_tip: Vector2 = hand_r + arm_dir * WEAPON_LENGTH
			draw_line(hand_r, weapon_tip, player_color, WEAPON_LINE_WIDTH)


# ------------------------------------------------------------------
# Helpers for weapon systems
# ------------------------------------------------------------------

# Returns the world-space position of the weapon tip, matching _draw() geometry.
func get_weapon_tip_world() -> Vector2:
	var body_length := CROUCH_BODY if is_crouching else STANDING_BODY
	var hip_y: float = -(LEG_UPPER + LEG_LOWER) * (0.65 if is_crouching else 1.0)
	var neck_y: float = hip_y - body_length
	var shoulder_r_local := Vector2(SHOULDER_HALF_WIDTH, neck_y)
	var arm_dir_local := Vector2(cos(aim_angle), sin(aim_angle))
	var weapon_ext: float
	match active_weapon_type:
		"sniper": weapon_ext = 40.0
		"shotgun": weapon_ext = 28.0
		"grenade": weapon_ext = 6.0
		_: weapon_ext = WEAPON_LENGTH
	var tip_local := shoulder_r_local + arm_dir_local * (ARM_UPPER + ARM_LOWER + weapon_ext)
	# Apply scale.x (facing flip) to map from renderer-local to world space.
	return global_position + Vector2(tip_local.x * scale.x, tip_local.y)


# Returns the world-space unit vector the weapon is pointing.
func get_aim_dir_world() -> Vector2:
	return Vector2(cos(aim_angle) * scale.x, sin(aim_angle))
