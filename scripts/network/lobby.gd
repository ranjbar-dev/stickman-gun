extends Node

# Lobby scene controller — host/join mode switching, color swatches (8 colors),
# round count selector, player list, and full RPC-based lobby state sync.
# RPCs are on this node (/root/Lobby), same path on all peers.

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

@onready var mode_panel: Control = $UI/ModePanel
@onready var host_panel: Control = $UI/HostPanel
@onready var join_panel: Control = $UI/JoinPanel
@onready var back_button: Button = $UI/BackButton

@onready var ip_label: Label = $UI/HostPanel/ConnectionInfo/IPLabel
@onready var host_color_grid: GridContainer = $UI/HostPanel/HostMain/LeftColumn/ColorSection/ColorGrid
@onready var round_spin_box: SpinBox = $UI/HostPanel/HostMain/LeftColumn/RoundSection/RoundSpinBox
@onready var host_player_list: VBoxContainer = $UI/HostPanel/HostMain/RightColumn/PlayersScroll/PlayerListContainer
@onready var host_players_title: Label = $UI/HostPanel/HostMain/RightColumn/PlayersTitle
@onready var start_button: Button = $UI/HostPanel/BottomRow/StartButton
@onready var host_status: Label = $UI/HostPanel/BottomRow/StatusLabel

@onready var ip_input: LineEdit = $UI/JoinPanel/InputRow/IPInput
@onready var connect_button: Button = $UI/JoinPanel/InputRow/ConnectButton
@onready var join_status: Label = $UI/JoinPanel/StatusLabel
@onready var join_color_grid: GridContainer = $UI/JoinPanel/JoinMain/LeftColumn/ColorSection/ColorGrid
@onready var rounds_display: Label = $UI/JoinPanel/JoinMain/LeftColumn/RoundsDisplay
@onready var join_player_list: VBoxContainer = $UI/JoinPanel/JoinMain/RightColumn/PlayersScroll/PlayerListContainer
@onready var join_players_title: Label = $UI/JoinPanel/JoinMain/RightColumn/PlayersTitle


func _ready() -> void:
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.server_full.connect(_on_server_full)
	multiplayer.connected_to_server.connect(_on_connected_to_server)

	$UI/ModePanel/ButtonRow/HostButton.pressed.connect(_on_host_button_pressed)
	$UI/ModePanel/ButtonRow/JoinButton.pressed.connect(_on_join_button_pressed)
	$UI/JoinPanel/InputRow/ConnectButton.pressed.connect(_on_connect_pressed)
	$UI/HostPanel/BottomRow/StartButton.pressed.connect(_on_start_pressed)
	$UI/BackButton.pressed.connect(_on_back_pressed)
	round_spin_box.value_changed.connect(_on_round_count_changed)

	_build_color_swatches(host_color_grid, true)
	_build_color_swatches(join_color_grid, false)

	# If we're returning from a game with an active connection, skip mode-select.
	if NetworkManager.peer != null:
		if NetworkManager.is_host:
			_show_host_panel()
			ip_label.text = NetworkManager.get_connection_string()
			_broadcast_state()
		else:
			_show_join_panel()
			join_status.text = "Returned from game. Waiting for host to start..."
	elif GameManager.pending_lobby_mode == "join":
		GameManager.pending_lobby_mode = ""
		_show_join_panel()
	else:
		_show_mode_select()


# ─────────────────────────── RPCs ────────────────────────────────────────────

