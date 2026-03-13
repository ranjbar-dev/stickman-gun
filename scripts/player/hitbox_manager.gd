class_name HitboxManager
extends Node

# Manages player health and hitbox response. Lives as a child of StickmanController
# so that HitscanWeapon's collider.get_parent() resolves to this node.
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §2.1

signal hit(hit_pos: Vector2, damage: int, is_headshot: bool)
signal died(kill_force: Vector2, killer_id: int)
signal health_changed(new_health: int)

@export var health: int = 3

var _is_dead: bool = false
var _last_attacker_id: int = 0


func _ready() -> void:
	$HeadHitbox.add_to_group("head_hitbox")
	$BodyHitbox.add_to_group("body_hitbox")


# Called by weapons when the HeadHitbox Area2D is hit.
# attacker_id is the peer_id of the shooter (0 if unknown).
func take_head_hit(hit_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO, attacker_id: int = 0) -> void:
	if _is_dead:
		return
	_last_attacker_id = attacker_id
	hit.emit(hit_pos, health, true)  # damage = current health → instant kill
	_apply_damage(health, hit_dir)


# Called by weapons when the BodyHitbox Area2D is hit.
# amount defaults to 1 for backward compat; Sniper and Grenade pass higher values.
func take_body_hit(hit_pos: Vector2, hit_dir: Vector2 = Vector2.ZERO, amount: int = 1, attacker_id: int = 0) -> void:
	if _is_dead:
		return
	_last_attacker_id = attacker_id
	hit.emit(hit_pos, amount, false)
	_apply_damage(amount, hit_dir)


func is_alive() -> bool:
	return not _is_dead


# Instantly kills the player without going through normal hit validation.
# Used when a peer disconnects mid-round so their stickman dies cleanly.
func force_kill() -> void:
	if _is_dead:
		return
	_is_dead = true
	health = 0
	health_changed.emit(health)
	died.emit(Vector2.ZERO, 0)


func _apply_damage(amount: int, hit_dir: Vector2) -> void:
	health -= amount
	if health <= 0:
		health = 0
		_is_dead = true
		health_changed.emit(health)
		died.emit(hit_dir, _last_attacker_id)
	else:
		health_changed.emit(health)
