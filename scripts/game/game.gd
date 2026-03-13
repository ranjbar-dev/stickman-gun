class_name GameScene
extends Node2D

# Game scene controller — spawns all players from GameManager.pending_round_data,
# wires HUD controls to the local player, and coordinates InputSync / StateSync /
# EventRpc nodes.
# Authoritative host model: host runs physics for all players; clients are display-only.

const PLAYER_SCENE := preload("res://scenes/player/stickman_controller.tscn")
const PICKUP_SCENE := preload("res://scenes/weapons/weapon_pickup.tscn")
const GRENADE_SCENE := preload("res://scenes/projectiles/grenade_projectile.tscn")
const ROUND_END_OVERLAY_SCENE := preload("res://scenes/ui/round_end_overlay.tscn")
const MATCH_END_OVERLAY_SCENE := preload("res://scenes/ui/match_end_overlay.tscn")
const _HIT_PARTICLES_SCENE := preload("res://scenes/effects/hit_particles.tscn")

# Must match lobby.gd PLAYER_COLORS exactly.
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2, 1.0),   # 0 Red
	Color(0.2, 0.4, 0.9, 1.0),   # 1 Blue
	Color(0.2, 0.8, 0.2, 1.0),   # 2 Green
	Color(0.95, 0.9, 0.1, 1.0),  # 3 Yellow
	Color(0.95, 0.5, 0.1, 1.0),  # 4 Orange
	Color(0.6, 0.2, 0.9, 1.0),   # 5 Purple
	Color(0.1, 0.9, 0.9, 1.0),   # 6 Cyan
	Color(0.95, 0.4, 0.7, 1.0),  # 7 Pink
]

const COLOR_NAMES: Array[String] = [
	"Red", "Blue", "Green", "Yellow", "Orange", "Purple", "Cyan", "Pink",
]

@onready var _players_container: Node2D = $PlayersContainer
@onready var _input_sync: InputSync = $InputSync
@onready var _state_sync: StateSync = $StateSync
@onready var _event_rpc: EventRpc = $EventRpc
@onready var _hud: HUD = $HUD
@onready var _left_joystick: VirtualJoystick = $HUD/LeftJoystick
@onready var _right_joystick: VirtualJoystick = $HUD/RightJoystick
@onready var _jump_button: Button = $HUD/JumpButton
@onready var _swap_button: Button = $HUD/SwapButton
@onready var _spectator_ui: Control = $HUD/SpectatorUI
@onready var _spectating_label: Label = $HUD/SpectatorUI/HBoxContainer/SpectatingLabel
@onready var _left_arrow: Button = $HUD/SpectatorUI/HBoxContainer/LeftArrowButton
@onready var _right_arrow: Button = $HUD/SpectatorUI/HBoxContainer/RightArrowButton

# peer_id -> StickmanController
var _players: Dictionary = {}
# peer_id -> most-recently-received input Dictionary (host only)
var _player_inputs: Dictionary = {}
# Number of players still alive (host tracks for round-end detection).
var _alive_count: int = 0
# True once the round-end RPC has been fired to prevent repeat triggers.
var _round_ended: bool = false
# Tracks the headshot flag of the most recent hit per player (host only).
var _last_hit_headshot: Dictionary = {}
# Spawn positions copied from pending_round_data for subsequent rounds.
var _spawn_positions: Array = []

# True once HUD.setup() has been called for the local player this session.
var _hud_configured: bool = false

# Spectator mode state.
var _dead_player_ids: Array[int] = []
var _is_spectating: bool = false
var _spectated_index: int = 0

# Object pools — pre-warmed in _ready() to avoid per-throw/hit allocations.
var _grenade_pool: ProjectilePool = null
var _particles_pool: ProjectilePool = null


func _ready() -> void:
	_input_sync._game = self
	_state_sync._game = self
	_event_rpc._game = self

	_left_arrow.pressed.connect(func() -> void: _cycle_spectator(-1))
	_right_arrow.pressed.connect(func() -> void: _cycle_spectator(1))

	if NetworkManager.is_host:
		NetworkManager.player_disconnected.connect(_on_peer_disconnected_in_game)
	else:
		NetworkManager.server_disconnected.connect(_on_server_disconnected_in_game)

	_init_pools()
	_spawn_players()
	_start_round_sequence()


