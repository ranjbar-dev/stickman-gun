# StickFight LAN — Godot 4 Android Game

## Project Overview

A simple 2D multiplayer stickman shooter for Android. Up to 8 players fight in free-for-all deathmatch on the same local WiFi network. Minimalist line-art style — stick figures and weapons are drawn with simple lines. Built with Godot 4 and GDScript.

## Source of Truth

Two design documents define every aspect of this game. Read them before implementing anything:

- `STICKFIGHT_GAME_DESIGN.md` — Complete game design: gameplay, weapons, terrain, networking, HUD, audio, UI flow, project structure
- `STICKFIGHT_IMPLEMENTATION_PLAN.md` — 6-phase build plan with task breakdowns, code snippets, and definition-of-done checklists

If there is ever a conflict between these documents and your assumptions, the documents win.

## Technology

- **Engine:** Godot 4.x
- **Language:** GDScript exclusively. No C#, no C++, no GDExtension.
- **Target:** Android, landscape orientation, 1920×1080 base resolution
- **Networking:** Godot's built-in `ENetMultiplayerPeer` (authoritative host model)

## Coding Standards

### GDScript Style

- Type hints on ALL function parameters and return types
- Type hints on ALL variable declarations where the type is not obvious from assignment
- `snake_case` for files, variables, functions, signals
- `PascalCase` for class names and node names
- `SCREAMING_SNAKE_CASE` for constants
- Use `@export` for values that should be tunable in the editor
- Use `@onready` for node references instead of `get_node()` in `_ready()`
- Prefer signals over direct method calls for decoupling between systems
- Use `class_name` declarations for reusable classes

### Script Organization

- Keep scripts under 300 lines. Split into components if longer.
- Group code in this order: `class_name`, `extends`, signals, enums, constants, `@export` vars, `@onready` vars, regular vars, `_ready()`, `_process()`, `_physics_process()`, `_draw()`, public methods, private methods (prefix with `_`)
- Write comments explaining WHY, not WHAT

### Scene Organization

- Each scene should be self-contained and testable independently
- Group related nodes under descriptive parent nodes
- Use meaningful node names that describe purpose, not type

### File Organization

Follow the project structure defined in Section 12 of STICKFIGHT_GAME_DESIGN.md:

```
stickfight_lan/
├── project.godot
├── assets/audio/sfx/          # .ogg sound effects
├── assets/audio/music/        # .ogg background music
├── assets/fonts/              # font resources
├── scenes/main_menu/          # main menu scene
├── scenes/lobby/              # lobby + color picker scenes
├── scenes/game/               # game world, terrain, weapon spawns
├── scenes/player/             # stickman, ragdoll, weapon holder
├── scenes/weapons/            # weapon scenes + pickup scene
├── scenes/projectiles/        # grenade projectile
├── scenes/hud/                # game HUD, virtual joystick, spectator HUD
├── scenes/ui/                 # round end, match end overlays
├── scripts/autoload/          # GameManager, NetworkManager, AudioManager
├── scripts/player/            # stickman controller, renderer, ragdoll, hitbox
├── scripts/weapons/           # weapon base, hitscan, grenade, pickup
├── scripts/terrain/           # terrain generator, spawn calculator
├── scripts/network/           # input sync, state sync, event RPCs
├── scripts/hud/               # joystick logic, spectator camera
└── addons/                    # QR code addon
```

## Build Phases

The project is built in 6 phases. Always check the implementation plan for the current phase. Never skip ahead.

1. **Phase 1:** Single stickman prototype (movement, joystick, pistol, camera)
2. **Phase 2:** Full weapons and combat (all 4 weapons, health, ragdoll, pickups)
3. **Phase 3:** Procedural terrain (seed-based generation, spawn points)
4. **Phase 4:** Networking (ENet, QR join, lobby, state sync, RPCs)
5. **Phase 5:** Game flow and UI (state machine, menus, scoreboard, spectator)
6. **Phase 6:** Audio and polish (SFX, music, particles, Android export)

## Implementation Rules

1. Before implementing any feature, read the relevant section of both design documents
2. Implement one task at a time. Do not batch multiple unrelated changes.
3. After each task, verify it works before proceeding to the next
4. Follow the exact weapon stats, movement constants, and other values from the design doc
5. Use the networking architecture exactly as described: authoritative host, clients send inputs only, host broadcasts state at 20-30Hz
6. All terrain generation must be deterministic from a seed using `RandomNumberGenerator`
7. All multiplayer state changes go through the host. Clients never modify game state directly.
8. Use `@rpc("any_peer", "unreliable")` for input sync, `@rpc("authority", "unreliable")` for state sync, `@rpc("authority", "reliable")` for game events
9. Ragdoll physics are cosmetic only — synced via kill force vector, minor drift between clients is acceptable
10. Sound is played locally on clients based on event RPCs from host — no audio streaming over network

## Testing Expectations

- Every scene should be runnable independently for testing
- Movement values (WALK_SPEED=200, JUMP_VELOCITY=-400, GRAVITY=980) are starting points — flag if they feel wrong
- Weapon balance values are in Section 5 of the design doc — implement exactly as specified
- Terrain generation: same seed must always produce identical results
- Networking: test with at least 2 clients on the same network before marking complete

## What NOT To Do

- Do not add features not in the design document
- Do not use C# or any language other than GDScript
- Do not use Godot 3 APIs — this is Godot 4 only
- Do not add online/internet multiplayer — this is LAN only
- Do not add AI bots, player accounts, progression, or monetization
- Do not use `@tool` scripts unless specifically needed for editor tooling
- Do not create separate .gd files for trivial helper functions — keep related logic together
- Do not use `await get_tree().process_frame` as a sync mechanism in multiplayer code
