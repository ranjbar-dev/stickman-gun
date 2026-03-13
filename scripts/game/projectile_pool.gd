class_name ProjectilePool
extends Node

# Generic object pool for PackedScene instances.
# Pre-warms `pool_size` instances as hidden children. Callers request an instance
# with acquire() and return it with release(). On acquire(), the node is made visible
# and reparented to `spawn_parent` (or kept here if null). On release(), it is hidden
# and reparented back to this pool.
#
# Usage:
#   pool = ProjectilePool.new()
#   pool.initialize(MY_SCENE, 6, $GameWorld)
#   var node = pool.acquire()
#   ...
#   pool.release(node)

@export var pool_size: int = 6

var _scene: PackedScene = null
var _spawn_parent: Node = null
var _available: Array[Node] = []


## Call once after adding the pool to the tree.
func initialize(scene: PackedScene, size: int, spawn_parent: Node) -> void:
	_scene = scene
	_spawn_parent = spawn_parent
	pool_size = size
	_prewarm()


func _prewarm() -> void:
	for i in pool_size:
		var inst: Node = _scene.instantiate()
		add_child(inst)
		inst.visible = false
		if inst is RigidBody2D:
			(inst as RigidBody2D).freeze = true
		_available.append(inst)


## Returns an instance ready to use. May instantiate a new one if the pool is exhausted.
func acquire() -> Node:
	var inst: Node
	if _available.is_empty():
		# Pool exhausted — grow by one to avoid hard failures.
		inst = _scene.instantiate()
		add_child(inst)
	else:
		inst = _available.pop_back()

	inst.visible = true
	# Unfreeze physics bodies that were frozen on release.
	if inst is RigidBody2D:
		(inst as RigidBody2D).freeze = false
	if _spawn_parent != null and inst.get_parent() != _spawn_parent:
		inst.reparent(_spawn_parent)
	return inst


## Returns a node to the pool. The node must have been obtained from acquire().
func release(inst: Node) -> void:
	if not is_instance_valid(inst):
		return
	inst.visible = false
	# Freeze physics bodies so they don't interact while pooled.
	if inst is RigidBody2D:
		(inst as RigidBody2D).linear_velocity = Vector2.ZERO
		(inst as RigidBody2D).angular_velocity = 0.0
		(inst as RigidBody2D).freeze = true
	if inst.get_parent() != self:
		inst.reparent(self)
	_available.append(inst)
