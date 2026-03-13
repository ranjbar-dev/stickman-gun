# StickFight LAN — Game Design Document

**Version:** 1.0
**Date:** March 13, 2026
**Engine:** Godot 4 (GDScript)
**Platform:** Android (Landscape)

---

## 1. Overview

StickFight LAN is a simple 2D multiplayer stickman shooter for Android. Up to 8 players on the same local network fight in free-for-all deathmatch rounds on procedurally generated terrain. The art style is pure minimalism — stick figures and weapons drawn with simple lines. One player hosts the game; others join by scanning a QR code.

---

## 2. Core Gameplay Loop

1. Host creates a game, configures round count (1–10)
2. Players join via QR code scan, pick a color from 8 options
3. Each round: new terrain is generated, players spawn, 3-second countdown, then fight
4. Last stickman standing wins the round
5. After all rounds, final scoreboard shows the match winner
6. Players can rematch or quit

---

## 3. Player Character — The Stickman

### 3.1 Visual Design

All drawn programmatically using Godot's `_draw()` method in the player's chosen color:

- **Head:** Small circle (`draw_arc`), ~12px radius
- **Body:** Single vertical line from head base to hip point
- **Arms:** Two segments per arm (upper arm + forearm) with elbow joint. Weapon arm rotates to follow aim direction
- **Legs:** Two segments per leg (upper leg + lower leg) with knee joint
- **Weapon:** Line extending from the hand point of the aiming arm

### 3.2 Color Selection

8 preset colors available in lobby:

1. Red
2. Blue
3. Green
4. Yellow
5. Orange
6. Purple
7. Cyan
8. Pink

Players tap a color swatch to claim it. Taken colors are dimmed/crossed out. First come, first served.

### 3.3 Physics & Collision

- **Alive state:** `CharacterBody2D` with a capsule `CollisionShape2D`
  - Handles walk, jump, crouch with `move_and_slide()`
  - Responsive, snappy movement — no floaty physics while alive
- **Dead state:** Transitions to ragdoll — a set of `RigidBody2D` segments:
  - Head, torso, upper arms (×2), forearms (×2), upper legs (×2), lower legs (×2)
  - Connected by `PinJoint2D` or `DampedSpringJoint2D`
  - Killing hit applies an impulse in the bullet's direction for dramatic ragdoll effect
  - Ragdoll is cosmetic only — no gameplay interaction after death

### 3.4 Hitboxes

- **Head hitbox:** Small `CollisionShape2D` (circle) on the head node — headshot = instant kill
- **Body hitbox:** Larger `CollisionShape2D` (capsule) covering torso and limbs — body shot = 1 damage point
- Hit detection checks head hitbox first (higher priority)

### 3.5 Health

- **3 hit points** for body shots
- **Headshot from any weapon = instant kill** regardless of remaining HP
- No health regeneration, no health pickups

---

## 4. Movement

### 4.1 Actions

| Action | Input | Behavior |
|--------|-------|----------|
| Walk left/right | Left joystick horizontal | Constant speed, immediate response |
| Jump | Dedicated button (near left joystick) | Fixed jump height, single jump only (no double jump) |
| Crouch | Left joystick pull down | Reduces collision shape height, lowers head hitbox, slows movement speed by ~50% |

### 4.2 Movement Parameters (Tunable Constants)

```
WALK_SPEED        = 200 px/s
CROUCH_SPEED      = 100 px/s
JUMP_VELOCITY     = -400 px/s (upward)
GRAVITY           = 980 px/s²
```

These values are starting points — will need playtesting to feel right.

---

## 5. Weapons System

### 5.1 Weapon Stats

| Weapon | Fire Rate | Damage | Range | Ammo | Projectile Type |
|--------|-----------|--------|-------|------|-----------------|
| Pistol | 3 shots/sec | 1 HP | Medium (~60% screen) | Unlimited | Hitscan, thin line trace |
| Sniper | 0.8 shots/sec | 2 HP | Full map | 5 rounds | Hitscan, visible tracer line lingers ~0.3s |
| Shotgun | 1.5 shots/sec | 1 HP per pellet | Short (~25% screen) | 8 shells | 5 pellets, spread cone ~30°, each is short-range hitscan |
| Grenade | 0.5 throws/sec | 2 HP | Medium (arc) | 3 grenades | Physics `RigidBody2D`, gravity-affected arc, bounces, explodes after 2s fuse or direct hit, blast radius ~80px |

