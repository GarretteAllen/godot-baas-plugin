extends Node

# Config
var api_key: String = ""
var base_url: String = "https://api.godotbaas.com"
var player_token: String = ""

# Retry settings
var max_retries: int = 3
var retry_delay_ms: int = 1000
var enable_retry: bool = true

# Offline queue
var enable_offline_queue: bool = true
var max_queue_size: int = 50
var queue_timeout_seconds: int = 300

# Security
var enable_request_signing: bool = true

# Endpoints
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

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	ERROR
}

enum RequestPriority {
	LOW,
	NORMAL,
	HIGH,
	CRITICAL
}

# State
var _http_client: HTTPRequest
var _authenticated: bool = false
var _player_data: Dictionary = {}
var _connection_state: ConnectionState = ConnectionState.DISCONNECTED
var _current_request: Dictionary = {}
var _retry_count: int = 0
var _retry_timer: Timer
var _request_queue: Array = []
var _is_online: bool = true
var _network_check_timer: Timer
var _processing_queue: bool = false
var _request_id_counter: int = 0
var _active_requests: Dictionary = {}

# Auth signals
signal authenticated(player_data: Dictionary)
signal auth_failed(error: String)
signal username_updated(player_data: Dictionary)

# Network signals
signal network_online()
signal network_offline()
signal request_queued(request_id: int)
signal queue_processed(successful: int, failed: int)

# Cloud save signals
signal data_saved(key: String, version: int)
signal data_loaded(key: String, value: Variant)
signal data_conflict(key: String, server_version: int, server_data: Variant)

# Leaderboard signals
signal score_submitted(leaderboard: String, rank: int)
signal leaderboard_loaded(leaderboard: String, entries: Array)

# Achievement signals
signal achievement_unlocked(achievement: Dictionary)
signal achievement_progress_updated(achievement: Dictionary)
signal achievement_unlock_failed(error: String)
signal achievements_loaded(achievements: Array)

# Friend signals
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

signal error(error_message: String)

func _ready() -> void:
	_http_client = HTTPRequest.new()
	add_child(_http_client)
	_http_client.request_completed.connect(_on_request_completed)
	_http_client.timeout = 30.0
	
	_retry_timer = Timer.new()
	add_child(_retry_timer)
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(_on_retry_timeout)
	
	_network_check_timer = Timer.new()
	add_child(_network_check_timer)
	_network_check_timer.wait_time = 5.0
	_network_check_timer.timeout.connect(_check_network_status)
	_network_check_timer.start()

func _exit_tree() -> void:
	if _http_client:
		_http_client.queue_free()
	if _retry_timer:
		_retry_timer.queue_free()
	if _network_check_timer:
		_network_check_timer.queue_free()
	
	_request_queue.clear()
	_active_requests.clear()


func get_connection_state() -> ConnectionState:
	return _connection_state

func is_baas_connected() -> bool:
	return _connection_state == ConnectionState.CONNECTED

func is_online() -> bool:
	return _is_online

func get_queue_size() -> int:
	return _request_queue.size()

func clear_queue() -> void:
	_request_queue.clear()

func cancel_request(request_id: int) -> bool:
	if _active_requests.has(request_id):
		_active_requests.erase(request_id)
		return true
	
	for i in range(_request_queue.size()):
		if _request_queue[i].get("id") == request_id:
			_request_queue.remove_at(i)
			return true
	
	return false

func cancel_all_requests() -> void:
	_active_requests.clear()
	_request_queue.clear()

func _check_network_status() -> void:
	var was_online = _is_online
	
	_is_online = (_connection_state == ConnectionState.CONNECTED or 
				  _connection_state == ConnectionState.CONNECTING)
	
	if was_online and not _is_online:
		network_offline.emit()
	elif not was_online and _is_online:
		network_online.emit()
		_process_queue()

func _process_queue() -> void:
	if _processing_queue or _request_queue.is_empty():
		return
	
	_processing_queue = true
	
	var successful = 0
	var failed = 0
	var requests_to_process = _request_queue.duplicate()
	_request_queue.clear()
	
	for queued_request in requests_to_process:
		var age = Time.get_unix_time_from_system() - queued_request.get("timestamp", 0)
		if age > queue_timeout_seconds:
			failed += 1
			continue
		
		_current_request = {
			"method": queued_request.get("method"),
			"endpoint": queued_request.get("endpoint"),
			"body": queued_request.get("body"),
			"requires_auth": queued_request.get("requires_auth")
		}
		_retry_count = 0
		_execute_request()
		successful += 1
		
		await get_tree().create_timer(0.1).timeout
	
	_processing_queue = false
	queue_processed.emit(successful, failed)

func _process_next_queued_request() -> void:
	if _request_queue.is_empty() or not _current_request.is_empty():
		return
	
	var queued_request = _request_queue.pop_front()
	
	var age = Time.get_unix_time_from_system() - queued_request.get("timestamp", 0)
	if age > queue_timeout_seconds:
		_process_next_queued_request()
		return
	
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

