class_name EventRpc
extends Node

# Reliable RPC node for discrete game events that must arrive on all peers.
# Lives in game.tscn (same node path on all peers) so Godot routes RPCs correctly.
# All RPCs are authority-only (host fires them) and call_local (host also runs them).
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §4.9

# Set by game.gd immediately after the scene loads.
var _game: GameScene


# ------------------------------------------------------------------
# Reliable event RPCs — host calls, all peers execute
# ------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func on_player_hit(player_id: int, damage: int, hit_pos: Vector2, is_headshot: bool) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_player_hit(player_id, damage, hit_pos, is_headshot)


@rpc("authority", "call_local", "reliable")
func on_player_killed(player_id: int, killer_id: int, force: Vector2) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_player_killed(player_id, killer_id, force)


@rpc("authority", "call_local", "reliable")
func on_weapon_picked_up(player_id: int, weapon_type: String, pickup_pos: Vector2) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_weapon_picked_up(player_id, weapon_type, pickup_pos)


@rpc("authority", "call_local", "reliable")
func on_weapon_dropped(player_id: int, old_type: String, drop_pos: Vector2, ammo: int) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_weapon_dropped(player_id, old_type, drop_pos, ammo)


@rpc("authority", "call_local", "reliable")
func on_round_end(winner_id: int, scores: Dictionary) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_round_end(winner_id, scores)


@rpc("authority", "call_local", "reliable")
func on_match_end(final_scores: Dictionary) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_match_end(final_scores)


# Sent by host when a grenade is thrown so clients can spawn a cosmetic copy.
# No call_local — host already has the authoritative projectile.
@rpc("authority", "reliable")
func on_grenade_thrown(thrower_id: int, pos: Vector2, vel: Vector2) -> void:
	if not is_instance_valid(_game):
		return
	_game.handle_grenade_thrown(thrower_id, pos, vel)
