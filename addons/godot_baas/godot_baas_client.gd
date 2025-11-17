extends Node

# Configuration properties
var api_key: String = ""
var base_url: String = "https://api.godotbaas.com"
var player_token: String = ""

# Retry configuration
var max_retries: int = 3
var retry_delay_ms: int = 1000  # Initial delay in milliseconds
var enable_retry: bool = true

# Offline queue configuration
var enable_offline_queue: bool = true
var max_queue_size: int = 50
var queue_timeout_seconds: int = 300  # 5 minutes

# Request signing configuration
var enable_request_signing: bool = true  # Set to false for development/testing

# API Endpoints (constants for better maintainability)
const ENDPOINT_AUTH_REGISTER = "/api/v1/game/auth/register"
const ENDPOINT_AUTH_LOGIN = "/api/v1/game/auth/login"
const ENDPOINT_AUTH_ANONYMOUS = "/api/v1/game/auth/anonymous"
const ENDPOINT_AUTH_LINK = "/api/v1/game/auth/link-account"
const ENDPOINT_PLAYER_DATA = "/api/v1/game/players/@me/data"
const ENDPOINT_LEADERBOARDS = "/api/v1/game/leaderboards"
const ENDPOINT_ANALYTICS = "/api/v1/game/analytics/events"
const ENDPOINT_FRIENDS = "/api/v1/game/friends"
const ENDPOINT_FRIEND_REQUEST = "/api/v1/game/friends/request"
const ENDPOINT_FRIEND_SEARCH = "/api/v1/game/friends/search"
const ENDPOINT_FRIEND_BLOCK = "/api/v1/game/friends/block"
const ENDPOINT_FRIEND_LEADERBOARD = "/api/v1/game/friends/leaderboard"

# Connection state
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	ERROR
}

# Request priority
enum RequestPriority {
	LOW,      # Analytics, non-critical events
	NORMAL,   # Regular gameplay requests
	HIGH,     # Authentication, critical saves
	CRITICAL  # Never queue, fail immediately if offline
}

# Internal state
var _http_client: HTTPRequest
var _authenticated: bool = false
var _player_data: Dictionary = {}
var _connection_state: ConnectionState = ConnectionState.DISCONNECTED
var _current_request: Dictionary = {}  # Tracks current request for retry
var _retry_count: int = 0
var _retry_timer: Timer
var _request_queue: Array = []  # Offline request queue
var _is_online: bool = true
var _network_check_timer: Timer
var _processing_queue: bool = false
var _request_id_counter: int = 0
var _active_requests: Dictionary = {}  # Track cancellable requests

# Signals for authentication
signal authenticated(player_data: Dictionary)
signal auth_failed(error: String)
signal username_updated(player_data: Dictionary)

# Signals for network state
signal network_online()
signal network_offline()
signal request_queued(request_id: int)
signal queue_processed(successful: int, failed: int)

# Signals for cloud saves
signal data_saved(key: String, version: int)
signal data_loaded(key: String, value: Variant)
signal data_conflict(key: String, server_version: int, server_data: Variant)

# Signals for leaderboards
signal score_submitted(leaderboard: String, rank: int)
signal leaderboard_loaded(leaderboard: String, entries: Array)

# Signals for achievements
signal achievement_unlocked(achievement: Dictionary)
signal achievement_progress_updated(achievement: Dictionary)
signal achievement_unlock_failed(error: String)
signal achievements_loaded(achievements: Array)

# Signals for friends
signal friend_request_sent(friendship: Dictionary)
signal friend_request_received(request: Dictionary)
signal friend_request_accepted(friend: Dictionary)
signal friend_request_declined()
signal friend_request_cancelled()
signal friends_loaded(friends: Array, count: int)
signal friend_removed()
signal pending_requests_loaded(requests: Array)
signal sent_requests_loaded(requests: Array)
signal players_found(players: Array)
signal player_blocked()
signal player_unblocked()
signal blocked_players_loaded(players: Array)
signal friend_leaderboard_loaded(leaderboard_slug: String, entries: Array)

# General error signal
signal error(error_message: String)

func _ready() -> void:
	# Create and configure HTTPRequest node
	_http_client = HTTPRequest.new()
	add_child(_http_client)
	_http_client.request_completed.connect(_on_request_completed)
	# Set reasonable timeout (30 seconds)
	_http_client.timeout = 30.0
	
	# Create retry timer
	_retry_timer = Timer.new()
	add_child(_retry_timer)
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_on_retry_timeout)
	
	# Create network check timer (check every 5 seconds)
	_network_check_timer = Timer.new()
	add_child(_network_check_timer)
	_network_check_timer.wait_time = 5.0
	_network_check_timer.timeout.connect(_check_network_status)
	_network_check_timer.start()

func _exit_tree() -> void:
	# Clean up HTTP client and timers
	if _http_client:
		_http_client.queue_free()
	if _retry_timer:
		_retry_timer.queue_free()
	if _network_check_timer:
		_network_check_timer.queue_free()
	
	# Clear queued requests
	_request_queue.clear()
	_active_requests.clear()

## Get current connection state
func get_connection_state() -> ConnectionState:
	return _connection_state

## Check if currently connected to BaaS
func is_baas_connected() -> bool:
	return _connection_state == ConnectionState.CONNECTED

## Check if network is online
func is_online() -> bool:
	return _is_online

## Get number of queued requests
func get_queue_size() -> int:
	return _request_queue.size()

## Clear the request queue
func clear_queue() -> void:
	_request_queue.clear()
	print("[GodotBaaS] Request queue cleared")

## Cancel a specific request by ID
func cancel_request(request_id: int) -> bool:
	if _active_requests.has(request_id):
		_active_requests.erase(request_id)
		print("[GodotBaaS] Request ", request_id, " cancelled")
		return true
	
	# Check if it's in the queue
	for i in range(_request_queue.size()):
		if _request_queue[i].get("id") == request_id:
			_request_queue.remove_at(i)
			print("[GodotBaaS] Queued request ", request_id, " cancelled")
			return true
	
	return false

