extends Node

# Config
var api_key: String = ""
var base_url: String = "https://api.godotbaas.com"
var player_token: String = ""

# Concurrency
var max_concurrent_requests: int = 2

# Write batching
var coalesce_writes_enabled: bool = true
var coalesce_window_ms: int = 150

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
var use_v2_signatures: bool = false
var project_signing_secret: String = ""

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

enum WriteType {
	OVERWRITE,
	INCREMENT,
	APPEND,
	ONE_SHOT
}

const WRITE_OPERATION_METADATA := {
	"save_data": {
		"coalescible": true,
		"write_type": WriteType.OVERWRITE,
		"merge_key_builder": "_merge_key_player_data",
		"merge_value_field": "value",
		"urgency": RequestPriority.NORMAL
	},
	"merge_data": {
		"coalescible": true,
		"write_type": WriteType.OVERWRITE,
		"merge_key_builder": "_merge_key_player_data",
		"merge_value_field": "value",
		"strategy_field": "strategy",
		"coalescible_strategies": ["merge", "increment", "decrement"],
		"urgency": RequestPriority.NORMAL
	},
	"track_event": {
		"coalescible": false,
		"write_type": WriteType.ONE_SHOT,
		"urgency": RequestPriority.LOW
	}
}

var _http_clients: Array = []
var _http_client_usage: Dictionary = {}
var _authenticated: bool = false
var _player_data: Dictionary = {}
var _connection_state: ConnectionState = ConnectionState.DISCONNECTED
var _request_queue: Array = []
var _is_online: bool = true
var _network_check_timer: Timer
var _request_id_counter: int = 0
var _active_requests: Dictionary = {}
var _pending_writes: Dictionary = {}
var _pending_write_flush_timer: Timer
var _pending_retry_timers: Dictionary = {}

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
	_initialize_http_clients()
	
	_pending_write_flush_timer = Timer.new()
	_pending_write_flush_timer.one_shot = true
	add_child(_pending_write_flush_timer)
	_pending_write_flush_timer.timeout.connect(_flush_pending_writes)

	_network_check_timer = Timer.new()
	add_child(_network_check_timer)
	_network_check_timer.wait_time = 5.0
	_network_check_timer.timeout.connect(_check_network_status)
	_network_check_timer.start()

func _exit_tree() -> void:
	_clear_http_clients()
	if _network_check_timer:
		_network_check_timer.queue_free()
	if _pending_write_flush_timer:
		_pending_write_flush_timer.queue_free()
	for timer in _pending_retry_timers.values():
		if timer:
			timer.stop()
			timer.queue_free()
	_pending_retry_timers.clear()
	
	_request_queue.clear()
	_active_requests.clear()
	_pending_writes.clear()


func _handle_write_operation(operation_name: String, method: String, endpoint: String, body: Dictionary, requires_auth: bool, default_priority: RequestPriority, context: Dictionary = {}) -> void:
	var metadata: Variant = WRITE_OPERATION_METADATA.get(operation_name)
	var priority: RequestPriority = default_priority
	if typeof(metadata) == TYPE_DICTIONARY:
		if metadata.has("urgency"):
			priority = metadata["urgency"]
	else:
		_make_request(method, endpoint, body, requires_auth, priority)
		return
	
	var is_coalescible: bool = metadata.get("coalescible", false)
	var write_type: WriteType = metadata.get("write_type", WriteType.ONE_SHOT)
	var merge_key: String = ""
	if metadata.has("merge_key_builder"):
		var builder_name: String = metadata["merge_key_builder"]
		if has_method(builder_name):
			merge_key = call(builder_name, context)
	var can_queue_merge: bool = is_coalescible and merge_key != ""
	if not coalesce_writes_enabled or not is_coalescible:
		_make_request(method, endpoint, body, requires_auth, priority, can_queue_merge, merge_key, write_type)
		return
	
	if metadata.has("strategy_field"):
		var strategy_field: String = metadata["strategy_field"]
		var strategy_value: Variant = context.get("strategy", body.get(strategy_field, ""))
		var allowed_strategies: Array = metadata.get("coalescible_strategies", [])
		if typeof(strategy_value) == TYPE_STRING and not allowed_strategies.has(strategy_value):
			_make_request(method, endpoint, body, requires_auth, priority, can_queue_merge, merge_key, write_type)
			return
		elif typeof(strategy_value) != TYPE_STRING and not allowed_strategies.is_empty():
			_make_request(method, endpoint, body, requires_auth, priority, can_queue_merge, merge_key, write_type)
			return
	
	if merge_key == "":
		_make_request(method, endpoint, body, requires_auth, priority, false, merge_key, write_type)
		return
	
	var pending_entry = {
		"method": method,
		"endpoint": endpoint,
		"data": body,
		"requires_auth": requires_auth,
		"priority": priority,
		"write_type": metadata.get("write_type", WriteType.ONE_SHOT),
		"timestamp": Time.get_unix_time_from_system(),
		"context": context.duplicate(true),
		"merge_key": merge_key
	}
	_queue_pending_write(merge_key, pending_entry)


