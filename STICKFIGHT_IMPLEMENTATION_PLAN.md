# StickFight LAN — Implementation Plan

**Reference:** STICKFIGHT_GAME_DESIGN.md
**Engine:** Godot 4.x (GDScript)
**Target:** Android (Landscape)

---

## Overview

6 phases. Each produces a testable milestone. Don't skip ahead.

**Estimated total:** ~4–6 weeks part-time solo dev.

---

## Phase 1 — Single Stickman Prototype

**Goal:** One stickman on a flat surface. Move, jump, crouch, aim, shoot pistol.
**Milestone:** Playable single character with working controls on Android.
**Estimated time:** 3–5 days

### Tasks

#### 1.1 Project Setup
- Create new Godot 4 project, set to landscape, configure Android export template
- Set project resolution to 1920×1080, stretch mode `canvas_items`, aspect `expand`
- Create the folder structure from the design doc (scenes/, scripts/, assets/, etc.)
- Set up autoloads: `GameManager`, `NetworkManager`, `AudioManager` (empty singletons for now)

#### 1.2 Virtual Joystick (`scenes/hud/virtual_joystick.tscn`)
- Create a reusable `Control` node-based floating joystick
- Properties: `joystick_radius`, `dead_zone` (15%), `direction: Vector2` (output)
- On touch down within designated screen half: joystick appears at touch position
- On touch drag: inner knob follows finger, clamped to radius, updates `direction`
- On touch up: joystick hides, `direction` resets to `Vector2.ZERO`
- Visual: semi-transparent outer circle + inner filled circle
- Two instances in HUD: left half = movement, right half = aim

```
Key signals:
- joystick_input(direction: Vector2)  # emitted every frame while active
- joystick_released()
```

#### 1.3 Stickman Renderer (`scripts/player/stickman_renderer.gd`)
- Attach to the stickman node, override `_draw()`
- Draw all body parts as lines/arcs using the player's color:
  - Head: `draw_arc(head_pos, 12, 0, TAU, 32, color, 2.0)`
  - Body: `draw_line(head_base, hip, color, 2.0)`
  - Left leg upper: `draw_line(hip, left_knee, color, 2.0)`
  - Left leg lower: `draw_line(left_knee, left_foot, color, 2.0)`
  - Right leg (same pattern)
  - Left arm (non-weapon): `draw_line(shoulder, left_elbow, color, 2.0)` + forearm
  - Right arm (weapon arm): rotates based on `aim_angle`
  - Weapon line: extends from hand position in aim direction
- Expose `aim_angle: float` and `is_crouching: bool` to control pose
- When crouching: shorten body line, lower head position, bend knees more
- Call `queue_redraw()` whenever aim_angle or crouch state changes

#### 1.4 Stickman Controller (`scripts/player/stickman_controller.gd`)
- Extends `CharacterBody2D`
- Movement constants:

```gdscript
const WALK_SPEED := 200.0
const CROUCH_SPEED := 100.0
const JUMP_VELOCITY := -400.0
const GRAVITY := 980.0
```

- `_physics_process(delta)`:
  - Apply gravity if not on floor
  - Read movement joystick direction:
    - X axis → horizontal velocity (WALK_SPEED or CROUCH_SPEED)
    - Y axis < -0.5 → crouch (set `is_crouching = true`, shrink collision shape)
  - Jump button → apply JUMP_VELOCITY if on floor and not crouching
  - Read aim joystick → update `aim_angle` on renderer
  - Call `move_and_slide()`
- Collision shape: `CapsuleShape2D`, height ~40px standing, ~25px crouching
- Export `player_color: Color` for the renderer

#### 1.5 Pistol Hitscan (`scripts/weapons/hitscan_weapon.gd`)
- `RayCast2D` attached to weapon tip, rotated to `aim_angle`
- Range: cast length ~600px (medium range)
- On aim joystick held (right joystick `direction.length() > dead_zone`):
  - Fire at 3 shots/sec rate (cooldown timer: 0.33s)
  - Enable raycast, force update, check collision
  - If collider is in "head_hitbox" group → headshot
  - If collider is in "body_hitbox" group → body hit
  - Draw a brief line trace (tracer visual) from weapon tip to ray hit point, fade after 0.05s
