class_name HUD
extends CanvasLayer

# Root HUD scene node. Call setup(player) after both this node and the player
# are present in the scene tree to wire all sub-component signals.

@onready var _health_display: HealthDisplay = $HealthDisplay
@onready var _weapon_display: WeaponDisplay = $WeaponDisplay
@onready var _grenade_overlay: GrenadeOverlay = $GrenadeOverlay


func setup(player: StickmanController) -> void:
	var hitbox: HitboxManager = player.get_node("HitboxManager")
	var holder: WeaponHolder = player.get_node("WeaponHolder")
	_health_display.setup(hitbox)
	_weapon_display.setup(holder)
	_grenade_overlay.setup(holder)