func _init_pools() -> void:
	_grenade_pool = ProjectilePool.new()
	add_child(_grenade_pool)
	_grenade_pool.initialize(GRENADE_SCENE, 6, self)

	_particles_pool = ProjectilePool.new()
	add_child(_particles_pool)
	_particles_pool.initialize(_HIT_PARTICLES_SCENE, 8, self)


# ------------------------------------------------------------------
# Spawning
# ------------------------------------------------------------------

func _spawn_players() -> void:
	var data: Dictionary = GameManager.pending_round_data
	var peer_ids: Array = data.get("peer_ids", [])
	var spawn_positions: Array = data.get("spawn_positions", [])
	var color_indices: Array = data.get("color_indices", [])

	_spawn_positions = spawn_positions.duplicate()
	_alive_count = peer_ids.size()

	for i: int in range(peer_ids.size()):
		var pid: int = peer_ids[i]
		var player: StickmanController = PLAYER_SCENE.instantiate()
		_players_container.add_child(player)

		var color_idx: int = color_indices[i] if i < color_indices.size() else 0
		player.player_color = PLAYER_COLORS[clampi(color_idx, 0, PLAYER_COLORS.size() - 1)]

		var spawn_pos: Vector2 = spawn_positions[i] \
			if i < spawn_positions.size() \
			else Vector2(400.0 + i * 600.0, 755.0)
		player.global_position = spawn_pos

		var is_local: bool = (pid == NetworkManager.local_player_id)
		player.setup_network(pid, is_local)
		if is_local:
			player.set_camera_limits(0.0, 4800.0, -300.0, 900.0)
		_players[pid] = player

		# Freeze players until countdown completes.
		player.process_mode = Node.PROCESS_MODE_DISABLED

		# Supply grenade pool so GrenadeWeapon avoids allocation on each throw.
		var wh: WeaponHolder = player.get_node_or_null("WeaponHolder") as WeaponHolder
		if wh != null:
			wh.set_grenade_pool(_grenade_pool)

		# Host connects to HitboxManager signals to detect hits/deaths and fire RPCs.
		if NetworkManager.is_host:
			var hbm: HitboxManager = player.get_node("HitboxManager") as HitboxManager
			hbm.hit.connect(func(hp: Vector2, dmg: int, hs: bool) -> void:
				_on_player_hit_server(pid, hp, dmg, hs)
			)
			hbm.died.connect(func(force: Vector2, killer_id: int) -> void:
				_on_player_died_server(pid, force, killer_id)
			)

	# Connect any WeaponPickup nodes already present in the scene.
	if NetworkManager.is_host:
		_connect_existing_pickups()


# ------------------------------------------------------------------
# Round start sequence — runs on every peer at the start of each round.
# Players are frozen; countdown runs; then players are unfrozen and
# weapon pickups spawn (on host) after a 2 s delay.
# ------------------------------------------------------------------

func _start_round_sequence() -> void:
	GameManager.current_state = GameManager.GameState.ROUND_START

	# Countdown overlay (programmatic — light enough not to need a separate scene).
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.50)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 180)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(lbl)

	for count: int in [3, 2, 1]:
		lbl.text = str(count)
		AudioManager.play_sfx("countdown_beep", Vector2.ZERO, false)
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return

	lbl.text = "FIGHT!"
	lbl.add_theme_font_size_override("font_size", 140)
	AudioManager.play_sfx("round_start", Vector2.ZERO, false)
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(self):
		return

	layer.queue_free()

	# Unfreeze players and wire local controls now that the round is live.
	GameManager.current_state = GameManager.GameState.ROUND_ACTIVE
	for player: StickmanController in _players.values():
		if is_instance_valid(player):
			player.process_mode = Node.PROCESS_MODE_INHERIT
	_connect_local_controls()

	# Weapon pickups appear 2 s after FIGHT (host spawns; clients learn via EventRpc).
	if NetworkManager.is_host:
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(self):
			_spawn_initial_pickups()