- On aim joystick released: stop firing

#### 1.6 Test Scene
- Create a simple test level: `StaticBody2D` ground (flat line) + 2–3 platform `StaticBody2D` lines
- Place one stickman, attach HUD with both joysticks + jump button
- Add a few `StaticBody2D` target dummies with head/body hitboxes to test shooting
- Test on Android: verify touch controls feel responsive

#### 1.7 Camera
- `Camera2D` as child of stickman, smoothing enabled
- Limit to map boundaries (left, right, bottom death zone)
- Zoom level: show roughly 1 screen width of the map around the player

### Phase 1 Definition of Done
- [ ] Stickman draws correctly with line-art style
- [ ] Walk left/right works smoothly
- [ ] Jump works (single jump, only from floor)
- [ ] Crouch works (visual change + slower speed + smaller hitbox)
- [ ] Aim joystick rotates the weapon arm
- [ ] Pistol fires hitscan rays at correct rate
- [ ] Tracer visual appears on shot
- [ ] Camera follows player
- [ ] Runs on Android at 60fps

---

## Phase 2 — Full Weapons & Combat

**Goal:** All 4 weapons working. Health system. Ragdoll death. Headshot detection.
**Milestone:** Can fight (solo with test dummies), pick up weapons, die spectacularly.
**Estimated time:** 5–7 days

### Tasks

#### 2.1 Health System (`scripts/player/hitbox_manager.gd`)
- Add two `Area2D` children to stickman:
  - `HeadHitbox`: small `CircleShape2D` (~10px radius) at head position, group "head_hitbox"
  - `BodyHitbox`: `CapsuleShape2D` covering torso/limbs, group "body_hitbox"
- `health: int = 3`
- `take_damage(amount: int, is_headshot: bool, hit_direction: Vector2)`:
  - If headshot → health = 0 (instant kill)
  - Else → health -= amount
  - If health <= 0 → emit `died(kill_force_vector)` signal

#### 2.2 Ragdoll System (`scripts/player/ragdoll_spawner.gd`)
- Ragdoll scene (`scenes/player/ragdoll.tscn`):
  - Head: `RigidBody2D` + `CircleShape2D`
  - Torso: `RigidBody2D` + `CapsuleShape2D` (short)
  - Upper arms ×2, forearms ×2, upper legs ×2, lower legs ×2: each a `RigidBody2D` + small `RectangleShape2D`
  - All connected with `PinJoint2D` at appropriate joint points
  - All parts drawn with same line-art style in player color
- On stickman death:
  - Hide the `CharacterBody2D` stickman
  - Instance ragdoll scene at stickman position, matching current pose
  - Apply impulse from `kill_force_vector` to the torso `RigidBody2D`
  - Ragdoll lives for ~5 seconds then fades out

#### 2.3 Weapon Base Class (`scripts/weapons/weapon_base.gd`)
```gdscript
class_name WeaponBase extends Node2D

@export var fire_rate: float        # shots per second
@export var damage: int             # damage per hit
@export var max_ammo: int           # -1 for unlimited
@export var weapon_type: String     # "pistol", "sniper", "shotgun", "grenade"

var current_ammo: int
var cooldown_timer: float = 0.0
var can_fire: bool = true

func _ready():
    current_ammo = max_ammo

func try_fire(aim_angle: float) -> bool:
    # Returns true if weapon fired, false if on cooldown/no ammo
    pass

func _process(delta):
    cooldown_timer -= delta
    if cooldown_timer <= 0:
        can_fire = true
```

#### 2.4 Sniper Weapon (`scripts/weapons/hitscan_weapon.gd` — extended)
- Inherits hitscan logic from pistol but with different params:
  - Fire rate: 0.8/sec (cooldown 1.25s)
  - Damage: 2
  - Range: full map (~4000px raycast)
  - Ammo: 5
- Tracer visual: thicker line, lingers 0.3s (use a `Line2D` with a fade tween)