### 5.2 Weapon Carrying Rules

- Player always has the pistol (cannot be dropped)
- Player can carry one additional weapon (sniper, shotgun, or grenade)
- Walking over a weapon pickup swaps the current non-pistol weapon
- Dropped weapon stays on ground with its remaining ammo for others to grab
- Swap between pistol and secondary weapon via a dedicated button

### 5.3 Weapon Pickups on Map

- 3–5 weapon spawn points generated as part of terrain generation
- Spawn points are placed on valid ground/platform surfaces, away from player spawn points
- Weapons appear 2 seconds after round starts (prevents instant grab kills)
- Each spawn point randomly selects: sniper, shotgun, or grenade
- Visual indicator: small blinking line drawing of the weapon hovering at the spawn point

### 5.4 Grenade Special Behavior

- Right joystick direction = throw angle
- Joystick pull distance = throw force (subtle trajectory preview arc shown as dotted line)
- Grenade bounces off terrain 1–2 times
- Explodes on 2-second fuse OR on direct player contact
- Blast radius damages anyone nearby including the thrower (self-damage possible)

### 5.5 Hitscan Implementation

- For pistol, sniper, and shotgun: on fire, cast a `RayCast2D` from the weapon tip in the aim direction
- Check ray intersection with head hitbox first, then body hitbox
- Sniper ray extends full map width; pistol and shotgun rays have distance limits
- Shotgun fires 5 rays within a random spread cone

---

## 6. Procedural Terrain Generation

### 6.1 Generation Method

All terrain is generated from a single integer seed. Host generates the seed, broadcasts to all clients. Deterministic generation ensures identical maps.

### 6.2 Terrain Components

- **Ground layer:** Baseline floor spanning full map width. Generated by placing 8–12 random height points across the width and connecting them with straight line segments. Height variation: ±15% of screen height. Creates jagged, uneven ground.
- **Platforms:** 4–8 floating horizontal line segments placed above the ground. Random width (100–250px), random height placement. Minimum vertical gap ensures jumpability. Minimum horizontal spacing prevents overlap.
- **Cover walls:** 2–4 short vertical line segments (50–100px tall) placed on ground or platforms. Provides crouch-behind cover.
- **Boundaries:** Invisible walls at left and right map edges. Death zone below the lowest ground point (falling off = instant death + ragdoll falling into void).

### 6.3 Map Dimensions

- Width: ~3–4× screen width (scrolling map)
- Height: ~2× screen height
- Camera follows the local player's stickman with smooth lerp

### 6.4 Spawn Points

- 8 spawn positions pre-calculated on valid surfaces
- Spread evenly across map width (divide map into 8 horizontal zones, place one spawn per zone)
- Minimum distance between any two spawns: ~300px
- Players spawn facing center of map

### 6.5 Visual Style

- All terrain drawn as white/light lines on a dark background
- Lines have a slight thickness (2–3px) matching the stickman line weight
- Ground fill below the ground line with a slightly lighter shade (optional, adds visual grounding)

---

## 7. Networking

### 7.1 Architecture: Authoritative Host

- One player's phone acts as both game server and client
- Host runs ALL game logic: physics, hit detection, damage, death, weapon spawns, round state
- Clients are thin: they send inputs and receive game state to render
- Uses Godot 4's `ENetMultiplayerPeer` over UDP

### 7.2 Connection Flow

```
1. Host taps "Host Game"
2. Godot creates ENetMultiplayerPeer server on port 7777
3. App detects phone's local IP (e.g. 192.168.1.42)
4. QR code is generated encoding: "stickfight://192.168.1.42:7777"
5. Joining player taps "Join Game" → camera opens
6. Scans QR → app parses IP + port
7. Godot creates ENetMultiplayerPeer client, connects to host
8. On connection success → player appears in lobby
9. Player picks color, host updates lobby state for all
10. Host taps "Start" → match begins
```

### 7.3 QR Code Generation

- Use a GDScript QR code library (e.g. `gdqrcode` addon) or generate QR as an image texture
- QR displayed prominently on the lobby screen
- Fallback: also display the IP:port as text for manual entry if camera fails

