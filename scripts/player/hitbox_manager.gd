class_name HitboxManager
extends Node

# Manages player health and hitbox response. Lives as a child of StickmanController
# so that HitscanWeapon's collider.get_parent() resolves to this node.
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §2.1

signal died(kill_force: Vector2)
signal health_changed(new_health: int)

@export var health: int = 3

var _is_dead: bool = false


func _ready() -> void:
	$HeadHitbox.add_to_group("head_hitbox")
	$BodyHitbox.add_to_group("body_hitbox")


# Called by HitscanWeapon (via has_method check) when the HeadHitbox Area2D is hit.
func take_head_hit(hit_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO) -> void:
	if _is_dead:
		return
	_apply_damage(health, hit_dir)  # instant kill — set health to 0


# Called by weapons (via has_method check) when the BodyHitbox Area2D is hit.
# amount defaults to 1 for backward compatibility; Sniper and Grenade pass higher values.
func take_body_hit(hit_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO, amount: int = 1) -> void:
	if _is_dead:
		return
	_apply_damage(amount, hit_dir)


func _apply_damage(amount: int, hit_dir: Vector2) -> void:
	health -= amount
	if health <= 0:
		health = 0
		_is_dead = true
		health_changed.emit(health)
		died.emit(hit_dir)
	else:
		health_changed.emit(health)