#### 2.5 Shotgun Weapon
- Same hitscan base, but fires 5 rays per shot
- Each ray: random angle within ±15° of aim direction (total 30° cone)
- Each ray: range ~300px (short)
- Each ray: 1 damage independently
- Fire rate: 1.5/sec, ammo: 8

#### 2.6 Grenade Weapon (`scripts/weapons/grenade_weapon.gd`)
- Completely different from hitscan — spawns a projectile
- `grenade_projectile.tscn`: `RigidBody2D` + small `CircleShape2D`
  - Drawn as a small circle with a line (fuse indicator)
  - On fire: apply impulse based on aim angle + joystick pull distance
  - Bounce: `physics_material` with bounce = 0.4
  - Fuse timer: 2.0 seconds → explode
  - On `body_entered` with player → explode immediately
  - Explode: check all bodies in blast radius (~80px `Area2D`), apply 2 damage + impulse
  - Self-damage: thrower can be hit by own grenade
- Trajectory preview:
  - While aiming (before fire), draw a dotted arc `Line2D`
  - Calculate 10–15 points of simulated trajectory using aim angle + force
  - Update every frame while aim joystick is held
  - Hide on release/fire

#### 2.7 Weapon Holder & Switching (`scripts/player/weapon_holder.gd`)
- Stickman has two weapon slots: `pistol_slot` (permanent) and `secondary_slot` (nullable)
- `active_slot: String = "pistol"` — which weapon is currently drawn/used
- Swap button toggles between pistol and secondary (if secondary exists)
- Visual: weapon line on the weapon arm changes based on active weapon:
  - Pistol: short line
  - Sniper: long thin line
  - Shotgun: medium line with wider end
  - Grenade: small circle at hand

#### 2.8 Weapon Pickup (`scripts/weapons/weapon_pickup.gd`)
- `Area2D` with a `CollisionShape2D` trigger zone
- Drawn as a blinking line-art icon of the weapon, hovering slightly
- On player `body_entered`:
  - If player has no secondary → pick up weapon
  - If player has secondary → swap: drop current secondary at this position with remaining ammo, pick up new one
  - Emit pickup sound event
- Pickup data: `weapon_type`, `ammo_count`

#### 2.9 Updated HUD
- Top-left: 3 health dots (filled circles = remaining HP, empty circles = lost HP)
- Top-right: weapon icon (simple line drawing matching weapon type) + "×5" ammo text
- Swap button: small touch target near right joystick
- Grenade mode: show trajectory preview overlay

### Phase 2 Definition of Done
- [ ] All 4 weapons fire correctly with distinct behavior
- [ ] Headshot hitbox → instant kill
- [ ] Body hitbox → correct damage per weapon
- [ ] Ragdoll spawns on death with directional impulse
- [ ] Weapon pickups work (grab, swap, drop)
- [ ] Grenade arcs, bounces, explodes with blast radius
- [ ] Grenade trajectory preview works
- [ ] HUD shows health, weapon, ammo
- [ ] Weapon swap button works

---

## Phase 3 — Procedural Terrain

**Goal:** Each run generates a unique, playable map from a seed.
**Milestone:** Fresh terrain every time. Spawn points work. Weapon spawns placed.
**Estimated time:** 3–4 days

### Tasks

#### 3.1 Terrain Generator (`scripts/terrain/terrain_generator.gd`)
- Input: `seed: int`
- Use `RandomNumberGenerator` with `rng.seed = seed` for determinism
- Generate terrain components and add them as children of a root `Node2D`

#### 3.2 Ground Layer Generation
- Map width: ~6000px (roughly 3× screen width of 1920)
- Place 10–14 control points evenly across width
- Each point Y: random between `800` and `950` (bottom portion of screen)
- Connect points with straight line segments
- Create `StaticBody2D` with `CollisionPolygon2D`:
  - Top edge = the generated line segments
  - Bottom edge = well below screen (e.g. Y=1200)
  - This creates a solid filled ground
- Draw the top edge as visible lines (white, 3px thick)
- Optionally fill below with a slightly lighter dark shade