### 7.4 Data Synchronization

**Client → Host (input only):**
```
{
  move_direction: float,     # -1.0 to 1.0 (left joystick X)
  is_crouching: bool,        # left joystick pulled down
  is_jumping: bool,          # jump button pressed
  aim_angle: float,          # right joystick angle in radians
  is_firing: bool,           # right joystick held
  swap_weapon: bool          # weapon swap button pressed
}
```
Sent every frame (~60fps). Small payload, ~20 bytes per packet.

**Host → All Clients (game state):**
```
Per player (×8 max):
{
  player_id: int,
  position: Vector2,
  velocity: Vector2,
  aim_angle: float,
  is_crouching: bool,
  is_grounded: bool,
  health: int,
  active_weapon: enum,
  ammo_count: int,
  is_alive: bool
}
```
Sent at 20–30 Hz (tick rate). ~50 bytes per player × 8 = ~400 bytes per tick. Trivial on LAN.

**Host → All Clients (events via RPC):**
- `player_hit(player_id, damage, hit_position, is_headshot)`
- `player_killed(player_id, killer_id, kill_force_vector)`
- `weapon_picked_up(player_id, weapon_type, spawn_point_id)`
- `weapon_dropped(player_id, weapon_type, position, remaining_ammo)`
- `round_start(terrain_seed, spawn_positions, weapon_spawn_data)`
- `round_end(winner_id, scores_dict)`
- `match_end(final_scores_dict)`

### 7.5 Client-Side Interpolation

- Clients buffer the two most recent state updates from host
- Render at a position interpolated between them (adds ~33–50ms visual delay)
- On LAN this is imperceptible but makes movement look smooth

### 7.6 Disconnection Handling

| Scenario | Behavior |
|----------|----------|
| Non-host player disconnects mid-round | Their stickman dies (ragdoll), removed from match |
| Non-host player disconnects in lobby | Removed from player list, their color freed |
| Host disconnects | All clients shown "Host disconnected" message, returned to main menu |
| Player tries to join a full game (8 players) | Shown "Game is full" message |

---

## 8. HUD & Controls Layout

### 8.1 In-Game HUD (Landscape)

```
┌─────────────────────────────────────────────────────┐
│ [♥♥♥]              Round 2/5 • 4 alive    [🔫 ×5] │
│                                                     │
│                                                     │
│                     GAME WORLD                      │
│                                                     │
│                                                     │
│   [JUMP]                                  [SWAP]   │
│      (◉)                                   (◉)     │
│   MOVE JOY                              AIM JOY    │
└─────────────────────────────────────────────────────┘
```

- **Top-left:** 3 health dots (filled = alive, empty = lost)
- **Top-center:** Round number and alive player count
- **Top-right:** Current weapon line-art icon + ammo count
- **Bottom-left:** Movement joystick (virtual, transparent, thumb-sized ~120px)
- **Above move joystick:** Jump button
- **Bottom-right:** Aim joystick (virtual, transparent, thumb-sized ~120px). Hold to aim + auto-fire
- **Near aim joystick:** Weapon swap button

### 8.2 Joystick Behavior

- Both joysticks are floating: they appear where the thumb touches within their designated screen half
- Dead zone: ~15% of joystick radius before registering input
- Visual: semi-transparent circle with inner dot showing direction
- Right joystick auto-fires while held. Release to stop firing

### 8.3 Spectator Mode

- On death, HUD joysticks and buttons disappear
- Left/right arrow buttons appear at screen edges to cycle between alive players
- Top label: "Spectating: [color name]"
- Camera smoothly transitions to followed player

### 8.4 Grenade Aim Overlay

- When grenade is the active weapon, holding the aim joystick shows a dotted arc line previewing the throw trajectory
- Arc updates in real-time as the player adjusts aim angle and force

---

## 9. Screens & UI Flow

### 9.1 Main Menu

```
┌─────────────────────────┐
│                         │
│     STICKFIGHT LAN      │
│     (line-art logo)     │
│                         │
│     [ HOST GAME ]       │
│     [ JOIN GAME ]       │
│     [ SETTINGS  ]       │
│                         │
└─────────────────────────┘
```

