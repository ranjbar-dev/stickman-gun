# Copilot Instructions for StickFight LAN

This is a Godot 4 GDScript project. A 2D multiplayer stickman shooter for Android.

## Always Do

- Use GDScript with full type hints on all parameters, return types, and non-obvious variables
- Follow Godot 4 API conventions (CharacterBody2D, move_and_slide, @export, @onready, @rpc)
- Use signals for communication between decoupled systems
- Keep scripts under 300 lines
- Use snake_case for files/variables/functions, PascalCase for classes/nodes, SCREAMING_SNAKE_CASE for constants
- Read STICKFIGHT_GAME_DESIGN.md and STICKFIGHT_IMPLEMENTATION_PLAN.md for specifications
- Create self-contained, independently testable scenes
- Use draw_line(), draw_arc(), draw_circle() for all visuals — this is a line-art game, no sprites

## Never Do

- Do not use C#, GDExtension, or any language besides GDScript
- Do not use Godot 3 syntax (KinematicBody2D, move_and_collide patterns, etc.)
- Do not add features not specified in the design documents
- Do not use @tool scripts unless specifically required
- Do not hardcode values that should be @export or const
- Do not use get_node() with string paths — use @onready or unique name references (%)