#### 3.3 Platform Generation
- Number of platforms: `rng.randi_range(4, 8)`
- For each platform:
  - Width: `rng.randf_range(100, 250)` px
  - X position: random within map bounds (with min spacing of 150px between platforms)
  - Y position: random between `400` and `700` (above ground, below top)
  - Verify jumpability: no platform more than `120px` above nearest reachable surface (ground or another platform)
  - Create `StaticBody2D` + `CollisionShape2D` (thin rectangle)
  - Draw as horizontal line (white, 3px)

#### 3.4 Cover Walls
- Number: `rng.randi_range(2, 4)`
- For each wall:
  - Height: `rng.randf_range(50, 100)` px
  - Placed on a random valid surface (ground control point or platform)
  - X: random position on that surface
  - Create `StaticBody2D` + `CollisionShape2D` (thin vertical rectangle)
  - Draw as vertical line (white, 3px)

#### 3.5 Boundaries & Death Zone
- Left wall: invisible `StaticBody2D` at X=0, full height
- Right wall: invisible `StaticBody2D` at X=map_width, full height
- Death zone: `Area2D` at Y=1100 spanning full width
  - On `body_entered`: kill the player instantly

#### 3.6 Spawn Point Calculator (`scripts/terrain/spawn_calculator.gd`)
- Divide map width into 8 equal horizontal zones
- For each zone, find a valid surface point (ground or platform with enough headroom)
- Place spawn point at surface Y minus stickman half-height
- Ensure minimum 300px between any two spawn points
- Output: `Array[Vector2]` of 8 spawn positions

#### 3.7 Weapon Spawn Placement
- Number of weapon spawns: `rng.randi_range(3, 5)`
- Place on valid surfaces, avoiding player spawn points (minimum 200px away)
- Spread across map (use similar zone-based approach)
- Each spawn randomly assigned: sniper, shotgun, or grenade
- Output: `Array[Dictionary]` with position + weapon_type

#### 3.8 Test Integration
- Create a test scene that generates terrain from a random seed on load
- Place one stickman at spawn point 0
- Place weapon pickups at weapon spawn points
- Verify: terrain is playable, platforms are reachable, spawns are valid
- Verify: same seed always produces identical terrain

### Phase 3 Definition of Done
- [ ] Terrain generates from seed deterministically
- [ ] Ground is uneven and interesting
- [ ] 4–8 platforms, all reachable by jumping
- [ ] 2–4 cover walls placed correctly
- [ ] Death zone kills on fall-off
- [ ] 8 valid spawn points calculated
- [ ] 3–5 weapon spawn points placed
- [ ] Same seed = same map every time

---

## Phase 4 — Networking

**Goal:** Host/client multiplayer working on LAN. QR code join. Full state sync.
**Milestone:** 2+ players fighting on the same terrain over WiFi.
**Estimated time:** 7–10 days (most complex phase)

### Tasks

#### 4.1 Network Manager Autoload (`scripts/autoload/network_manager.gd`)
```gdscript
# Core state
var is_host: bool = false
var peer: ENetMultiplayerPeer
var local_player_id: int
var connected_players: Dictionary = {}  # {peer_id: {color, ready, name}}

# Constants
const PORT := 7777
const MAX_CLIENTS := 7  # + host = 8

# Signals
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed()
signal server_disconnected()
```

#### 4.2 Host Setup
- `create_server()`:
  - Create `ENetMultiplayerPeer`, `create_server(PORT, MAX_CLIENTS)`
  - Set `multiplayer.multiplayer_peer = peer`
  - `is_host = true`
  - `local_player_id = 1` (host is always peer ID 1)
  - Get local IP: use `IP.get_local_addresses()`, filter for `192.168.*` or `10.*` or `172.16-31.*`
  - Generate QR code string: `"stickfight://IP:PORT"`
- Connect signals: `multiplayer.peer_connected`, `peer_disconnected`

#### 4.3 QR Code Generation
- Use a GDScript QR code library (options):
  - `gdqrcode` addon — pure GDScript, generates QR as `Image`
  - Or generate QR via a minimal lookup table approach
- Display QR as `TextureRect` in lobby, large and centered
- Below QR: show IP:PORT as text fallback