func _queue_pending_write(merge_key: String, entry: Dictionary) -> void:
	if _pending_writes.has(merge_key):
		var merged = _merge_pending_write(_pending_writes[merge_key], entry)
		_pending_writes[merge_key] = merged
	else:
		_pending_writes[merge_key] = entry
	_schedule_pending_write_flush()


func _merge_pending_write(existing: Dictionary, incoming: Dictionary) -> Dictionary:
	var write_type: WriteType = incoming.get("write_type", WriteType.ONE_SHOT)
	existing["write_type"] = write_type
	match write_type:
		WriteType.OVERWRITE:
			existing["data"] = incoming.get("data", {})
		WriteType.INCREMENT:
			existing["data"] = _merge_increment_payload(existing.get("data", {}), incoming.get("data", {}))
		WriteType.APPEND:
			existing["data"] = _merge_append_payload(existing.get("data", []), incoming.get("data", []))
		_:
			existing["data"] = incoming.get("data", {})
	
	existing["timestamp"] = incoming.get("timestamp", Time.get_unix_time_from_system())
	existing["context"] = incoming.get("context", {})
	existing["method"] = incoming.get("method", existing.get("method", ""))
	existing["endpoint"] = incoming.get("endpoint", existing.get("endpoint", ""))
	existing["requires_auth"] = incoming.get("requires_auth", existing.get("requires_auth", false))
	var existing_priority: RequestPriority = existing.get("priority", RequestPriority.NORMAL)
	var incoming_priority: RequestPriority = incoming.get("priority", RequestPriority.NORMAL)
	existing["priority"] = existing_priority if existing_priority > incoming_priority else incoming_priority
	return existing


func _merge_increment_payload(original: Variant, incoming: Variant) -> Dictionary:
	var base: Dictionary = {}
	if typeof(original) == TYPE_DICTIONARY:
		base = original.duplicate(true)
	var additions: Dictionary = {}
	if typeof(incoming) == TYPE_DICTIONARY:
		additions = incoming
	for key in additions.keys():
		var delta = additions[key]
		if typeof(delta) == TYPE_INT or typeof(delta) == TYPE_FLOAT:
			var current_value = base.get(key, 0)
			if typeof(current_value) == TYPE_INT or typeof(current_value) == TYPE_FLOAT:
				base[key] = current_value + delta
			else:
				base[key] = delta
		else:
			base[key] = delta
	return base


func _merge_append_payload(original: Variant, incoming: Variant) -> Array:
	var base_array: Array = []
	if typeof(original) == TYPE_ARRAY:
		base_array = original.duplicate(true)
	if typeof(incoming) == TYPE_ARRAY:
		for item in incoming:
			base_array.append(item)
	return base_array


func _schedule_pending_write_flush() -> void:
	if not _pending_write_flush_timer:
		return
	if _pending_writes.is_empty():
		if _pending_write_flush_timer.time_left > 0:
			_pending_write_flush_timer.stop()
		return
	var wait_time_ms = max(coalesce_window_ms, 1)
	_pending_write_flush_timer.start(wait_time_ms / 1000.0)


func _flush_pending_writes() -> void:
	if _pending_writes.is_empty():
		return
	var writes_to_flush = _pending_writes.duplicate(true)
	_pending_writes.clear()
	for merge_key in writes_to_flush.keys():
		var entry: Dictionary = writes_to_flush[merge_key]
		var method: String = entry.get("method", "POST")
		var endpoint: String = entry.get("endpoint", "")
		var body: Dictionary = entry.get("data", {})
		var requires_auth: bool = entry.get("requires_auth", false)
		var priority: RequestPriority = entry.get("priority", RequestPriority.NORMAL)
		if endpoint == "":
			continue
		_make_request(method, endpoint, body, requires_auth, priority)