- Minimalist line-art title
- Three buttons: Host, Join, Settings
- Settings: master volume slider only (v1)

### 9.2 Lobby — Host View

```
┌──────────────────────────────────────────┐
│  LOBBY (Host)                            │
│                                          │
│  ┌────────┐   Players:                   │
│  │ QR     │   ● Red (Host)              │
│  │ CODE   │   ● Blue                     │
│  │        │   ● Green                    │
│  └────────┘   ○ (waiting...)             │
│               ○ (waiting...)             │
│  IP: 192.168.1.42:7777                   │
│                                          │
│  Rounds: [◄] 5 [►]                      │
│                                          │
│  [ START GAME ]  (enabled when 2+ join)  │
└──────────────────────────────────────────┘
```

### 9.3 Lobby — Joining Player View

```
┌──────────────────────────────────────────┐
│  LOBBY                                   │
│                                          │
│  Pick your color:                        │
│  [🔴][🔵][🟢][🟡][🟠][🟣][🔵][🩷]     │
│                                          │
│  Players:                                │
│  ● Red (Host)                            │
│  ● Blue ← YOU                            │
│  ● Green                                 │
│  ○ (waiting...)                          │
│                                          │
│  Waiting for host to start...            │
└──────────────────────────────────────────┘
```

### 9.4 Round End Overlay

```
┌─────────────────────────┐
│                         │
│   ROUND 2 WINNER:       │
│   🔵 Blue               │
│                         │
│   Red: 1 win            │
│   Blue: 1 win           │
│   Green: 0 wins         │
│                         │
│   Next round in 5...    │
└─────────────────────────┘
```

### 9.5 Match End Screen

```
┌─────────────────────────────┐
│                             │
│   MATCH OVER!               │
│                             │
│   🏆 Blue wins! (3 rounds) │
│                             │
│   Player  Rounds  Kills  HS │
│   Blue      3      12    4  │
│   Red       2       9    2  │
│   Green     0       5    1  │
│                             │
│   [ REMATCH ]  [ QUIT ]    │
└─────────────────────────────┘
```

---

## 10. Audio

### 10.1 Sound Effects

| Sound | Trigger | Type | Positional |
|-------|---------|------|------------|
| Pistol shot | Pistol fires | Short pop | Yes (`AudioStreamPlayer2D`) |
| Sniper shot | Sniper fires | Loud crack + echo | Yes |
| Shotgun blast | Shotgun fires | Punchy boom | Yes |
| Grenade throw | Grenade launched | Whoosh | Yes |
| Explosion | Grenade detonates | Bass thump | Yes |
| Hit marker | Your bullet hits a player | Quick thud | No (UI feedback) |
| Headshot | Headshot scored | High-pitched ping | No (UI feedback) |
| Death | Player killed | Short crunch | Yes |
| Weapon pickup | Player grabs weapon | Metallic click | Yes |
| Jump | Player jumps | Subtle light sound | No |
| Countdown beep | 3-2-1 countdown | Beep tone | No |
| Round start | FIGHT! | Horn/buzz | No |
| Victory | Round/match won | Short jingle | No |

### 10.2 Background Music

- Single looping track: lo-fi or chiptune style
- Low volume, not distracting
- Optional: slight fade during final-two-alive for tension

### 10.3 Audio Format