func _generate_nonce() -> String:
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	return random_bytes.hex_encode()

func _generate_signature(body_string: String, timestamp: String) -> String:
	var data = body_string + timestamp
	var ctx = HashingContext.new()
	
	var key = api_key.to_utf8_buffer()
	var key_bytes = PackedByteArray()
	
	if key.size() > 64:
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(key)
		key_bytes = ctx.finish()
		key_bytes.resize(64)
	else:
		key_bytes = key.duplicate()
		key_bytes.resize(64)
	
	var ipad = PackedByteArray()
	ipad.resize(64)
	for i in range(64):
		ipad[i] = key_bytes[i] ^ 0x36
	
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(ipad)
	ctx.update(data.to_utf8_buffer())
	var inner_hash = ctx.finish()
	
	var opad = PackedByteArray()
	opad.resize(64)
	for i in range(64):
		opad[i] = key_bytes[i] ^ 0x5c
	
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(opad)
	ctx.update(inner_hash)
	var final_hash = ctx.finish()
	
	return final_hash.hex_encode()

func _get_timestamp() -> String:
	return str(int(Time.get_unix_time_from_system() * 1000))

func register_player(email: String, password: String, username: String = "") -> void:
	var body = {
		"email": email,
		"password": password
	}
	
	if username != "":
		body["username"] = username
	
	_make_request("POST", ENDPOINT_AUTH_REGISTER, body, false, RequestPriority.HIGH)

func login_player(email: String, password: String) -> void:
	var body = {
		"email": email,
		"password": password
	}
	
	_make_request("POST", ENDPOINT_AUTH_LOGIN, body, false, RequestPriority.HIGH)

func login_with_device_id() -> void:
	var device_id = _get_or_create_device_id()
	
	var body = {
		"deviceId": device_id
	}
	_make_request("POST", "/api/v1/game/auth/device", body, false, RequestPriority.HIGH)

func login_anonymous() -> void:
	_make_request("POST", ENDPOINT_AUTH_ANONYMOUS, {}, false, RequestPriority.HIGH)

func link_account(email: String, password: String, username: String = "") -> void:
	if not _authenticated or player_token == "":
		auth_failed.emit("Cannot link account: Not authenticated as anonymous player")
		return
	
	var body = {
		"email": email,
		"password": password
	}
	
	if username != "":
		body["username"] = username
	
	_make_request("POST", ENDPOINT_AUTH_LINK, body, true)

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

func logout() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot logout: Not authenticated")
		return
	
	_make_request("POST", "/api/v1/game/auth/logout", {}, true, RequestPriority.HIGH)

func save_data(key: String, value: Variant, version: int = -1) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot save data: Not authenticated")
		return
	
	var body = {
		"value": value,
		"version": version
	}
	
	_make_request("POST", ENDPOINT_PLAYER_DATA + "/" + key, body, true)

func load_data(key: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot load data: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_PLAYER_DATA + "/" + key, {}, true)

func delete_data(key: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot delete data: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_PLAYER_DATA + "/" + key, {}, true)

func resolve_conflict_with_server_data(key: String, server_version: int) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot resolve conflict: Not authenticated")
		return
	
	load_data(key)

func resolve_conflict_with_local_data(key: String, local_value: Variant, server_version: int) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot resolve conflict: Not authenticated")
		return
	
	save_data(key, local_value, server_version)

func resolve_conflict_with_merged_data(key: String, merged_value: Variant, server_version: int) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot resolve conflict: Not authenticated")
		return
	save_data(key, merged_value, server_version)

func merge_data(key: String, value: Variant, version: int = -1, strategy: String = "merge") -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot merge data: Not authenticated")
		return
	
	var body = {
		"value": value,
		"version": version,
		"strategy": strategy
	}
	
	_make_request("PATCH", ENDPOINT_PLAYER_DATA + "/" + key, body, true)

func add_to_inventory(key: String, items: Array, version: int = 0) -> void:
	merge_data(key, {"items": items}, version, "append")

func remove_from_inventory(key: String, items: Array, version: int = 0) -> void:
	merge_data(key, {"items": items}, version, "remove")

func increment_values(key: String, amounts: Dictionary, version: int = 0) -> void:
	merge_data(key, amounts, version, "increment")

func decrement_values(key: String, amounts: Dictionary, version: int = 0) -> void:
	merge_data(key, amounts, version, "decrement")

func list_data() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot list data: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_PLAYER_DATA, {}, true)

func submit_score(leaderboard_slug: String, score: int, metadata: Dictionary = {}) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot submit score: Not authenticated")
		return
	
	var body = {
		"score": score
	}
	
	if metadata.size() > 0:
		body["metadata"] = metadata
	
	_make_request("POST", ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "/submit", body, true)

func get_leaderboard(leaderboard_slug: String, limit: int = 100) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get leaderboard: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "?limit=" + str(limit), {}, true)