func _merge_key_player_data(context: Dictionary) -> String:
	var key = str(context.get("key", ""))
	return "player_data:" + key


func _initialize_http_clients() -> void:
	_clear_http_clients()
	var pool_size = max(1, max_concurrent_requests)
	for i in range(pool_size):
		var client = HTTPRequest.new()
		add_child(client)
		client.timeout = 30.0
		var callable = Callable(self, "_on_http_request_completed").bind(client)
		client.set_meta("_baas_completion_callable", callable)
		client.request_completed.connect(callable)
		_http_clients.append(client)
		_http_client_usage[client.get_instance_id()] = {
			"busy": false,
			"request_id": -1
		}


func _clear_http_clients() -> void:
	for client in _http_clients:
		if client:
			var callable = client.get_meta("_baas_completion_callable", null)
			if callable and client.request_completed.is_connected(callable):
				client.request_completed.disconnect(callable)
			client.queue_free()
	_http_clients.clear()
	_http_client_usage.clear()


func _get_idle_http_client() -> HTTPRequest:
	for client in _http_clients:
		if client and not _http_client_usage.get(client.get_instance_id(), {}).get("busy", false):
			return client
	return null


func _mark_client_busy(client: HTTPRequest, request_id: int) -> void:
	if not client:
		return
	var client_id = client.get_instance_id()
	var usage = _http_client_usage.get(client_id, {})
	usage["busy"] = true
	usage["request_id"] = request_id
	_http_client_usage[client_id] = usage


func _mark_client_idle(client: HTTPRequest) -> void:
	if not client:
		return
	var client_id = client.get_instance_id()
	var usage = _http_client_usage.get(client_id, {})
	usage["busy"] = false
	usage["request_id"] = -1
	_http_client_usage[client_id] = usage


func _try_dispatch_request(request: Dictionary) -> bool:
	if not _is_online:
		return false
	var client = _get_idle_http_client()
	if client == null:
		return false
	_active_requests[request.get("id")] = request
	_execute_request_with_client(client, request)
	return true


func _execute_request_with_client(client: HTTPRequest, request: Dictionary) -> void:
	if not client:
		return
	var method = request.get("method", "GET")
	var endpoint = request.get("endpoint", "")
	var body = request.get("body", {})
	var requires_auth = request.get("requires_auth", false)
	request["client"] = client
	request["client_id"] = client.get_instance_id()
	if not request.has("retries"):
		request["retries"] = 0
	_mark_client_busy(client, request.get("id", -1))
	_connection_state = ConnectionState.CONNECTING
	
	var url = base_url + endpoint
	var body_string = "{}"
	if body.size() > 0:
		body_string = JSON.stringify(body)
		body_string = _normalize_json_numbers(body_string)
	
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"X-API-Key: " + api_key
	]
	
	if enable_request_signing:
		var timestamp = _get_timestamp()
		var nonce = _generate_nonce()
		if use_v2_signatures and project_signing_secret != "":
			var signature = _generate_signature_v2(body_string, timestamp)
			headers.append("X-Signature-V2: " + signature)
			headers.append("X-Timestamp-V2: " + timestamp)
		else:
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
	
	var request_error = client.request(url, headers, http_method, body_string)
	if request_error != OK:
		_connection_state = ConnectionState.ERROR
		_handle_request_failure(request.get("id", -1), "Network error: Failed to initiate request (Error code: " + str(request_error) + ")", true)
		return


func _on_http_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, client: HTTPRequest) -> void:
	var client_id = client.get_instance_id()
	var usage = _http_client_usage.get(client_id, {})
	var request_id = usage.get("request_id", -1)
	if request_id == -1:
		_mark_client_idle(client)
		return
	var request: Dictionary = _active_requests.get(request_id, {})
	if request.is_empty():
		_mark_client_idle(client)
		return
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_connection_state = ConnectionState.ERROR
		var error_message = _map_http_error(result)
		var retryable = _is_retryable_error(result)
		_handle_request_failure(request_id, error_message, retryable)
		return
	
	var body_string = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(body_string) != OK:
		error.emit("Failed to parse response: Invalid JSON")
		_finalize_request(request_id)
		_try_process_queue()
		return
	var response_data = json.data
	if response_code >= 400:
		_handle_error_response(request, response_code, response_data)
		_finalize_request(request_id)
		_try_process_queue()
		return
	_connection_state = ConnectionState.CONNECTED
	_is_online = true
	_handle_success_response(response_code, response_data, request)
	_finalize_request(request_id)
	_try_process_queue()


