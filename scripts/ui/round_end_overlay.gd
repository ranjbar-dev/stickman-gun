class_name RoundEndOverlay
extends CanvasLayer

# Round end overlay — shown for 5 seconds over the game world.
# Displays: winner color + name, round number, running score tally,
# and a "Next round in N..." countdown.

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2, 1.0),   # 0 Red
	Color(0.2, 0.4, 0.9, 1.0),   # 1 Blue
	Color(0.2, 0.8, 0.2, 1.0),   # 2 Green
	Color(0.95, 0.9, 0.1, 1.0),  # 3 Yellow
	Color(0.95, 0.5, 0.1, 1.0),  # 4 Orange
	Color(0.6, 0.2, 0.9, 1.0),   # 5 Purple
	Color(0.1, 0.9, 0.9, 1.0),   # 6 Cyan
	Color(0.95, 0.4, 0.7, 1.0),  # 7 Pink
]
const COLOR_NAMES: Array[String] = [
	"Red", "Blue", "Green", "Yellow", "Orange", "Purple", "Cyan", "Pink",
]
const DISPLAY_SECONDS: int = 5

@onready var _winner_label: Label = $Background/VBox/WinnerLabel
@onready var _scores_container: VBoxContainer = $Background/VBox/ScoresContainer
@onready var _countdown_label: Label = $Background/VBox/CountdownLabel


func _ready() -> void:
	layer = 20


# Called by game.gd immediately after instantiation.
# round_data: GameManager.pending_round_data (has peer_ids + color_indices).
func setup(winner_id: int, scores: Dictionary, round_num: int, round_data: Dictionary) -> void:
	# Winner line
	var winner_color_name := _color_name_for_peer(winner_id, round_data)
	if winner_id != 0:
		_winner_label.text = "%s wins Round %d!" % [winner_color_name, round_num]
		_winner_label.add_theme_color_override("font_color",
			_color_for_peer(winner_id, round_data))
	else:
		_winner_label.text = "DRAW — No winner this round"
		_winner_label.remove_theme_color_override("font_color")

	# Score tally
	var peer_ids: Array = round_data.get("peer_ids", [])
	for pid_var: Variant in peer_ids:
		var pid: int = int(pid_var)
		var row := HBoxContainer.new()
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(28, 28)
		dot.color = _color_for_peer(pid, round_data)
		var lbl := Label.new()
		lbl.text = "  %s — %d win(s)" % [_color_name_for_peer(pid, round_data),
			scores.get(pid, 0)]
		lbl.add_theme_font_size_override("font_size", 32)
		row.add_child(dot)
		row.add_child(lbl)
		_scores_container.add_child(row)

	# Start countdown
	_run_countdown()


func _run_countdown() -> void:
	for i: int in range(DISPLAY_SECONDS, 0, -1):
		if not is_instance_valid(self):
			return
		_countdown_label.text = "Next round in %d..." % i
		await get_tree().create_timer(1.0).timeout


# ── helpers ──────────────────────────────────────────────────────────────────

func _color_for_peer(pid: int, round_data: Dictionary) -> Color:
	var peer_ids: Array = round_data.get("peer_ids", [])
	var color_indices: Array = round_data.get("color_indices", [])
	var idx: int = peer_ids.find(pid)
	if idx < 0 or idx >= color_indices.size():
		return Color.WHITE
	return PLAYER_COLORS[clampi(color_indices[idx], 0, PLAYER_COLORS.size() - 1)]


func _color_name_for_peer(pid: int, round_data: Dictionary) -> String:
	var peer_ids: Array = round_data.get("peer_ids", [])
	var color_indices: Array = round_data.get("color_indices", [])
	var idx: int = peer_ids.find(pid)
	if idx < 0 or idx >= color_indices.size():
		return "Player %d" % pid
	return COLOR_NAMES[clampi(color_indices[idx], 0, COLOR_NAMES.size() - 1)]