## Cancel all active and queued requests
func cancel_all_requests() -> void:
	_active_requests.clear()
	_request_queue.clear()
	print("[GodotBaaS] All requests cancelled")

## Check network status (called periodically)
func _check_network_status() -> void:
	var was_online = _is_online
	
	# Simple check: if we have a connection state, we're likely online
	# More sophisticated check could ping a lightweight endpoint
	_is_online = (_connection_state == ConnectionState.CONNECTED or 
				  _connection_state == ConnectionState.CONNECTING)
	
	# Emit signals on state change
	if was_online and not _is_online:
		print("[GodotBaaS] Network went offline")
		network_offline.emit()
	elif not was_online and _is_online:
		print("[GodotBaaS] Network came online")
		network_online.emit()
		# Process queued requests
		_process_queue()

## Process queued requests when back online
func _process_queue() -> void:
	if _processing_queue or _request_queue.is_empty():
		return
	
	_processing_queue = true
	print("[GodotBaaS] Processing ", _request_queue.size(), " queued requests")
	
	var successful = 0
	var failed = 0
	var requests_to_process = _request_queue.duplicate()
	_request_queue.clear()
	
	for queued_request in requests_to_process:
		# Check if request has expired
		var age = Time.get_unix_time_from_system() - queued_request.get("timestamp", 0)
		if age > queue_timeout_seconds:
			print("[GodotBaaS] Request expired (age: ", age, "s)")
			failed += 1
			continue
		
		# Execute the request
		_current_request = {
			"method": queued_request.get("method"),
			"endpoint": queued_request.get("endpoint"),
			"body": queued_request.get("body"),
			"requires_auth": queued_request.get("requires_auth")
		}
		_retry_count = 0
		_execute_request()
		successful += 1
		
		# Small delay between requests to avoid flooding
		await get_tree().create_timer(0.1).timeout
	
	_processing_queue = false
	queue_processed.emit(successful, failed)
	print("[GodotBaaS] Queue processed: ", successful, " successful, ", failed, " failed")

## Process next queued request (called after a request completes)
func _process_next_queued_request() -> void:
	if _request_queue.is_empty() or not _current_request.is_empty():
		return
	
	# Get next request from queue
	var queued_request = _request_queue.pop_front()
	
	# Check if request has expired
	var age = Time.get_unix_time_from_system() - queued_request.get("timestamp", 0)
	if age > queue_timeout_seconds:
		print("[GodotBaaS] Queued request expired (age: ", age, "s)")
		# Try next one
		_process_next_queued_request()
		return
	
	print("[GodotBaaS] Processing queued request (ID: ", queued_request.get("id"), ")")
	
	# Set as current request and execute
	_current_request = {
		"id": queued_request.get("id"),
		"method": queued_request.get("method"),
		"endpoint": queued_request.get("endpoint"),
		"body": queued_request.get("body"),
		"requires_auth": queued_request.get("requires_auth"),
		"priority": queued_request.get("priority")
	}
	_retry_count = 0
	_execute_request()

# Security helper functions

## Generate a unique nonce for request using cryptographically secure random
func _generate_nonce() -> String:
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	return random_bytes.hex_encode()

## Generate HMAC-SHA256 signature using API key as secret
## The API key itself is used as the signing secret - this is safe because:
## 1. API keys are already required to be kept secure
## 2. They're already in the client (unavoidable for client-server communication)
## 3. The server can derive the same signature using the API key
func _generate_signature(body_string: String, timestamp: String) -> String:
	var data = body_string + timestamp
	var ctx = HashingContext.new()
	
	# Use API key as the signing secret
	var key = api_key.to_utf8_buffer()
	var key_bytes = PackedByteArray()
	
	# Ensure key is 64 bytes (SHA256 block size)
	if key.size() > 64:
		# Hash the key if it's too long
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(key)
		key_bytes = ctx.finish()
		key_bytes.resize(64)
	else:
		key_bytes = key.duplicate()
		key_bytes.resize(64)
	
	# Inner hash: H(K XOR ipad, message)
	var ipad = PackedByteArray()
	ipad.resize(64)
	for i in range(64):
		ipad[i] = key_bytes[i] ^ 0x36
	
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(ipad)
	ctx.update(data.to_utf8_buffer())
	var inner_hash = ctx.finish()
	
	# Outer hash: H(K XOR opad, inner_hash)
	var opad = PackedByteArray()
	opad.resize(64)
	for i in range(64):
		opad[i] = key_bytes[i] ^ 0x5c
	
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(opad)
	ctx.update(inner_hash)
	var final_hash = ctx.finish()
	
	# Convert to hex string
	return final_hash.hex_encode()

## Get current timestamp in milliseconds
func _get_timestamp() -> String:
	return str(int(Time.get_unix_time_from_system() * 1000))

# Authentication methods

## Player registration
## Creates a new player account with email and password
## @param email: Player's email address
## @param password: Player's password
## @param username: Optional username for the player
func register_player(email: String, password: String, username: String = "") -> void:
	var body = {
		"email": email,
		"password": password
	}
	
	# Add username if provided
	if username != "":
		body["username"] = username
	
	_make_request("POST", ENDPOINT_AUTH_REGISTER, body, false, RequestPriority.HIGH)

## Player login
## Authenticates an existing player with email and password
## @param email: Player's email address
## @param password: Player's password
func login_player(email: String, password: String) -> void:
	var body = {
		"email": email,
		"password": password
	}
	
	_make_request("POST", ENDPOINT_AUTH_LOGIN, body, false, RequestPriority.HIGH)

## Device ID login
## Creates or logs into an existing player account using device ID
## The device ID is automatically generated and stored locally
func login_with_device_id() -> void:
	var device_id = _get_or_create_device_id()
	print("[GodotBaaS] Logging in with device ID: ", device_id.substr(0, 8), "...")
	
	var body = {
		"deviceId": device_id
	}
	_make_request("POST", "/api/v1/game/auth/device", body, false, RequestPriority.HIGH)