# Client → host: request a color change (any peer may send; only host processes).
@rpc("any_peer", "reliable")
func request_color(color_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	_server_handle_color_request(sender_id, color_index)


# Host → all peers (including self via call_local): push full lobby state.
@rpc("authority", "call_local", "reliable")
func sync_lobby_state(state: Dictionary) -> void:
	_apply_lobby_state(state)


# ─────────────────────────── Button Handlers ─────────────────────────────────

func _on_host_button_pressed() -> void:
	var err: Error = NetworkManager.create_server()
	_show_host_panel()
	if err != OK:
		host_status.text = "Failed to start server (error %d)" % err
		return
	ip_label.text = NetworkManager.get_connection_string()
	NetworkManager.round_count = int(round_spin_box.value)
	_broadcast_state()


func _on_join_button_pressed() -> void:
	_show_join_panel()


func _on_connect_pressed() -> void:
	var raw: String = ip_input.text.strip_edges()
	if raw.is_empty():
		join_status.text = "Enter an IP address."
		return

	var ip: String
	var port: int = NetworkManager.PORT

	if ":" in raw:
		var parts: PackedStringArray = raw.split(":", false, 1)
		ip = parts[0]
		if parts.size() > 1:
			port = parts[1].to_int()
	else:
		ip = raw

	join_status.text = "Connecting to %s:%d..." % [ip, port]
	connect_button.disabled = true

	var err: Error = NetworkManager.join_server(ip, port)
	if err != OK:
		join_status.text = "Connection error (code %d)" % err
		connect_button.disabled = false


func _on_start_pressed() -> void:
	if not NetworkManager.is_host:
		return

	# Build deterministic peer list, assign spawn positions spread across the map.
	var peer_ids: Array = NetworkManager.connected_players.keys()
	peer_ids.sort()

	var spawn_positions: Array = []
	var color_indices: Array = []
	var spacing: float = 600.0
	var start_x: float = 400.0

	for i: int in range(peer_ids.size()):
		spawn_positions.append(Vector2(start_x + i * spacing, 755.0))
		var pid: int = peer_ids[i]
		color_indices.append(
			NetworkManager.connected_players[pid].get("color_index", i)
		)

	GameManager.start_round.rpc({
		"peer_ids": peer_ids,
		"spawn_positions": spawn_positions,
		"color_indices": color_indices,
		"max_rounds": NetworkManager.round_count,
	})


func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_network()
	connect_button.disabled = false
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _on_round_count_changed(value: float) -> void:
	if not NetworkManager.is_host:
		return
	NetworkManager.round_count = int(value)
	_broadcast_state()


# ─────────────────────────── NetworkManager Signals ──────────────────────────

func _on_connected_to_server() -> void:
	join_status.text = "Connected! Waiting for host..."
	# Host will broadcast full state to all peers (including us) via sync_lobby_state.


func _on_player_connected(peer_id: int) -> void:
	if NetworkManager.is_host:
		host_status.text = "Player %d joined. (%d connected)" % [
			peer_id, NetworkManager.connected_players.size(),
		]
		_broadcast_state()


func _on_player_disconnected(peer_id: int) -> void:
	if NetworkManager.is_host:
		host_status.text = "Player %d left. (%d connected)" % [
			peer_id, NetworkManager.connected_players.size(),
		]
		_broadcast_state()
	else:
		join_status.text = "Player %d disconnected." % peer_id


func _on_connection_failed() -> void:
	join_status.text = "Connection failed. Check IP and try again."
	connect_button.disabled = false


func _on_server_disconnected() -> void:
	NetworkManager.disconnect_from_network()
	connect_button.disabled = false
	join_status.text = "Host disconnected."


func _on_server_full() -> void:
	connect_button.disabled = false
	join_status.text = "Game is full."


# ─────────────────────────── Host-Side Logic ─────────────────────────────────

func _server_handle_color_request(sender_id: int, color_index: int) -> void:
	if color_index < 0 or color_index >= PLAYER_COLORS.size():
		return
	# Reject if another player already has this color.
	for pid: int in NetworkManager.connected_players:
		if pid == sender_id:
			continue
		if NetworkManager.connected_players[pid].get("color_index", -1) == color_index:
			return
	NetworkManager.connected_players[sender_id]["color_index"] = color_index
	_broadcast_state()


func _broadcast_state() -> void:
	if not NetworkManager.is_host:
		return
	sync_lobby_state.rpc(_build_state_dict())


func _build_state_dict() -> Dictionary:
	var players_data: Dictionary = {}
	for pid: int in NetworkManager.connected_players:
		players_data[pid] = {
			"color_index": NetworkManager.connected_players[pid].get("color_index", -1),
		}
	return {
		"players": players_data,
		"round_count": NetworkManager.round_count,
	}


# ─────────────────────────── Apply Synced State ──────────────────────────────

func _apply_lobby_state(state: Dictionary) -> void:
	var players_data: Dictionary = state.get("players", {})
	var round_count: int = state.get("round_count", 3)

	# Sync NetworkManager.connected_players to authoritative state.
	for pid_var: Variant in players_data.keys():
		var pid: int = int(pid_var)
		if pid not in NetworkManager.connected_players:
			NetworkManager.connected_players[pid] = {}
		NetworkManager.connected_players[pid]["color_index"] = \
			players_data[pid_var].get("color_index", -1)

	# Remove peers absent from the authoritative state.
	var incoming_ids: Array = players_data.keys().map(func(v: Variant) -> int: return int(v))
	var to_remove: Array[int] = []
	for pid: int in NetworkManager.connected_players:
		if pid not in incoming_ids:
			to_remove.append(pid)
	for pid: int in to_remove:
		NetworkManager.connected_players.erase(pid)

	NetworkManager.round_count = round_count

	_refresh_player_list()
	_refresh_color_swatches()
	_update_start_button()

	if is_instance_valid(rounds_display):
		rounds_display.text = "ROUNDS: %d" % round_count

	var count: int = NetworkManager.connected_players.size()
	var title_text: String = "PLAYERS (%d/8)" % count
	if is_instance_valid(host_players_title):
		host_players_title.text = title_text
	if is_instance_valid(join_players_title):
		join_players_title.text = title_text


# ─────────────────────────── Color Swatches ──────────────────────────────────

func _build_color_swatches(grid: GridContainer, _is_host_panel: bool) -> void:
	for i: int in range(PLAYER_COLORS.size()):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 80)
		btn.name = "Swatch%d" % i
		btn.tooltip_text = COLOR_NAMES[i]

		var style_normal := StyleBoxFlat.new()
		style_normal.bg_color = PLAYER_COLORS[i]
		style_normal.corner_radius_top_left = 6
		style_normal.corner_radius_top_right = 6
		style_normal.corner_radius_bottom_left = 6
		style_normal.corner_radius_bottom_right = 6
		btn.add_theme_stylebox_override("normal", style_normal)

		var style_hover := style_normal.duplicate() as StyleBoxFlat
		style_hover.bg_color = PLAYER_COLORS[i].lightened(0.2)
		btn.add_theme_stylebox_override("hover", style_hover)

		var style_pressed := style_normal.duplicate() as StyleBoxFlat
		style_pressed.bg_color = PLAYER_COLORS[i].darkened(0.2)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		var idx := i  # Capture loop variable for the closure.
		btn.pressed.connect(func() -> void: _on_swatch_pressed(idx))
		grid.add_child(btn)


