extends Node

# NetworkManager — ENet host/client, LAN IP detection, connection state.
# Authoritative host model: host runs game logic, clients send inputs only.

const PORT := 7777
const MAX_CLIENTS := 7  # plus host = 8 total

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_disconnected()
# Emitted on a client when the host explicitly rejected the connection because
# the lobby is full or a game is already in progress.
signal server_full()

var is_host: bool = false
var peer: ENetMultiplayerPeer = null
var local_player_id: int = 0
# {peer_id: {color_index: int, is_ready: bool}}
var connected_players: Dictionary = {}
var local_ip: String = ""
var round_count: int = 3

# Set by notify_server_full RPC so _on_server_disconnected can emit the right signal.
var _server_full_pending: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Public API ---

func create_server() -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_player_id = 1  # host is always peer 1
	local_ip = _detect_local_ip()
	connected_players[1] = {color_index = -1, is_ready = false}
	return OK


func join_server(ip: String, port: int = PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	return OK


func disconnect_from_network() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_host = false
	local_player_id = 0
	connected_players.clear()
	local_ip = ""
	round_count = 3
	_server_full_pending = false


# Returns "IP:PORT" string for display / QR encoding.
# QR payload uses this with a "stickfight://" prefix when gdqrcode addon is available.
func get_connection_string() -> String:
	return "%s:%d" % [local_ip, PORT]


# --- Server-full rejection RPC ---

# Sent by the host to a peer that is being rejected (lobby full or game in progress).
# The peer sets a flag so _on_server_disconnected can emit server_full instead.
@rpc("authority", "reliable")
func notify_server_full() -> void:
	_server_full_pending = true


# --- Signal Handlers ---

func _on_peer_connected(id: int) -> void:
	# Reject the peer if the lobby is already full or a game is in progress.
	if is_host and _should_reject_peer():
		notify_server_full.rpc_id(id)
		call_deferred("_kick_peer", id)
		return
	connected_players[id] = {color_index = -1, is_ready = false}
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	connected_players.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	local_player_id = multiplayer.get_unique_id()
	connected_players[local_player_id] = {color_index = -1, is_ready = false}


func _on_connection_failed() -> void:
	peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	peer = null
	connected_players.clear()
	if _server_full_pending:
		_server_full_pending = false
		server_full.emit()
	else:
		server_disconnected.emit()


# --- Private Helpers ---

func _detect_local_ip() -> String:
	for addr: String in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or _is_172_lan_range(addr):
			# Prefer IPv4; skip loopback and IPv6
			if not ":" in addr and addr != "127.0.0.1":
				return addr
	return "127.0.0.1"


# 172.16.0.0/12 covers 172.16.x.x through 172.31.x.x
func _is_172_lan_range(addr: String) -> bool:
	if not addr.begins_with("172."):
		return false
	var parts: PackedStringArray = addr.split(".")
	if parts.size() < 2:
		return false
	var second: int = parts[1].to_int()
	return second >= 16 and second <= 31


# Returns true when the host should reject a newly connecting peer.
# Rejects if the lobby is at max capacity or if a round/match is active.
func _should_reject_peer() -> bool:
	if connected_players.size() >= 8:
		return true
	var state: int = GameManager.current_state
	return state != GameManager.GameState.MENU and state != GameManager.GameState.LOBBY


# Disconnects a single peer by ID; called deferred so the notify RPC can flush first.
func _kick_peer(id: int) -> void:
	if peer:
		(peer as ENetMultiplayerPeer).disconnect_peer(id)