func _map_http_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "Network error: Chunked body size mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Network error: Cannot connect to server"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Network error: Cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Network error: Connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "Network error: TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Network error: No response from server"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Network error: Response body size limit exceeded"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "Network error: Request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Network error: Cannot open download file"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Network error: Download file write error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "Network error: Redirect limit reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "Network error: Request timeout"
		_:
			return "Network error: Unknown error (code: " + str(result) + ")"


func _is_retryable_error(result: int) -> bool:
	return result in [
		HTTPRequest.RESULT_CANT_CONNECT,
		HTTPRequest.RESULT_CANT_RESOLVE,
		HTTPRequest.RESULT_CONNECTION_ERROR,
		HTTPRequest.RESULT_NO_RESPONSE,
		HTTPRequest.RESULT_REQUEST_FAILED,
		HTTPRequest.RESULT_TIMEOUT
	]


func _finalize_request(request_id: int) -> void:
	var request: Dictionary = _active_requests.get(request_id, {})
	if request.is_empty():
		return
	if request.has("client"):
		_mark_client_idle(request["client"])
	_active_requests.erase(request_id)
	if _pending_retry_timers.has(request_id):
		var timer = _pending_retry_timers[request_id]
		if timer:
			timer.stop()
			timer.queue_free()
		_pending_retry_timers.erase(request_id)


func _schedule_retry(request: Dictionary, delay_ms: int) -> void:
	var request_id = request.get("id", -1)
	if request_id == -1:
		return
	var timer = Timer.new()
	timer.one_shot = true
	add_child(timer)
	_pending_retry_timers[request_id] = timer
	var request_copy = request.duplicate(true)
	timer.timeout.connect(func():
		_pending_retry_timers.erase(request_id)
		if timer:
			timer.queue_free()
		request_copy["timestamp"] = Time.get_unix_time_from_system()
		if not _try_dispatch_request(request_copy):
			_enqueue_or_merge_request(request_copy, true)
	)
	timer.start(delay_ms / 1000.0)


func _try_process_queue() -> void:
	if not _is_online:
		return
	var dispatched = 0
	var expired = 0
	while not _request_queue.is_empty():
		var client = _get_idle_http_client()
		if client == null:
			break
		var queued_request = _request_queue.pop_front()
		var age = Time.get_unix_time_from_system() - queued_request.get("timestamp", 0)
		if age > queue_timeout_seconds:
			expired += 1
			continue
		_active_requests[queued_request.get("id")] = queued_request
		_execute_request_with_client(client, queued_request)
		dispatched += 1
	if dispatched > 0 or expired > 0:
		queue_processed.emit(dispatched, expired)


func _handle_request_failure(request_id: int, error_message: String, retryable: bool) -> void:
	var request: Dictionary = _active_requests.get(request_id, {})
	if request.is_empty():
		return
	var can_retry = enable_retry and retryable
	var retries = request.get("retries", 0)
	if can_retry and retries < max_retries:
		var updated_request = request.duplicate(true)
		updated_request["retries"] = retries + 1
		_finalize_request(request_id)
		var delay = retry_delay_ms * pow(2, retries)
		_schedule_retry(updated_request, delay)
		return
	_finalize_request(request_id)
	var message = error_message
	if retries >= max_retries and can_retry:
		message += " (Max retries reached)"
	error.emit(message)

func _enqueue_or_merge_request(request: Dictionary, prioritize: bool = false) -> int:
	if request.get("coalescible", false) and request.get("merge_key", "") != "":
		var merge_index = _find_queue_merge_index(request.get("merge_key", ""), request.get("write_type", WriteType.ONE_SHOT))
		if merge_index != -1:
			var merged_entry = _merge_queue_requests(_request_queue[merge_index], request)
			_request_queue[merge_index] = merged_entry
			request_queued.emit(request.get("id", -1))
			return request.get("id", -1)
	
	if prioritize:
		_insert_request_sorted(request)
	else:
		_request_queue.append(request)
	
	_apply_queue_overflow_policy(request)
	request_queued.emit(request.get("id", -1))
	return request.get("id", -1)


