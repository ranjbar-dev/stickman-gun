class_name StickmanController
extends CharacterBody2D

const RAGDOLL_SCENE := preload("res://scenes/player/ragdoll.tscn")

# Movement tuning — all values from STICKFIGHT_GAME_DESIGN.md Section 4.
const WALK_SPEED: float = 200.0
const CROUCH_SPEED: float = 100.0
const JUMP_VELOCITY: float = -400.0
const GRAVITY: float = 980.0

# Left-joystick Y threshold to enter crouch (0–1 normalised; positive = down).
const CROUCH_Y_THRESHOLD: float = 0.6

# Mirrors StateSync.SYNC_INTERVAL — kept local to avoid cross-script coupling.
const INTERP_INTERVAL: float = 1.0 / 20.0

# Standing capsule: radius=15, total height=90 → cylinder=60px.
# Offset pins the capsule bottom to local Y=0 (feet), matching StickmanRenderer origin.
const STAND_RADIUS: float = 15.0
const STAND_HEIGHT: float = 90.0

# Crouching capsule: radius=12, total height=50 → cylinder=26px.
const CROUCH_RADIUS: float = 12.0
const CROUCH_HEIGHT: float = 50.0

@export var player_color: Color = Color.WHITE:
	set(value):
		player_color = value
		if _renderer:
			_renderer.player_color = value

@onready var _renderer: StickmanRenderer = $StickmanRenderer
@onready var _col: CollisionShape2D = $CollisionShape2D
@onready var _weapon_holder: WeaponHolder = $WeaponHolder
@onready var _camera: Camera2D = $Camera2D
@onready var _hitbox_manager: HitboxManager = $HitboxManager

var peer_id: int = 0

var _move_dir: float = 0.0
var _is_crouching: bool = false
var _jump_requested: bool = false
# 1.0 = facing right, -1.0 = facing left.
var _facing: float = 1.0
# True while the aim joystick is held; suppresses movement-based facing updates.
var _aim_active: bool = false
# Raw joystick vector sent to the host so aim direction and grenade throw force are accurate.
var _raw_aim_dir: Vector2 = Vector2.ZERO

# Guard against double-triggering death visuals (host runs _on_died via signal AND
# receives the on_player_killed RPC with call_local).
var _death_triggered: bool = false

# Client-side interpolation state (remote players on clients only).
var _interp_prev: Dictionary = {}
var _interp_curr: Dictionary = {}
var _interp_timer: float = 0.0
# True only for remote players on client peers — local player & host skip interpolation.
var _needs_interpolation: bool = false


func _ready() -> void:
	_renderer.player_color = player_color
	_apply_shape(false)
	_weapon_holder.set_renderer(_renderer)
	# died now carries (force, killer_id); we only need the force for the visual.
	_hitbox_manager.died.connect(func(force: Vector2, _killer_id: int) -> void: _on_died(force))


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

func set_camera_limits(left: float, right: float, top: float, bottom: float) -> void:
	_camera.set_limits(left, right, top, bottom)


func connect_joystick(left: VirtualJoystick) -> void:
	left.joystick_input.connect(_on_move_input)
	left.joystick_released.connect(_on_move_released)


func connect_aim_joystick(right: VirtualJoystick) -> void:
	right.joystick_input.connect(_on_aim_input)
	right.joystick_released.connect(_on_aim_released)


# Called by the jump button's button_down signal.
func request_jump() -> void:
	if is_on_floor():
		_jump_requested = true


# Toggles between pistol and secondary slot (no-op if no secondary is held).
func request_swap() -> void:
	_weapon_holder.swap_weapon()


# Exposes the holder so pickups can call pick_up_secondary() directly.
func get_weapon_holder() -> WeaponHolder:
	return _weapon_holder


