class_name GrenadeWeapon
extends WeaponBase

# Spawns GrenadeProjectile with physics arc. Emits trajectory_updated with
# world-space preview points while the aim joystick is held so the HUD overlay
# can draw the arc. Throw force scales with joystick magnitude.
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.4, Implementation Plan §2.6.

signal trajectory_updated(world_points: PackedVector2Array)

const GRENADE_SCENE := preload("res://scenes/projectiles/grenade_projectile.tscn")

const MAX_THROW_SPEED: float = 600.0   # pixels per second at full joystick deflection
const MIN_THROW_SPEED: float = 200.0   # minimum speed so the grenade always travels
const GRAVITY: float = 980.0           # must match StickmanController.GRAVITY
const PREVIEW_STEPS: int = 15
const PREVIEW_DT: float = 0.08         # seconds per simulation step

var _show_preview: bool = false
# World-space arc points computed each frame; emitted via trajectory_updated signal.
var _preview_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	super()
	fire_rate = 0.5
	damage = 2
	max_ammo = 3
	current_ammo = 3


func set_aim_input(dir: Vector2) -> void:
	super(dir)
	_show_preview = dir.length() > 0.05


func stop_firing() -> void:
	super()
	_show_preview = false
	_preview_points.clear()
	trajectory_updated.emit(_preview_points)


func _process(delta: float) -> void:
	super(delta)
	if _show_preview and _renderer != null:
		_calc_preview_points()
		trajectory_updated.emit(_preview_points)


func _fire() -> void:
	if _renderer == null:
		return

	var from: Vector2 = _renderer.get_weapon_tip_world()
	var throw_vel: Vector2 = _calc_throw_velocity()
	var owner_id: int = _get_owner_peer_id()

	# Grenade projectile is authoritative — only the host spawns it.
	# Clients receive an RPC (on_grenade_thrown) to spawn a cosmetic copy.
	if NetworkManager.is_host:
		var grenade: GrenadeProjectile = GRENADE_SCENE.instantiate()
		grenade.global_position = from
		grenade.thrower_id = owner_id
		# Add to the game world via the spawn parent set by WeaponHolder; fall back to
		# current scene if the weapon was constructed outside the normal hierarchy.
		var target: Node = _spawn_parent if _spawn_parent != null else get_tree().current_scene
		target.add_child(grenade)
		grenade.linear_velocity = throw_vel

		# Notify clients so they can spawn a cosmetic grenade.
		var event_rpc: EventRpc = target.get_node_or_null("EventRpc") as EventRpc
		if event_rpc:
			event_rpc.on_grenade_thrown.rpc(owner_id, from, throw_vel)

	_show_preview = false
	_preview_points.clear()
	trajectory_updated.emit(_preview_points)


# ------------------------------------------------------------------
# Trajectory preview
# ------------------------------------------------------------------

func _calc_preview_points() -> void:
	var from: Vector2 = _renderer.get_weapon_tip_world()
	var vel: Vector2 = _calc_throw_velocity()
	_preview_points.clear()

	var pos: Vector2 = from
	for i in PREVIEW_STEPS:
		_preview_points.append(pos)
		vel.y += GRAVITY * PREVIEW_DT
		pos += vel * PREVIEW_DT


func _calc_throw_velocity() -> Vector2:
	var raw_len: float = _aim_dir.length()
	var speed: float = clampf(raw_len * MAX_THROW_SPEED, MIN_THROW_SPEED, MAX_THROW_SPEED)
	var dir: Vector2 = _aim_dir.normalized() if raw_len > 0.01 else Vector2.RIGHT
	return dir * speed