func _insert_request_sorted(request: Dictionary) -> void:
	var inserted = false
	for i in range(_request_queue.size()):
		if _request_queue[i].get("priority", RequestPriority.NORMAL) < request.get("priority", RequestPriority.NORMAL):
			_request_queue.insert(i, request)
			inserted = true
			break
	if not inserted:
		_request_queue.append(request)


func _find_queue_merge_index(merge_key: String, write_type: WriteType) -> int:
	for i in range(_request_queue.size()):
		var entry: Dictionary = _request_queue[i]
		if entry.get("merge_key", "") == merge_key and entry.get("write_type", write_type) == write_type:
			return i
	return -1


func _merge_queue_requests(existing: Dictionary, incoming: Dictionary) -> Dictionary:
	var write_type: WriteType = incoming.get("write_type", WriteType.ONE_SHOT)
	existing["write_type"] = write_type
	match write_type:
		WriteType.OVERWRITE:
			existing["body"] = incoming.get("body", {})
		WriteType.INCREMENT:
			existing["body"] = _merge_increment_payload(existing.get("body", {}), incoming.get("body", {}))
		WriteType.APPEND:
			existing["body"] = _merge_append_payload(existing.get("body", []), incoming.get("body", []))
		_:
			existing["body"] = incoming.get("body", {})

	existing["timestamp"] = incoming.get("timestamp", Time.get_unix_time_from_system())
	var existing_priority: RequestPriority = existing.get("priority", RequestPriority.NORMAL)
	var incoming_priority: RequestPriority = incoming.get("priority", RequestPriority.NORMAL)
	existing["priority"] = existing_priority if existing_priority > incoming_priority else incoming_priority
	return existing


func _apply_queue_overflow_policy(latest_request: Dictionary) -> void:
	if _request_queue.size() <= max_queue_size:
		return
	var indices_to_consider: Array = []
	for i in range(_request_queue.size()):
		var entry: Dictionary = _request_queue[i]
		if entry.get("priority", RequestPriority.NORMAL) == RequestPriority.CRITICAL:
			continue
		indices_to_consider.append(i)
	if indices_to_consider.is_empty():
		_request_queue.pop_front()
		return
	var merge_key = latest_request.get("merge_key", "")
	for idx in indices_to_consider:
		var entry: Dictionary = _request_queue[idx]
		if merge_key != "" and entry.get("merge_key", "") == merge_key:
			_request_queue.remove_at(idx)
			return
	var oldest_index = indices_to_consider[0]
	_request_queue.remove_at(oldest_index)


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

# V2 Signature Configuration Methods
func configure_v2_signatures(signing_secret: String) -> void:
	project_signing_secret = signing_secret
	use_v2_signatures = true
	print("[BaaS] V2 signatures enabled")

func disable_v2_signatures() -> void:
	use_v2_signatures = false
	project_signing_secret = ""
	print("[BaaS] V2 signatures disabled, using legacy V1")

func is_using_v2_signatures() -> bool:
	return use_v2_signatures and project_signing_secret != ""

func get_signature_version() -> String:
	if not enable_request_signing:
		return "none"
	elif is_using_v2_signatures():
		return "v2"
	else:
		return "v1"

func auto_upgrade_to_v2_if_needed(project_id: String) -> void:
	if is_using_v2_signatures():
		return  # Already using V2


func validate_v2_configuration() -> Dictionary:
	var result = {
		"valid": true,
		"issues": [],
		"recommendations": []
	}
	
	if use_v2_signatures and project_signing_secret == "":
		result.valid = false
		result.issues.append("V2 signatures enabled but no signing secret provided")
		result.recommendations.append("Call configure_v2_signatures(secret) with a valid signing secret")
	elif not use_v2_signatures and project_signing_secret != "":
		result.issues.append("Signing secret provided but V2 signatures not enabled")
		result.recommendations.append("Call configure_v2_signatures(secret) to enable V2")
	
	if enable_request_signing and api_key == "":
		result.valid = false
		result.issues.append("Request signing enabled but no API key provided")
		result.recommendations.append("Set api_key to your project's API key")
	
	return result

