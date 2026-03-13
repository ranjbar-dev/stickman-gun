extends Node

# GameManager — global state machine, round/match logic, and round-start RPC.
# start_round is defined here (persistent autoload) so it is reachable on all
# peers regardless of which scene is currently active.

enum GameState { MENU, LOBBY, ROUND_ACTIVE, ROUND_END, MATCH_END }

var current_state: GameState = GameState.MENU
var round_number: int = 0
var match_scores: Dictionary = {}  # player_id -> wins

# Filled by start_round before the scene transition; game.gd reads this in _ready().
var pending_round_data: Dictionary = {}


func _ready() -> void:
	pass


# Called by host; executes on all peers (call_local) to transition into the game scene.
# data keys: peer_ids (Array), spawn_positions (Array[Vector2]), color_indices (Array[int])
@rpc("authority", "call_local", "reliable")
func start_round(data: Dictionary) -> void:
	current_state = GameState.ROUND_ACTIVE
	pending_round_data = data
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")