# Spawns weapon pickups at fixed map locations. Only called on the host;
# clients receive pickup/drop events via EventRpc.
func _spawn_initial_pickups() -> void:
	var pickup_data: Array[Dictionary] = [
		{"type": "sniper",  "pos": Vector2(900.0,  575.0)},
		{"type": "shotgun", "pos": Vector2(2400.0, 455.0)},
		{"type": "grenade", "pos": Vector2(3800.0, 575.0)},
	]
	for data: Dictionary in pickup_data:
		var pickup: WeaponPickup = PICKUP_SCENE.instantiate() as WeaponPickup
		pickup.weapon_type = data["type"]
		pickup.global_position = data["pos"]
		pickup.add_to_group("weapon_pickups")
		add_child(pickup)
		_connect_pickup(pickup)


func _connect_local_controls() -> void:
	var local: StickmanController = get_local_player()
	if not is_instance_valid(local):
		return
	if not _left_joystick.joystick_input.is_connected(local._on_move_input):
		local.connect_joystick(_left_joystick)
	if not _right_joystick.joystick_input.is_connected(local._on_aim_input):
		local.connect_aim_joystick(_right_joystick)
	if not _jump_button.button_down.is_connected(local.request_jump):
		_jump_button.button_down.connect(local.request_jump)
	if not _swap_button.button_down.is_connected(local.request_swap):
		_swap_button.button_down.connect(local.request_swap)
	_setup_hud_if_needed(local)


func _setup_hud_if_needed(local: StickmanController) -> void:
	if _hud_configured:
		return
	_hud_configured = true
	_hud.setup(local)


func _disconnect_local_controls() -> void:
	var local: StickmanController = get_local_player()
	if not is_instance_valid(local):
		return
	if _left_joystick.joystick_input.is_connected(local._on_move_input):
		_left_joystick.joystick_input.disconnect(local._on_move_input)
	if _left_joystick.joystick_released.is_connected(local._on_move_released):
		_left_joystick.joystick_released.disconnect(local._on_move_released)
	if _right_joystick.joystick_input.is_connected(local._on_aim_input):
		_right_joystick.joystick_input.disconnect(local._on_aim_input)
	if _right_joystick.joystick_released.is_connected(local._on_aim_released):
		_right_joystick.joystick_released.disconnect(local._on_aim_released)
	if _jump_button.button_down.is_connected(local.request_jump):
		_jump_button.button_down.disconnect(local.request_jump)
	if _swap_button.button_down.is_connected(local.request_swap):
		_swap_button.button_down.disconnect(local.request_swap)


# ------------------------------------------------------------------
# Spectator mode
# ------------------------------------------------------------------

func _get_alive_spectator_targets() -> Array:
	var targets: Array = []
	for pid: int in _players:
		if pid == NetworkManager.local_player_id:
			continue
		if pid in _dead_player_ids:
			continue
		var p: StickmanController = _players[pid]
		if is_instance_valid(p):
			targets.append(p)
	return targets


func _get_color_name_for_player(pid: int) -> String:
	var peer_ids: Array = GameManager.pending_round_data.get("peer_ids", [])
	var color_indices: Array = GameManager.pending_round_data.get("color_indices", [])
	var idx: int = peer_ids.find(pid)
	if idx == -1:
		return "?"
	var color_idx: int = color_indices[idx] if idx < color_indices.size() else 0
	return COLOR_NAMES[clampi(color_idx, 0, COLOR_NAMES.size() - 1)]


func _apply_spectator_camera(targets: Array) -> void:
	if targets.is_empty():
		return
	_spectated_index = clampi(_spectated_index, 0, targets.size() - 1)
	var target: StickmanController = targets[_spectated_index]
	var local: StickmanController = get_local_player()
	if is_instance_valid(local):
		local.get_camera().start_spectating(target)
	var pid: int = target.peer_id
	_spectating_label.text = "Spectating: " + _get_color_name_for_player(pid)


