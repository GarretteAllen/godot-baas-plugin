extends Control

# UI References
@onready var log_output: RichTextLabel = $MarginContainer/HBoxContainer/RightPanel/LogOutput
@onready var test_buttons: VBoxContainer = $MarginContainer/HBoxContainer/LeftPanel/ScrollContainer/TestButtons

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
	GodotBaaS.achievement_unlocked.connect(_on_achievement_unlocked)
	GodotBaaS.achievement_progress_updated.connect(_on_achievement_progress_updated)
	GodotBaaS.achievement_unlock_failed.connect(_on_achievement_unlock_failed)
	GodotBaaS.achievements_loaded.connect(_on_achievements_loaded)
	GodotBaaS.friend_request_sent.connect(_on_friend_request_sent)
	GodotBaaS.friend_request_accepted.connect(_on_friend_request_accepted)
	GodotBaaS.friends_loaded.connect(_on_friends_loaded)
	GodotBaaS.pending_requests_loaded.connect(_on_pending_requests_loaded)
	GodotBaaS.players_found.connect(_on_players_found)
	GodotBaaS.player_blocked.connect(_on_player_blocked)
	GodotBaaS.friend_leaderboard_loaded.connect(_on_friend_leaderboard_loaded)
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
		"TestDeviceLogin":
			test_device_login()
		"TestLinkAccount":
			test_link_account()
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
		"TestGrantAchievement":
			test_grant_achievement()
		"TestUpdateProgress":
			test_update_progress()
		"TestGetAchievements":
			test_get_achievements()
		"TestSearchPlayers":
			test_search_players()
		"TestSendFriendRequest":
			test_send_friend_request()
		"TestGetFriends":
			test_get_friends()
		"TestGetPendingRequests":
			test_get_pending_requests()
		"TestBlockPlayer":
			test_block_player()
		"TestGetFriendLeaderboard":
			test_get_friend_leaderboard()
		"TestRunAll":
			run_all_tests()

# Test 1: Device ID Login
func test_device_login() -> void:
	log_message("\n[TEST] Device ID Login")
	log_message("→ Logging in with device ID...")
	log_message("  (Device ID is automatically generated and stored)")
	GodotBaaS.login_with_device_id()

# Test 2: Link Account (Upgrade to Email/Password)
func test_link_account() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Link Account")
	log_message("→ Upgrading device account to email/password...")
	var random_email = "test_" + str(randi()) + "@example.com"
	var password = "SecurePassword123!"
	var username = "TestPlayer" + str(randi_range(1000, 9999))
	
	log_message("  Email: " + random_email)
	log_message("  Username: " + username)
	GodotBaaS.link_account(random_email, password, username)

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

# Test 9: Grant Achievement
func test_grant_achievement() -> void:
	log_message("\n[TEST] Grant Achievement")
	log_message("→ Granting achievement 'first_test'...")
	log_message("  (Make sure this achievement exists in your dashboard)")
	GodotBaaS.grant_achievement("first_test")

# Test 10: Update Achievement Progress
func test_update_progress() -> void:
	log_message("\n[TEST] Update Achievement Progress")
	log_message("→ Updating progress for 'test_progress' achievement...")
	log_message("  Setting progress to 50...")
	GodotBaaS.update_achievement_progress("test_progress", 50)
	
	await get_tree().create_timer(2.0).timeout
	
	log_message("→ Incrementing progress by 25...")
	GodotBaaS.update_achievement_progress("test_progress", 25, true)

# Test 11: Get All Achievements
func test_get_achievements() -> void:
	log_message("\n[TEST] Get All Achievements")
	log_message("→ Fetching all achievements...")
	GodotBaaS.get_achievements(false)  # Don't include hidden
	
	await get_tree().create_timer(2.0).timeout
	
	log_message("→ Fetching all achievements (including hidden)...")
	GodotBaaS.get_achievements(true)

# Test 12: Search Players
func test_search_players() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Search Players")
	log_message("→ Searching for players...")
	log_message("  ⚠ EDIT THIS: Change 'test' to search for a real player")
	GodotBaaS.search_players("test")

# Test 13: Send Friend Request
func test_send_friend_request() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Send Friend Request")
	log_message("  ⚠ EDIT THIS: Replace with actual player ID or username")
	log_message("  Example: GodotBaaS.send_friend_request(\"player_id_here\")")
	log_message("  You can get player IDs from the search results above")
	log_message("")
	log_message("✗ SKIPPED - Please edit the code to add a friend ID")
	
	# UNCOMMENT AND EDIT THIS LINE:
	# GodotBaaS.send_friend_request("PUT_FRIEND_PLAYER_ID_HERE")

