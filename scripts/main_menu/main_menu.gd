extends Node

# Main menu scene — entry point of the game.
# HOST GAME: creates LAN server and goes to lobby (lobby auto-detects active host).
# JOIN GAME:  sets pending_lobby_mode so lobby opens in join-panel mode.
# SETTINGS:   toggles an overlay with a master-volume slider.

@onready var _host_button: Button = $UI/ButtonContainer/HostButton
@onready var _join_button: Button = $UI/ButtonContainer/JoinButton
@onready var _settings_button: Button = $UI/ButtonContainer/SettingsButton
@onready var _settings_panel: Control = $UI/SettingsPanel
@onready var _volume_slider: HSlider = $UI/SettingsPanel/VBox/VolumeSlider
@onready var _settings_back: Button = $UI/SettingsPanel/VBox/BackButton
@onready var _status_label: Label = $UI/StatusLabel


func _ready() -> void:
	GameManager.current_state = GameManager.GameState.MAIN_MENU
	GameManager.pending_lobby_mode = ""
	_settings_panel.visible = false
	_status_label.text = ""

	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_back.pressed.connect(_on_settings_back_pressed)
	_volume_slider.value_changed.connect(_on_volume_changed)

	# Start background music on the main menu.
	AudioManager.play_music("theme")

	# Restore slider to current Master bus volume.
	var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	_volume_slider.value = db_to_linear(db) * 100.0


func _on_host_pressed() -> void:
	_status_label.text = "Starting server..."
	var err: Error = NetworkManager.create_server()
	if err != OK:
		_status_label.text = "Failed to start server (error %d)" % err
		return
	GameManager.current_state = GameManager.GameState.LOBBY
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")


func _on_join_pressed() -> void:
	GameManager.pending_lobby_mode = "join"
	get_tree().change_scene_to_file("res://scenes/lobby/lobby.tscn")


func _on_settings_pressed() -> void:
	_settings_panel.visible = true


func _on_settings_back_pressed() -> void:
	_settings_panel.visible = false


func _on_volume_changed(value: float) -> void:
	AudioManager.set_master_volume(value / 100.0)
