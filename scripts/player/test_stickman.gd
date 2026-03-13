extends Node2D

@onready var _stickman: StickmanRenderer = $StickmanNode
@onready var _aim_slider: HSlider = $UI/Panel/VBoxContainer/AimRow/AimSlider
@onready var _aim_label: Label = $UI/Panel/VBoxContainer/AimRow/AimValueLabel
@onready var _crouch_button: CheckButton = $UI/Panel/VBoxContainer/CrouchRow/CrouchButton


func _ready() -> void:
	_aim_slider.value_changed.connect(_on_aim_changed)
	_crouch_button.toggled.connect(_on_crouch_toggled)
	_on_aim_changed(_aim_slider.value)


func _on_aim_changed(value: float) -> void:
	_stickman.aim_angle = value
	_aim_label.text = "%.2f rad" % value


func _on_crouch_toggled(pressed: bool) -> void:
	_stickman.is_crouching = pressed