#### 4.4 Client Join
- "Join Game" → open device camera using Godot's `CameraFeed` or Android intent
- **Simpler alternative for v1:** Instead of in-app camera, show a text input field where the player types the IP:PORT (displayed on host screen). QR can be scanned with any QR reader app which copies the text, then paste into the field.
- **Better v1 approach:** Generate QR that is a plain text `192.168.x.x:7777`. Player uses any QR scanner → copies text → pastes into join field. Avoids camera permission complexity.
- `join_server(ip: String, port: int)`:
  - Create `ENetMultiplayerPeer`, `create_client(ip, port)`
  - Set `multiplayer.multiplayer_peer = peer`
  - `is_host = false`

#### 4.5 Lobby Sync
- When client connects:
  - Server RPC → send client the current lobby state (all players + colors)
  - Client picks a color → RPC to server
  - Server validates (color not taken) → broadcasts updated lobby state to all
- Lobby data structure (synced by host):
```gdscript
# Per player
{
  peer_id: int,
  color_index: int,    # 0-7, -1 = not picked
  is_ready: bool
}
```
- Host sees "Start" button when `connected_players.size() >= 2`

#### 4.6 Input Synchronization (`scripts/network/input_sync.gd`)
- Each client sends inputs to host every physics frame via **unreliable** RPC (UDP, no guarantee, newest wins):
```gdscript
@rpc("any_peer", "unreliable")
func send_input(input_data: Dictionary):
    # Host receives and applies to the correct player
    # input_data = {move_dir, is_crouching, is_jumping, aim_angle, is_firing, swap_weapon}
```
- Host stores latest input per player, applies during `_physics_process`

#### 4.7 State Synchronization (`scripts/network/state_sync.gd`)
- Host sends game state to all clients at 20Hz (every 3 physics frames if running at 60fps)
- Use **unreliable** channel for position/state (latest wins, no need for ordered delivery):
```gdscript
@rpc("authority", "unreliable")
func sync_state(state: Dictionary):
    # state contains all player positions, rotations, health, weapons, etc.
```
- State payload per player: position (Vector2), velocity (Vector2), aim_angle (float), is_crouching (bool), health (int), active_weapon (String), ammo (int), is_alive (bool)
- Clients receive state → interpolate between last two states for smooth rendering

#### 4.8 Client-Side Interpolation
- Client stores a buffer of the last 2 received states
- Renders at a position interpolated between state[n-1] and state[n]
- Interpolation factor based on time since last state received vs expected interval (1/20 = 50ms)
- This adds ~50ms visual delay but ensures smooth movement even with network jitter

#### 4.9 Event RPCs (`scripts/network/event_rpc.gd`)
- Use **reliable** RPCs for discrete game events (these must arrive):
```gdscript
@rpc("authority", "reliable")
func on_player_hit(player_id: int, damage: int, hit_pos: Vector2, is_headshot: bool):
    # Client plays hit effect / sound

@rpc("authority", "reliable")
func on_player_killed(player_id: int, killer_id: int, force: Vector2):
    # Client spawns ragdoll with force

@rpc("authority", "reliable")
func on_weapon_picked_up(player_id: int, weapon_type: String, spawn_id: int):
    # Client updates weapon pickup visuals

@rpc("authority", "reliable")
func on_round_start(terrain_seed: int, spawns: Array, weapon_spawns: Array):
    # Client generates terrain, places players

@rpc("authority", "reliable")
func on_round_end(winner_id: int, scores: Dictionary):
    # Client shows round end overlay

@rpc("authority", "reliable")
func on_match_end(final_scores: Dictionary):
    # Client shows match end screen
```

#### 4.10 Multiplayer Spawner Setup
- Use Godot 4's `MultiplayerSpawner` for stickman instantiation
- Host spawns all player scenes, `MultiplayerSpawner` replicates to clients
- Each stickman's `set_multiplayer_authority()` is set to host (peer 1) since host is authoritative
- Clients only control their own input → send to host

#### 4.11 Host Game Logic
- Host's `_physics_process`:
  1. For each alive player: apply their latest received input, run physics
  2. Process weapon firing: perform raycasts / spawn grenades
  3. Check hits: head vs body, apply damage
  4. Check deaths: trigger ragdoll events
  5. Check alive count: if 1 remaining → round end
  6. Every 3rd frame: broadcast state to clients