func _check_network_status() -> void:
	var was_online = _is_online
	
	_is_online = (_connection_state == ConnectionState.CONNECTED or 
				  _connection_state == ConnectionState.CONNECTING)
	
	if was_online and not _is_online:
		network_offline.emit()
	elif not was_online and _is_online:
		network_online.emit()
		_try_process_queue()

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

func _generate_signature_v2(body_string: String, timestamp: String) -> String:
	var data = body_string + timestamp
	var ctx = HashingContext.new()
	
	var key = project_signing_secret.to_utf8_buffer()
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
	var endpoint = ENDPOINT_PLAYER_DATA + "/" + key
	var context = {
		"key": key
	}
	_handle_write_operation("save_data", "POST", endpoint, body, true, RequestPriority.NORMAL, context)

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
	var endpoint = ENDPOINT_PLAYER_DATA + "/" + key
	var context = {
		"key": key,
		"strategy": strategy
	}
	_handle_write_operation("merge_data", "PATCH", endpoint, body, true, RequestPriority.NORMAL, context)

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

func _make_request(method: String, endpoint: String, body: Dictionary = {}, requires_auth: bool = false, priority: RequestPriority = RequestPriority.NORMAL, can_queue_merge: bool = false, merge_key: String = "", write_type: WriteType = WriteType.ONE_SHOT) -> int:
	_request_id_counter += 1
	var request_id = _request_id_counter
	
	var request = {
		"id": request_id,
		"method": method,
		"endpoint": endpoint,
		"body": body,
		"requires_auth": requires_auth,
		"priority": priority,
		"timestamp": Time.get_unix_time_from_system(),
		"merge_key": merge_key,
		"write_type": write_type,
		"coalescible": can_queue_merge,
		"retries": 0
	}
	
	if not _is_online and enable_offline_queue and priority != RequestPriority.CRITICAL:
		return _enqueue_or_merge_request(request, true)
	
	if _try_dispatch_request(request):
		return request_id
	
	_enqueue_or_merge_request(request, true)
	return request_id

func _handle_error_response(request: Dictionary, response_code: int, response_data: Variant) -> bool:
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
					_handle_version_conflict(request)
					return false
			
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
			elif msg_lower.contains("v2 signature required") or msg_lower.contains("signature v2"):
				if not is_using_v2_signatures():
					print("[BaaS] Backend requires V2 signatures - please configure with configure_v2_signatures()")
					error.emit("V2 signatures required. Please configure with project_signing_secret from BaaS dashboard.")
				else:
					error.emit("Invalid V2 signature configuration: " + str(error_message))
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
	return true

func _handle_version_conflict(request: Dictionary) -> void:
	var endpoint = request.get("endpoint", "")
	var body = request.get("body", {})
	var request_id = request.get("id", -1)
	if endpoint == "":
		error.emit("Version conflict: Cannot resolve - missing endpoint")
		_finalize_request(request_id)
		_try_process_queue()
		return
	var key_match = endpoint.split("/")
	if key_match.is_empty():
		error.emit("Version conflict: Cannot extract key from endpoint")
		_finalize_request(request_id)
		_try_process_queue()
		return
	var key = key_match[key_match.size() - 1]
	var local_data = body.get("value", {})
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
			_finalize_request(request_id)
			_try_process_queue()
			return
		var body_string = response_body.get_string_from_utf8()
		var json = JSON.new()
		if json.parse(body_string) != OK:
			data_conflict.emit(key, 0, local_data)
			_finalize_request(request_id)
			_try_process_queue()
			return
		var response_data = json.data
		if typeof(response_data) == TYPE_DICTIONARY and response_data.has("data"):
			var data = response_data["data"]
			if typeof(data) == TYPE_DICTIONARY:
				var server_version = data.get("version", 0)
				var server_data = data.get("value", {})
				data_conflict.emit(key, server_version, server_data)
				_finalize_request(request_id)
				_try_process_queue()
				return
		data_conflict.emit(key, 0, local_data)
		_finalize_request(request_id)
		_try_process_queue()
	)
	temp_http.request(url, headers)

func _handle_success_response(_response_code: int, response_data: Variant, request: Dictionary) -> void:
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
	
	var endpoint = request.get("endpoint", "")
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
