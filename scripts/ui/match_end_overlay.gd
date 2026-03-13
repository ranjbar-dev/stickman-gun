class_name MatchEndOverlay
extends CanvasLayer

# Match end screen — shown after all rounds are completed.
# Displays: overall winner, per-player stats (rounds won, kills, headshots).
# REMATCH returns everyone to lobby (host only). QUIT disconnects and goes to main menu.

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2, 1.0),
	Color(0.2, 0.4, 0.9, 1.0),
	Color(0.2, 0.8, 0.2, 1.0),
	Color(0.95, 0.9, 0.1, 1.0),
	Color(0.95, 0.5, 0.1, 1.0),
	Color(0.6, 0.2, 0.9, 1.0),
	Color(0.1, 0.9, 0.9, 1.0),
	Color(0.95, 0.4, 0.7, 1.0),
]
const COLOR_NAMES: Array[String] = [
	"Red", "Blue", "Green", "Yellow", "Orange", "Purple", "Cyan", "Pink",
]

@onready var _winner_label: Label = $Background/VBox/WinnerLabel
@onready var _stats_grid: GridContainer = $Background/VBox/StatsGrid
@onready var _rematch_button: Button = $Background/VBox/Buttons/RematchButton
@onready var _quit_button: Button = $Background/VBox/Buttons/QuitButton


func _ready() -> void:
	layer = 20
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


# Called by game.gd immediately after instantiation.
func setup(final_scores: Dictionary, p_kill_stats: Dictionary, round_data: Dictionary) -> void:
	# Determine overall winner
	var best_wins: int = -1
	var best_pid: int = -1
	var tie: bool = false
	for pid_var: Variant in final_scores:
		var pid: int = int(pid_var)
		var wins: int = final_scores[pid_var]
		if wins > best_wins:
			best_wins = wins
			best_pid = pid
			tie = false
		elif wins == best_wins:
			tie = true

	if tie or best_pid == -1:
		_winner_label.text = "Draw!"
		_winner_label.remove_theme_color_override("font_color")
	else:
		var name := _color_name_for_peer(best_pid, round_data)
		_winner_label.text = "%s Wins the Match!" % name
		_winner_label.add_theme_color_override("font_color",
			_color_for_peer(best_pid, round_data))

	# Build stats table header
	_add_header_row()

	# Stats rows — sorted by round wins descending
	var peer_ids: Array = round_data.get("peer_ids", []).duplicate()
	peer_ids.sort_custom(func(a: Variant, b: Variant) -> bool:
		return final_scores.get(a, 0) > final_scores.get(b, 0)
	)
	for pid_var: Variant in peer_ids:
		var pid: int = int(pid_var)
		var ks: Dictionary = p_kill_stats.get(pid, {})
		_add_stat_row(pid, final_scores.get(pid, 0), ks.get("kills", 0),
			ks.get("headshots", 0), round_data)

	# REMATCH only usable by host
	_rematch_button.disabled = not NetworkManager.is_host
	if not NetworkManager.is_host:
		_rematch_button.text = "Waiting for host..."


func _add_header_row() -> void:
	for header: String in ["Player", "Rounds Won", "Kills", "Headshots"]:
		var lbl := Label.new()
		lbl.text = header
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
		_stats_grid.add_child(lbl)


func _add_stat_row(pid: int, wins: int, kills: int, headshots: int,
		round_data: Dictionary) -> void:
	var color := _color_for_peer(pid, round_data)
	var color_name := _color_name_for_peer(pid, round_data)

	# Player (colored dot + name)
	var player_row := HBoxContainer.new()
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(24, 24)
	dot.color = color
	var name_lbl := Label.new()
	name_lbl.text = "  " + color_name
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", color)
	player_row.add_child(dot)
	player_row.add_child(name_lbl)
	_stats_grid.add_child(player_row)

	for val: int in [wins, kills, headshots]:
		var lbl := Label.new()
		lbl.text = str(val)
		lbl.add_theme_font_size_override("font_size", 30)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stats_grid.add_child(lbl)


func _on_rematch_pressed() -> void:
	if NetworkManager.is_host:
		GameManager.return_to_lobby.rpc()


func _on_quit_pressed() -> void:
	NetworkManager.disconnect_from_network()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


# ── helpers ──────────────────────────────────────────────────────────────────

func _color_for_peer(pid: int, round_data: Dictionary) -> Color:
	var peer_ids: Array = round_data.get("peer_ids", [])
	var color_indices: Array = round_data.get("color_indices", [])
	var idx: int = peer_ids.find(pid)
	if idx < 0 or idx >= color_indices.size():
		return Color.WHITE
	return PLAYER_COLORS[clampi(color_indices[idx], 0, PLAYER_COLORS.size() - 1)]


func _color_name_for_peer(pid: int, round_data: Dictionary) -> String:
	var peer_ids: Array = round_data.get("peer_ids", [])
	var color_indices: Array = round_data.get("color_indices", [])
	var idx: int = peer_ids.find(pid)
	if idx < 0 or idx >= color_indices.size():
		return "Player %d" % pid
	return COLOR_NAMES[clampi(color_indices[idx], 0, COLOR_NAMES.size() - 1)]