#### 4.12 Disconnection Handling
- `multiplayer.peer_disconnected` signal on host:
  - Kill that player's stickman (ragdoll), remove from match
  - Broadcast updated player list
- `multiplayer.server_disconnected` signal on client:
  - Show "Host disconnected" popup
  - Return to main menu

### Phase 4 Definition of Done
- [ ] Host can create server, QR/text code shown
- [ ] Client can join via IP:PORT
- [ ] Lobby shows all players, color picking works
- [ ] Host can start game, all clients receive round_start
- [ ] Inputs flow from clients to host
- [ ] Game state flows from host to clients at 20Hz
- [ ] Players see each other move smoothly (interpolation)
- [ ] Shooting works across network (host detects hits, clients see effects)
- [ ] Deaths sync correctly (ragdoll on all clients)
- [ ] Weapon pickups sync
- [ ] Disconnection handled gracefully
- [ ] 2–4 player test on real WiFi network

---

## Phase 5 — Game Flow & UI

**Goal:** Complete game loop from menu to match end. Spectator mode. Scoreboard.
**Milestone:** Full playable match with multiple rounds.
**Estimated time:** 4–5 days

### Tasks

#### 5.1 Game Manager State Machine (`scripts/autoload/game_manager.gd`)
```gdscript
enum GameState {
    MAIN_MENU,
    LOBBY,
    ROUND_START,
    ROUND_ACTIVE,
    ROUND_END,
    MATCH_END
}

var current_state: GameState = GameState.MAIN_MENU
var round_number: int = 0
var max_rounds: int = 5
var scores: Dictionary = {}  # {peer_id: round_wins}
var kill_stats: Dictionary = {}  # {peer_id: {kills, headshots}}
```

#### 5.2 Main Menu Scene (`scenes/main_menu/main_menu.tscn`)
- Line-art title "STICKFIGHT LAN" drawn with simple lines
- Three buttons: HOST GAME, JOIN GAME, SETTINGS
- Settings: single master volume slider + back button
- HOST GAME → transition to lobby as host
- JOIN GAME → show IP input field (or camera for QR) → connect → lobby as client

#### 5.3 Lobby Scene (`scenes/lobby/lobby.tscn`)
- **Host view:** QR code + IP text, player list, color swatches (host picks too), round count selector (1–10, default 5), START button
- **Client view:** Color swatches, player list, "Waiting for host..." text
- Color picker: 8 colored rectangles. Tap to claim. Taken = dimmed + X overlay
- Player list: colored dot + "Player" label for each connected player. Host marked with "(Host)"
- Real-time sync: lobby state updates broadcast by host whenever a player joins, leaves, or picks a color

#### 5.4 Round Start Sequence
- Host generates new terrain seed → broadcasts `on_round_start` RPC
- All clients generate terrain from seed
- Players placed at spawn positions (frozen — `CharacterBody2D` disabled)
- Weapon pickups NOT yet visible
- Countdown overlay: "3" → "2" → "1" → "FIGHT!" (1 second each, big centered text)
- At "FIGHT!": unfreeze players, start weapon spawn timer (2s delay)
- At 2s: weapon pickups appear

#### 5.5 Round Active Logic (Host)
- Track `alive_players: Array[int]`
- On player death: remove from alive_players
- When `alive_players.size() == 1`:
  - Winner = remaining player
  - Increment their score
  - Broadcast `on_round_end(winner_id, scores)`
- Edge case: last two die simultaneously (same physics frame):
  - Draw round — no one gets a point
  - Broadcast round_end with `winner_id = -1`

#### 5.6 Round End Overlay (`scenes/ui/round_end.tscn`)
- Shows for 5 seconds over the game world
- Winner's color dot + "Blue wins Round 2!"
- Running score tally: each player's color + round wins
- Auto-transition countdown: "Next round in 5... 4..."
- If draw: "DRAW — No winner this round"

#### 5.7 Match End Screen (`scenes/ui/match_end.tscn`)
- Triggered when `round_number > max_rounds`
- Winner: player with most round wins (tie = "Draw!")
- Stats table: Player color, rounds won, total kills, headshots
- Two buttons: REMATCH (→ lobby, keep same players), QUIT (→ main menu)
- REMATCH: host broadcasts return-to-lobby, all clients follow

