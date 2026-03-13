extends Node

# GameManager — global state machine, round/match logic
# TODO Phase 2: implement game states (LOBBY, ROUND_ACTIVE, ROUND_END, MATCH_END)
# TODO Phase 2: track round wins per player, detect match winner
# TODO Phase 2: broadcast state transitions via NetworkManager

enum GameState { MENU, LOBBY, ROUND_ACTIVE, ROUND_END, MATCH_END }

var current_state: GameState = GameState.MENU
var round_number: int = 0
var match_scores: Dictionary = {}  # player_id -> wins


func _ready() -> void:
	pass
