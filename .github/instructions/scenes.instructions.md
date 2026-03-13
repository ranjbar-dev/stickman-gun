---
applyTo: "**/*.tscn"
---

# Godot Scene Conventions

## Node Naming

- Use PascalCase for all node names
- Name nodes by purpose, not type: `HeadHitbox` not `Area2D`, `WeaponArm` not `Node2D3`
- Use unique name access (%) for nodes referenced from scripts

## Scene Organization

- Group related nodes under descriptive parents
- Collision shapes must be children of their physics body
- Keep scene trees shallow — avoid deep nesting beyond 4 levels
- Each scene should be independently testable

## Physics Layers

Use consistent collision layers across the project:

- Layer 1: Terrain/ground (StaticBody2D)
- Layer 2: Players (CharacterBody2D)
- Layer 3: Hitboxes — head (Area2D)
- Layer 4: Hitboxes — body (Area2D)
- Layer 5: Weapon pickups (Area2D)
- Layer 6: Projectiles (RigidBody2D / Area2D)
- Layer 7: Death zone (Area2D)
- Layer 8: Ragdoll segments (RigidBody2D)

## Common Scene Patterns

### Player stickman (CharacterBody2D)
- CollisionShape2D (capsule, adjusts for crouch)
- HeadHitbox (Area2D + CircleShape2D)
- BodyHitbox (Area2D + CapsuleShape2D)
- WeaponHolder (Node2D, rotates with aim)
- StickmanRenderer (Node2D, handles _draw())

### Weapon pickup (Area2D)
- CollisionShape2D (trigger zone)
- Visual indicator (Node2D with _draw())

### Ragdoll (Node2D container)
- Head (RigidBody2D)
- Torso (RigidBody2D)
- UpperArmL/R, ForearmL/R, UpperLegL/R, LowerLegL/R (RigidBody2D each)
- PinJoint2D connections between segments