#### 5.8 Spectator Mode
- On death: disable HUD joysticks and buttons
- Enable spectator HUD: left/right arrow buttons at screen edges
- Track `spectating_index` cycling through `alive_players`
- Camera smoothly lerps to followed player's position
- Top label: "Spectating: [color name]" (e.g. "Spectating: Blue")
- On round end: spectator mode auto-disables

#### 5.9 Scene Transitions
- Use `SceneTree.change_scene_to_packed()` for major transitions (menu ↔ lobby)
- Game world stays loaded across rounds — just regenerate terrain + reset players
- Round end / match end are overlay `CanvasLayer` nodes on top of game world

### Phase 5 Definition of Done
- [ ] Full flow: Menu → Lobby → Round → Round End → ... → Match End → Menu
- [ ] Host can configure round count
- [ ] Countdown 3-2-1-FIGHT works
- [ ] Weapon spawns appear after 2s delay
- [ ] Round ends correctly when 1 player left
- [ ] Draw round handled
- [ ] Scoreboard tracks round wins across rounds
- [ ] Match end shows full stats
- [ ] Rematch returns to lobby
- [ ] Spectator mode works (camera follows, cycle players)
- [ ] Disconnection during any state handled gracefully

---

## Phase 6 — Audio & Polish

**Goal:** Sound effects, music, visual polish, Android optimization.
**Milestone:** Release-ready game.
**Estimated time:** 3–4 days

### Tasks

#### 6.1 Audio Manager (`scripts/autoload/audio_manager.gd`)
- Singleton managing all audio playback
- Methods:
```gdscript
func play_sfx(sfx_name: String, position: Vector2 = Vector2.ZERO, positional: bool = true):
    # Spawns AudioStreamPlayer2D at position if positional
    # Otherwise uses AudioStreamPlayer

func play_music(track_name: String):
    # Crossfade to new music track

func set_master_volume(value: float):
    # 0.0 to 1.0, maps to AudioServer bus volume
```
- Preload all `.ogg` files into a dictionary on `_ready()`
- Pool `AudioStreamPlayer2D` nodes (create ~16, reuse oldest when all busy)

#### 6.2 Sound Effect Files
- Source free SFX from: freesound.org, kenney.nl, or generate with sfxr/jsfxr
- All exported as `.ogg`, mono, 44100 Hz
- Files needed (13 total):
  - `pistol_shot.ogg`, `sniper_shot.ogg`, `shotgun_blast.ogg`
  - `grenade_throw.ogg`, `explosion.ogg`
  - `hit_marker.ogg`, `headshot.ogg`, `death.ogg`
  - `weapon_pickup.ogg`, `jump.ogg`
  - `countdown_beep.ogg`, `round_start.ogg`, `victory.ogg`

#### 6.3 Background Music
- Single looping track, chiptune or lo-fi style
- Source from: opengameart.org or create with BeepBox/Bosca Ceoil
- Low volume by default (~-12dB on the music bus)
- Loop seamlessly (`loop = true` in Godot import settings)

#### 6.4 Sound Integration Points
- Hook `AudioManager.play_sfx()` calls into:
  - Weapon fire events (per weapon type)
  - Hit/headshot event RPCs (client-side)
  - Death event RPCs (client-side, positional at death location)
  - Weapon pickup (client-side)
  - Jump action
  - Countdown beeps (round start sequence)
  - Round start horn
  - Victory jingle (round/match end)
- Music: start on main menu, continue through lobby, same track during gameplay

#### 6.5 Audio Bus Setup
- Godot Audio Bus layout:
  - **Master** — overall volume (controlled by settings slider)
  - **SFX** — all sound effects route here
  - **Music** — background music routes here
- Settings slider controls Master bus volume