func _enter_spectator_mode() -> void:
	if _is_spectating:
		return
	_is_spectating = true
	_disconnect_local_controls()
	_left_joystick.visible = false
	_right_joystick.visible = false
	_jump_button.visible = false
	_swap_button.visible = false

	var targets: Array = _get_alive_spectator_targets()
	_spectated_index = 0
	_spectator_ui.visible = true
	if targets.is_empty():
		_spectating_label.text = "Spectating: (waiting)"
		_left_arrow.visible = false
		_right_arrow.visible = false
	else:
		_left_arrow.visible = true
		_right_arrow.visible = true
		_apply_spectator_camera(targets)


func _cycle_spectator(dir: int) -> void:
	if not _is_spectating:
		return
	var targets: Array = _get_alive_spectator_targets()
	if targets.is_empty():
		return
	_spectated_index = (_spectated_index + dir + targets.size()) % targets.size()
	_apply_spectator_camera(targets)


func _exit_spectator_mode() -> void:
	if not _is_spectating:
		return
	_is_spectating = false
	_dead_player_ids.clear()
	_spectated_index = 0

	var local: StickmanController = get_local_player()
	if is_instance_valid(local):
		local.get_camera().stop_spectating()

	_spectator_ui.visible = false
	_left_joystick.visible = true
	_right_joystick.visible = true
	_jump_button.visible = true
	_swap_button.visible = true


# Connect weapon_taken signal for all WeaponPickup nodes currently in the tree.
func _connect_existing_pickups() -> void:
	for node in get_tree().get_nodes_in_group("weapon_pickups"):
		_connect_pickup(node)


func _connect_pickup(pickup: WeaponPickup) -> void:
	if not pickup.weapon_taken.is_connected(_on_weapon_taken_server):
		pickup.weapon_taken.connect(_on_weapon_taken_server)


# ------------------------------------------------------------------
# Physics (host only) — apply received inputs to non-local players
# ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_host:
		return
	for pid: int in _players:
		if pid == NetworkManager.local_player_id:
			continue
		var input: Dictionary = _player_inputs.get(pid, {})
		if not input.is_empty():
			_players[pid].apply_input_snapshot(input)


# ------------------------------------------------------------------
# Public API — used by InputSync and StateSync nodes
# ------------------------------------------------------------------

func get_local_player() -> StickmanController:
	return _players.get(NetworkManager.local_player_id)


func set_player_input(pid: int, input: Dictionary) -> void:
	_player_inputs[pid] = input


func get_all_player_states() -> Dictionary:
	var states: Dictionary = {}
	for pid: int in _players:
		states[pid] = _players[pid].get_state_snapshot()
	return states


func apply_all_player_states(states: Dictionary) -> void:
	for pid_var: Variant in states:
		var pid: int = int(pid_var)
		if _players.has(pid):
			_players[pid].apply_network_state(states[pid_var])


# ------------------------------------------------------------------
# Server-side event detection — host only, fires EventRpc calls
# ------------------------------------------------------------------

func _on_player_hit_server(player_id: int, hit_pos: Vector2, damage: int, is_headshot: bool) -> void:
	_last_hit_headshot[player_id] = is_headshot
	_event_rpc.on_player_hit.rpc(player_id, damage, hit_pos, is_headshot)


func _on_player_died_server(player_id: int, force: Vector2, killer_id: int) -> void:
	_event_rpc.on_player_killed.rpc(player_id, killer_id, force)

	# Update kill stats for the killer.
	if killer_id != 0 and killer_id != player_id:
		var ks: Dictionary = GameManager.kill_stats.get(killer_id, {"kills": 0, "headshots": 0})
		ks["kills"] += 1
		if _last_hit_headshot.get(player_id, false):
			ks["headshots"] += 1
		GameManager.kill_stats[killer_id] = ks

	if _round_ended:
		return
	_alive_count -= 1
	if _alive_count <= 1:
		_round_ended = true
		var winner_id: int = _find_alive_winner()
		# Update match scores.
		if winner_id != 0:
			GameManager.match_scores[winner_id] = GameManager.match_scores.get(winner_id, 0) + 1
		_event_rpc.on_round_end.rpc(winner_id, GameManager.match_scores.duplicate())