func get_player_rank(leaderboard_slug: String, player_id: String = "") -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get player rank: Not authenticated")
		return
	
	var endpoint: String
	if player_id == "":
		endpoint = ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "/me/rank"
	else:
		endpoint = ENDPOINT_LEADERBOARDS + "/" + leaderboard_slug + "/players/" + player_id + "/rank"
	
	_make_request("GET", endpoint, {}, true)

func grant_achievement(achievement_id: String) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot grant achievement: Not authenticated")
		return
	
	var body = {
		"achievementId": achievement_id
	}
	
	_make_request("POST", "/api/v1/game/achievements/grant", body, true)

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

func get_achievements(include_hidden: bool = false) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot get achievements: Not authenticated")
		return
	
	var endpoint = "/api/v1/game/achievements"
	if include_hidden:
		endpoint += "?includeHidden=true"
	
	_make_request("GET", endpoint, {}, true)

func get_achievement(achievement_id: String) -> void:
	if not _authenticated or player_token == "":
		achievement_unlock_failed.emit("Cannot get achievement: Not authenticated")
		return
	
	_make_request("GET", "/api/v1/game/achievements/" + achievement_id, {}, true)

func track_event(event_name: String, properties: Dictionary = {}) -> void:
	var body = {
		"eventName": event_name
	}
	
	if properties.size() > 0:
		body["properties"] = properties
	
	var requires_auth = _authenticated and player_token != ""
	_make_request("POST", ENDPOINT_ANALYTICS, body, requires_auth, RequestPriority.LOW)

func send_friend_request(player_identifier: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot send friend request: Not authenticated")
		return
	
	var body = {
		"targetPlayerId": player_identifier
	}
	
	_make_request("POST", ENDPOINT_FRIEND_REQUEST, body, true)

func accept_friend_request(friendship_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot accept friend request: Not authenticated")
		return
	
	_make_request("POST", ENDPOINT_FRIEND_REQUEST + "/" + friendship_id + "/accept", {}, true)

func decline_friend_request(friendship_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot decline friend request: Not authenticated")
		return
	
	_make_request("POST", ENDPOINT_FRIEND_REQUEST + "/" + friendship_id + "/decline", {}, true)

func cancel_friend_request(friendship_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot cancel friend request: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_FRIEND_REQUEST + "/" + friendship_id, {}, true)

func get_friends() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get friends: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIENDS, {}, true)

func remove_friend(friend_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot remove friend: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_FRIENDS + "/" + friend_id, {}, true)

func get_pending_requests() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get pending requests: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIENDS + "/requests/pending", {}, true)

func get_sent_requests() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get sent requests: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIENDS + "/requests/sent", {}, true)

func search_players(query: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot search players: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIEND_SEARCH + "?q=" + query, {}, true)

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

func unblock_player(player_id: String) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot unblock player: Not authenticated")
		return
	
	_make_request("DELETE", ENDPOINT_FRIEND_BLOCK + "/" + player_id, {}, true)

func get_blocked_players() -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get blocked players: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIEND_BLOCK, {}, true)

func get_friend_leaderboard(leaderboard_slug: String, limit: int = 100) -> void:
	if not _authenticated or player_token == "":
		error.emit("Cannot get friend leaderboard: Not authenticated")
		return
	
	_make_request("GET", ENDPOINT_FRIEND_LEADERBOARD + "/" + leaderboard_slug + "?limit=" + str(limit), {}, true)

func _make_request(method: String, endpoint: String, body: Dictionary = {}, requires_auth: bool = false, priority: RequestPriority = RequestPriority.NORMAL) -> int:
	_request_id_counter += 1
	var request_id = _request_id_counter
	
	if not _is_online and enable_offline_queue and priority != RequestPriority.CRITICAL:
		# Queue the request
		if _request_queue.size() >= max_queue_size:
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
		
		var inserted = false
		for i in range(_request_queue.size()):
			if _request_queue[i].get("priority", RequestPriority.NORMAL) < priority:
				_request_queue.insert(i, queued_request)
				inserted = true
				break
		
		if not inserted:
			_request_queue.append(queued_request)
		
		request_queued.emit(request_id)
		return request_id
	
	if _http_client.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
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
	
	_current_request = {
		"id": request_id,
		"method": method,
		"endpoint": endpoint,
		"body": body,
		"requires_auth": requires_auth,
		"priority": priority
	}
	
	_active_requests[request_id] = _current_request
	_retry_count = 0
	_execute_request()
	
	return request_id