- All audio files in `.ogg` format (Godot preferred)
- Positional sounds use `AudioStreamPlayer2D` (volume scales with distance from player's stickman)
- UI/music sounds use `AudioStreamPlayer` (non-positional)
- Master volume slider in settings

---

## 11. Game State Machine

```
MAIN_MENU
  │
  ├── Host Game ──► LOBBY (as host)
  │                   │
  └── Join Game ──► LOBBY (as client)
                      │
                      ▼
                 ROUND_START (3s countdown)
                      │
                      ▼
                 ROUND_ACTIVE
                      │
                      ├── Last player standing ──► ROUND_END (5s)
                      │                              │
                      │                              ├── More rounds left ──► ROUND_START
                      │                              │
                      │                              └── All rounds done ──► MATCH_END
                      │
                      └── Host disconnects ──► MAIN_MENU (all clients)
                                                  │
                                              MATCH_END
                                                  │
                                                  ├── Rematch ──► LOBBY
                                                  └── Quit ──► MAIN_MENU
```

### 11.1 State Details

| State | Duration | What Happens |
|-------|----------|-------------|
| MAIN_MENU | Until player action | Entry point. Host/Join/Settings |
| LOBBY | Until host starts | QR code shown, players join, pick colors, host sets rounds |
| ROUND_START | 3 seconds | Terrain generated from seed, players spawn frozen, countdown 3-2-1-FIGHT, weapons appear at 2s |
| ROUND_ACTIVE | Until 1 player left | Full gameplay. Host processes all logic. Draw if last two kill each other simultaneously |
| ROUND_END | 5 seconds | Winner shown, scoreboard overlay, auto-advance |
| MATCH_END | Until player action | Final scoreboard with stats. Rematch or quit |

---

## 12. Godot 4 Project Structure

```
stickfight_lan/
├── project.godot
├── assets/
│   ├── audio/
│   │   ├── sfx/
│   │   │   ├── pistol_shot.ogg
│   │   │   ├── sniper_shot.ogg
│   │   │   ├── shotgun_blast.ogg
│   │   │   ├── grenade_throw.ogg
│   │   │   ├── explosion.ogg
│   │   │   ├── hit_marker.ogg
│   │   │   ├── headshot.ogg
│   │   │   ├── death.ogg
│   │   │   ├── weapon_pickup.ogg
│   │   │   ├── jump.ogg
│   │   │   ├── countdown_beep.ogg
│   │   │   ├── round_start.ogg
│   │   │   └── victory.ogg
│   │   └── music/
│   │       └── bg_loop.ogg
│   └── fonts/
│       └── default_font.tres
├── scenes/
│   ├── main_menu/
│   │   └── main_menu.tscn
│   ├── lobby/
│   │   ├── lobby.tscn
│   │   └── color_picker.tscn
│   ├── game/
│   │   ├── game_world.tscn
│   │   ├── terrain_generator.tscn
│   │   └── weapon_spawn_point.tscn
│   ├── player/
│   │   ├── stickman.tscn
│   │   ├── ragdoll.tscn
│   │   └── weapon_holder.tscn
│   ├── weapons/
│   │   ├── pistol.tscn
│   │   ├── sniper.tscn
│   │   ├── shotgun.tscn
│   │   ├── grenade.tscn
│   │   └── weapon_pickup.tscn
│   ├── projectiles/
│   │   └── grenade_projectile.tscn
│   ├── hud/
│   │   ├── game_hud.tscn
│   │   ├── virtual_joystick.tscn
│   │   └── spectator_hud.tscn
│   └── ui/
│       ├── round_end.tscn
│       └── match_end.tscn
├── scripts/
│   ├── autoload/
│   │   ├── game_manager.gd        # Global state machine, round/match logic
│   │   ├── network_manager.gd     # ENet setup, connection handling, QR generation
│   │   └── audio_manager.gd       # Centralized sound playback
│   ├── player/
│   │   ├── stickman_controller.gd # Movement, input handling
│   │   ├── stickman_renderer.gd   # Line-art drawing
│   │   ├── ragdoll_spawner.gd     # Transition to ragdoll on death
│   │   └── hitbox_manager.gd      # Head vs body hit detection
│   ├── weapons/
│   │   ├── weapon_base.gd         # Base weapon class
│   │   ├── hitscan_weapon.gd      # Pistol, sniper, shotgun logic
│   │   ├── grenade_weapon.gd      # Grenade arc, fuse, explosion
│   │   └── weapon_pickup.gd       # Pickup interaction
│   ├── terrain/
│   │   ├── terrain_generator.gd   # Seed-based procedural generation
│   │   └── spawn_calculator.gd    # Player + weapon spawn placement
│   ├── network/
│   │   ├── input_sync.gd          # Client input → host
│   │   ├── state_sync.gd          # Host state → clients
│   │   └── event_rpc.gd           # Discrete event RPCs
│   └── hud/
│       ├── virtual_joystick.gd    # Floating joystick logic
│       └── spectator_camera.gd    # Cycle between alive players
└── addons/
    └── gdqrcode/                  # QR code generation addon
```

---

## 13. Implementation Priorities

Suggested build order, from core to polish:

### Phase 1 — Playable Single-Player Prototype
1. Stickman rendering (line-art draw)
2. Movement (walk, jump, crouch) with `CharacterBody2D`
3. Virtual joystick controls
4. Pistol weapon (hitscan raycast)
5. Basic terrain (hardcoded flat ground + a few platforms)
6. Health system + death (simple respawn for testing)

### Phase 2 — Full Weapons & Physics
7. Sniper, shotgun, grenade weapons
8. Weapon pickup system
9. Ragdoll death system
10. Headshot vs body hit detection
11. Grenade arc preview + physics projectile

### Phase 3 — Procedural Terrain
12. Seed-based terrain generator
13. Spawn point calculator
14. Weapon spawn point placement

### Phase 4 — Networking
15. ENet host/client setup
16. QR code generation + scanning
17. Lobby system (join, color pick, round config)
18. Input sync (client → host)
19. State sync (host → clients)
20. Event RPCs (hits, kills, pickups, round flow)
21. Client-side interpolation

### Phase 5 — Game Flow & UI
22. Full state machine (menu → lobby → rounds → match end)
23. Round start countdown
24. Round end scoreboard
25. Match end stats screen
26. Spectator mode
27. Disconnection handling

### Phase 6 — Audio & Polish
28. All sound effects
29. Background music
30. Settings screen (volume)
31. Playtesting & balance tuning

---

## 14. Assumptions

- **LAN only** — no internet multiplayer, no matchmaking servers
- **No player accounts or progression** — purely session-based
- **No AI bots** — only human players
- **No monetization** — personal/friends project
- **No destructible terrain** in v1 — can be added later
- **No pickups besides weapons** in v1
- **Android only** — no iOS or desktop builds planned initially
- **Minimum Android version:** API 24 (Android 7.0) — Godot 4 minimum
- **Minimum 2 players to start** — maximum 8

---

## 15. Decision Log

| # | Decision | Alternatives Considered | Reason |
|---|----------|------------------------|--------|
| 1 | Free-for-all deathmatch, last man standing | Team-based, respawn-based, battle royale | Simplest mode, works well with 2–8 players |
| 2 | Procedurally generated terrain | Flat arena, hand-designed maps | Keeps rounds fresh without manual design |
| 3 | Walk/jump/crouch movement | Adding wall climb, ladders | Three actions is enough depth |
| 4 | All 4 weapon types | Fewer weapons | Good variety, distinct roles |
| 5 | Pistol start + random map spawns | Loadout select, random assignment | Creates weapon scramble dynamic |
| 6 | Dual virtual joystick | Tap-to-aim, auto-aim, slingshot | Mobile shooter standard |
| 7 | One life, spectate on death | Respawns, limited lives | Maximizes tension |
| 8 | QR code join | Manual IP, auto-discovery | Zero-friction UX |
| 9 | Authoritative host | Peer-to-peer, dedicated server | Simplest, negligible LAN advantage |
| 10 | Landscape orientation | Portrait, both | Better view for side-scrolling arena |
| 11 | Godot 4 with GDScript | Unity, LibGDX, pure Android | Existing experience, fast iteration |
| 12 | Headshot instant kill, body 2–3 hits | HP bar, one-shot | Rewards skill |
| 13 | Limited ammo + unlimited pistol | All unlimited, magazine system | Resource tension without frustration |
| 14 | No pickups besides weapons | Health packs, power-ups | Minimal scope for v1 |
| 15 | Full ragdoll physics on death | No physics, basic only | Satisfying visual payoff |
| 16 | Static terrain | Destructible, hazards | Manageable scope for v1 |
| 17 | Configurable rounds 1–10 | Fixed round count | Host flexibility |
| 18 | Player picks from 8 colors | Random, custom colors | Simple, social |
| 19 | SFX + background music | Silent, SFX only | Adds polish |
| 20 | Terrain synced via seed | Full data sync | Minimal network traffic |

---

## 16. Future Considerations (Not in v1)

These are explicitly out of scope but could be added later:

- Destructible terrain
- More weapon types (rocket launcher, melee)
- Power-ups (speed boost, shield, double damage)
- Custom stickman accessories (hats, drawn with lines)
- Online multiplayer (relay server)
- AI bots for practice
- Team mode
- Map editor
- Replay system
- Killcam for spectators
