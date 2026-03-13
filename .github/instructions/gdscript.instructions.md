---
applyTo: "**/*.gd"
---

# GDScript Conventions

## Script Structure (in this order)

1. `class_name` declaration (if reusable)
2. `extends` statement
3. Signals
4. Enums
5. Constants
6. `@export` variables
7. `@onready` variables
8. Regular variables
9. `_ready()`
10. `_process(delta)`
11. `_physics_process(delta)`
12. `_draw()`
13. `_input(event)` / `_unhandled_input(event)`
14. Public methods
15. Private methods (prefixed with `_`)

## Type Hints

Always use explicit type hints:

```gdscript
# Good
var speed: float = 200.0
var player_color: Color = Color.RED
var is_alive: bool = true

func take_damage(amount: int, is_headshot: bool) -> void:
    pass

func get_health() -> int:
    return health
```

## Signals

Declare signals with typed parameters:

```gdscript
signal died(kill_force: Vector2)
signal health_changed(new_health: int)
signal weapon_picked_up(weapon_type: String)
```

## Node References

Use @onready, never get_node() with string paths:

```gdscript
# Good
@onready var head_hitbox: Area2D = %HeadHitbox
@onready var body_hitbox: Area2D = %BodyHitbox

# Bad
var head_hitbox = get_node("HeadHitbox")
```

## Multiplayer RPCs

Use Godot 4 RPC syntax:

```gdscript
# Client to host (input)
@rpc("any_peer", "unreliable")
func send_input(input_data: Dictionary) -> void:
    pass

# Host to clients (state)
@rpc("authority", "unreliable")
func sync_state(state: Dictionary) -> void:
    pass

# Host to clients (events)
@rpc("authority", "reliable")
func on_player_killed(player_id: int, killer_id: int, force: Vector2) -> void:
    pass
```

## Drawing (Line-Art Style)

All visuals use _draw() with configurable line width:

```gdscript
const LINE_WIDTH: float = 2.0

func _draw() -> void:
    draw_arc(head_pos, 12.0, 0.0, TAU, 32, player_color, LINE_WIDTH)
    draw_line(shoulder, hip, player_color, LINE_WIDTH)
```

## Physics

- Use CharacterBody2D + move_and_slide() for player movement
- Use RigidBody2D + PinJoint2D for ragdoll segments
- Use RayCast2D for hitscan weapons
- Use Area2D for hitboxes, pickups, blast radius, death zone