func _execute_request() -> void:
	var method = _current_request["method"]
	var endpoint = _current_request["endpoint"]
	var body = _current_request["body"]
	var requires_auth = _current_request["requires_auth"]
	
	_connection_state = ConnectionState.CONNECTING
	
	var url = base_url + endpoint
	var body_string = ""
	if body.size() > 0:
		body_string = JSON.stringify(body)
		body_string = _normalize_json_numbers(body_string)
	else:
		body_string = "{}"
	
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key
	]
	
	if enable_request_signing:
		var timestamp = _get_timestamp()
		var nonce = _generate_nonce()
		var signature = _generate_signature(body_string, timestamp)
		headers.append("X-Signature: " + signature)
		headers.append("X-Timestamp: " + timestamp)
		headers.append("X-Nonce: " + nonce)
	
	if requires_auth and player_token != "":
		headers.append("X-Player-Token: " + player_token)
	
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
	
	var request_error = _http_client.request(url, headers, http_method, body_string)
	
	if request_error != OK:
		_connection_state = ConnectionState.ERROR
		_handle_request_failure("Network error: Failed to initiate request (Error code: " + str(request_error) + ")")
		return

func _handle_request_failure(error_message: String) -> void:
	if enable_retry and _retry_count < max_retries:
		_retry_count += 1
		var delay = retry_delay_ms * pow(2, _retry_count - 1)
		_retry_timer.start(delay / 1000.0)
	else:
		if _retry_count >= max_retries:
			error.emit(error_message + " (Max retries reached)")
		else:
			error.emit(error_message)
		_current_request.clear()
		_retry_count = 0

func _on_retry_timeout() -> void:
	if _current_request.is_empty() or not _current_request.has("method"):
		return
	
	_execute_request()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	
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
		
		if should_retry:
			_handle_request_failure(error_message)
		else:
			error.emit(error_message)
			_current_request.clear()
			_retry_count = 0
		return
	
	var body_string = body.get_string_from_utf8()
	
	var json = JSON.new()
	var parse_result = json.parse(body_string)
	
	if parse_result != OK:
		error.emit("Failed to parse response: Invalid JSON")
		return
	
	var response_data = json.data
	
	if response_code >= 400:
		_handle_error_response(response_code, response_data)
		return
	_connection_state = ConnectionState.CONNECTED
	_is_online = true
	
	if _retry_timer and _retry_timer.time_left > 0:
		_retry_timer.stop()
	
	var request_id = _current_request.get("id", -1)
	if request_id != -1:
		_active_requests.erase(request_id)
	
	var endpoint = _current_request.get("endpoint", "")
	_current_request.clear()
	_retry_count = 0
	_handle_success_response(response_code, response_data, endpoint)
	
	_process_next_queued_request()

func _handle_error_response(response_code: int, response_data: Variant) -> void:
	var error_message = "Unknown error"
	
	if typeof(response_data) == TYPE_DICTIONARY:
		if response_data.has("error"):
			var error_obj = response_data["error"]
			if typeof(error_obj) == TYPE_DICTIONARY and error_obj.has("message"):
				var msg = error_obj["message"]
				error_message = str(msg) if typeof(msg) != TYPE_STRING else msg
			elif typeof(error_obj) == TYPE_STRING:
				error_message = error_obj
		elif response_data.has("message"):
			var msg = response_data["message"]
			error_message = str(msg) if typeof(msg) != TYPE_STRING else msg
	
	match response_code:
		401:
			_authenticated = false
			player_token = ""
			auth_failed.emit(error_message)
		
		409:
			if typeof(response_data) == TYPE_DICTIONARY and response_data.has("error"):
				var error_obj = response_data["error"]
				if typeof(error_obj) == TYPE_DICTIONARY and error_obj.get("code") == "CONFLICT":
					_handle_version_conflict()
					return
			
			if typeof(response_data) == TYPE_DICTIONARY:
				var key = response_data.get("key", "")
				var current_version = response_data.get("currentVersion", 0)
				var current_data = response_data.get("currentData", {})
				data_conflict.emit(key, current_version, current_data)
			else:
				error.emit("Conflict: " + error_message)
		
		413:
			error.emit("Storage quota exceeded: " + error_message)
		
		429:
			error.emit("Rate limit exceeded: " + error_message)
		
		400:
			var msg_lower = error_message.to_lower() if typeof(error_message) == TYPE_STRING else ""
			if msg_lower.contains("email") or msg_lower.contains("password") or msg_lower.contains("authentication"):
				auth_failed.emit(error_message)
			else:
				error.emit("Bad request: " + str(error_message))
		
		403:
			var msg_lower = error_message.to_lower() if typeof(error_message) == TYPE_STRING else ""
			if msg_lower.contains("authentication") or msg_lower.contains("credentials"):
				auth_failed.emit(error_message)
			else:
				error.emit("Forbidden: " + str(error_message))
		
		404:
			var msg_lower = error_message.to_lower() if typeof(error_message) == TYPE_STRING else ""
			if msg_lower.contains("achievement"):
				achievement_unlock_failed.emit(error_message)
			else:
				error.emit("Not found: " + str(error_message))
		
		500, 502, 503, 504:
			error.emit("Server error: " + str(error_message))
		
		_:
			var msg_lower = error_message.to_lower() if typeof(error_message) == TYPE_STRING else ""
			if msg_lower.contains("achievement"):
				achievement_unlock_failed.emit(error_message)
			else:
				error.emit("HTTP " + str(response_code) + ": " + str(error_message))

