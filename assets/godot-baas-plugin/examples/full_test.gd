extends Control

# UI References
@onready var log_output: RichTextLabel = $VBoxContainer/LogOutput
@onready var test_buttons: VBoxContainer = $VBoxContainer/TestButtons

# Test state
var test_results: Dictionary = {}
var current_version: int = 0
var test_player_id: String = ""

func _ready() -> void:
	# Configure GodotBaaS (REPLACE WITH YOUR VALUES)
	GodotBaaS.api_key = "gb_live_your_api_key_here"
	GodotBaaS.base_url = "https://api.godotbaas.com"
	
	# Connect all signals
	GodotBaaS.authenticated.connect(_on_authenticated)
	GodotBaaS.auth_failed.connect(_on_auth_failed)
	GodotBaaS.data_saved.connect(_on_data_saved)
	GodotBaaS.data_loaded.connect(_on_data_loaded)
	GodotBaaS.data_conflict.connect(_on_data_conflict)
	GodotBaaS.score_submitted.connect(_on_score_submitted)
	GodotBaaS.leaderboard_loaded.connect(_on_leaderboard_loaded)
	GodotBaaS.error.connect(_on_error)
	
	# Connect test buttons
	for button in test_buttons.get_children():
		if button is Button:
			button.pressed.connect(_on_test_button_pressed.bind(button.name))
	
	log_message("=== Godot BaaS Full Test Suite ===")
	log_message("API Key: " + GodotBaaS.api_key.substr(0, 15) + "...")
	log_message("Base URL: " + GodotBaaS.base_url)
	log_message("")
	log_message("Click buttons to run tests")
	log_message("=" + "=".repeat(49))

# Test button handler
func _on_test_button_pressed(test_name: String) -> void:
	match test_name:
		"TestAnonymousLogin":
			test_anonymous_login()
		"TestSaveData":
			test_save_data()
		"TestLoadData":
			test_load_data()
		"TestUpdateData":
			test_update_data()
		"TestDeleteData":
			test_delete_data()
		"TestSubmitScore":
			test_submit_score()
		"TestGetLeaderboard":
			test_get_leaderboard()
		"TestTrackEvent":
			test_track_event()
		"TestRunAll":
			run_all_tests()

# Test 1: Anonymous Login
func test_anonymous_login() -> void:
	log_message("\n[TEST] Anonymous Login")
	log_message("→ Logging in anonymously...")
	GodotBaaS.login_anonymous()

# Test 2: Save Data
func test_save_data() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Save Data")
	var test_data = {
		"level": 5,
		"gold": 1000,
		"inventory": ["sword", "shield", "potion"],
		"timestamp": Time.get_unix_time_from_system()
	}
	log_message("→ Saving data: " + JSON.stringify(test_data))
	GodotBaaS.save_data("test_progress", test_data, current_version)

# Test 3: Load Data
func test_load_data() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Load Data")
	log_message("→ Loading data with key 'test_progress'...")
	GodotBaaS.load_data("test_progress")

# Test 4: Update Data (with version)
func test_update_data() -> void:
	if not _check_authenticated():
		return
	
	if current_version == 0:
		log_message("\n[TEST] Update Data - SKIPPED")
		log_message("⚠ Please save data first to get a version number")
		return
	
	log_message("\n[TEST] Update Data")
	var updated_data = {
		"level": 10,
		"gold": 2500,
		"inventory": ["sword", "shield", "potion", "mega_potion"],
		"timestamp": Time.get_unix_time_from_system()
	}
	log_message("→ Updating data with version " + str(current_version))
	GodotBaaS.save_data("test_progress", updated_data, current_version)

# Test 5: Delete Data
func test_delete_data() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Delete Data")
	log_message("→ Deleting data with key 'test_progress'...")
	GodotBaaS.delete_data("test_progress")
	current_version = 0

# Test 6: Submit Score
func test_submit_score() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Submit Score")
	var random_score = randi_range(1000, 10000)
	var metadata = {
		"platform": OS.get_name(),
		"timestamp": Time.get_unix_time_from_system()
	}
	log_message("→ Submitting score: " + str(random_score))
	GodotBaaS.submit_score("test-leaderboard", random_score, metadata)

# Test 7: Get Leaderboard
func test_get_leaderboard() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Get Leaderboard")
	log_message("→ Fetching top 10 entries from 'test-leaderboard'...")
	GodotBaaS.get_leaderboard("test-leaderboard", 10)

# Test 8: Track Analytics Event
func test_track_event() -> void:
	log_message("\n[TEST] Track Analytics Event")
	var event_properties = {
		"test_run": true,
		"timestamp": Time.get_unix_time_from_system(),
		"platform": OS.get_name()
	}
	log_message("→ Tracking event 'test_event'...")
	GodotBaaS.track_event("test_event", event_properties)
	log_message("✓ Event tracked (fire-and-forget)")
	test_results["track_event"] = true

