extends Node

# AudioManager — centralized sound playback
# TODO Phase 1+: wire up AudioStreamPlayer pool for SFX
# TODO Phase 2: add background music with looping
# TODO Phase 2: expose volume controls for SFX and music buses

func _ready() -> void:
	pass


func play_sfx(_sound_name: String) -> void:
	# TODO: look up AudioStream by name from a preloaded dictionary and play it
	pass


func play_music(_track_name: String) -> void:
	# TODO: play looping background music track
	pass


func stop_music() -> void:
	# TODO: stop currently playing music
	pass