## Anonymous login (deprecated - use login_with_device_id instead)
## Creates an anonymous player session without credentials
func login_anonymous() -> void:
	_make_request("POST", ENDPOINT_AUTH_ANONYMOUS, {}, false, RequestPriority.HIGH)

## Link anonymous account to registered account
## Converts an anonymous player account to a registered account
## Preserves all player data during the linking process
## @param email: Email address for the new registered account
## @param password: Password for the new registered account
## @param username: Optional username for the account
func link_account(email: String, password: String, username: String = "") -> void:
	if not _authenticated or player_token == "":
		auth_failed.emit("Cannot link account: Not authenticated as anonymous player")
		return
	
	var body = {
		"email": email,
		"password": password
	}
	
	# Add username if provided
	if username != "":
		body["username"] = username
	
	# This request requires authentication (player token from anonymous session)
	_make_request("POST", ENDPOINT_AUTH_LINK, body, true)

## Set username for current player
## Allows anonymous players to set a username without linking to email
## Username must be unique within the project
## @param username: Desired username (3-20 characters)
func set_username(username: String) -> void:
	if not _authenticated or player_token == "":
		auth_failed.emit("Cannot set username: Not authenticated")
		return
	
	if username.strip_edges().length() < 3:
		error.emit("Username must be at least 3 characters")
		return
	
	if username.strip_edges().length() > 20:
		error.emit("Username must be at most 20 characters")
		return
	
	var body = {
		"username": username.strip_edges()
	}
	
	_make_request("POST", "/api/v1/game/auth/set-username", body, true)

# Cloud Save methods

## Save player data
## Stores player data with a specific key and version for conflict resolution
## @param key: Unique identifier for the data
## @param value: The data to save (will be converted to JSON)
## @param version: Current version number for optimistic locking (0 for new data)
func save_data(key: String, value: Variant, version: int = 0) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot save data: Not authenticated")
		return
	
	var body = {
		"value": value,
		"version": version
	}
	
	_make_request("POST", ENDPOINT_PLAYER_DATA + "/" + key, body, true)

## Load player data
## Retrieves player data by key
## @param key: Unique identifier for the data to load
func load_data(key: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot load data: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_PLAYER_DATA + "/" + key, {}, true)

## Delete player data
## Removes player data by key
## @param key: Unique identifier for the data to delete
func delete_data(key: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot delete data: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_PLAYER_DATA + "/" + key, {}, true)

## Merge/patch player data
## Useful for inventory systems - add/remove items without replacing entire data
## @param key: Unique identifier for the data
## @param value: The data to merge (e.g., items to add/remove)
## @param version: Current version number for optimistic locking
## @param strategy: Merge strategy - "merge", "append", "remove", "increment", "decrement"
func merge_data(key: String, value: Variant, version: int = 0, strategy: String = "merge") -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot merge data: Not authenticated")
		return
	
	var body = {
		"value": value,
		"version": version,
		"strategy": strategy
	}
	
	_make_request("PATCH", ENDPOINT_PLAYER_DATA + "/" + key, body, true)

## Add items to inventory (convenience method)
## @param key: Inventory key (e.g., "inventory")
## @param items: Array of items to add
## @param version: Current version number
func add_to_inventory(key: String, items: Array, version: int = 0) -> void:
	merge_data(key, {"items": items}, version, "append")

## Remove items from inventory (convenience method)
## @param key: Inventory key (e.g., "inventory")
## @param items: Array of items to remove
## @param version: Current version number
func remove_from_inventory(key: String, items: Array, version: int = 0) -> void:
	merge_data(key, {"items": items}, version, "remove")

## Increment currency/stats (convenience method)
## @param key: Data key (e.g., "currency")
## @param amounts: Dictionary of values to increment (e.g., {"gold": 100, "gems": 5})
## @param version: Current version number
func increment_values(key: String, amounts: Dictionary, version: int = 0) -> void:
	merge_data(key, amounts, version, "increment")

## Decrement currency/stats (convenience method)
## @param key: Data key (e.g., "currency")
## @param amounts: Dictionary of values to decrement (e.g., {"gold": 50})
## @param version: Current version number
func decrement_values(key: String, amounts: Dictionary, version: int = 0) -> void:
	merge_data(key, amounts, version, "decrement")

## List all player data keys
## Retrieves a list of all data keys stored for the current player
func list_data() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot list data: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_PLAYER_DATA, {}, true)

# Leaderboard methods

## Submit score to leaderboard
## Submits a player's score to a specific leaderboard
## @param leaderboard_slug: Unique identifier for the leaderboard
## @param score: The score value to submit
## @param metadata: Optional metadata to attach to the score entry
func submit_score(leaderboard_slug: String, score: int, metadata: Dictionary = {}) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot submit score: Not authenticated")
		return
	
	var body = {
		"score": score
	}
	
	# Add metadata if provided
	if metadata.size() > 0:
		body["metadata"] = metadata
	
	_make_request("POST", ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "/submit", body, true)

## Get leaderboard entries
## Retrieves the top entries from a leaderboard
## @param leaderboard_slug: Unique identifier for the leaderboard
## @param limit: Maximum number of entries to retrieve (default: 100)
func get_leaderboard(leaderboard_slug: String, limit: int = 100) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get leaderboard: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "?limit=" + str(limit), {}, true)

## Get player's rank on a leaderboard
## Retrieves the current player's rank on a specific leaderboard
## @param leaderboard_slug: Unique identifier for the leaderboard
func get_player_rank(leaderboard_slug: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get player rank: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "/rank", {}, true)

# Achievement methods

