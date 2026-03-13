---
applyTo: "scripts/network/**/*.gd,scripts/autoload/network_manager.gd"
---

# Networking Instructions

## Architecture: Authoritative Host

- One phone is both server and client (peer ID 1)
- Host runs ALL game logic: physics, hit detection, damage, death, weapon spawns, round state
- Clients are thin: send inputs, receive state, render
- ENetMultiplayerPeer on port 7777

## Data Flow

### Client → Host (every physics frame)
- Unreliable RPC: move_direction, is_crouching, is_jumping, aim_angle, is_firing, swap_weapon
- ~20 bytes per packet, sent at 60fps

### Host → All Clients (20-30 Hz)
- Unreliable RPC: per-player position, velocity, aim_angle, crouch state, health, weapon, ammo, alive status
- ~400 bytes per tick for 8 players

### Host → All Clients (events, as they happen)
- Reliable RPC: player_hit, player_killed, weapon_picked_up, weapon_dropped, round_start, round_end, match_end

## Client-Side Interpolation

- Buffer last 2 received states
- Render at interpolated position between state[n-1] and state[n]
- Adds ~50ms visual delay — imperceptible on LAN

## Connection Flow

1. Host creates ENetMultiplayerPeer server on port 7777
2. Host detects local IP via IP.get_local_addresses()
3. QR code encodes "stickfight://IP:PORT"
4. Client scans QR, parses IP+port, creates ENet client
5. On connection: client appears in lobby
6. Host broadcasts lobby state to all on any change

## Disconnection Rules

- Non-host disconnects mid-round: their stickman dies (ragdoll), removed from match
- Non-host disconnects in lobby: removed from player list, color freed
- Host disconnects: all clients shown "Host disconnected", return to main menu
- Game full (8 players): show "Game is full" to new joiners

## Critical Rules

- Clients NEVER modify game state — they only send inputs and render received state
- All RayCast2D hit detection runs on the host only
- Ragdoll is spawned locally on each client from a kill force vector — minor drift is acceptable
- Terrain is synced via seed only — all clients generate deterministically from the same seed
- Sound effects play locally on clients triggered by event RPCs