func _handle_version_conflict() -> void:
	if not _current_request.has("endpoint") or not _current_request.has("body"):
		error.emit("Version conflict: Cannot resolve - missing request data")
		_current_request.clear()
		_retry_count = 0
		_process_next_queued_request()
		return
	
	var endpoint = _current_request["endpoint"]
	var body = _current_request["body"]
	
	var key_match = endpoint.split("/")
	if key_match.size() == 0:
		error.emit("Version conflict: Cannot extract key from endpoint")
		_current_request.clear()
		_retry_count = 0
		_process_next_queued_request()
		return
	
	var key = key_match[key_match.size() - 1]
	var local_data = body.get("value", {})
	
	_current_request.clear()
	_retry_count = 0
	
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	
	var url = base_url + ENDPOINT_PLAYER_DATA + "/" + key
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key,
		"X-Player-Token: " + player_token
	]
	
	temp_http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray):
		temp_http.queue_free()
		
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			data_conflict.emit(key, 0, local_data)
			_process_next_queued_request()
			return
		
		var body_string = response_body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(body_string) != OK:
			data_conflict.emit(key, 0, local_data)
			_process_next_queued_request()
			return
		
		var response_data = json.data
		if typeof(response_data) == TYPE_DICTIONARY and response_data.has("data"):
			var data = response_data["data"]
			if typeof(data) == TYPE_DICTIONARY:
				var server_version = data.get("version", 0)
				var server_data = data.get("value", {})
				
				data_conflict.emit(key, server_version, server_data)
				_process_next_queued_request()
				return
		
		data_conflict.emit(key, 0, local_data)
		_process_next_queued_request()
	)
	
	temp_http.request(url, headers)

