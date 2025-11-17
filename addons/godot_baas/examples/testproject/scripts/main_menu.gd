extends Control

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var player_label: Label = $CenterContainer/VBoxContainer/PlayerLabel
@onready var leaderboard_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/LeaderboardButton
@onready var friends_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/FriendsButton
@onready var achievements_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/AchievementsButton
@onready var game_button: Button = $CenterContainer/VBoxContainer/ButtonsContainer/GameButton

func _ready() -> void:
	# Connect to GameManager signals
	GameManager.authentication_changed.connect(_on_authentication_changed)
	GameManager.player_data_updated.connect(_on_player_data_updated)
	
	# Update UI
	_update_ui()

func _update_ui() -> void:
	if GameManager.is_authenticated:
		status_label.text = "Status: ✅ Connected"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		
		var username = GameManager.player_username
		if username == "" or username == "Player":
			username = "Anonymous Player"
		
		player_label.text = "Player: " + username
		if GameManager.is_anonymous:
			player_label.text += " (Anonymous)"
		
		# Enable feature buttons
		leaderboard_button.disabled = false
		friends_button.disabled = false
		achievements_button.disabled = false
		game_button.disabled = false
	else:
		status_label.text = "Status: ⚠️ Not Connected"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		player_label.text = "Player: Not Logged In"
		
		# Disable feature buttons
		leaderboard_button.disabled = true
		friends_button.disabled = true
		achievements_button.disabled = true
		game_button.disabled = true

func _on_authentication_changed(authenticated: bool) -> void:
	_update_ui()

func _on_player_data_updated(_data: Dictionary) -> void:
	_update_ui()

func _on_quick_start_pressed() -> void:
	print("[MainMenu] Quick start - logging in with device ID...")
	GameManager.auto_login()

func _on_login_pressed() -> void:
	GameManager.change_scene("res://scenes/auth_screen.tscn")

func _on_leaderboard_pressed() -> void:
	GameManager.change_scene("res://scenes/leaderboard_screen.tscn")

func _on_friends_pressed() -> void:
	GameManager.change_scene("res://scenes/friends_screen.tscn")

func _on_achievements_pressed() -> void:
	GameManager.change_scene("res://scenes/achievements_screen.tscn")

func _on_game_pressed() -> void:
	GameManager.change_scene("res://scenes/game_screen.tscn")

func _on_settings_pressed() -> void:
	GameManager.change_scene("res://scenes/settings_screen.tscn")
