class_name WeaponBase
extends Node2D

# Abstract base for all weapons. Subclasses override _fire().
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §2.3

signal ammo_changed(current: int, max_val: int)

@export var fire_rate: float = 3.0   # shots per second
@export var damage: int = 1
@export var max_ammo: int = -1       # -1 = unlimited

var current_ammo: int = -1

var _renderer: StickmanRenderer = null
var _is_firing: bool = false
var _cooldown: float = 0.0
# Raw aim joystick direction (magnitude encodes throw force for Grenade).
var _aim_dir: Vector2 = Vector2.RIGHT
# Node to add dynamically-spawned objects to (e.g. grenades). Set by WeaponHolder.
var _spawn_parent: Node = null


func _ready() -> void:
	current_ammo = max_ammo


# Called by WeaponHolder after both nodes are ready.
func set_renderer(r: StickmanRenderer) -> void:
	_renderer = r


# Called by WeaponHolder so spawned projectiles land in the game scene, not inside
# the player's subtree.
func set_spawn_parent(node: Node) -> void:
	_spawn_parent = node


# Called every frame with the raw aim joystick vector.
# Magnitude is used by GrenadeWeapon; hitscan weapons use only the direction.
func set_aim_input(dir: Vector2) -> void:
	_aim_dir = dir


func start_firing() -> void:
	_is_firing = true


func stop_firing() -> void:
	_is_firing = false


func _process(delta: float) -> void:
	_cooldown -= delta
	if _is_firing and _cooldown <= 0.0:
		var has_ammo: bool = (max_ammo == -1) or (current_ammo > 0)
		if has_ammo:
			_fire()
			_cooldown = 1.0 / fire_rate
			if max_ammo != -1:
				current_ammo -= 1
				ammo_changed.emit(current_ammo, max_ammo)


# Override in subclasses. Called when cooldown has elapsed and ammo is available.
func _fire() -> void:
	pass


# Returns the RIDs of the owning player's hitbox Area2D nodes for raycast exclusion.
# Traverses: this weapon → WeaponHolder → StickmanController → HitboxManager → Area2D children.
func _get_owner_exclusions() -> Array[RID]:
	var rids: Array[RID] = []
	var controller: Node = get_parent().get_parent()  # WeaponHolder → StickmanController
	if controller == null:
		return rids
	var hbm: Node = controller.get_node_or_null("HitboxManager")
	if hbm == null:
		return rids
	for child in hbm.get_children():
		if child is CollisionObject2D:
			rids.append(child.get_rid())
	return rids


# Returns the peer_id of the StickmanController that owns this weapon.
# Used to identify the attacker when a hit is registered on the host.
func _get_owner_peer_id() -> int:
	var controller: Node = get_parent().get_parent()  # WeaponHolder → StickmanController
	if controller is StickmanController:
		return controller.peer_id
	return 0