func _handle_success_response(_response_code: int, response_data: Variant, endpoint: String = "") -> void:
	if typeof(response_data) != TYPE_DICTIONARY:
		error.emit("Invalid response format: Expected dictionary")
		return
	
	if response_data.has("playerToken") or response_data.has("player_token"):
		_handle_auth_success(response_data)
		return
	
	if response_data.has("data"):
		var data = response_data["data"]
		if typeof(data) == TYPE_DICTIONARY and (data.has("token") or data.has("player")):
			_handle_auth_success(data)
			return
	
	if response_data.has("data"):
		var data = response_data["data"]
		if typeof(data) == TYPE_DICTIONARY:
			if data.has("value") and data.has("key"):
				var key = data["key"]
				var value = data["value"]
				
				if data.has("version") and typeof(value) == TYPE_DICTIONARY:
					value["_version"] = data["version"]
				
				data_loaded.emit(key, value)
				return
			
			if data.has("version") and data.has("key") and not data.has("value"):
				var key = data["key"]
				var version = data["version"]
				data_saved.emit(key, version)
				return
	
	if response_data.has("value") and response_data.has("key"):
		var key = response_data["key"]
		var value = response_data["value"]
		
		if response_data.has("version") and typeof(value) == TYPE_DICTIONARY:
			value["_version"] = response_data["version"]
		
		data_loaded.emit(key, value)
		return
	
	if response_data.has("version") and response_data.has("key") and not response_data.has("value"):
		var key = response_data["key"]
		var version = response_data["version"]
		print("[GodotBaaS] Emitting data_saved signal - Key: ", key, ", Version: ", version)
		data_saved.emit(key, version)
		return
	
	if response_data.has("rank") and response_data.has("leaderboardId"):
		var rank = response_data["rank"]
		var leaderboard_id = response_data.get("leaderboardId", "")
		var leaderboard_slug = response_data.get("leaderboardSlug", leaderboard_id)
		score_submitted.emit(leaderboard_slug, rank)
		return
	
	# Check if leaderboard data is wrapped in a "data" field
	if response_data.has("entries") and (response_data.has("leaderboardSlug") or response_data.has("leaderboard")):
		var entries = response_data["entries"]
		var leaderboard_slug = response_data.get("leaderboardSlug", "")
		
		if leaderboard_slug == "" and response_data.has("leaderboard"):
			var leaderboard_info = response_data["leaderboard"]
			if typeof(leaderboard_info) == TYPE_DICTIONARY:
				leaderboard_slug = leaderboard_info.get("slug", "")
			elif typeof(leaderboard_info) == TYPE_STRING:
				leaderboard_slug = leaderboard_info
		
		leaderboard_loaded.emit(leaderboard_slug, entries)
		return
	
	if response_data.has("data"):
		var data = response_data["data"]
		if typeof(data) == TYPE_DICTIONARY:
			if data.has("entries") and (data.has("leaderboardSlug") or data.has("leaderboard")):
				var entries = data["entries"]
				var leaderboard_slug = data.get("leaderboardSlug", "")
				
				if leaderboard_slug == "" and data.has("leaderboard"):
					var leaderboard_info = data["leaderboard"]
					if typeof(leaderboard_info) == TYPE_DICTIONARY:
						leaderboard_slug = leaderboard_info.get("slug", "")
					elif typeof(leaderboard_info) == TYPE_STRING:
						leaderboard_slug = leaderboard_info
				
				leaderboard_loaded.emit(leaderboard_slug, entries)
				return
	
	if response_data.has("rank") and response_data.has("score"):
		var leaderboard_slug = response_data.get("leaderboardSlug", "")
		var single_entry = [response_data]
		leaderboard_loaded.emit(leaderboard_slug, single_entry)
		return
	
	if response_data.has("success") and response_data.has("player") and response_data.has("message"):
		var message = response_data["message"]
		var msg_str = str(message) if typeof(message) != TYPE_STRING else message
		if "username" in msg_str.to_lower():
			var player = response_data["player"]
			username_updated.emit(player)
			return
	
	if response_data.has("success") and response_data.has("achievement") and response_data.has("isNewUnlock"):
		var achievement = response_data["achievement"]
		var is_new_unlock = response_data["isNewUnlock"]
		
		if is_new_unlock:
			achievement_unlocked.emit(achievement)
		return
	
	if response_data.has("success") and response_data.has("achievement") and response_data.has("unlocked"):
		var achievement = response_data["achievement"]
		var unlocked = response_data["unlocked"]
		
		achievement_progress_updated.emit(achievement)
		
		if unlocked:
			achievement_unlocked.emit(achievement)
		return
	
	if response_data.has("achievements") and response_data.has("stats"):
		var achievements = response_data["achievements"]
		achievements_loaded.emit(achievements)
		return
	
	if response_data.has("id") and response_data.has("name") and response_data.has("description"):
		achievements_loaded.emit([response_data])
		return
	
	if response_data.has("success") and response_data.has("data"):
		var data = response_data["data"]
		if endpoint.contains("/friends/search"):
			players_found.emit(data)
			return
		
		if endpoint.contains("/friends/block"):
			blocked_players_loaded.emit(data)
			return
		
		if data.has("requesterId") and data.has("addresseeId") and data.has("status"):
			if data["status"] == "PENDING":
				friend_request_sent.emit(data)
				return
			elif data["status"] == "ACCEPTED":
				print("[GodotBaaS] Friend request accepted")
				friend_request_accepted.emit(data)
				return
		
		if data.has("friends") and data.has("count"):
			var friends = data["friends"]
			var count = data["count"]
			print("[GodotBaaS] Loaded ", friends.size(), " friends")
			friends_loaded.emit(friends, count)
			return
		
		if data is Array and data.size() > 0 and (data[0].has("requesterId") or data[0].has("requester")):
			print("[GodotBaaS] Loaded ", data.size(), " friend requests")
			pending_requests_loaded.emit(data)
			sent_requests_loaded.emit(data)
			return
		
		if data is Array and data.size() > 0 and data[0].has("username"):
			print("[GodotBaaS] Found ", data.size(), " players")
			players_found.emit(data)
			return
		
		if data is Array and data.size() > 0:
			var is_blocked_list = true
			for item in data:
				if not item.has("id"):
					is_blocked_list = false
					break
			
			if is_blocked_list:
				print("[GodotBaaS] Loaded ", data.size(), " blocked players")
				blocked_players_loaded.emit(data)
				return
		

	
	if response_data.has("success") and response_data.has("message"):
		var message = response_data["message"]
		var msg_str = str(message) if typeof(message) != TYPE_STRING else message
		var msg_lower = msg_str.to_lower()
		
		if "removed" in msg_lower:
			print("[GodotBaaS] Friend removed")
			friend_removed.emit()
			return
		elif "declined" in msg_lower:
			print("[GodotBaaS] Friend request declined")
			friend_request_declined.emit()
			return
		elif "cancelled" in msg_lower:
			print("[GodotBaaS] Friend request cancelled")
			friend_request_cancelled.emit()
			return
		elif "blocked" in msg_lower and "un" not in msg_lower:
			print("[GodotBaaS] Player blocked")
			player_blocked.emit()
			return
		elif "unblocked" in msg_lower:
			print("[GodotBaaS] Player unblocked")
			player_unblocked.emit()
			return
	
	if response_data.has("success") and response_data.has("data"):
		var data = response_data["data"]
		if data is Array and data.size() > 0:
			if data[0].has("rank") or data[0].has("score"):
				print("[GodotBaaS] Loaded friend leaderboard entries")
				friend_leaderboard_loaded.emit("", data)
				return
	
	if response_data.has("success") and response_data.has("message"):
		var message = response_data["message"]
		var msg_str = str(message) if typeof(message) != TYPE_STRING else message
		if "logged out" in msg_str.to_lower():
			print("[GodotBaaS] Player logged out successfully")
			_authenticated = false
			player_token = ""
			_player_data.clear()
			auth_failed.emit("Logged out successfully")
			return

