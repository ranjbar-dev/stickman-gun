class_name GameScene
extends Node2D

# Game scene controller — spawns all players from GameManager.pending_round_data,
# wires HUD controls to the local player, and coordinates InputSync / StateSync /
# EventRpc nodes.
# Authoritative host model: host runs physics for all players; clients are display-only.

const PLAYER_SCENE := preload("res://scenes/player/stickman_controller.tscn")
const PICKUP_SCENE := preload("res://scenes/weapons/weapon_pickup.tscn")
const GRENADE_SCENE := preload("res://scenes/projectiles/grenade_projectile.tscn")

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

@onready var _players_container: Node2D = $PlayersContainer
@onready var _input_sync: InputSync = $InputSync
@onready var _state_sync: StateSync = $StateSync
@onready var _event_rpc: EventRpc = $EventRpc
@onready var _left_joystick: VirtualJoystick = $HUD/LeftJoystick
@onready var _right_joystick: VirtualJoystick = $HUD/RightJoystick
@onready var _jump_button: Button = $HUD/JumpButton
@onready var _swap_button: Button = $HUD/SwapButton

# peer_id -> StickmanController
var _players: Dictionary = {}
# peer_id -> most-recently-received input Dictionary (host only)
var _player_inputs: Dictionary = {}
# Number of players still alive (host tracks for round-end detection).
var _alive_count: int = 0
# True once the round-end RPC has been fired to prevent repeat triggers.
var _round_ended: bool = false


func _ready() -> void:
	_input_sync._game = self
	_state_sync._game = self
	_event_rpc._game = self
	_spawn_players()

	if NetworkManager.is_host:
		_spawn_initial_pickups()
		NetworkManager.player_disconnected.connect(_on_peer_disconnected_in_game)
	else:
		NetworkManager.server_disconnected.connect(_on_server_disconnected_in_game)


# ------------------------------------------------------------------
# Spawning
# ------------------------------------------------------------------

func _spawn_players() -> void:
	var data: Dictionary = GameManager.pending_round_data
	var peer_ids: Array = data.get("peer_ids", [])
	var spawn_positions: Array = data.get("spawn_positions", [])
	var color_indices: Array = data.get("color_indices", [])

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
		_players[pid] = player

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

	_connect_local_controls()


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
	local.connect_joystick(_left_joystick)
	local.connect_aim_joystick(_right_joystick)
	_jump_button.button_down.connect(local.request_jump)
	_swap_button.button_down.connect(local.request_swap)


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
	_event_rpc.on_player_hit.rpc(player_id, damage, hit_pos, is_headshot)


func _on_player_died_server(player_id: int, force: Vector2, killer_id: int) -> void:
	_event_rpc.on_player_killed.rpc(player_id, killer_id, force)

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
	AudioManager.play_sfx("hit")


func handle_player_killed(player_id: int, _killer_id: int, force: Vector2) -> void:
	var player: StickmanController = _players.get(player_id)
	if not is_instance_valid(player):
		return
	player.trigger_death_visuals(force)


func handle_weapon_picked_up(player_id: int, weapon_type: String, _pickup_pos: Vector2) -> void:
	var player: StickmanController = _players.get(player_id)
	if not is_instance_valid(player):
		return
	player.set_active_weapon_type(weapon_type)


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
	var grenade: GrenadeProjectile = GRENADE_SCENE.instantiate() as GrenadeProjectile
	grenade.global_position = pos
	grenade.thrower_id = thrower_id
	add_child(grenade)
	grenade.linear_velocity = vel


func handle_round_end(winner_id: int, scores: Dictionary) -> void:
	_show_round_end_overlay(winner_id, scores)
	# After a brief pause all peers return to lobby so the host can start a new round.
	# Full multi-round match progression is a future phase.
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(self):
		_return_to_lobby()


func handle_match_end(final_scores: Dictionary) -> void:
	_show_match_end_overlay(final_scores)
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(self):
		_return_to_lobby()


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
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")


# ------------------------------------------------------------------
# Overlay helpers — simple programmatic UI
# ------------------------------------------------------------------

func _show_round_end_overlay(winner_id: int, scores: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0.0, 0.0, 0.0, 0.65)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)

	var label := Label.new()
	if winner_id != 0:
		label.text = "Player %d wins the round!" % winner_id
	else:
		label.text = "Draw!"

	var score_lines: Array[String] = []
	for pid in scores:
		score_lines.append("P%d: %d win(s)" % [pid, scores[pid]])
	if not score_lines.is_empty():
		label.text += "\n" + "\n".join(score_lines)
	label.text += "\n\nReturning to lobby in 4s..."

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)


func _show_match_end_overlay(final_scores: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var panel := ColorRect.new()
	panel.color = Color(0.0, 0.0, 0.0, 0.75)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)

	var label := Label.new()
	label.text = "Match Over!\n"
	var sorted: Array = final_scores.keys()
	sorted.sort_custom(func(a: Variant, b: Variant) -> bool:
		return final_scores[a] > final_scores[b]
	)
	for pid in sorted:
		label.text += "P%d: %d win(s)\n" % [pid, final_scores[pid]]

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)


func _return_to_lobby() -> void:
	GameManager.current_state = GameManager.GameState.LOBBY
	GameManager.match_scores.clear()
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")