func _on_swatch_pressed(color_index: int) -> void:
	if NetworkManager.is_host:
		_server_handle_color_request(NetworkManager.local_player_id, color_index)
	else:
		request_color.rpc_id(1, color_index)


func _refresh_color_swatches() -> void:
	_refresh_grid_swatches(host_color_grid)
	_refresh_grid_swatches(join_color_grid)


func _refresh_grid_swatches(grid: GridContainer) -> void:
	if not is_instance_valid(grid):
		return

	# Build a map of which color belongs to which peer.
	var taken_by: Dictionary = {}  # color_index (int) -> peer_id (int)
	for pid: int in NetworkManager.connected_players:
		var cidx: int = NetworkManager.connected_players[pid].get("color_index", -1)
		if cidx >= 0:
			taken_by[cidx] = pid

	var my_color: int = NetworkManager.connected_players \
		.get(NetworkManager.local_player_id, {}) \
		.get("color_index", -1)

	for i: int in range(grid.get_child_count()):
		var btn := grid.get_child(i) as Button
		if not btn:
			continue

		var taken_by_other: bool = taken_by.has(i) and taken_by[i] != NetworkManager.local_player_id
		var is_mine: bool = (i == my_color)

		btn.disabled = taken_by_other
		btn.modulate = Color(0.3, 0.3, 0.3, 1.0) if taken_by_other else Color.WHITE

		# White border highlights the locally selected color.
		var style := btn.get_theme_stylebox("normal") as StyleBoxFlat
		if style:
			var border_w: int = 4 if is_mine else 0
			style.border_color = Color.WHITE
			style.border_width_top = border_w
			style.border_width_right = border_w
			style.border_width_bottom = border_w
			style.border_width_left = border_w


# ─────────────────────────── Player List ─────────────────────────────────────

func _refresh_player_list() -> void:
	_clear_container(host_player_list)
	_clear_container(join_player_list)

	for pid: int in NetworkManager.connected_players:
		var color_idx: int = NetworkManager.connected_players[pid].get("color_index", -1)
		var dot_color: Color = PLAYER_COLORS[color_idx] if color_idx >= 0 else Color(0.4, 0.4, 0.4)
		var you_tag: String = " (you)" if pid == NetworkManager.local_player_id else ""
		var host_tag: String = " [Host]" if pid == 1 else ""
		var label_text: String = "Player %d%s%s" % [pid, host_tag, you_tag]

		for container: VBoxContainer in [host_player_list, join_player_list]:
			if not is_instance_valid(container):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)

			var swatch := ColorRect.new()
			swatch.custom_minimum_size = Vector2(28, 28)
			swatch.color = dot_color
			row.add_child(swatch)

			var lbl := Label.new()
			lbl.text = label_text
			lbl.add_theme_font_size_override("font_size", 30)
			if color_idx >= 0:
				lbl.add_theme_color_override("font_color", dot_color.lightened(0.3))
			row.add_child(lbl)

			container.add_child(row)


func _clear_container(container: VBoxContainer) -> void:
	if not is_instance_valid(container):
		return
	for child: Node in container.get_children():
		child.queue_free()


# ─────────────────────────── Start Button ────────────────────────────────────

func _update_start_button() -> void:
	if not is_instance_valid(start_button):
		return
	start_button.disabled = not (
		NetworkManager.is_host and NetworkManager.connected_players.size() >= 2
	)


# ─────────────────────────── Panel Visibility ────────────────────────────────

func _show_mode_select() -> void:
	mode_panel.visible = true
	host_panel.visible = false
	join_panel.visible = false
	back_button.visible = false


func _show_host_panel() -> void:
	mode_panel.visible = false
	host_panel.visible = true
	join_panel.visible = false
	back_button.visible = true


func _show_join_panel() -> void:
	mode_panel.visible = false
	host_panel.visible = false
	join_panel.visible = true
	back_button.visible = true
