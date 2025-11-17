extends Control

@onready var score_label: Label = $UI/TopBar/MarginContainer/HBoxContainer/ScoreLabel
@onready var coins_label: Label = $UI/TopBar/MarginContainer/HBoxContainer/CoinsLabel
@onready var high_score_label: Label = $UI/TopBar/MarginContainer/HBoxContainer/HighScoreLabel
@onready var status_label: Label = $UI/GameArea/VBoxContainer/StatusLabel
@onready var click_button: Button = $UI/GameArea/VBoxContainer/ClickButton

var current_score: int = 0
var click_count: int = 0

func _ready() -> void:
	# Connect to GameManager signals
	GameManager.score_updated.connect(_on_score_updated)
	GameManager.coins_updated.connect(_on_coins_updated)
	
	# Connect to GodotBaaS signals
	GodotBaaS.data_saved.connect(_on_data_saved)
	GodotBaaS.score_submitted.connect(_on_score_submitted)
	GodotBaaS.error.connect(_on_error)
	
	# Update UI
	_update_ui()

func _update_ui() -> void:
	score_label.text = "Score: " + str(current_score)
	coins_label.text = "💰 Coins: " + str(GameManager.coins)
	high_score_label.text = "High Score: " + str(GameManager.high_score)

func _on_click_button_pressed() -> void:
	click_count += 1
	current_score += 10
	GameManager.set_score(current_score)
	GameManager.add_coins(1)
	
	# Animate button
	click_button.scale = Vector2(1.1, 1.1)
	var tween = create_tween()
	tween.tween_property(click_button, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Track analytics event every 10 clicks
	if click_count % 10 == 0:
		GodotBaaS.track_event("game_clicks", {
			"click_count": click_count,
			"score": current_score
		})
	
	# Check for achievements
	if click_count == 10:
		GodotBaaS.grant_achievement("first_clicks")
	elif click_count == 100:
		GodotBaaS.grant_achievement("click_master")
	
	# Update progress achievement
	GodotBaaS.update_achievement_progress("click_progress", click_count, false)
	
	_update_ui()

func _on_save_pressed() -> void:
	status_label.text = "⏳ Saving progress..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	GameManager.save_progress()

func _on_submit_pressed() -> void:
	if current_score == 0:
		status_label.text = "⚠️ Score must be greater than 0"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	status_label.text = "⏳ Submitting score..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	
	var metadata = {
		"clicks": click_count,
		"platform": OS.get_name()
	}
	GodotBaaS.submit_score("test-leaderboard", current_score, metadata)

func _on_reset_pressed() -> void:
	current_score = 0
	click_count = 0
	GameManager.set_score(0)
	_update_ui()
	status_label.text = "Game reset!"
	status_label.add_theme_color_override("font_color", Color.CYAN)

func _on_score_updated(_score: int) -> void:
	_update_ui()

func _on_coins_updated(_coins: int) -> void:
	_update_ui()

func _on_data_saved(_key: String, _version: int) -> void:
	status_label.text = "✅ Progress saved!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_score_submitted(_leaderboard: String, rank: int) -> void:
	status_label.text = "✅ Score submitted! Rank: #" + str(rank)
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_error(error_message: String) -> void:
	status_label.text = "❌ " + error_message
	status_label.add_theme_color_override("font_color", Color.RED)

func _on_back_pressed() -> void:
	GameManager.change_scene("res://scenes/main_menu.tscn")
