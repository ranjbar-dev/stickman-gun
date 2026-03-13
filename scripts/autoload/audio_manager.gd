extends Node

# AudioManager — centralized audio playback for all SFX and music.
# Pool of AudioStreamPlayer2D nodes for positional sounds; single flat
# AudioStreamPlayer for UI/non-positional sounds; two music players for
# seamless crossfading. Registered as autoload "AudioManager".
# Design ref: STICKFIGHT_IMPLEMENTATION_PLAN.md §6.1

const SFX_POOL_SIZE: int = 16
const MUSIC_CROSSFADE_DURATION: float = 0.5

var _sfx_streams: Dictionary = {}    # String → AudioStream
var _music_streams: Dictionary = {}  # String → AudioStream

var _sfx_pool: Array[AudioStreamPlayer2D] = []
var _ui_player: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _music_next: AudioStreamPlayer

# Round-robin index into the pool.
var _pool_index: int = 0


func _ready() -> void:
	_build_sfx_pool()
	_build_music_players()
	_preload_streams()


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

# Play a sound by name. Pass position and positional=true for spatial audio
# (AudioStreamPlayer2D). Non-positional sounds (UI events) pass positional=false.
func play_sfx(sfx_name: String, position: Vector2 = Vector2.ZERO, positional: bool = true) -> void:
	var stream: AudioStream = _sfx_streams.get(sfx_name)
	if stream == null:
		return

	if positional:
		var player: AudioStreamPlayer2D = _get_pool_player()
		player.stream = stream
		player.global_position = position
		player.play()
	else:
		_ui_player.stream = stream
		_ui_player.play()


# Start a music track by name. No-op if the track is already playing.
# Crossfades from the current track to the new one.
func play_music(track_name: String) -> void:
	var stream: AudioStream = _music_streams.get(track_name)
	if stream == null:
		return
	if _music_current.playing and _music_current.stream == stream:
		return

	_music_next.stream = stream
	_music_next.volume_db = -80.0
	_music_next.play()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_music_current, "volume_db", -80.0, MUSIC_CROSSFADE_DURATION)
	tween.tween_property(_music_next, "volume_db", 0.0, MUSIC_CROSSFADE_DURATION)
	tween.chain().tween_callback(_swap_music_players)


func stop_music() -> void:
	_music_current.stop()
	_music_next.stop()


# Set master output volume. value is linear 0.0–1.0; silence below 0.001.
func set_master_volume(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	var db: float = -80.0 if clamped < 0.001 else linear_to_db(clamped)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)


# ------------------------------------------------------------------
# Setup helpers
# ------------------------------------------------------------------

func _build_sfx_pool() -> void:
	for i: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer2D.new()
		player.bus = "SFX"
		player.max_distance = 1200.0
		add_child(player)
		_sfx_pool.append(player)


func _build_music_players() -> void:
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "SFX"
	add_child(_ui_player)

	_music_current = AudioStreamPlayer.new()
	_music_current.bus = "Music"
	add_child(_music_current)

	_music_next = AudioStreamPlayer.new()
	_music_next.bus = "Music"
	_music_next.volume_db = -80.0
	add_child(_music_next)


func _preload_streams() -> void:
	var sfx_names: Array[String] = [
		"pistol_shot", "sniper_shot", "shotgun_blast",
		"grenade_throw", "explosion",
		"hit_marker", "headshot", "death",
		"weapon_pickup", "jump",
		"countdown_beep", "round_start", "victory",
	]
	for sfx_name: String in sfx_names:
		var path: String = "res://assets/audio/sfx/%s.ogg" % sfx_name
		if ResourceLoader.exists(path):
			_sfx_streams[sfx_name] = load(path)
		else:
			push_warning("AudioManager: missing SFX '%s' at %s" % [sfx_name, path])

	var music_names: Array[String] = ["theme"]
	for music_name: String in music_names:
		var path: String = "res://assets/audio/music/%s.ogg" % music_name
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			# Enable seamless looping without relying on editor import settings.
			if stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
			_music_streams[music_name] = stream
		else:
			push_warning("AudioManager: missing music '%s' at %s" % [music_name, path])


# ------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------

# Returns the next available pool player. Prefers idle slots; falls back to
# stealing the current round-robin head when all 16 are busy.
func _get_pool_player() -> AudioStreamPlayer2D:
	for i: int in SFX_POOL_SIZE:
		var idx: int = (_pool_index + i) % SFX_POOL_SIZE
		if not _sfx_pool[idx].playing:
			_pool_index = (idx + 1) % SFX_POOL_SIZE
			return _sfx_pool[idx]
	# All busy — steal oldest.
	var stolen: AudioStreamPlayer2D = _sfx_pool[_pool_index]
	_pool_index = (_pool_index + 1) % SFX_POOL_SIZE
	return stolen


func _swap_music_players() -> void:
	_music_current.stop()
	_music_current.volume_db = 0.0
	var tmp: AudioStreamPlayer = _music_current
	_music_current = _music_next
	_music_next = tmp
	_music_next.volume_db = -80.0
