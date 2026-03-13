class_name GrenadeOverlay
extends Control

# Full-screen transparent overlay that draws the grenade trajectory arc.
# Subscribes to GrenadeWeapon.trajectory_updated and converts world-space
# points to viewport space for rendering on top of everything else.
# Call setup() to bind to a WeaponHolder instance.
# Design ref: STICKFIGHT_GAME_DESIGN.md §5.4

var _world_points: PackedVector2Array = PackedVector2Array()
var _grenade_weapon: GrenadeWeapon = null


func setup(holder: WeaponHolder) -> void:
	holder.active_weapon_changed.connect(_on_weapon_changed)
	_on_weapon_changed(holder.get_active_weapon())


func _on_weapon_changed(weapon: WeaponBase) -> void:
	if _grenade_weapon != null and _grenade_weapon.trajectory_updated.is_connected(_on_trajectory_updated):
		_grenade_weapon.trajectory_updated.disconnect(_on_trajectory_updated)
	_grenade_weapon = null
	_world_points.clear()

	if weapon is GrenadeWeapon:
		_grenade_weapon = weapon as GrenadeWeapon
		_grenade_weapon.trajectory_updated.connect(_on_trajectory_updated)

	queue_redraw()


func _on_trajectory_updated(world_points: PackedVector2Array) -> void:
	_world_points = world_points
	queue_redraw()


func _draw() -> void:
	if _world_points.size() < 2:
		return
	var vp_transform: Transform2D = get_viewport().get_canvas_transform()
	for i: int in range(0, _world_points.size() - 1, 2):
		draw_line(
			vp_transform * _world_points[i],
			vp_transform * _world_points[i + 1],
			Color(1.0, 1.0, 1.0, 0.6),
			2.0
		)