## Grant an achievement to the current player
## Awards an achievement to the authenticated player
## @param achievement_id: Unique identifier for the achievement to grant
func grant_achievement(achievement_id: String) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot grant achievement: Not authenticated")
		return
	
	var body = {
		"achievementId": achievement_id
	}
	
	_make_request("POST", "/api/v1/game/achievements/grant", body, true)

## Update achievement progress
## Updates the progress value for a progress-based achievement
## Automatically grants the achievement when progress reaches the target value
## @param achievement_id: Unique identifier for the achievement
## @param progress: The progress value to set or increment
## @param increment: If true, adds to current progress; if false, sets progress to the value
func update_achievement_progress(achievement_id: String, progress: int, increment: bool = false) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot update achievement progress: Not authenticated")
		return
	
	var body = {
		"achievementId": achievement_id,
		"progress": progress,
		"increment": increment
	}
	
	_make_request("POST", "/api/v1/game/achievements/progress", body, true)

## Get all achievements for the current player
## Retrieves all achievement definitions with unlock status and progress
## @param include_hidden: If true, includes hidden achievements; if false, only shows hidden achievements that are unlocked
func get_achievements(include_hidden: bool = false) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot get achievements: Not authenticated")
		return
	
	var endpoint = "/api/v1/game/achievements"
	if include_hidden:
		endpoint += "?includeHidden=true"
	
	_make_request("GET", endpoint, {}, true)

## Get a specific achievement for the current player
## Retrieves a single achievement with unlock status and progress
## @param achievement_id: Unique identifier for the achievement
func get_achievement(achievement_id: String) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot get achievement: Not authenticated")
		return
	
	_make_request("GET", "/api/v1/game/achievements/" + achievement_id, {}, true)

# Analytics methods

## Track analytics event
## Sends a custom event to the analytics system for tracking player behavior
## This is a fire-and-forget operation - no response signal is emitted
## Events can be sent with or without authentication (authenticated events include player context)
## @param event_name: Name of the event to track (e.g., "level_completed", "item_purchased")
## @param properties: Optional dictionary of event properties/metadata
func track_event(event_name: String, properties: Dictionary = {}) -> void:
	var body = {
		"eventName": event_name
	}
	
	# Add properties if provided
	if properties.size() > 0:
		body["properties"] = properties
	
	# Send event with authentication if player is logged in
	# This allows tracking events with player context
	# If not authenticated, events are still tracked but without player association
	var requires_auth = _authenticated and player_token != ""
	_make_request("POST", ENDPOINT_ANALYTICS, body, requires_auth, RequestPriority.LOW)

# Friend Request methods

## Send a friend request to another player
## @param player_identifier: Player ID or username to send request to
func send_friend_request(player_identifier: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot send friend request: Not authenticated")
		return
	
	var body = {
		"targetPlayerId": player_identifier
	}
	
	_make_request("POST", ENDPOINT_FRIEND_REQUEST, body, true)

## Accept a friend request
## @param friendship_id: ID of the friendship record to accept
func accept_friend_request(friendship_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot accept friend request: Not authenticated")
		return
	
	_make_request("POST", ENDPOINT_FRIEND_REQUEST + "/" + friendship_id + "/accept", {}, true)

## Decline a friend request
## @param friendship_id: ID of the friendship record to decline
func decline_friend_request(friendship_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot decline friend request: Not authenticated")
		return
	
	_make_request("POST", ENDPOINT_FRIEND_REQUEST + "/" + friendship_id + "/decline", {}, true)

## Cancel a sent friend request
## @param friendship_id: ID of the friendship record to cancel
func cancel_friend_request(friendship_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot cancel friend request: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_FRIEND_REQUEST + "/" + friendship_id, {}, true)

# Friend List methods

## Get the current player's friend list
func get_friends() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get friends: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIENDS, {}, true)

## Remove a friend from the friend list
## @param friend_id: Player ID of the friend to remove
func remove_friend(friend_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot remove friend: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_FRIENDS + "/" + friend_id, {}, true)

## Get all pending friend requests received by the current player
func get_pending_requests() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get pending requests: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIENDS + "/requests/pending", {}, true)

## Get all friend requests sent by the current player
func get_sent_requests() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get sent requests: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIENDS + "/requests/sent", {}, true)

# Player Search methods

## Search for players by username or player ID
## @param query: Search query (username or player ID)
func search_players(query: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot search players: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIEND_SEARCH + "?q=" + query, {}, true)

# Player Blocking methods

## Block a player to prevent friend requests and interactions
## @param player_id: Player ID to block
## @param reason: Optional reason for blocking
func block_player(player_id: String, reason: String = "") -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot block player: Not authenticated")
		return
	
	var body = {
		"playerId": player_id
	}
	
	if reason != "":
		body["reason"] = reason
	
	_make_request("POST", ENDPOINT_FRIEND_BLOCK, body, true)

## Unblock a previously blocked player
## @param player_id: Player ID to unblock
func unblock_player(player_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot unblock player: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_FRIEND_BLOCK + "/" + player_id, {}, true)

## Get list of all blocked players
func get_blocked_players() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get blocked players: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIEND_BLOCK, {}, true)

# Friend Leaderboard methods

## Get leaderboard entries filtered to only friends
## @param leaderboard_slug: Unique identifier for the leaderboard
## @param limit: Maximum number of entries to retrieve (default: 100)
func get_friend_leaderboard(leaderboard_slug: String, limit: int = 100) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get friend leaderboard: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIEND_LEADERBOARD + "/" + leaderboard_slug + "?limit=" + str(limit), {}, true)