# Test 14: Get Friends List
func test_get_friends() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Get Friends List")
	log_message("→ Fetching friends list...")
	GodotBaaS.get_friends()

# Test 15: Get Pending Friend Requests
func test_get_pending_requests() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Get Pending Friend Requests")
	log_message("→ Fetching pending friend requests...")
	GodotBaaS.get_pending_requests()

# Test 16: Block Player
func test_block_player() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Block Player")
	log_message("  ⚠ EDIT THIS: Replace with actual player ID to block")
	log_message("  Example: GodotBaaS.block_player(\"player_id_here\", \"spam\")")
	log_message("")
	log_message("✗ SKIPPED - Please edit the code to add a player ID")
	
	# UNCOMMENT AND EDIT THIS LINE:
	# GodotBaaS.block_player("PUT_PLAYER_ID_HERE", "Testing block feature")

# Test 17: Get Friend Leaderboard
func test_get_friend_leaderboard() -> void:
	if not _check_authenticated():
		return
	
	log_message("\n[TEST] Get Friend Leaderboard")
	log_message("→ Fetching friend leaderboard for 'test-leaderboard'...")
	GodotBaaS.get_friend_leaderboard("test-leaderboard", 50)

# Run all tests in sequence
func run_all_tests() -> void:
	log_message("\n" + "=".repeat(50))
	log_message("RUNNING ALL TESTS")
	log_message("=".repeat(50))
	test_results.clear()
	current_version = 0
	
	# Test 1: Device ID Login
	test_device_login()
	await get_tree().create_timer(2.0).timeout
	
	# Test 2: Save Data
	if test_results.get("login", false):
		test_save_data()
		await get_tree().create_timer(2.0).timeout
	
	# Test 3: Load Data
	if test_results.get("save_data", false):
		test_load_data()
		await get_tree().create_timer(2.0).timeout
	
	# Test 4: Update Data
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
	
	# Test 8: Get Achievements
	if test_results.get("login", false):
		test_get_achievements()
		await get_tree().create_timer(2.0).timeout
	
	# Test 9: Grant Achievement
	if test_results.get("login", false):
		log_message("\n→ Testing achievement grant...")
		log_message("  (Create an achievement with ID 'first_test' in dashboard)")
		test_grant_achievement()
		await get_tree().create_timer(2.0).timeout
	
	# Test 10: Update Progress
	if test_results.get("login", false):
		log_message("\n→ Testing achievement progress...")
		log_message("  (Create a progress achievement with ID 'test_progress' in dashboard)")
		test_update_progress()
		await get_tree().create_timer(3.0).timeout
	
	# Test 11: Link Account (Optional - upgrades to email/password)
	if test_results.get("login", false):
		log_message("\n→ Skipping account linking test (optional)")
		log_message("  Run 'TestLinkAccount' manually to test account upgrade")
	
	# Test 12: Delete Data
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
	log_message("  Device ID: " + str(player_data.get("deviceId", "N/A")).substr(0, 13) + "...")
	log_message("  Is Anonymous: " + str(player_data.get("isAnonymous", false)))
	
	if player_data.get("email"):
		log_message("  Email: " + str(player_data.get("email")))
		log_message("  Username: " + str(player_data.get("username")))
		test_results["link_account"] = true
	
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

func _on_achievement_unlocked(achievement: Dictionary) -> void:
	log_message("🏆 ACHIEVEMENT UNLOCKED!")
	log_message("  Name: " + str(achievement.get("name", "Unknown")))
	log_message("  Description: " + str(achievement.get("description", "")))
	log_message("  Points: " + str(achievement.get("points", 0)))
	log_message("  Rarity: " + str(achievement.get("rarity", "COMMON")))
	test_results["grant_achievement"] = true

func _on_achievement_progress_updated(achievement: Dictionary) -> void:
	log_message("📊 ACHIEVEMENT PROGRESS UPDATED")
	log_message("  Name: " + str(achievement.get("name", "Unknown")))
	log_message("  Progress: " + str(achievement.get("progress", 0)) + "/" + str(achievement.get("targetValue", 100)))
	
	if achievement.get("isUnlocked", false):
		log_message("  🎉 Achievement unlocked!")
	
	test_results["update_progress"] = true

