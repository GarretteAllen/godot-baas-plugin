extends Control

const LEADERBOARD_SLUG = "test-leaderboard"

@onready var global_entries_list: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/Global/ScrollContainer/EntriesList
@onready var friends_entries_list: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/Friends/ScrollContainer/EntriesList
@onready var score_input: SpinBox = $MarginContainer/VBoxContainer/SubmitPanel/MarginContainer/HBoxContainer/ScoreInput
@onready var status_label: Label = $MarginContainer/VBoxContainer/SubmitPanel/MarginContainer/HBoxContainer/StatusLabel

func _ready() -> void:
	# Connect to GodotBaaS signals
	GodotBaaS.leaderboard_loaded.connect(_on_leaderboard_loaded)
	GodotBaaS.friend_leaderboard_loaded.connect(_on_friend_leaderboard_loaded)
	GodotBaaS.score_submitted.connect(_on_score_submitted)
	GodotBaaS.error.connect(_on_error)
	
	# Load global leaderboard on start
	_load_global_leaderboard()

func _load_global_leaderboard() -> void:
	_clear_list(global_entries_list)
	_add_loading_label(global_entries_list)
	GodotBaaS.get_leaderboard(LEADERBOARD_SLUG, 50)

func _load_friends_leaderboard() -> void:
	_clear_list(friends_entries_list)
	_add_loading_label(friends_entries_list)
	GodotBaaS.get_friend_leaderboard(LEADERBOARD_SLUG, 50)

func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()

func _add_loading_label(list: VBoxContainer) -> void:
	var label = Label.new()
	label.text = "⏳ Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(label)

func _create_entry_panel(rank: int, username: String, score: int, is_current_player: bool = false) -> PanelContainer:
	var panel = PanelContainer.new()
	
	# Highlight current player
	if is_current_player:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.3, 0.5, 0.3, 0.5)
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_color = Color.GREEN
		panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	margin.add_child(hbox)
	
	# Rank
	var rank_label = Label.new()
	rank_label.custom_minimum_size = Vector2(60, 0)
	var rank_icon = "🥇" if rank == 1 else ("🥈" if rank == 2 else ("🥉" if rank == 3 else ""))
	rank_label.text = rank_icon + " #" + str(rank)
	rank_label.add_theme_font_size_override("font_size", 18)
	hbox.add_child(rank_label)
	
	# Username
	var name_label = Label.new()
	name_label.text = username + (" (You)" if is_current_player else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_label)
	
	# Score
	var score_label = Label.new()
	score_label.text = str(score) + " pts"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.add_theme_font_size_override("font_size", 18)
	score_label.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(score_label)
	
	return panel

func _on_leaderboard_loaded(_leaderboard: String, entries: Array) -> void:
	_clear_list(global_entries_list)
	
	if entries.is_empty():
		var label = Label.new()
		label.text = "No entries yet. Be the first to submit a score!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		global_entries_list.add_child(label)
		return
	
	for entry in entries:
		var rank = entry.get("rank", 0)
		var username = entry.get("username", "Unknown")
		var score = entry.get("score", 0)
		var is_current = entry.get("isCurrentPlayer", false)
		
		var panel = _create_entry_panel(rank, username, score, is_current)
		global_entries_list.add_child(panel)

func _on_friend_leaderboard_loaded(_leaderboard_slug: String, entries: Array) -> void:
	_clear_list(friends_entries_list)
	
	if entries.is_empty():
		var label = Label.new()
		label.text = "No friend scores yet. Add some friends and compete!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		friends_entries_list.add_child(label)
		return
	
	for entry in entries:
		var rank = entry.get("rank", 0)
		var username = entry.get("username", "Unknown")
		var score = entry.get("score", 0)
		var is_current = entry.get("isCurrentPlayer", false)
		
		var panel = _create_entry_panel(rank, username, score, is_current)
		friends_entries_list.add_child(panel)

func _on_score_submitted(_leaderboard: String, rank: int) -> void:
	status_label.text = "✅ Score submitted! Your rank: #" + str(rank)
	status_label.add_theme_color_override("font_color", Color.GREEN)
	
	# Refresh leaderboards
	await get_tree().create_timer(1.0).timeout
	_load_global_leaderboard()

func _on_error(error_message: String) -> void:
	status_label.text = "❌ " + error_message
	status_label.add_theme_color_override("font_color", Color.RED)

func _on_refresh_global_pressed() -> void:
	_load_global_leaderboard()

func _on_refresh_friends_pressed() -> void:
	_load_friends_leaderboard()

func _on_submit_pressed() -> void:
	var score = int(score_input.value)
	status_label.text = "⏳ Submitting score..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	
	var metadata = {
		"platform": OS.get_name(),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	GodotBaaS.submit_score(LEADERBOARD_SLUG, score, metadata)

func _on_back_pressed() -> void:
	GameManager.change_scene("res://scenes/main_menu.tscn")
