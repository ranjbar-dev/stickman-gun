class_name WeaponDisplay
extends Control

# Shows the active weapon name and remaining ammo count (top-right HUD element).
# Call setup() to bind to a WeaponHolder instance.
# Design ref: STICKFIGHT_GAME_DESIGN.md §8

@onready var _weapon_label: Label = $WeaponLabel
@onready var _ammo_label: Label = $AmmoLabel

var _current_weapon: WeaponBase = null


func setup(holder: WeaponHolder) -> void:
	holder.active_weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(holder.get_active_weapon())


func _on_weapon_changed(weapon: WeaponBase) -> void:
	if _current_weapon != null and _current_weapon.ammo_changed.is_connected(_on_ammo_changed):
		_current_weapon.ammo_changed.disconnect(_on_ammo_changed)

	_current_weapon = weapon
	weapon.ammo_changed.connect(_on_ammo_changed)

	_weapon_label.text = _weapon_name(weapon)
	_refresh_ammo(weapon.current_ammo, weapon.max_ammo)


func _on_ammo_changed(current: int, max_val: int) -> void:
	_refresh_ammo(current, max_val)


func _refresh_ammo(current: int, max_val: int) -> void:
	if max_val == -1:
		_ammo_label.text = "x\u221e"
	else:
		_ammo_label.text = "x%d" % current


func _weapon_name(weapon: WeaponBase) -> String:
	if weapon is GrenadeWeapon: return "GRENADE"
	if weapon is SniperWeapon:  return "SNIPER"
	if weapon is ShotgunWeapon: return "SHOTGUN"
	return "PISTOL"