#### 6.6 Visual Polish
- **Muzzle flash:** Brief white circle at weapon tip on fire (1 frame, `_draw()`)
- **Hit particles:** Small line fragments burst from hit point (use `GPUParticles2D` or manual `_draw()` lines)
- **Death effect:** Brief screen shake on the killer's client (small camera offset, 0.1s)
- **Tracer lines:** Already implemented, but ensure sniper tracer is visually distinct (thicker, longer linger)
- **Weapon pickup glow:** Subtle pulsing brightness on pickup icons
- **Grenade fuse:** Small shrinking line on the grenade circle as fuse counts down

#### 6.7 Android Optimization
- **Target:** Stable 60fps on mid-range Android devices
- Profile with Godot's built-in profiler + Android GPU profiler
- Key optimizations:
  - Limit ragdoll body count: max 3 active ragdolls, oldest fades and queues_free
  - Pool projectiles and particles instead of instantiating/freeing
  - Use `VisibleOnScreenNotifier2D` to skip drawing off-screen objects
  - Keep draw calls minimal: batch line drawing where possible
  - Network: compress state packets if bandwidth is an issue (unlikely on LAN)

#### 6.8 Android Export Configuration
- Export template: Godot Android export
- Min SDK: API 24 (Android 7.0)
- Permissions needed:
  - `INTERNET` — for ENet networking
  - `ACCESS_WIFI_STATE` — to detect local IP
  - `ACCESS_NETWORK_STATE` — network availability check
  - `CAMERA` — only if implementing in-app QR scanning (optional for v1)
- Screen orientation: locked landscape
- App icon: simple stickman silhouette with crosshair

#### 6.9 Playtesting Checklist
- [ ] 2-player test: basic combat flow
- [ ] 4-player test: performance + network stability
- [ ] 8-player test: stress test, verify no lag spikes
- [ ] All weapons: verify damage values feel balanced
- [ ] Terrain: verify all generated maps are playable (no unreachable spawns)
- [ ] Edge cases: simultaneous deaths, player disconnect mid-round, host disconnect
- [ ] Controls: verify joystick feel on different phone sizes
- [ ] Audio: verify positional sound works, volume levels balanced

### Phase 6 Definition of Done
- [ ] All 13 sound effects play at correct triggers
- [ ] Background music loops
- [ ] Volume slider works
- [ ] Visual polish effects present (muzzle flash, particles, screen shake)
- [ ] Stable 60fps on mid-range Android (test on real device)
- [ ] APK builds and installs cleanly
- [ ] 8-player LAN test passed
- [ ] All playtesting checklist items verified

---

## Quick Reference: Key Godot 4 APIs

| Need | Godot API |
|------|-----------|
| Networking | `ENetMultiplayerPeer`, `MultiplayerSpawner`, `MultiplayerSynchronizer` |
| RPCs | `@rpc("any_peer", "reliable"/"unreliable")` |
| Physics body | `CharacterBody2D` + `move_and_slide()` |
| Ragdoll | `RigidBody2D` + `PinJoint2D` |
| Hit detection | `RayCast2D` (hitscan), `Area2D` (blast radius, pickups) |
| Drawing | `_draw()` + `draw_line()`, `draw_arc()`, `draw_circle()` |
| Particles | `GPUParticles2D` or custom `_draw()` |
| Audio | `AudioStreamPlayer`, `AudioStreamPlayer2D`, `AudioBusLayout` |
| Camera | `Camera2D` with smoothing + limits |
| Random | `RandomNumberGenerator` with explicit seed |
| Scene mgmt | `SceneTree.change_scene_to_packed()`, `add_child()` |
| Timers | `Timer` node or `get_tree().create_timer()` |
| Touch input | `InputEventScreenTouch`, `InputEventScreenDrag` |

---

## Post-Launch Ideas (Future Versions)

Explicitly NOT in v1 but worth noting:

1. **Destructible terrain** — walls that break when shot
2. **More weapons** — rocket launcher, melee knife, mine
3. **Power-ups** — speed boost, shield, double damage
4. **Stickman hats** — cosmetic line-art accessories
5. **Online multiplayer** — WebSocket relay server for internet play
6. **AI bots** — fill empty slots with computer players
7. **Team mode** — 4v4
8. **Map editor** — let host draw custom terrain
9. **Replay/killcam** — record and playback
10. **Leaderboard** — persistent stats across sessions (local SQLite)
