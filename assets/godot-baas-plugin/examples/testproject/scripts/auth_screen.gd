extends Control

# Login tab
@onready var login_email: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Login/LoginEmail
@onready var login_password: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Login/LoginPassword
@onready var login_status: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Login/StatusLabel

# Register tab
@onready var register_username: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Register/RegisterUsername
@onready var register_email: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Register/RegisterEmail
@onready var register_password: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Register/RegisterPassword
@onready var register_status: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/Register/StatusLabel

# Link account tab
@onready var link_username: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/LinkAccount/LinkUsername
@onready var link_email: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/LinkAccount/LinkEmail
@onready var link_password: LineEdit = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/LinkAccount/LinkPassword
@onready var link_status: Label = $CenterContainer/Panel/MarginContainer/VBoxContainer/TabContainer/LinkAccount/StatusLabel

func _ready() -> void:
	# Connect to GameManager signals
	GameManager.authentication_changed.connect(_on_authentication_changed)
	
	# Connect to GodotBaaS signals for detailed feedback
	GodotBaaS.auth_failed.connect(_on_auth_failed)

func _on_login_button_pressed() -> void:
	var email = login_email.text.strip_edges()
	var password = login_password.text
	
	if email == "" or password == "":
		login_status.text = "⚠️ Please fill in all fields"
		login_status.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	login_status.text = "⏳ Logging in..."
	login_status.add_theme_color_override("font_color", Color.WHITE)
	
	GameManager.login_with_email(email, password)

func _on_register_button_pressed() -> void:
	var username = register_username.text.strip_edges()
	var email = register_email.text.strip_edges()
	var password = register_password.text
	
	if username == "" or email == "" or password == "":
		register_status.text = "⚠️ Please fill in all fields"
		register_status.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	if password.length() < 8:
		register_status.text = "⚠️ Password must be at least 8 characters"
		register_status.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	register_status.text = "⏳ Creating account..."
	register_status.add_theme_color_override("font_color", Color.WHITE)
	
	GameManager.register_account(email, password, username)

func _on_link_button_pressed() -> void:
	if not GameManager.is_authenticated or not GameManager.is_anonymous:
		link_status.text = "⚠️ Must be logged in as anonymous"
		link_status.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	var username = link_username.text.strip_edges()
	var email = link_email.text.strip_edges()
	var password = link_password.text
	
	if username == "" or email == "" or password == "":
		link_status.text = "⚠️ Please fill in all fields"
		link_status.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	if password.length() < 8:
		link_status.text = "⚠️ Password must be at least 8 characters"
		link_status.add_theme_color_override("font_color", Color.ORANGE)
		return
	
	link_status.text = "⏳ Linking account..."
	link_status.add_theme_color_override("font_color", Color.WHITE)
	
	GameManager.link_to_email(email, password, username)

func _on_authentication_changed(authenticated: bool) -> void:
	if authenticated:
		# Success! Go back to main menu
		await get_tree().create_timer(0.5).timeout
		GameManager.change_scene("res://scenes/main_menu.tscn")

func _on_auth_failed(error: String) -> void:
	# Update all status labels
	var error_text = "❌ " + error
	
	login_status.text = error_text
	login_status.add_theme_color_override("font_color", Color.RED)
	
	register_status.text = error_text
	register_status.add_theme_color_override("font_color", Color.RED)
	
	link_status.text = error_text
	link_status.add_theme_color_override("font_color", Color.RED)

func _on_back_pressed() -> void:
	GameManager.change_scene("res://scenes/main_menu.tscn")