# Called after spawning to configure network role for this player node.
# local_player=true keeps the camera active on this peer.
# On clients, physics is always disabled (host is authoritative for all players).
func setup_network(pid: int, local_player: bool) -> void:
	peer_id = pid
	if not local_player:
		_camera.enabled = false
	if not NetworkManager.is_host:
		set_physics_process(false)
	# Interpolate only remote players on client peers — local player snaps directly
	# to avoid adding perceived lag to the player's own character.
	_needs_interpolation = not NetworkManager.is_host and not local_player


# Captures current local input state and clears the one-shot jump flag.
# Called every frame by InputSync on client machines before sending to host.
func get_input_snapshot() -> Dictionary:
	var snapshot := {
		"move_dir": _move_dir,
		"is_crouching": _is_crouching,
		"jump_requested": _jump_requested,
		"aim_angle": _renderer.aim_angle,
		"facing": _facing,
		"is_firing": _weapon_holder.is_active_weapon_firing(),
		"aim_vec": _raw_aim_dir,
	}
	_jump_requested = false
	return snapshot


# Applied by the host to non-local player nodes before running move_and_slide().
func apply_input_snapshot(input: Dictionary) -> void:
	_move_dir = input.get("move_dir", 0.0)
	_is_crouching = input.get("is_crouching", false)
	if input.get("jump_requested", false):
		_jump_requested = true
	_facing = input.get("facing", _facing)
	_renderer.aim_angle = input.get("aim_angle", 0.0)
	# Forward aim vector to weapons so grenade throw force is accurate on the host.
	var aim_vec: Vector2 = input.get("aim_vec", Vector2.ZERO)
	if aim_vec != Vector2.ZERO:
		_weapon_holder.set_aim_input(aim_vec)
	# Start/stop firing on the host for this remote player.
	if input.get("is_firing", false):
		_weapon_holder.start_firing()
	else:
		_weapon_holder.stop_active_weapon()


# Applied by clients to all player nodes when a state broadcast is received.
func apply_network_state(state: Dictionary) -> void:
	if not _needs_interpolation:
		# Local player or host: apply directly so there is no added visual latency.
		global_position = state.get("position", global_position)
		velocity = state.get("velocity", velocity)
		_move_dir = state.get("move_dir", 0.0)
		_is_crouching = state.get("is_crouching", false)
		_facing = state.get("facing", _facing)
		_renderer.aim_angle = state.get("aim_angle", 0.0)
		_renderer.scale.x = _facing
		_renderer.is_crouching = _is_crouching
		_renderer.queue_redraw()
		return

	# Remote player on a client: push new state into the interpolation buffer.
	# Shift current → previous only once we have an initial state to start from.
	if not _interp_curr.is_empty():
		_interp_prev = _interp_curr
	_interp_curr = state
	_interp_timer = 0.0


# Returns the authoritative state snapshot the host broadcasts to clients.
func get_state_snapshot() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"move_dir": _move_dir,
		"is_crouching": _is_crouching,
		"aim_angle": _renderer.aim_angle,
		"facing": _facing,
	}


# ------------------------------------------------------------------
# Interpolation (client remote players only)
# ------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _needs_interpolation or _interp_curr.is_empty():
		return

	_interp_timer += delta

	if _interp_prev.is_empty():
		# Only one state received so far — apply it directly until a second arrives.
		global_position = _interp_curr.get("position", global_position)
	else:
		var alpha: float = clamp(_interp_timer / INTERP_INTERVAL, 0.0, 1.0)
		global_position = lerp(
			_interp_prev.get("position", global_position) as Vector2,
			_interp_curr.get("position", global_position) as Vector2,
			alpha
		)
		_renderer.aim_angle = lerp_angle(
			_interp_prev.get("aim_angle", 0.0) as float,
			_interp_curr.get("aim_angle", 0.0) as float,
			alpha
		)

	# Discrete states snap to the current value — lerping a boolean makes no sense.
	_facing = _interp_curr.get("facing", _facing)
	_is_crouching = _interp_curr.get("is_crouching", false)
	_renderer.scale.x = _facing
	_renderer.is_crouching = _is_crouching
	_renderer.queue_redraw()


