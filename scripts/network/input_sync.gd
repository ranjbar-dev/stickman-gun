class_name InputSync
extends Node

# InputSync — sends local player input to the host every physics frame.
# Lives inside game.tscn so the node path is identical on all peers, ensuring
# Godot's RPC routing resolves correctly.

# Set by game.gd immediately after adding this node.
var _game: GameScene


func _physics_process(_delta: float) -> void:
	if NetworkManager.is_host:
		return
	if not is_instance_valid(_game):
		return
	var player: StickmanController = _game.get_local_player()
	if not is_instance_valid(player):
		return
	send_input.rpc_id(1, player.get_input_snapshot())


# Received by host only; any_peer allows clients to call this on the host.
@rpc("any_peer", "unreliable")
func send_input(input: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_game.set_player_input(sender, input)