func _on_weapon_taken_server(
		player_id: int, weapon_type: String, pickup_pos: Vector2,
		dropped_type: String, dropped_ammo: int) -> void:
	_event_rpc.on_weapon_picked_up.rpc(player_id, weapon_type, pickup_pos)

	if not dropped_type.is_empty():
		# Spawn a pickup for the displaced weapon on the host, then broadcast.
		var new_pickup: WeaponPickup = PICKUP_SCENE.instantiate() as WeaponPickup
		new_pickup.weapon_type = dropped_type
		new_pickup.ammo_count = dropped_ammo
		new_pickup.global_position = pickup_pos
		new_pickup.add_to_group("weapon_pickups")
		add_child(new_pickup)
		_connect_pickup(new_pickup)

		_event_rpc.on_weapon_dropped.rpc(player_id, dropped_type, pickup_pos, dropped_ammo)


# Returns the peer_id of the sole surviving player, or 0 if none / tied.
func _find_alive_winner() -> int:
	for pid: int in _players:
		var player: StickmanController = _players[pid]
		if is_instance_valid(player) and player.visible:
			return pid
	return 0


# ------------------------------------------------------------------
# EventRpc handlers — called on all peers (including host via call_local)
# ------------------------------------------------------------------

func handle_player_hit(player_id: int, _damage: int, _hit_pos: Vector2, _is_headshot: bool) -> void:
	var player: StickmanController = _players.get(player_id)
	if not is_instance_valid(player):
		return
	player.show_hit_flash()
	var sfx: String = "headshot" if _is_headshot else "hit_marker"
	AudioManager.play_sfx(sfx, _hit_pos)
	# Spawn hit particles from pool at the impact point.
	var particles: HitParticles = _particles_pool.acquire() as HitParticles
	if particles != null:
		particles._pool = _particles_pool
		particles.reset(_hit_pos)


func handle_player_killed(player_id: int, _killer_id: int, force: Vector2) -> void:
	var player: StickmanController = _players.get(player_id)
	if not is_instance_valid(player):
		return
	var death_pos: Vector2 = player.global_position
	AudioManager.play_sfx("death", death_pos)
	player.trigger_death_visuals(force)

	# Screen shake on the killer's client only.
	if _killer_id == NetworkManager.local_player_id:
		var local: StickmanController = get_local_player()
		if is_instance_valid(local):
			local.get_camera().shake()

	_dead_player_ids.append(player_id)
	var local_id: int = NetworkManager.local_player_id
	if player_id == local_id:
		_enter_spectator_mode()
	elif _is_spectating:
		# If the currently spectated player just died, cycle to the next alive one.
		var targets: Array = _get_alive_spectator_targets()
		if targets.is_empty():
			return
		_spectated_index = clamp(_spectated_index, 0, targets.size() - 1)
		_apply_spectator_camera(targets)


func handle_weapon_picked_up(player_id: int, weapon_type: String, _pickup_pos: Vector2) -> void:
	var player: StickmanController = _players.get(player_id)
	if not is_instance_valid(player):
		return
	player.set_active_weapon_type(weapon_type)
	AudioManager.play_sfx("weapon_pickup", _pickup_pos)


func handle_weapon_dropped(player_id: int, old_type: String, drop_pos: Vector2, ammo: int) -> void:
	# On host the pickup was already spawned in _on_weapon_taken_server.
	if NetworkManager.is_host:
		return
	# Clients spawn a cosmetic-only pickup (monitoring disabled so it can't be triggered).
	var pickup: WeaponPickup = PICKUP_SCENE.instantiate() as WeaponPickup
	pickup.weapon_type = old_type
	pickup.ammo_count = ammo
	pickup.global_position = drop_pos
	add_child(pickup)
	# Disable physics — cosmetic only on clients.
	pickup.set_deferred("monitoring", false)
	pickup.set_deferred("monitorable", false)


# Clients spawn a cosmetic grenade with the same physics as the host's authoritative one.
# Damage is already guarded in GrenadeProjectile._explode() so no double-hits occur.
func handle_grenade_thrown(thrower_id: int, pos: Vector2, vel: Vector2) -> void:
	var grenade: GrenadeProjectile = _grenade_pool.acquire() as GrenadeProjectile
	if grenade == null:
		return
	grenade._pool = _grenade_pool
	grenade.reset(pos, vel, thrower_id)