func _handle_auth_success(response_data: Dictionary) -> void:
	print("[GodotBaaS] Handling auth success with data: ", response_data)
	
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
	
	player_token = token
	_authenticated = true
	
	var player_info = {}
	if response_data.has("player"):
		player_info = response_data["player"]
	elif response_data.has("data"):
		player_info = response_data["data"]
	else:
		player_info = response_data.duplicate()
		player_info.erase("playerToken")
		player_info.erase("player_token")
	
	_player_data = player_info
	authenticated.emit(player_info)

func _get_or_create_device_id() -> String:
	var device_id_file = "user://godot_baas_device_id.dat"
	
	if FileAccess.file_exists(device_id_file):
		var file = FileAccess.open(device_id_file, FileAccess.READ)
		if file:
			var device_id = file.get_line()
			file.close()
			if device_id != "":
				return device_id
	
	var device_id = _generate_device_id()
	
	var file = FileAccess.open(device_id_file, FileAccess.WRITE)
	if file:
		file.store_line(device_id)
		file.close()
		print("[GodotBaaS] Generated new device ID: ", device_id.substr(0, 8), "...")
	else:
		push_error("[GodotBaaS] Failed to save device ID to file")
	
	return device_id

func _generate_device_id() -> String:
	var crypto = Crypto.new()
	var random_bytes = crypto.generate_random_bytes(16)
	
	var hex_string = ""
	for byte in random_bytes:
		hex_string += "%02x" % byte
	
	var uuid = hex_string.substr(0, 8) + "-" + \
			   hex_string.substr(8, 4) + "-" + \
			   hex_string.substr(12, 4) + "-" + \
			   hex_string.substr(16, 4) + "-" + \
			   hex_string.substr(20, 12)
	
	return uuid

func _normalize_json_numbers(json_string: String) -> String:
	var regex = RegEx.new()
	regex.compile("(\\d+)\\.0(?!\\d)")
	return regex.sub(json_string, "$1", true)

# Messaging signals
signal message_sent(message: Dictionary)
signal message_received(message: Dictionary)
signal conversation_loaded(conversation: Dictionary)
signal conversations_loaded(conversations: Array)
signal message_deleted()

# Group signals
signal group_created(group: Dictionary)
signal group_loaded(group: Dictionary)
signal groups_loaded(groups: Array)
signal group_updated(group: Dictionary)
signal group_deleted()
signal group_left()
signal player_invited(invitation: Dictionary)
signal invitation_accepted()
signal invitation_declined()
signal pending_invitations_loaded(invitations: Array)
signal member_removed()
signal ownership_transferred()
signal member_muted()
signal member_unmuted()

# Group messaging signals
signal group_message_sent(message: Dictionary)
signal group_message_received(message: Dictionary)
signal group_messages_loaded(data: Dictionary)
signal group_message_deleted()
signal group_messages_marked_read()
signal group_messages_searched(messages: Array)

# Notification signals
signal notification_received(notification: Dictionary)
signal notifications_loaded(data: Dictionary)
signal notification_marked_read()
signal all_notifications_marked_read()
signal notification_deleted()
signal notification_preferences_loaded(preferences: Dictionary)
signal notification_preferences_updated(preferences: Dictionary)
signal notifications_muted()
signal notifications_unmuted()

# Messaging endpoints
const ENDPOINT_MESSAGES_DIRECT = "/api/v1/game/messages/direct"
const ENDPOINT_MESSAGES_CONVERSATIONS = "/api/v1/game/messages/conversations"
const ENDPOINT_MESSAGES_BLOCK = "/api/v1/game/messages/block"
const ENDPOINT_MESSAGES_BLOCKED = "/api/v1/game/messages/blocked"

# Group endpoints
const ENDPOINT_GROUPS = "/api/v1/game/groups"
const ENDPOINT_GROUP_INVITATIONS_PENDING = "/api/v1/game/groups/invitations/pending"

# Notification endpoints
const ENDPOINT_NOTIFICATIONS = "/api/v1/game/notifications"
const ENDPOINT_NOTIFICATIONS_PREFERENCES = "/api/v1/game/notifications/preferences"
const ENDPOINT_NOTIFICATIONS_MUTE = "/api/v1/game/notifications/mute"
const ENDPOINT_NOTIFICATIONS_UNMUTE = "/api/v1/game/notifications/unmute"
const ENDPOINT_NOTIFICATIONS_READ_ALL = "/api/v1/game/notifications/read-all"

# ============================================================================
# MESSAGING METHODS
# ============================================================================

func send_message(recipient_id: String, content: String) -> void:
	var body = {
		"recipientId": recipient_id,
		"content": content
	}
	_make_request("POST", ENDPOINT_MESSAGES_DIRECT, body, true)

func get_conversations() -> void:
	_make_request("GET", ENDPOINT_MESSAGES_CONVERSATIONS, {}, true)

func get_conversation(conversation_id: String, limit: int = 50, offset: int = 0) -> void:
	var url = ENDPOINT_MESSAGES_CONVERSATIONS + "/" + conversation_id + "?limit=" + str(limit) + "&offset=" + str(offset)
	_make_request("GET", url, {}, true)

