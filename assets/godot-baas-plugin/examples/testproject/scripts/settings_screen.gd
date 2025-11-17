extends Control

@onready var api_key_input: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/ConfigSection/ApiKeyInput
@onready var base_url_input: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/ConfigSection/BaseUrlInput
@onready var player_id_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/InfoSection/PlayerIdLabel
@onready var username_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/InfoSection/UsernameLabel
@onready var account_type_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/InfoSection/AccountTypeLabel
@onready var status_label: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/StatusLabel

func _ready() -> void:
	# Load current configuration
	api_key_input.text = GameManager.API_KEY
	base_url_input.text = GameManager.BASE_URL
	
	# Update player info
	_update_player_info()
	
	# Connect to GameManager signals
	GameManager.authentication_changed.connect(_on_authentication_changed)

func _update_player_info() -> void:
	if GameManager.is_authenticated:
		player_id_label.text = "Player ID: " + GameManager.player_id
		username_label.text = "Username: " + (GameManager.player_username if GameManager.player_username != "" else "Anonymous")
		account_type_label.text = "Account Type: " + ("Anonymous" if GameManager.is_anonymous else "Registered")
	else:
		player_id_label.text = "Player ID: Not logged in"
		username_label.text = "Username: N/A"
		account_type_label.text = "Account Type: N/A"

func _on_authentication_changed(_authenticated: bool) -> void:
	_update_player_info()

func _on_save_config_pressed() -> void:
	var new_api_key = api_key_input.text.strip_edges()
	var new_base_url = base_url_input.text.strip_edges()
	
	if new_api_key == "" or new_base_url == "":
		status_label.text = "⚠️ Please fill in all fields"
		status_label.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	# Update configuration
	GodotBaaS.api_key = new_api_key
	GodotBaaS.base_url = new_base_url
	
	status_label.text = "✅ Configuration saved! Restart may be required."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	
	print("[Settings] API Key updated to: ", new_api_key.substr(0, 15), "...")
	print("[Settings] Base URL updated to: ", new_base_url)

func _on_docs_pressed() -> void:
	OS.shell_open("https://godotbaas.com/docs")

func _on_dashboard_pressed() -> void:
	OS.shell_open("https://dashboard.godotbaas.com")

func _on_github_pressed() -> void:
	OS.shell_open("https://github.com/GarretteAllen/godot-baas-plugin")

func _on_back_pressed() -> void:
	GameManager.change_scene("res://scenes/main_menu.tscn")