# Run all tests in sequence
func run_all_tests() -> void:
	log_message("\n" + "=".repeat(50))
	log_message("RUNNING ALL TESTS")
	log_message("=".repeat(50))
	test_results.clear()
	current_version = 0
	
	# Test 1: Login
	test_anonymous_login()
	await get_tree().create_timer(2.0).timeout
	
	# Test 2: Save
	if test_results.get("login", false):
		test_save_data()
		await get_tree().create_timer(2.0).timeout
	
	# Test 3: Load
	if test_results.get("save_data", false):
		test_load_data()
		await get_tree().create_timer(2.0).timeout
	
	# Test 4: Update
	if test_results.get("load_data", false):
		test_update_data()
		await get_tree().create_timer(2.0).timeout
	
	# Test 5: Submit Score
	if test_results.get("login", false):
		test_submit_score()
		await get_tree().create_timer(2.0).timeout
	
	# Test 6: Get Leaderboard
	if test_results.get("submit_score", false):
		test_get_leaderboard()
		await get_tree().create_timer(2.0).timeout
	
	# Test 7: Track Event
	test_track_event()
	await get_tree().create_timer(1.0).timeout
	
	# Test 8: Delete Data
	if test_results.get("save_data", false):
		test_delete_data()
	
	# Summary
	await get_tree().create_timer(2.0).timeout
	print_test_summary()

# Signal Handlers

func _on_authenticated(player_data: Dictionary) -> void:
	test_player_id = player_data.get("id", "")
	log_message("✓ AUTHENTICATED")
	log_message("  Player ID: " + test_player_id)
	log_message("  Is Anonymous: " + str(player_data.get("isAnonymous", false)))
	test_results["login"] = true

func _on_auth_failed(error: String) -> void:
	log_message("✗ AUTH FAILED: " + error, true)
	test_results["login"] = false

func _on_data_saved(key: String, version: int) -> void:
	current_version = version
	log_message("✓ DATA SAVED")
	log_message("  Key: " + key)
	log_message("  Version: " + str(version))
	test_results["save_data"] = true

func _on_data_loaded(key: String, value: Variant) -> void:
	log_message("✓ DATA LOADED")
	log_message("  Key: " + key)
	log_message("  Value: " + JSON.stringify(value))
	test_results["load_data"] = true

func _on_data_conflict(key: String, server_version: int, server_data: Variant) -> void:
	log_message("⚠ DATA CONFLICT", true)
	log_message("  Key: " + key)
	log_message("  Server Version: " + str(server_version))
	log_message("  Server Data: " + JSON.stringify(server_data))
	current_version = server_version

func _on_score_submitted(leaderboard: String, rank: int) -> void:
	log_message("✓ SCORE SUBMITTED")
	log_message("  Leaderboard: " + leaderboard)
	log_message("  Your Rank: #" + str(rank))
	test_results["submit_score"] = true

func _on_leaderboard_loaded(leaderboard: String, entries: Array) -> void:
	log_message("✓ LEADERBOARD LOADED")
	log_message("  Leaderboard: " + leaderboard)
	log_message("  Entries: " + str(entries.size()))
	
	if entries.size() > 0:
		log_message("  Top 3:")
		for i in range(min(3, entries.size())):
			var entry = entries[i]
			log_message("    #" + str(entry.get("rank", i+1)) + " - Score: " + str(entry.get("score", 0)))
	
	test_results["get_leaderboard"] = true

func _on_error(error_message: String) -> void:
	log_message("✗ ERROR: " + error_message, true)

# Helper functions

func _check_authenticated() -> bool:
	if GodotBaaS.player_token == "":
		log_message("⚠ Not authenticated! Please login first.", true)
		return false
	return true

func log_message(message: String, is_error: bool = false) -> void:
	var color = "white"
	if is_error:
		color = "red"
	elif message.begins_with("✓"):
		color = "green"
	elif message.begins_with("⚠"):
		color = "yellow"
	elif message.begins_with("→"):
		color = "cyan"
	
	log_output.append_text("[color=" + color + "]" + message + "[/color]\n")
	print(message)

func print_test_summary() -> void:
	log_message("\n" + "=".repeat(50))
	log_message("TEST SUMMARY")
	log_message("=".repeat(50))
	
	var total = test_results.size()
	var passed = 0
	
	for test_name in test_results:
		var result = test_results[test_name]
		if result:
			passed += 1
			log_message("✓ " + test_name)
		else:
			log_message("✗ " + test_name, true)
	
	log_message("")
	log_message("Results: " + str(passed) + "/" + str(total) + " tests passed")
	
	if passed == total:
		log_message("🎉 ALL TESTS PASSED!")
	else:
		log_message("⚠ Some tests failed", true)