# Internal HTTP request handler with priority support
func _make_request(method: String, endpoint: String, body: Dictionary = {}, requires_auth: bool = false, priority: RequestPriority = RequestPriority.NORMAL) -> int:
	# Generate unique request ID
	_request_id_counter += 1
	var request_id = _request_id_counter
	
	# Check if we're offline and should queue
	if not _is_online and enable_offline_queue and priority != RequestPriority.CRITICAL:
		# Queue the request
		if _request_queue.size() >= max_queue_size:
			print("[GodotBaaS] Queue full, dropping oldest request")
			_request_queue.pop_front()
		
		var queued_request = {
			"id": request_id,
			"method": method,
			"endpoint": endpoint,
			"body": body,
			"requires_auth": requires_auth,
			"priority": priority,
			"timestamp": Time.get_unix_time_from_system()
		}
		
		# Insert based on priority (higher priority first)
		var inserted = false
		for i in range(_request_queue.size()):
			if _request_queue[i].get("priority", RequestPriority.NORMAL) < priority:
				_request_queue.insert(i, queued_request)
				inserted = true
				break
		
		if not inserted:
			_request_queue.append(queued_request)
		
		print("[GodotBaaS] Request queued (ID: ", request_id, ", Priority: ", priority, ", Queue size: ", _request_queue.size(), ")")
		request_queued.emit(request_id)
		return request_id
	
	# Check if HTTPRequest is currently busy
	if _http_client.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		# Queue this request to be executed after current one completes
		print("[GodotBaaS] HTTPRequest busy, queueing request (ID: ", request_id, ")")
		var queued_request = {
			"id": request_id,
			"method": method,
			"endpoint": endpoint,
			"body": body,
			"requires_auth": requires_auth,
			"priority": priority,
			"timestamp": Time.get_unix_time_from_system()
		}
		_request_queue.append(queued_request)
		request_queued.emit(request_id)
		return request_id
	
	# Store request context for potential retry
	_current_request = {
		"id": request_id,
		"method": method,
		"endpoint": endpoint,
		"body": body,
		"requires_auth": requires_auth,
		"priority": priority
	}
	
	# Track active request
	_active_requests[request_id] = _current_request
	
	# Reset retry count for new request
	_retry_count = 0
	
	# Execute the request
	_execute_request()
	
	return request_id

# Execute the actual HTTP request (can be retried)
func _execute_request() -> void:
	var method = _current_request["method"]
	var endpoint = _current_request["endpoint"]
	var body = _current_request["body"]
	var requires_auth = _current_request["requires_auth"]
	
	# Update connection state
	_connection_state = ConnectionState.CONNECTING
	
	# Construct full URL
	var url = base_url + endpoint
	
	# Convert body to JSON string
	var body_string = ""
	if body.size() > 0:
		body_string = JSON.stringify(body)
		# Fix: Remove .0 from integers to match backend serialization
		# Godot serializes all numbers as floats (e.g., 5 becomes 5.0)
		# But Node.js serializes integers without .0
		# This causes signature mismatch
		body_string = _normalize_json_numbers(body_string)
	else:
		body_string = "{}"
	
	# Prepare base headers
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key
	]
	
	# Add security headers if signing is enabled
	# Note: Development API keys (gb_dev_*) bypass validation on the server
	if enable_request_signing:
		var timestamp = _get_timestamp()
		var nonce = _generate_nonce()
		var signature = _generate_signature(body_string, timestamp)
		
		print("[GodotBaaS] Signing request - Body: ", body_string)
		print("[GodotBaaS] Timestamp: ", timestamp)
		print("[GodotBaaS] Signature: ", signature.substr(0, 20), "...")
		
		headers.append("X-Signature: " + signature)
		headers.append("X-Timestamp: " + timestamp)
		headers.append("X-Nonce: " + nonce)
	
	# Add player token header for authenticated requests
	if requires_auth and player_token != "":
		headers.append("X-Player-Token: " + player_token)
	
	# Determine HTTP method
	var http_method = HTTPClient.METHOD_GET
	match method.to_upper():
		"GET":
			http_method = HTTPClient.METHOD_GET
		"POST":
			http_method = HTTPClient.METHOD_POST
		"PUT":
			http_method = HTTPClient.METHOD_PUT
		"DELETE":
			http_method = HTTPClient.METHOD_DELETE
		"PATCH":
			http_method = HTTPClient.METHOD_PATCH
	
	# Make the HTTP request
	var request_error = _http_client.request(url, headers, http_method, body_string)
	
	# Handle network errors immediately
	if request_error != OK:
		_connection_state = ConnectionState.ERROR
		_handle_request_failure("Network error: Failed to initiate request (Error code: " + str(request_error) + ")")
		return

# Handle request failure with retry logic
func _handle_request_failure(error_message: String) -> void:
	# Check if we should retry
	if enable_retry and _retry_count < max_retries:
		_retry_count += 1
		var delay = retry_delay_ms * pow(2, _retry_count - 1)  # Exponential backoff
		print("[GodotBaaS] Request failed, retrying in ", delay, "ms (attempt ", _retry_count, "/", max_retries, ")")
		_retry_timer.start(delay / 1000.0)
	else:
		# Max retries reached or retry disabled
		if _retry_count >= max_retries:
			error.emit(error_message + " (Max retries reached)")
		else:
			error.emit(error_message)
		_current_request.clear()
		_retry_count = 0

# Retry timeout callback
func _on_retry_timeout() -> void:
	# Check if there's still a request to retry
	if _current_request.is_empty() or not _current_request.has("method"):
		print("[GodotBaaS] Retry cancelled - no active request")
		return
	
	print("[GodotBaaS] Retrying request...")
	_execute_request()

