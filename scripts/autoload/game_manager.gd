extends Node

# GameManager — global state machine, round/match logic, and persistent RPCs.
# Lives as an autoload so RPCs defined here are reachable on all peers regardless
# of which scene is currently active.

enum GameState { MAIN_MENU, LOBBY, ROUND_START, ROUND_ACTIVE, ROUND_END, MATCH_END }

var current_state: GameState = GameState.MAIN_MENU
var round_number: int = 0
var max_rounds: int = 5
var match_scores: Dictionary = {}   # peer_id -> round wins
var kill_stats: Dictionary = {}     # peer_id -> {kills: int, headshots: int}

# Filled by start_round before the scene transition; game.gd reads this in _ready().
var pending_round_data: Dictionary = {}

# Set by main menu before switching to lobby so lobby knows which panel to show.
# Values: "" (show mode-select), "join" (auto-open join panel).
var pending_lobby_mode: String = ""


func _ready() -> void:
	pass


# Called by host on all peers to start the very first round of a new match.
# data keys: peer_ids (Array), spawn_positions (Array[Vector2]),
#            color_indices (Array[int]), max_rounds (int)
@rpc("authority", "call_local", "reliable")
func start_round(data: Dictionary) -> void:
	current_state = GameState.ROUND_START
	round_number = 1
	max_rounds = data.get("max_rounds", 5)
	match_scores.clear()
	kill_stats.clear()
	pending_round_data = data
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


# Called by host on all peers (e.g. after REMATCH) to return everyone to the lobby
# while keeping the network connection alive.
@rpc("authority", "call_local", "reliable")
func return_to_lobby() -> void:
	current_state = GameState.LOBBY
	round_number = 0
	match_scores.clear()
	kill_stats.clear()
	pending_round_data.clear()
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")