# ------------------------------------------------------------------
# Physics
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Gravity — only accumulate when airborne so landing resets velocity cleanly.
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Consume jump request exactly once per physics frame.
	if _jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
	_jump_requested = false

	# Horizontal movement.
	var speed: float = CROUCH_SPEED if _is_crouching else WALK_SPEED
	velocity.x = _move_dir * speed

	# Movement-based facing only when the aim joystick is idle.
	if not _aim_active:
		if _move_dir > 0.0:
			_facing = 1.0
		elif _move_dir < 0.0:
			_facing = -1.0

	# Sync renderer: flip horizontally for facing, set crouch state.
	_renderer.scale.x = _facing
	_renderer.is_crouching = _is_crouching

	_apply_shape(_is_crouching)
	move_and_slide()


# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

func _on_move_input(dir: Vector2) -> void:
	_move_dir = dir.x
	_is_crouching = dir.y > CROUCH_Y_THRESHOLD


func _on_move_released() -> void:
	_move_dir = 0.0
	_is_crouching = false


func _on_aim_input(dir: Vector2) -> void:
	_aim_active = true
	_raw_aim_dir = dir
	# Facing follows the horizontal aim component.
	if dir.x > 0.0:
		_facing = 1.0
	elif dir.x < 0.0:
		_facing = -1.0
	# Only update aim angle when outside the dead zone so the last valid direction
	# is preserved when the thumb rests near centre.
	if dir.length() > 0.0:
		_renderer.aim_angle = atan2(dir.y, dir.x * _facing)
	_weapon_holder.set_aim_input(dir)
	_weapon_holder.start_firing()


func _on_aim_released() -> void:
	_aim_active = false
	_raw_aim_dir = Vector2.ZERO
	_renderer.aim_angle = 0.0
	_weapon_holder.stop_active_weapon()


# Resize the CapsuleShape2D and reposition it so its bottom stays at local Y=0.
func _apply_shape(crouching: bool) -> void:
	var shape := _col.shape as CapsuleShape2D
	if crouching:
		shape.radius = CROUCH_RADIUS
		shape.height = CROUCH_HEIGHT
		_col.position.y = -(CROUCH_HEIGHT * 0.5)
	else:
		shape.radius = STAND_RADIUS
		shape.height = STAND_HEIGHT
		_col.position.y = -(STAND_HEIGHT * 0.5)


func _on_died(kill_force: Vector2) -> void:
	if _death_triggered:
		return
	_death_triggered = true

	_weapon_holder.stop_active_weapon()
	set_physics_process(false)
	set_process_input(false)

	# Spawn ragdoll at current position before hiding this body.
	var ragdoll: Ragdoll = RAGDOLL_SCENE.instantiate()
	ragdoll.initialize(global_position, player_color, kill_force)
	get_parent().add_child(ragdoll)

	# Hide the CharacterBody2D — ragdoll takes over visually.
	visible = false
	$CollisionShape2D.set_deferred("disabled", true)


# Called by EventRpc handler on all peers to play death visuals (ragdoll + hide).
# The guard in _on_died prevents double-execution when the host's signal also fires.
func trigger_death_visuals(force: Vector2) -> void:
	_on_died(force)


# Brief white-flash hit indicator — called on all peers via on_player_hit RPC.
func show_hit_flash() -> void:
	var tween := create_tween()
	tween.tween_property(_renderer, "modulate", Color(2.5, 2.5, 2.5, 1.0), 0.04)
	tween.tween_property(_renderer, "modulate", Color.WHITE, 0.12)


# Syncs the renderer weapon appearance after a pickup event received by clients.
func set_active_weapon_type(wtype: String) -> void:
	_renderer.active_weapon_type = wtype
	_renderer.queue_redraw()