func delete_message(message_id: String) -> void:
	var url = "/api/v1/game/messages/" + message_id
	_make_request("DELETE", url, {}, true)

func mark_message_read(message_id: String) -> void:
	var url = "/api/v1/game/messages/" + message_id + "/read"
	_make_request("POST", url, {}, true)

# ============================================================================
# GROUP METHODS
# ============================================================================

func create_group(name: String, description: String = "", max_members: int = 0) -> void:
	var body = {"name": name}
	if description != "":
		body["description"] = description
	if max_members > 0:
		body["maxMembers"] = max_members
	_make_request("POST", ENDPOINT_GROUPS, body, true)

func get_player_groups() -> void:
	_make_request("GET", ENDPOINT_GROUPS, {}, true)

func get_group(group_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id
	_make_request("GET", url, {}, true)

func update_group(group_id: String, name: String = "", description: String = "", max_members: int = 0) -> void:
	var body = {}
	if name != "":
		body["name"] = name
	if description != "":
		body["description"] = description
	if max_members > 0:
		body["maxMembers"] = max_members
	var url = ENDPOINT_GROUPS + "/" + group_id
	_make_request("PATCH", url, body, true)

func delete_group(group_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id
	_make_request("DELETE", url, {}, true)

func leave_group(group_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/leave"
	_make_request("POST", url, {}, true)

func invite_player(group_id: String, player_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/invite"
	var body = {"playerId": player_id}
	_make_request("POST", url, body, true)

func accept_invitation(group_id: String, invitation_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/invitations/" + invitation_id + "/accept"
	_make_request("POST", url, {}, true)

func decline_invitation(group_id: String, invitation_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/invitations/" + invitation_id + "/decline"
	_make_request("POST", url, {}, true)

func get_pending_invitations() -> void:
	_make_request("GET", ENDPOINT_GROUP_INVITATIONS_PENDING, {}, true)

func remove_member(group_id: String, player_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/members/" + player_id
	_make_request("DELETE", url, {}, true)

func transfer_ownership(group_id: String, new_owner_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/transfer-ownership"
	var body = {"newOwnerId": new_owner_id}
	_make_request("POST", url, body, true)

func mute_member(group_id: String, player_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/members/" + player_id + "/mute"
	_make_request("POST", url, {}, true)

func unmute_member(group_id: String, player_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/members/" + player_id + "/mute"
	_make_request("DELETE", url, {}, true)

# ============================================================================
# GROUP MESSAGING METHODS
# ============================================================================

func send_group_message(group_id: String, content: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/messages"
	var body = {"content": content}
	_make_request("POST", url, body, true)

func get_group_messages(group_id: String, limit: int = 100, offset: int = 0) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/messages?limit=" + str(limit) + "&offset=" + str(offset)
	_make_request("GET", url, {}, true)

func delete_group_message(group_id: String, message_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/messages/" + message_id
	_make_request("DELETE", url, {}, true)

func mark_group_messages_read(group_id: String) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/messages/read"
	_make_request("POST", url, {}, true)

func search_group_messages(group_id: String, query: String, limit: int = 50) -> void:
	var url = ENDPOINT_GROUPS + "/" + group_id + "/messages/search?q=" + query.uri_encode() + "&limit=" + str(limit)
	_make_request("GET", url, {}, true)

# ============================================================================
# NOTIFICATION METHODS
# ============================================================================

func get_notifications(limit: int = 20, offset: int = 0) -> void:
	var url = ENDPOINT_NOTIFICATIONS + "?limit=" + str(limit) + "&offset=" + str(offset)
	_make_request("GET", url, {}, true)

func mark_notification_read(notification_id: String) -> void:
	var url = ENDPOINT_NOTIFICATIONS + "/" + notification_id + "/read"
	_make_request("POST", url, {}, true)

func mark_all_notifications_read() -> void:
	_make_request("POST", ENDPOINT_NOTIFICATIONS_READ_ALL, {}, true)

func delete_notification(notification_id: String) -> void:
	var url = ENDPOINT_NOTIFICATIONS + "/" + notification_id
	_make_request("DELETE", url, {}, true)

func get_notification_preferences() -> void:
	_make_request("GET", ENDPOINT_NOTIFICATIONS_PREFERENCES, {}, true)

func update_notification_preferences(direct_messages: bool = true, group_messages: bool = true, invitations: bool = true) -> void:
	var body = {
		"directMessagesEnabled": direct_messages,
		"groupMessagesEnabled": group_messages,
		"invitationsEnabled": invitations
	}
	_make_request("PATCH", ENDPOINT_NOTIFICATIONS_PREFERENCES, body, true)

func mute_notifications(mute_until: String) -> void:
	var body = {"muteUntil": mute_until}
	_make_request("POST", ENDPOINT_NOTIFICATIONS_MUTE, body, true)

func unmute_notifications() -> void:
	_make_request("POST", ENDPOINT_NOTIFICATIONS_UNMUTE, {}, true)