# Response handler
func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	print("[GodotBaaS] Request completed - Result: ", result, ", Response code: ", response_code)
	
	# Check for network-level errors
	if result != HTTPRequest.RESULT_SUCCESS:
		_connection_state = ConnectionState.ERROR
		var error_message = "Network error: "
		var should_retry = false
		
		match result:
			HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
				error_message += "Chunked body size mismatch"
			HTTPRequest.RESULT_CANT_CONNECT:
				error_message += "Cannot connect to server"
				should_retry = true
			HTTPRequest.RESULT_CANT_RESOLVE:
				error_message += "Cannot resolve hostname"
				should_retry = true
			HTTPRequest.RESULT_CONNECTION_ERROR:
				error_message += "Connection error"
				should_retry = true
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				error_message += "TLS handshake error"
			HTTPRequest.RESULT_NO_RESPONSE:
				error_message += "No response from server"
				should_retry = true
			HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
				error_message += "Response body size limit exceeded"
			HTTPRequest.RESULT_REQUEST_FAILED:
				error_message += "Request failed"
				should_retry = true
			HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
				error_message += "Cannot open download file"
			HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
				error_message += "Download file write error"
			HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
				error_message += "Redirect limit reached"
			HTTPRequest.RESULT_TIMEOUT:
				error_message += "Request timeout"
				should_retry = true
			_:
				error_message += "Unknown error (code: " + str(result) + ")"
				should_retry = true
		
		# Retry if appropriate
		if should_retry:
			_handle_request_failure(error_message)
		else:
			error.emit(error_message)
			_current_request.clear()
			_retry_count = 0
		return
	
	# Parse response body
	var body_string = body.get_string_from_utf8()
	print("[GodotBaaS] Response body: ", body_string)
	
	var json = JSON.new()
	var parse_result = json.parse(body_string)
	
	# Handle JSON parsing errors
	if parse_result != OK:
		print("[GodotBaaS] JSON parse error at line ", json.get_error_line(), ": ", json.get_error_message())
		error.emit("Failed to parse response: Invalid JSON at line " + str(json.get_error_line()) + " - " + json.get_error_message())
		return
	
	var response_data = json.data
	print("[GodotBaaS] Parsed response data: ", response_data)
	
	# Handle HTTP error responses (4xx and 5xx)
	if response_code >= 400:
		print("[GodotBaaS] Error response - Code: ", response_code)
		_handle_error_response(response_code, response_data)
		return
	
	# Handle successful responses (2xx and 3xx)
	print("[GodotBaaS] Success response - Code: ", response_code)
	_connection_state = ConnectionState.CONNECTED
	_is_online = true  # Mark as online on successful response
	
	# Cancel any pending retry timer
	if _retry_timer and _retry_timer.time_left > 0:
		_retry_timer.stop()
	
	# Remove from active requests
	var request_id = _current_request.get("id", -1)
	if request_id != -1:
		_active_requests.erase(request_id)
	
	_current_request.clear()  # Clear request context on success
	_retry_count = 0  # Reset retry count
	_handle_success_response(response_code, response_data)
	
	# Process next request in queue if any
	_process_next_queued_request()

# Handle error responses with specific error codes
func _handle_error_response(response_code: int, response_data: Variant) -> void:
	var error_message = "Unknown error"
	
	# Extract error message from response if available
	if typeof(response_data) == TYPE_DICTIONARY:
		if response_data.has("error"):
			var error_obj = response_data["error"]
			if typeof(error_obj) == TYPE_DICTIONARY and error_obj.has("message"):
				error_message = error_obj["message"]
			elif typeof(error_obj) == TYPE_STRING:
				error_message = error_obj
		elif response_data.has("message"):
			error_message = response_data["message"]
	
	# Handle specific error codes
	match response_code:
		401:
			# Unauthorized - token expired or invalid
			_authenticated = false
			player_token = ""
			auth_failed.emit(error_message)
		
		409:
			# Conflict - data version mismatch during cloud save
			# This occurs when the client's version number doesn't match the server's current version
			# The client should:
			# 1. Receive the current server version and data via the data_conflict signal
			# 2. Merge or resolve conflicts between local and server data
			# 3. Retry the save operation with the correct version number
			if typeof(response_data) == TYPE_DICTIONARY:
				var key = response_data.get("key", "")
				var current_version = response_data.get("currentVersion", 0)
				var current_data = response_data.get("currentData", {})
				data_conflict.emit(key, current_version, current_data)
			else:
				error.emit("Conflict: " + error_message)
		
		413:
			# Payload Too Large - storage quota exceeded
			error.emit("Storage quota exceeded: " + error_message)
		
		429:
			# Too Many Requests - rate limit exceeded
			error.emit("Rate limit exceeded: " + error_message)
		
		400:
			# Bad Request - could be validation error during auth
			# Check if this is an auth-related error
			if error_message.to_lower().contains("email") or error_message.to_lower().contains("password") or error_message.to_lower().contains("authentication"):
				auth_failed.emit(error_message)
			else:
				error.emit("Bad request: " + error_message)
		
		403:
			# Forbidden - could be auth-related
			if error_message.to_lower().contains("authentication") or error_message.to_lower().contains("credentials"):
				auth_failed.emit(error_message)
			else:
				error.emit("Forbidden: " + error_message)
		
		404:
			# Not Found - could be achievement not found
			if error_message.to_lower().contains("achievement"):
				achievement_unlock_failed.emit(error_message)
			else:
				error.emit("Not found: " + error_message)
		
		500, 502, 503, 504:
			# Server errors
			error.emit("Server error: " + error_message)
		
		_:
			# Generic error - check if it's achievement-related
			if error_message.to_lower().contains("achievement"):
				achievement_unlock_failed.emit(error_message)
			else:
				error.emit("HTTP " + str(response_code) + ": " + error_message)

