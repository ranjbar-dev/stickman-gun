extends Node2D

const WEAPON_PICKUP_SCENE := preload("res://scenes/weapons/weapon_pickup.tscn")

# Ten seeds exercising different terrain shapes and edge cases.
const TEST_SEEDS: Array[int] = [
	12345,      # original set
	98765,
	42424,
	77777,
	55555,
	1,          # minimal seed
	999999,     # large round value
	314159,     # pi-ish
	2147483647, # INT32_MAX
	100000,     # round power-of-ten
]

@onready var _terrain: TerrainGenerator = $TerrainGenerator
@onready var _weapon_pickups: Node2D = $WeaponPickups
@onready var _player: StickmanController = $Player
@onready var _left_joystick: VirtualJoystick = $HUD/LeftJoystick
@onready var _right_joystick: VirtualJoystick = $HUD/RightJoystick
@onready var _jump_button: Button = $HUD/JumpButton
@onready var _swap_button: Button = $HUD/SwapButton
@onready var _seed_label: Label = $HUD/SeedLabel
@onready var _next_button: Button = $HUD/NextSeedButton

var _current_seed_idx: int = 0
# Cached for _draw() — set after each terrain generation.
var _debug_spawns: Array[Vector2] = []
var _debug_weapon_spawns: Array[Vector2] = []

var _validator: TerrainValidator = TerrainValidator.new()


func _ready() -> void:
	_player.connect_joystick(_left_joystick)
	_player.connect_aim_joystick(_right_joystick)
	_jump_button.button_down.connect(_player.request_jump)
	_swap_button.button_down.connect(_player.request_swap)
	_next_button.pressed.connect(_on_next_seed)
	_apply_seed(0)


func _draw() -> void:
	# Cyan + markers at each player spawn point.
	for sp in _debug_spawns:
		var arm: float = 12.0
		draw_line(sp + Vector2(-arm, 0), sp + Vector2(arm, 0), Color.CYAN, 2.0)
		draw_line(sp + Vector2(0, -arm), sp + Vector2(0, arm), Color.CYAN, 2.0)

	# Yellow diamond markers at each weapon spawn point.
	for wp in _debug_weapon_spawns:
		var r: float = 8.0
		var pts := PackedVector2Array([
			wp + Vector2(0, -r), wp + Vector2(r, 0),
			wp + Vector2(0, r),  wp + Vector2(-r, 0),
			wp + Vector2(0, -r)
		])
		draw_polyline(pts, Color.YELLOW, 2.0)


func _on_next_seed() -> void:
	_current_seed_idx = (_current_seed_idx + 1) % TEST_SEEDS.size()
	_apply_seed(_current_seed_idx)


func _apply_seed(idx: int) -> void:
	var seed_value: int = TEST_SEEDS[idx]
	_seed_label.text = "SEED: %d  [%d/%d]" % [seed_value, idx + 1, TEST_SEEDS.size()]

	# Run full DoD validation (generates terrain internally, including determinism re-check).
	_validator.run(_terrain, seed_value)

	# Validator leaves the terrain in its last generated state (same seed).
	# Regenerate once more so the scene tree is consistent after the validator's cleanup.
	_terrain.generate(seed_value)

	# Place player at first spawn point.
	if not _terrain.spawn_points.is_empty():
		_player.global_position = _terrain.spawn_points[0]
	else:
		_player.global_position = Vector2(300.0, 900.0)

	# Constrain camera to the full map width.
	_player.set_camera_limits(0.0, TerrainGenerator.MAP_WIDTH, -300.0, 1050.0)

	# Rebuild weapon pickups.
	for child in _weapon_pickups.get_children():
		child.queue_free()

	for ws in _terrain.weapon_spawns:
		var pickup := WEAPON_PICKUP_SCENE.instantiate() as WeaponPickup
		pickup.weapon_type = ws.weapon_type
		pickup.position = ws.position
		_weapon_pickups.add_child(pickup)

	# Update debug overlay.
	_debug_spawns = _terrain.spawn_points.duplicate()
	_debug_weapon_spawns = []
	for ws in _terrain.weapon_spawns:
		_debug_weapon_spawns.append(ws.position)
	queue_redraw()
