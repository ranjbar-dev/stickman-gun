class_name StickmanController
extends CharacterBody2D

# Movement tuning — all values from STICKFIGHT_GAME_DESIGN.md Section 4.
const WALK_SPEED: float = 200.0
const CROUCH_SPEED: float = 100.0
const JUMP_VELOCITY: float = -400.0
const GRAVITY: float = 980.0

# Left-joystick Y threshold to enter crouch (0–1 normalised; positive = down).
const CROUCH_Y_THRESHOLD: float = 0.6

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
@onready var _weapon: HitscanWeapon = $HitscanWeapon
@onready var _camera: Camera2D = $Camera2D

var _move_dir: float = 0.0
var _is_crouching: bool = false
var _jump_requested: bool = false
# 1.0 = facing right, -1.0 = facing left.
var _facing: float = 1.0
# True while the aim joystick is held; suppresses movement-based facing updates.
var _aim_active: bool = false


func _ready() -> void:
	_renderer.player_color = player_color
	_apply_shape(false)
	_weapon.set_renderer(_renderer)


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
	# Facing follows the horizontal aim component.
	if dir.x > 0.0:
		_facing = 1.0
	elif dir.x < 0.0:
		_facing = -1.0
	# Only update aim angle when outside the dead zone so the last valid direction
	# is preserved when the thumb rests near centre.
	if dir.length() > 0.0:
		_renderer.aim_angle = atan2(dir.y, dir.x * _facing)
	_weapon.start_firing()


func _on_aim_released() -> void:
	_aim_active = false
	_renderer.aim_angle = 0.0
	_weapon.stop_firing()


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