func _on_achievement_unlock_failed(error: String) -> void:
	log_message("✗ ACHIEVEMENT UNLOCK FAILED: " + error, true)

func _on_achievements_loaded(achievements: Array) -> void:
	log_message("✓ ACHIEVEMENTS LOADED")
	log_message("  Total: " + str(achievements.size()))
	
	var unlocked_count = 0
	for achievement in achievements:
		if achievement.get("isUnlocked", false):
			unlocked_count += 1
	
	log_message("  Unlocked: " + str(unlocked_count))
	log_message("  Locked: " + str(achievements.size() - unlocked_count))
	
	if achievements.size() > 0:
		log_message("  Sample achievements:")
		for i in range(min(3, achievements.size())):
			var ach = achievements[i]
			var status = "🔓" if ach.get("isUnlocked", false) else "🔒"
			log_message("    " + status + " " + str(ach.get("name", "Unknown")))
	
	test_results["get_achievements"] = true

func _on_friend_request_sent(friendship: Dictionary) -> void:
	log_message("✓ FRIEND REQUEST SENT")
	log_message("  Friendship ID: " + str(friendship.get("id", "")))
	log_message("  Status: " + str(friendship.get("status", "PENDING")))
	test_results["send_friend_request"] = true

func _on_friend_request_accepted(friend: Dictionary) -> void:
	log_message("🤝 FRIEND REQUEST ACCEPTED")
	log_message("  Friend: " + str(friend.get("username", "Unknown")))
	log_message("  Player ID: " + str(friend.get("id", "")))

func _on_friends_loaded(friends: Array, count: int) -> void:
	log_message("✓ FRIENDS LIST LOADED")
	log_message("  Total Friends: " + str(count))
	
	if friends.size() > 0:
		log_message("  Your friends:")
		for i in range(min(5, friends.size())):
			var friend = friends[i]
			var status = str(friend.get("onlineStatus", "offline"))
			var status_icon = "🟢" if status == "online" else ("🟡" if status == "away" else "⚫")
			log_message("    " + status_icon + " " + str(friend.get("username", "Unknown")))
	else:
		log_message("  No friends yet. Send some friend requests!")
	
	test_results["get_friends"] = true

func _on_pending_requests_loaded(requests: Array) -> void:
	log_message("✓ PENDING REQUESTS LOADED")
	log_message("  Total Pending: " + str(requests.size()))
	
	if requests.size() > 0:
		log_message("  Pending requests:")
		for i in range(min(5, requests.size())):
			var request = requests[i]
			var requester = request.get("requester", {})
			log_message("    From: " + str(requester.get("username", "Unknown")))
			log_message("      ID: " + str(request.get("id", "")))
	else:
		log_message("  No pending requests")
	
	test_results["get_pending_requests"] = true

func _on_players_found(players: Array) -> void:
	log_message("✓ PLAYERS FOUND")
	log_message("  Results: " + str(players.size()))
	
	if players.size() > 0:
		log_message("  Players:")
		for i in range(min(5, players.size())):
			var player = players[i]
			var relationship = str(player.get("relationshipStatus", "none"))
			var status_text = ""
			match relationship:
				"friend":
					status_text = " (Already friends)"
				"pending_sent":
					status_text = " (Request sent)"
				"pending_received":
					status_text = " (Wants to be friends)"
				"blocked":
					status_text = " (Blocked)"
			
			log_message("    " + str(player.get("username", "Unknown")) + status_text)
			log_message("      ID: " + str(player.get("id", "")))
	else:
		log_message("  No players found")
	
	test_results["search_players"] = true

func _on_player_blocked() -> void:
	log_message("✓ PLAYER BLOCKED")
	log_message("  Player has been blocked successfully")
	test_results["block_player"] = true

func _on_friend_leaderboard_loaded(leaderboard_slug: String, entries: Array) -> void:
	log_message("✓ FRIEND LEADERBOARD LOADED")
	log_message("  Leaderboard: " + leaderboard_slug)
	log_message("  Entries: " + str(entries.size()))
	
	if entries.size() > 0:
		log_message("  Friend rankings:")
		for i in range(min(5, entries.size())):
			var entry = entries[i]
			var is_you = entry.get("isCurrentPlayer", false)
			var marker = " (You)" if is_you else ""
			log_message("    #" + str(entry.get("rank", i+1)) + " - " + str(entry.get("username", "Unknown")) + ": " + str(entry.get("score", 0)) + marker)
	else:
		log_message("  No friend scores yet")
	
	test_results["get_friend_leaderboard"] = true

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