# Handle successful responses
func _handle_success_response(_response_code: int, response_data: Variant) -> void:
	# Ensure response_data is a dictionary
	if typeof(response_data) != TYPE_DICTIONARY:
		error.emit("Invalid response format: Expected dictionary")
		return
	
	# Check if this is an authentication response
	# Handle both direct token format and nested data format
	if response_data.has("playerToken") or response_data.has("player_token"):
		_handle_auth_success(response_data)
		return
	
	# Check for nested auth response (data.token format)
	if response_data.has("data"):
		var data = response_data["data"]
		if typeof(data) == TYPE_DICTIONARY and (data.has("token") or data.has("player")):
			_handle_auth_success(data)
			return
	
	# Check for nested responses first (most common from our backend)
	if response_data.has("data"):
		var data = response_data["data"]
		if typeof(data) == TYPE_DICTIONARY:
			# Check if this is a cloud LOAD response (has value) - check this FIRST
			if data.has("value") and data.has("key"):
				var key = data["key"]
				var value = data["value"]
				
				# Include version in the value for convenience
				if data.has("version") and typeof(value) == TYPE_DICTIONARY:
					value["_version"] = data["version"]
				
				print("[GodotBaaS] Emitting data_loaded signal - Key: ", key, ", Value: ", value)
				data_loaded.emit(key, value)
				return
			
			# Check if this is a cloud SAVE response (no value, just version)
			if data.has("version") and data.has("key") and not data.has("value"):
				var key = data["key"]
				var version = data["version"]
				print("[GodotBaaS] Emitting data_saved signal (nested) - Key: ", key, ", Version: ", version)
				data_saved.emit(key, version)
				return
	
	# Check if this is a cloud load response (data loaded) at root level
	if response_data.has("value") and response_data.has("key"):
		var key = response_data["key"]
		var value = response_data["value"]
		
		# Include version in the value for convenience
		if response_data.has("version") and typeof(value) == TYPE_DICTIONARY:
			value["_version"] = response_data["version"]
		
		print("[GodotBaaS] Emitting data_loaded signal (root) - Key: ", key, ", Value: ", value)
		data_loaded.emit(key, value)
		return
	
	# Check if this is a cloud save response (data saved) at root level
	if response_data.has("version") and response_data.has("key") and not response_data.has("value"):
		var key = response_data["key"]
		var version = response_data["version"]
		print("[GodotBaaS] Emitting data_saved signal - Key: ", key, ", Version: ", version)
		data_saved.emit(key, version)
		return
	
	# Check if this is a score submission response
	if response_data.has("rank") and response_data.has("leaderboardId"):
		var rank = response_data["rank"]
		var leaderboard_id = response_data.get("leaderboardId", "")
		var leaderboard_slug = response_data.get("leaderboardSlug", leaderboard_id)
		score_submitted.emit(leaderboard_slug, rank)
		return
	
	# Check if this is a leaderboard entries response
	if response_data.has("entries") and response_data.has("leaderboard"):
		var entries = response_data["entries"]
		var leaderboard_info = response_data["leaderboard"]
		var leaderboard_slug = ""
		
		# Extract leaderboard slug from leaderboard info
		if typeof(leaderboard_info) == TYPE_DICTIONARY:
			leaderboard_slug = leaderboard_info.get("slug", "")
		elif typeof(leaderboard_info) == TYPE_STRING:
			leaderboard_slug = leaderboard_info
		
		leaderboard_loaded.emit(leaderboard_slug, entries)
		return
	
	# Check if this is a player rank response
	if response_data.has("rank") and response_data.has("score"):
		# This is a player rank response, emit as leaderboard_loaded with single entry
		var leaderboard_slug = response_data.get("leaderboardSlug", "")
		var single_entry = [response_data]
		leaderboard_loaded.emit(leaderboard_slug, single_entry)
		return
	
	# Check if this is a username update response
	if response_data.has("success") and response_data.has("player") and response_data.has("message"):
		var message = response_data["message"]
		if "username" in message.to_lower():
			var player = response_data["player"]
			print("[GodotBaaS] Username updated: ", player.get("username", ""))
			username_updated.emit(player)
			return
	
	# Check if this is an achievement grant response
	if response_data.has("success") and response_data.has("achievement") and response_data.has("isNewUnlock"):
		var achievement = response_data["achievement"]
		var is_new_unlock = response_data["isNewUnlock"]
		
		# Only emit achievement_unlocked if this is a new unlock
		if is_new_unlock:
			print("[GodotBaaS] Achievement unlocked: ", achievement.get("name", "Unknown"))
			achievement_unlocked.emit(achievement)
		else:
			print("[GodotBaaS] Achievement already unlocked: ", achievement.get("name", "Unknown"))
		return
	
	# Check if this is an achievement progress update response
	if response_data.has("success") and response_data.has("achievement") and response_data.has("unlocked"):
		var achievement = response_data["achievement"]
		var unlocked = response_data["unlocked"]
		
		# Emit progress updated signal
		print("[GodotBaaS] Achievement progress updated: ", achievement.get("name", "Unknown"))
		achievement_progress_updated.emit(achievement)
		
		# If the achievement was unlocked by this progress update, also emit unlocked signal
		if unlocked:
			print("[GodotBaaS] Achievement unlocked through progress: ", achievement.get("name", "Unknown"))
			achievement_unlocked.emit(achievement)
		return
	
	# Check if this is a get achievements response (list of achievements)
	if response_data.has("achievements") and response_data.has("stats"):
		var achievements = response_data["achievements"]
		print("[GodotBaaS] Loaded ", achievements.size(), " achievements")
		achievements_loaded.emit(achievements)
		return
	
	# Check if this is a single achievement response (from get_achievement)
	# This should be checked after the grant/progress responses to avoid conflicts
	if response_data.has("id") and response_data.has("name") and response_data.has("description"):
		# This looks like a single achievement object
		print("[GodotBaaS] Loaded single achievement: ", response_data.get("name", "Unknown"))
		achievements_loaded.emit([response_data])
		return
	
	# Check if this is a friend request sent response
	if response_data.has("success") and response_data.has("data"):
		var data = response_data["data"]
		
		# Friend request sent
		if data.has("requesterId") and data.has("addresseeId") and data.has("status"):
			if data["status"] == "PENDING":
				print("[GodotBaaS] Friend request sent")
				friend_request_sent.emit(data)
				return
			elif data["status"] == "ACCEPTED":
				print("[GodotBaaS] Friend request accepted")
				friend_request_accepted.emit(data)
				return
		
		# Friends loaded
		if data.has("friends") and data.has("count"):
			var friends = data["friends"]
			var count = data["count"]
			print("[GodotBaaS] Loaded ", friends.size(), " friends")
			friends_loaded.emit(friends, count)
			return
		
		# Pending/sent requests loaded (check this BEFORE player search)
		if data is Array and data.size() > 0 and (data[0].has("requesterId") or data[0].has("requester")):
			# This is a friend request list
			print("[GodotBaaS] Loaded ", data.size(), " friend requests")
			pending_requests_loaded.emit(data)
			sent_requests_loaded.emit(data)
			return
		
		# Player search results
		if data is Array and data.size() > 0 and data[0].has("username"):
			print("[GodotBaaS] Found ", data.size(), " players")
			players_found.emit(data)
			return
		
		# Blocked players loaded
		if data is Array and data.size() >= 0:
			# Check if this looks like a blocked players list
			var is_blocked_list = true
			for item in data:
				if not item.has("id"):
					is_blocked_list = false
					break
			
			if is_blocked_list:
				print("[GodotBaaS] Loaded ", data.size(), " blocked players")
				blocked_players_loaded.emit(data)
				return
		
		# Empty array fallback (could be empty pending requests)
		if data is Array:
			print("[GodotBaaS] Loaded empty array - assuming friend requests")
			pending_requests_loaded.emit(data)
			sent_requests_loaded.emit(data)
			return
	
	# Check for simple success messages (friend removed, blocked, unblocked, etc.)
	if response_data.has("success") and response_data.has("message"):
		var message = response_data["message"]
		
		if "removed" in message.to_lower():
			print("[GodotBaaS] Friend removed")
			friend_removed.emit()
			return
		elif "declined" in message.to_lower():
			print("[GodotBaaS] Friend request declined")
			friend_request_declined.emit()
			return
		elif "cancelled" in message.to_lower():
			print("[GodotBaaS] Friend request cancelled")
			friend_request_cancelled.emit()
			return
		elif "blocked" in message.to_lower() and "un" not in message.to_lower():
			print("[GodotBaaS] Player blocked")
			player_blocked.emit()
			return
		elif "unblocked" in message.to_lower():
			print("[GodotBaaS] Player unblocked")
			player_unblocked.emit()
			return
	
	# Check if this is a friend leaderboard response
	if response_data.has("success") and response_data.has("data"):
		var data = response_data["data"]
		if data is Array and data.size() > 0:
			# Check if this looks like leaderboard entries
			if data[0].has("rank") or data[0].has("score"):
				# This could be a friend leaderboard - we need to determine the slug
				# For now, emit with empty slug - the caller will know which leaderboard they requested
				print("[GodotBaaS] Loaded friend leaderboard entries")
				friend_leaderboard_loaded.emit("", data)
				return
	
	# Additional response handlers will be added in subsequent tasks
	pass

