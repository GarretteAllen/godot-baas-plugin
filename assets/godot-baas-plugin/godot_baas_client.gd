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

# API Endpoints (constants for better maintainability)
const ENDPOINT_AUTH_REGISTER = "/api/v1/game/auth/register"
const ENDPOINT_AUTH_LOGIN = "/api/v1/game/auth/login"
const ENDPOINT_AUTH_ANONYMOUS = "/api/v1/game/auth/anonymous"
const ENDPOINT_AUTH_LINK = "/api/v1/game/auth/link-account"
const ENDPOINT_PLAYER_DATA = "/api/v1/game/players/@me/data"
const ENDPOINT_LEADERBOARDS = "/api/v1/game/leaderboards"
const ENDPOINT_ANALYTICS = "/api/v1/game/analytics/events"

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
	else:
		body_string = "{}"
	
	# Generate security headers (Phase 1 Security)
	var timestamp = _get_timestamp()
	var nonce = _generate_nonce()
	var signature = _generate_signature(body_string, timestamp)
	
	# Prepare headers
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key,
		"X-Signature: " + signature,
		"X-Timestamp: " + timestamp,
		"X-Nonce: " + nonce
	]
	
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
	
	# Remove from active requests
	var request_id = _current_request.get("id", -1)
	if request_id != -1:
		_active_requests.erase(request_id)
	
	_current_request.clear()  # Clear request context on success
	_retry_count = 0  # Reset retry count
	_handle_success_response(response_code, response_data)

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
			# Not Found
			error.emit("Not found: " + error_message)
		
		500, 502, 503, 504:
			# Server errors
			error.emit("Server error: " + error_message)
		
		_:
			# Generic error
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
