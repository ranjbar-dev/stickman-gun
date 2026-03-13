class_name StateSync
extends Node

# StateSync — host broadcasts all player states to clients at 20 Hz.
# Uses an accumulator rather than a Godot Timer so the broadcast stays locked to
# _process and avoids creating an extra idle-frame object.

const SYNC_INTERVAL: float = 1.0 / 20.0

# Set by game.gd immediately after adding this node.
var _game: GameScene

var _timer: float = 0.0


func _process(delta: float) -> void:
	if not NetworkManager.is_host:
		return
	_timer += delta
	if _timer >= SYNC_INTERVAL:
		_timer -= SYNC_INTERVAL
		_broadcast_state()


func _broadcast_state() -> void:
	if not is_instance_valid(_game):
		return
	sync_state.rpc(_game.get_all_player_states())


# Received by all clients (not the host itself — no call_local).
# Clients apply the authoritative snapshot directly to their player nodes.
@rpc("authority", "unreliable")
func sync_state(states: Dictionary) -> void:
	if not is_instance_valid(_game):
		return
	_game.apply_all_player_states(states)
