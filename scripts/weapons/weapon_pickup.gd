class_name WeaponPickup
extends Area2D

# Area2D trigger zone. When a stickman walks over it the weapon is moved into
# the player's secondary slot. If the player already has a secondary, the old
# weapon is dropped as a new pickup at the same position.
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §2.8

const BLINK_PERIOD: float = 0.5

signal weapon_taken(player_id: int, weapon_type: String, pickup_pos: Vector2, dropped_type: String, dropped_ammo: int)

@export var weapon_type: String = "sniper"  # "sniper" | "shotgun" | "grenade"
# Ammo to apply after pickup. -1 means use the weapon's own default.
@export var ammo_count: int = -1

var _blink_on: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var timer := Timer.new()
	timer.wait_time = BLINK_PERIOD
	timer.timeout.connect(_toggle_blink)
	add_child(timer)
	timer.start()


func _draw() -> void:
	match weapon_type:
		"sniper":
			# Long horizontal bar.
			draw_line(Vector2(-18.0, 0.0), Vector2(18.0, 0.0), Color.WHITE, 3.0)
			draw_line(Vector2(-18.0, -4.0), Vector2(-18.0, 4.0), Color.WHITE, 2.0)
		"shotgun":
			# Short wide barrel with a fork at the right end.
			draw_line(Vector2(-12.0, 0.0), Vector2(12.0, 0.0), Color.WHITE, 4.0)
			draw_line(Vector2(8.0, -5.0), Vector2(12.0, 0.0), Color.WHITE, 2.0)
			draw_line(Vector2(8.0, 5.0), Vector2(12.0, 0.0), Color.WHITE, 2.0)
		"grenade":
			# Small circle body with a short fuse line on top.
			draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 20, Color.WHITE, 2.0)
			draw_line(Vector2(0.0, -8.0), Vector2(3.0, -14.0), Color.YELLOW, 2.0)
		_:
			draw_line(Vector2(-10.0, 0.0), Vector2(10.0, 0.0), Color.WHITE, 2.0)


# ------------------------------------------------------------------
# Pickup logic
# ------------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	# Only stickman controllers have a WeaponHolder child.
	var holder: WeaponHolder = body.get_node_or_null("WeaponHolder")
	if holder == null:
		return

	var player_id: int = body.get("peer_id") if body.has_method("get_weapon_holder") else 0
	var dropped: Dictionary = holder.pick_up_secondary(weapon_type, ammo_count)

	weapon_taken.emit(
		player_id,
		weapon_type,
		global_position,
		dropped.get("weapon_type", ""),
		dropped.get("ammo", -1)
	)

	queue_free()


func _toggle_blink() -> void:
	_blink_on = !_blink_on
	visible = _blink_on