# Handle successful authentication responses
func _handle_auth_success(response_data: Dictionary) -> void:
	print("[GodotBaaS] Handling auth success with data: ", response_data)
	
	# Extract player token (handle multiple formats)
	var token = ""
	if response_data.has("playerToken"):
		token = response_data["playerToken"]
	elif response_data.has("player_token"):
		token = response_data["player_token"]
	elif response_data.has("token"):
		token = response_data["token"]
	
	print("[GodotBaaS] Extracted token: ", token.substr(0, 20) if token != "" else "NONE", "...")
	
	if token == "":
		print("[GodotBaaS] ERROR: No token found in response")
		auth_failed.emit("Authentication succeeded but no token received")
		return
	
	# Store the player token
	player_token = token
	_authenticated = true
	
	# Extract player data (handle both camelCase and snake_case)
	var player_info = {}
	if response_data.has("player"):
		player_info = response_data["player"]
	elif response_data.has("data"):
		player_info = response_data["data"]
	else:
		# If no player object, use the response data itself
		player_info = response_data.duplicate()
		# Remove the token from player data
		player_info.erase("playerToken")
		player_info.erase("player_token")
	
	# Store player data
	_player_data = player_info
	
	# Emit authenticated signal with player data
	authenticated.emit(player_info)


## Get or create a unique device ID
## Device ID is stored locally and persists across app restarts
func _get_or_create_device_id() -> String:
	var device_id_file = "user://godot_baas_device_id.dat"
	
	# Try to load existing device ID
	if FileAccess.file_exists(device_id_file):
		var file = FileAccess.open(device_id_file, FileAccess.READ)
		if file:
			var device_id = file.get_line()
			file.close()
			if device_id != "":
				return device_id
	
	# Generate new device ID
	var device_id = _generate_device_id()
	
	# Save device ID to file
	var file = FileAccess.open(device_id_file, FileAccess.WRITE)
	if file:
		file.store_line(device_id)
		file.close()
		print("[GodotBaaS] Generated new device ID: ", device_id.substr(0, 8), "...")
	else:
		push_error("[GodotBaaS] Failed to save device ID to file")
	
	return device_id

## Generate a unique device ID using UUID v4 format
func _generate_device_id() -> String:
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	
	# Convert to hex string
	var hex_string = ""
	for byte in random_bytes:
		hex_string += "%02x" % byte
	
	# Format as UUID (8-4-4-4-12)
	var uuid = hex_string.substr(0, 8) + "-" + \
			   hex_string.substr(8, 4) + "-" + \
			   hex_string.substr(12, 4) + "-" + \
			   hex_string.substr(16, 4) + "-" + \
			   hex_string.substr(20, 12)
	
	return uuid


## Normalize JSON numbers to match backend serialization
## Godot serializes all numbers as floats (5 -> 5.0)
## Node.js serializes integers without decimals (5 -> 5)
## This causes signature mismatches
func _normalize_json_numbers(json_string: String) -> String:
	# Use regex to replace .0 with nothing for integer values
	# Match pattern: number followed by .0 (but not .0X where X is another digit)
	var regex = RegEx.new()
	regex.compile("(\\d+)\\.0(?!\\d)")
	return regex.sub(json_string, "$1", true)