func handle_round_end(winner_id: int, scores: Dictionary) -> void:
	_exit_spectator_mode()
	GameManager.current_state = GameManager.GameState.ROUND_END
	AudioManager.play_sfx("victory", Vector2.ZERO, false)

	# Show round-end overlay for 5 seconds.
	var overlay: RoundEndOverlay = ROUND_END_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	overlay.setup(winner_id, scores, GameManager.round_number,
		GameManager.pending_round_data)

	await get_tree().create_timer(5.0).timeout
	if not is_instance_valid(self):
		return
	if is_instance_valid(overlay):
		overlay.queue_free()

	GameManager.round_number += 1

	if NetworkManager.is_host:
		if GameManager.round_number > GameManager.max_rounds:
			_event_rpc.on_match_end.rpc(
				GameManager.match_scores.duplicate(),
				GameManager.kill_stats.duplicate()
			)
		else:
			_rpc_begin_next_round.rpc()


func handle_match_end(final_scores: Dictionary, p_kill_stats: Dictionary) -> void:
	GameManager.current_state = GameManager.GameState.MATCH_END
	var overlay: MatchEndOverlay = MATCH_END_OVERLAY_SCENE.instantiate()
	add_child(overlay)
	overlay.setup(final_scores, p_kill_stats, GameManager.pending_round_data)


# Host broadcasts this to all peers to start the next round within the same match.
@rpc("authority", "call_local", "reliable")
func _rpc_begin_next_round() -> void:
	_exit_spectator_mode()

	# Remove all weapon pickups.
	for pickup in get_tree().get_nodes_in_group("weapon_pickups"):
		pickup.queue_free()

	# Reset every player: revive them, restore to spawn, re-freeze for countdown.
	var peer_ids: Array = GameManager.pending_round_data.get("peer_ids", [])
	var spawn_positions: Array = GameManager.pending_round_data.get("spawn_positions", [])
	for i: int in range(peer_ids.size()):
		var pid: int = peer_ids[i]
		var player: StickmanController = _players.get(pid)
		if not is_instance_valid(player):
			continue
		var spawn_pos: Vector2 = spawn_positions[i] \
			if i < spawn_positions.size() else Vector2(400.0 + i * 600.0, 755.0)
		player.revive(spawn_pos)
		player.process_mode = Node.PROCESS_MODE_DISABLED

		# Reset health.
		var hbm: HitboxManager = player.get_node_or_null("HitboxManager") as HitboxManager
		if hbm:
			hbm.reset()

		# Strip secondary weapon so each round starts with pistol only.
		var wh: WeaponHolder = player.get_node_or_null("WeaponHolder") as WeaponHolder
		if wh:
			wh.clear_secondary()
		# Update renderer on remote clients so the weapon line resets to pistol.
		player.set_active_weapon_type("pistol")

	# Disconnect HUD controls (they will be re-wired at FIGHT in _start_round_sequence).
	_disconnect_local_controls()

	_round_ended = false
	_alive_count = peer_ids.size()
	_last_hit_headshot.clear()

	_start_round_sequence()


# ------------------------------------------------------------------
# Disconnection handlers
# ------------------------------------------------------------------

# Host only — fires when a remote peer drops.  If they were still alive, force-kill
# their stickman so ragdolls appear on all clients and round-end logic fires normally.
func _on_peer_disconnected_in_game(peer_id: int) -> void:
	_player_inputs.erase(peer_id)

	var player: StickmanController = _players.get(peer_id)
	if not is_instance_valid(player):
		return

	var hbm: HitboxManager = player.get_node("HitboxManager") as HitboxManager
	if hbm and hbm.is_alive():
		hbm.force_kill()


# Client only — fires when the host drops.  Show a brief overlay then return to lobby.
func _on_server_disconnected_in_game() -> void:
	NetworkManager.disconnect_from_network()

	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0.0, 0.0, 0.0, 0.80)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)

	var label := Label.new()
	label.text = "Host disconnected.\nReturning to lobby..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 52)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)

	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


# ------------------------------------------------------------------
# (Old programmatic overlay helpers removed — replaced by RoundEndOverlay
#  and MatchEndOverlay scene classes in scripts/ui/.)
# ------------------------------------------------------------------
