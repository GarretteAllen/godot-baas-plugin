extends Node

## Global game state manager
## Handles authentication state, player data, and scene transitions

# Configuration
const API_KEY = "gb_live_83af2f08cbc5e42dc47ef964f355f56aeb73c5ea9cc93217c6ccbb8d65ef7f6a"  # REPLACE WITH YOUR API KEY
const BASE_URL = "https://api.godotbaas.com"

# Player state
var is_authenticated: bool = false
var player_data: Dictionary = {}
var player_id: String = ""
var player_username: String = ""
var is_anonymous: bool = true

# Game state
var current_score: int = 0
var high_score: int = 0
var coins: int = 0
var level: int = 1

# Signals
signal authentication_changed(authenticated: bool)
signal player_data_updated(data: Dictionary)
signal score_updated(score: int)
signal coins_updated(coins: int)

func _ready() -> void:
	# Configure GodotBaaS
	GodotBaaS.api_key = API_KEY
	GodotBaaS.base_url = BASE_URL
	
	# Connect to GodotBaaS signals
	GodotBaaS.authenticated.connect(_on_authenticated)
	GodotBaaS.auth_failed.connect(_on_auth_failed)
	GodotBaaS.data_loaded.connect(_on_data_loaded)
	GodotBaaS.data_saved.connect(_on_data_saved)
	GodotBaaS.error.connect(_on_error)
	
	print("[GameManager] Initialized with API Key: ", API_KEY.substr(0, 15), "...")

## Auto-login with device ID
func auto_login() -> void:
	print("[GameManager] Attempting auto-login with device ID...")
	GodotBaaS.login_with_device_id()

## Login with email and password
func login_with_email(email: String, password: String) -> void:
	print("[GameManager] Logging in with email: ", email)
	GodotBaaS.login_player(email, password)

## Register new account
func register_account(email: String, password: String, username: String) -> void:
	print("[GameManager] Registering new account: ", email)
	GodotBaaS.register_player(email, password, username)

## Link anonymous account to email
func link_to_email(email: String, password: String, username: String) -> void:
	print("[GameManager] Linking account to email: ", email)
	GodotBaaS.link_account(email, password, username)

## Load player progress from cloud
func load_progress() -> void:
	if not is_authenticated:
		push_warning("[GameManager] Cannot load progress: Not authenticated")
		return
	
	print("[GameManager] Loading player progress...")
	GodotBaaS.load_data("player_progress")

## Save player progress to cloud
func save_progress() -> void:
	if not is_authenticated:
		push_warning("[GameManager] Cannot save progress: Not authenticated")
		return
	
	var progress_data = {
		"level": level,
		"coins": coins,
		"high_score": high_score,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	print("[GameManager] Saving player progress: ", progress_data)
	GodotBaaS.save_data("player_progress", progress_data, 0)

## Update score
func set_score(new_score: int) -> void:
	current_score = new_score
	if current_score > high_score:
		high_score = current_score
	score_updated.emit(current_score)

## Add coins
func add_coins(amount: int) -> void:
	coins += amount
	coins_updated.emit(coins)

## Spend coins
func spend_coins(amount: int) -> bool:
	if coins >= amount:
		coins -= amount
		coins_updated.emit(coins)
		return true
	return false

## Change scene
func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)

# Signal handlers

func _on_authenticated(data: Dictionary) -> void:
	print("[GameManager] Authentication successful!")
	is_authenticated = true
	player_data = data
	
	# Handle potentially null values from the API
	var id_value = data.get("id")
	player_id = id_value if id_value != null else ""
	
	var username_value = data.get("username")
	player_username = username_value if username_value != null else "Player"
	
	var is_anon_value = data.get("isAnonymous")
	is_anonymous = is_anon_value if is_anon_value != null else true
	
	authentication_changed.emit(true)
	player_data_updated.emit(data)
	
	# Auto-load progress after authentication
	load_progress()

func _on_auth_failed(error: String) -> void:
	print("[GameManager] Authentication failed: ", error)
	is_authenticated = false
	authentication_changed.emit(false)

func _on_data_loaded(key: String, value: Variant) -> void:
	if key == "player_progress":
		print("[GameManager] Progress loaded: ", value)
		if typeof(value) == TYPE_DICTIONARY:
			level = value.get("level", 1)
			coins = value.get("coins", 0)
			high_score = value.get("high_score", 0)
			
			coins_updated.emit(coins)
			score_updated.emit(high_score)
			player_data_updated.emit(value)

func _on_data_saved(key: String, version: int) -> void:
	print("[GameManager] Data saved: ", key, " (version: ", version, ")")

func _on_error(error_message: String) -> void:
	# Handle "not found" errors gracefully (e.g., first time player with no saved data)
	if "not found" in error_message.to_lower() and "player_progress" in error_message:
		print("[GameManager] No saved progress found - this is normal for new players")
		return
	
	# Log other errors
	push_error("[GameManager] Error: " + error_message)
