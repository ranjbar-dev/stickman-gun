class_name WeaponHolder
extends Node2D

# Manages the player's two weapon slots: a permanent pistol and an optional
# secondary (sniper / shotgun / grenade). Routes aim/fire to the active slot
# and keeps the renderer in sync.
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §2.7

signal active_weapon_changed(weapon: WeaponBase)

const SNIPER_SCENE  := preload("res://scenes/weapons/sniper_weapon.tscn")
const SHOTGUN_SCENE := preload("res://scenes/weapons/shotgun_weapon.tscn")
const GRENADE_SCENE := preload("res://scenes/weapons/grenade_weapon.tscn")

@onready var _pistol: WeaponBase = $HitscanWeapon

var _secondary: WeaponBase = null
var _active_is_pistol: bool = true
var _renderer: StickmanRenderer = null


# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

# Called by StickmanController after both nodes are ready.
func set_renderer(r: StickmanRenderer) -> void:
	_renderer = r
	_setup_weapon(_pistol)
	if _secondary != null:
		_setup_weapon(_secondary)
	_sync_renderer_type()


# ------------------------------------------------------------------
# Active weapon access
# ------------------------------------------------------------------

func get_active_weapon() -> WeaponBase:
	return _pistol if _active_is_pistol else _secondary


func is_active_weapon_firing() -> bool:
	return get_active_weapon()._is_firing


# ------------------------------------------------------------------
# Input forwarding
# ------------------------------------------------------------------

func set_aim_input(dir: Vector2) -> void:
	get_active_weapon().set_aim_input(dir)


func start_firing() -> void:
	get_active_weapon().start_firing()


# Stops both slots to guarantee neither fires after joystick release or death.
func stop_active_weapon() -> void:
	_pistol.stop_firing()
	if _secondary != null:
		_secondary.stop_firing()


# ------------------------------------------------------------------
# Swap
# ------------------------------------------------------------------

func swap_weapon() -> void:
	if _secondary == null:
		return
	get_active_weapon().stop_firing()
	_active_is_pistol = !_active_is_pistol
	_sync_renderer_type()
	active_weapon_changed.emit(get_active_weapon())


# ------------------------------------------------------------------
# Pickup / drop
# ------------------------------------------------------------------

# Equips a new secondary. Returns a dict with the old secondary's data if one
# was displaced ({weapon_type, ammo}), or an empty dict if the slot was free.
func pick_up_secondary(weapon_type: String, ammo: int) -> Dictionary:
	var dropped_data: Dictionary = {}

	if _secondary != null:
		dropped_data = {
			"weapon_type": _type_of_weapon(_secondary),
			"ammo": _secondary.current_ammo,
		}
		_secondary.stop_firing()
		remove_child(_secondary)
		_secondary.queue_free()
		_secondary = null

	var scene: PackedScene = _scene_for_type(weapon_type)
	_secondary = scene.instantiate() as WeaponBase
	add_child(_secondary)
	_setup_weapon(_secondary)

	# Override ammo only when the pickup specifies a non-default count.
	if ammo >= 0:
		_secondary.current_ammo = ammo

	# Auto-switch to the new weapon.
	_active_is_pistol = false
	_sync_renderer_type()
	active_weapon_changed.emit(_secondary)

	return dropped_data


# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

func _setup_weapon(weapon: WeaponBase) -> void:
	weapon.set_renderer(_renderer)
	# Supply the game scene as spawn target so GrenadeWeapon can add projectiles
	# without hard-coding tree depth. WeaponHolder sits at:
	# game_scene → StickmanController → WeaponHolder → weapon
	weapon.set_spawn_parent(get_parent().get_parent())


func _sync_renderer_type() -> void:
	if _renderer == null:
		return
	_renderer.active_weapon_type = _type_of_weapon(get_active_weapon())


func _scene_for_type(weapon_type: String) -> PackedScene:
	match weapon_type:
		"sniper":  return SNIPER_SCENE
		"shotgun": return SHOTGUN_SCENE
		"grenade": return GRENADE_SCENE
		_:         return SNIPER_SCENE  # fallback; should not happen in practice


func _type_of_weapon(weapon: WeaponBase) -> String:
	if weapon is SniperWeapon:  return "sniper"
	if weapon is ShotgunWeapon: return "shotgun"
	if weapon is GrenadeWeapon: return "grenade"
	return "pistol"
