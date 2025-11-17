# Godot BaaS Plugin

Backend services for your Godot game without the headache.

## 🎮 Test Game Available!

Want to see all features in action? Check out the **comprehensive test game** in `examples/testproject/`:

- ✅ Full authentication flow (device ID, email/password, account linking)
- ✅ Cloud saves with auto-sync
- ✅ Global and friend leaderboards
- ✅ Complete friends system (search, add, accept, remove)
- ✅ Achievements with progress tracking
- ✅ Simple clicker game to test everything
- ✅ Clean, well-documented code you can learn from

**[→ Open Test Game README](examples/testproject/README.md)** | **[→ Quick Start Guide](examples/testproject/QUICK_START.md)**

## Setup

Copy the `addons/godot_baas` folder into your project's `addons` directory. Enable the plugin in Project Settings → Plugins.

Get your API key from the dashboard and you're good to go.

## Quick Start

```gdscript
extends Node

func _ready():
    GodotBaaS.api_key = "gb_live_your_key_here"
    GodotBaaS.authenticated.connect(_on_login)
    GodotBaaS.login_with_device_id()

func _on_login(player):
    print("Logged in as: ", player.id)
```

That's it. Your players can now save progress, compete on leaderboards, and you get analytics.

## Authentication

### Device ID (Recommended)

Players start playing immediately. No signup forms, no friction.

```gdscript
GodotBaaS.login_with_device_id()
```

The plugin generates a unique ID and saves it locally. Same account every time they open your game.

### Upgrade to Email/Password

Let players link an email so they can play on multiple devices:

```gdscript
GodotBaaS.link_account("player@email.com", "password", "username")
```

Their progress carries over. Device ID still works on the original device.

### Email/Password Login

If they already have an account:

```gdscript
GodotBaaS.login_player("player@email.com", "password")
```

## Cloud Saves

Save anything. Load it anywhere.

```gdscript
# Save
var save_data = {
    "level": 10,
    "gold": 5000,
    "inventory": ["sword", "shield"]
}
GodotBaaS.save_data("player_progress", save_data)

# Load
GodotBaaS.load_data("player_progress")
GodotBaaS.data_loaded.connect(func(key, data):
    print("Loaded: ", data)
)
```

### Versioning

Prevent data loss when players play offline on multiple devices:

```gdscript
var current_version = 0

GodotBaaS.data_saved.connect(func(key, version):
    current_version = version
)

# Save with version check
GodotBaaS.save_data("progress", data, current_version)
```

If versions don't match, you get a conflict signal. Handle it however makes sense for your game.

### Merging Data

Instead of replacing entire save files, merge specific values. Great for adding gold, updating inventory, or incrementing stats:

```gdscript
# Add gold
GodotBaaS.merge_data("player_stats", {"gold": 100}, current_version, "increment")

# Remove gold
GodotBaaS.merge_data("player_stats", {"gold": 50}, current_version, "decrement")

# Add items to inventory
GodotBaaS.merge_data("inventory", {"items": ["sword", "potion"]}, current_version, "append")

# Remove items
GodotBaaS.merge_data("inventory", {"items": ["potion"]}, current_version, "remove")

# Merge objects (updates only specified fields)
GodotBaaS.merge_data("settings", {"volume": 0.8}, current_version, "merge")
```

Strategies:
- `merge` - Update specific fields, keep the rest
- `append` - Add to arrays
- `remove` - Remove from arrays
- `increment` - Add to numbers
- `decrement` - Subtract from numbers

Convenience method for inventory:

```gdscript
GodotBaaS.add_to_inventory("inventory", ["sword", "shield"], current_version)
```

## Leaderboards

```gdscript
# Submit score
GodotBaaS.submit_score("weekly_high_scores", 9999)

# Get top players
GodotBaaS.get_leaderboard("weekly_high_scores", 10)
GodotBaaS.leaderboard_loaded.connect(func(board, entries):
    for entry in entries:
        print("#", entry.rank, " - ", entry.score)
)
```

Leaderboards reset automatically based on your settings (daily, weekly, monthly, or never).

## Analytics

Track whatever you want:

```gdscript
GodotBaaS.track_event("level_completed", {
    "level": 5,
    "time": 120.5,
    "deaths": 3
})
```

Fire and forget. Check the dashboard to see what players are doing.

## Friends System

Let players connect with each other, build social relationships, and compete with friends.

### Sending Friend Requests

Players can send friend requests to other players by username or player ID:

```gdscript
# Search for players first
GodotBaaS.search_players("player123")
GodotBaaS.players_found.connect(func(players):
    for player in players:
        print(player.username, " - ", player.relationshipStatus)
)

# Send friend request
GodotBaaS.send_friend_request("player_id_here")
GodotBaaS.friend_request_sent.connect(func(friendship):
    print("Friend request sent!")
)
```

### Managing Friend Requests

Handle incoming friend requests:

```gdscript
# Get pending requests when player logs in
GodotBaaS.get_pending_requests()
GodotBaaS.pending_requests_loaded.connect(func(requests):
    for request in requests:
        print("Request from: ", request.requester.username)
        show_friend_request_notification(request)
)

# Accept a friend request
GodotBaaS.accept_friend_request(friendship_id)
GodotBaaS.friend_request_accepted.connect(func(friend):
    print("Now friends with: ", friend.username)
)

# Decline a friend request
GodotBaaS.decline_friend_request(friendship_id)
GodotBaaS.friend_request_declined.connect(func():
    print("Friend request declined")
)

# Cancel a sent request
GodotBaaS.cancel_friend_request(friendship_id)
```

### Friend List

Get and display the player's friend list with online status:

```gdscript
# Get all friends
GodotBaaS.get_friends()
GodotBaaS.friends_loaded.connect(func(friends, count):
    print("You have ", count, " friends")
    for friend in friends:
        print(friend.username, " - ", friend.onlineStatus)
        # onlineStatus: "online", "offline", or "away"
)

# Remove a friend
GodotBaaS.remove_friend(friend_id)
GodotBaaS.friend_removed.connect(func():
    print("Friend removed")
)
```

### Online Status

Friend online status is automatically included in the friend list:
- `online` - Friend is currently active
- `offline` - Friend is not connected
- `away` - Friend has been inactive for 5+ minutes

Listen for real-time status changes via WebSocket:

```gdscript
# Connect to status change events
# (Requires WebSocket connection to be established)
func _on_friend_status_changed(data):
    print("Friend ", data.friendId, " is now ", data.status)
```

### Blocking Players

Block players to prevent unwanted interactions:

```gdscript
# Block a player
GodotBaaS.block_player(player_id, "Optional reason")
GodotBaaS.player_blocked.connect(func():
    print("Player blocked")
)

# Unblock a player
GodotBaaS.unblock_player(player_id)
GodotBaaS.player_unblocked.connect(func():
    print("Player unblocked")
)

# Get list of blocked players
GodotBaaS.get_blocked_players()
GodotBaaS.blocked_players_loaded.connect(func(players):
    for player in players:
        print("Blocked: ", player.username)
)
```

**Note:** Blocking a player automatically removes any existing friendship.

### Friend Leaderboards

Show leaderboards filtered to only include friends:

```gdscript
# Get friend-only leaderboard
GodotBaaS.get_friend_leaderboard("weekly_high_scores", 100)
GodotBaaS.friend_leaderboard_loaded.connect(func(slug, entries):
    print("Friend leaderboard for: ", slug)
    for entry in entries:
        var marker = " (You)" if entry.get("isCurrentPlayer") else ""
        print("#", entry.rank, " - ", entry.username, ": ", entry.score, marker)
)
```

The friend leaderboard always includes your own entry, even if you're not in the top results.

### Friend System Data Structures

**Friend object:**
```gdscript
{
    "id": "player_id",
    "username": "player123",
    "email": "player@example.com",  # May be null
    "avatarUrl": null,
    "onlineStatus": "online",  # "online", "offline", or "away"
    "friendshipId": "friendship_id",
    "friendsSince": "2024-01-15T10:35:00.000Z"
}
```

**Friend request object:**
```gdscript
{
    "id": "friendship_id",
    "requesterId": "sender_id",
    "addresseeId": "receiver_id",
    "status": "PENDING",  # "PENDING", "ACCEPTED", "DECLINED"
    "createdAt": "2024-01-15T10:30:00.000Z",
    "requester": {
        "id": "sender_id",
        "username": "sender_name",
        "email": "sender@example.com"
    }
}
```

**Search result object:**
```gdscript
{
    "id": "player_id",
    "username": "player123",
    "email": "player@example.com",
    "avatarUrl": null,
    "relationshipStatus": "none"  # "friend", "pending_sent", "pending_received", "blocked", "none"
}
```

### Common Friend System Patterns

**Show friend request notification:**

```gdscript
func _ready():
    GodotBaaS.authenticated.connect(_on_authenticated)
    GodotBaaS.friend_request_received.connect(_on_friend_request_received)

func _on_authenticated(player):
    # Load pending requests on login
    GodotBaaS.get_pending_requests()

func _on_friend_request_received(request):
    # Show notification popup
    notification_popup.show_friend_request(
        request.requester.username,
        request.id
    )
```

**Display friends list with online indicators:**

```gdscript
func show_friends_list():
    GodotBaaS.get_friends()
    GodotBaaS.friends_loaded.connect(_on_friends_loaded)

func _on_friends_loaded(friends, count):
    friend_list.clear()
    
    for friend in friends:
        var item = friend_item_scene.instantiate()
        item.set_friend_data(friend)
        
        # Set online indicator color
        match friend.onlineStatus:
            "online":
                item.set_status_color(Color.GREEN)
            "away":
                item.set_status_color(Color.YELLOW)
            "offline":
                item.set_status_color(Color.GRAY)
        
        friend_list.add_child(item)
```

**Search and add friends:**

```gdscript
func on_search_button_pressed():
    var query = search_input.text
    GodotBaaS.search_players(query)

func _ready():
    GodotBaaS.players_found.connect(_on_players_found)
    GodotBaaS.friend_request_sent.connect(_on_request_sent)

func _on_players_found(players):
    search_results.clear()
    
    for player in players:
        var item = player_item_scene.instantiate()
        item.set_player_data(player)
        
        # Show appropriate button based on relationship
        match player.relationshipStatus:
            "friend":
                item.show_remove_button()
            "pending_sent":
                item.show_pending_label()
            "pending_received":
                item.show_accept_button()
            "none":
                item.show_add_button()
        
        search_results.add_child(item)

func on_add_friend_clicked(player_id):
    GodotBaaS.send_friend_request(player_id)

func _on_request_sent(friendship):
    print("Friend request sent!")
    # Refresh search results
    on_search_button_pressed()
```

**Friend leaderboard with highlighting:**

```gdscript
func show_friend_leaderboard():
    GodotBaaS.get_friend_leaderboard("weekly_scores", 50)
    GodotBaaS.friend_leaderboard_loaded.connect(_on_friend_leaderboard_loaded)

func _on_friend_leaderboard_loaded(slug, entries):
    leaderboard_list.clear()
    
    for entry in entries:
        var item = leaderboard_item_scene.instantiate()
        item.set_entry_data(entry)
        
        # Highlight current player
        if entry.get("isCurrentPlayer", false):
            item.set_highlight(true)
        
        leaderboard_list.add_child(item)
```

### Rate Limiting

Friend requests are rate limited to prevent spam:
- Maximum 10 friend requests per hour per player
- If exceeded, you'll receive an error signal

Handle rate limiting gracefully:

```gdscript
func _ready():
    GodotBaaS.error.connect(_on_error)

func _on_error(error_message):
    if "rate limit" in error_message.to_lower():
        show_error_popup("You're sending too many friend requests. Please wait a bit.")
    else:
        show_error_popup(error_message)
```

### Troubleshooting

**"Cannot send request to this player" error**

This is a generic error that could mean:
- The player has blocked you (the system doesn't reveal this for privacy)
- The player doesn't exist
- The players are in different projects

**Friend request not appearing**

Make sure to call `get_pending_requests()` after authentication to load pending requests.

**Online status not updating**

Online status is updated automatically when players log in/out. Status changes to "away" after 5 minutes of inactivity. Real-time updates require WebSocket connection.

**Search returns no results**

- Search is limited to players in the same project
- Players who have blocked you won't appear in search results
- Search requires at least 2 characters

## Achievements

Reward players for completing goals and milestones in your game.

### Granting Achievements

Unlock an achievement when a player completes a goal:

```gdscript
# Grant achievement by ID
GodotBaaS.grant_achievement("first_win")

# Listen for unlock
GodotBaaS.achievement_unlocked.connect(func(achievement):
    print("Unlocked: ", achievement.name)
    show_achievement_popup(achievement)
)
```

The system prevents duplicate unlocks automatically. If the player already has the achievement, it returns success without creating a duplicate.

### Progress-Based Achievements

Track incremental progress toward achievements that require multiple steps:

```gdscript
# Set progress to specific value
GodotBaaS.update_achievement_progress("kill_100_enemies", 50)

# Increment progress
GodotBaaS.update_achievement_progress("collect_coins", 10, true)

# Listen for progress updates
GodotBaaS.achievement_progress_updated.connect(func(achievement):
    print("Progress: ", achievement.progress, "/", achievement.targetValue)
    update_progress_bar(achievement)
)
```

When progress reaches the target value, the achievement unlocks automatically and emits both `achievement_progress_updated` and `achievement_unlocked` signals.

### Retrieving Achievements

Get all achievements for the current player:

```gdscript
# Get all achievements (hidden ones only show if unlocked)
GodotBaaS.get_achievements()

# Include hidden achievements even if not unlocked
GodotBaaS.get_achievements(true)

# Handle response
GodotBaaS.achievements_loaded.connect(func(achievements):
    for achievement in achievements:
        print(achievement.name, " - ", achievement.isUnlocked)
        if achievement.isUnlocked:
            print("  Unlocked: ", achievement.unlockedAt)
        elif achievement.targetValue:
            print("  Progress: ", achievement.progress, "/", achievement.targetValue)
)
```

### Achievement Data Structure

Each achievement contains:

```gdscript
{
    "id": "first_win",
    "name": "First Victory",
    "description": "Win your first match",
    "iconUrl": "https://...",
    "points": 10,
    "rarity": "COMMON",  # COMMON, UNCOMMON, RARE, EPIC, LEGENDARY
    "isHidden": false,
    "isUnlocked": true,
    "progress": 1,
    "targetValue": 1,
    "unlockedAt": "2024-01-15T10:30:00Z",
    "metadata": {}  # Custom data from dashboard
}
```

### Common Patterns

**Show achievement notification:**

```gdscript
func _ready():
    GodotBaaS.achievement_unlocked.connect(_on_achievement_unlocked)

func _on_achievement_unlocked(achievement):
    # Show popup with achievement details
    achievement_popup.show_achievement(
        achievement.name,
        achievement.description,
        achievement.iconUrl,
        achievement.points
    )
    
    # Play sound effect
    achievement_sound.play()
```

**Track progress for multiple achievements:**

```gdscript
func on_enemy_killed():
    # This might unlock multiple achievements
    GodotBaaS.update_achievement_progress("kill_10_enemies", 1, true)
    GodotBaaS.update_achievement_progress("kill_100_enemies", 1, true)
    GodotBaaS.update_achievement_progress("kill_1000_enemies", 1, true)

func _ready():
    GodotBaaS.achievement_unlocked.connect(func(achievement):
        print("Achievement unlocked: ", achievement.name)
    )
```

**Display achievement list in menu:**

```gdscript
func show_achievements_menu():
    GodotBaaS.get_achievements()
    GodotBaaS.achievements_loaded.connect(_on_achievements_loaded)

func _on_achievements_loaded(achievements):
    achievement_list.clear()
    
    for achievement in achievements:
        var item = achievement_item_scene.instantiate()
        item.set_achievement_data(achievement)
        achievement_list.add_child(item)
```

**Handle unlock failures:**

```gdscript
func _ready():
    GodotBaaS.achievement_unlock_failed.connect(_on_unlock_failed)

func _on_unlock_failed(error):
    match error:
        "ACHIEVEMENT_NOT_FOUND":
            print("Achievement doesn't exist in dashboard")
        "UNAUTHORIZED_ACCESS":
            print("Player not authenticated")
        _:
            print("Failed to unlock achievement: ", error)
```

### Creating Achievements

Achievements are created in the dashboard, not in code. This lets you:
- Update achievement details without changing game code
- Add new achievements without releasing updates
- Track analytics and completion rates
- Configure points, rarity, and hidden status

In your dashboard:
1. Go to your project's Achievements tab
2. Click "Create Achievement"
3. Set the achievement ID (use this in your code)
4. Configure name, description, icon, points, and rarity
5. For progress-based achievements, set a target value
6. Mark as hidden if you want it to be a secret until unlocked

### Troubleshooting

**"Achievement not found" errors**

Make sure the achievement exists in your dashboard and the ID matches exactly (case-sensitive).

**Progress not updating**

Check that the achievement has a target value set in the dashboard. Achievements without target values can only be granted directly.

**Hidden achievements showing**

Hidden achievements only appear in the list after they're unlocked, unless you explicitly pass `true` to `get_achievements(true)`.

**Duplicate unlock notifications**

The backend prevents duplicate unlocks, but if you're seeing multiple notifications, make sure you're not calling `grant_achievement()` multiple times in quick succession.

## Signals

Connect to these to handle responses:

```gdscript
# Auth
GodotBaaS.authenticated.connect(_on_authenticated)
GodotBaaS.auth_failed.connect(_on_auth_failed)

# Cloud saves
GodotBaaS.data_saved.connect(_on_data_saved)
GodotBaaS.data_loaded.connect(_on_data_loaded)
GodotBaaS.data_conflict.connect(_on_conflict)

# Leaderboards
GodotBaaS.score_submitted.connect(_on_score_submitted)
GodotBaaS.leaderboard_loaded.connect(_on_leaderboard_loaded)

# Achievements
GodotBaaS.achievement_unlocked.connect(_on_achievement_unlocked)
GodotBaaS.achievement_progress_updated.connect(_on_progress_updated)
GodotBaaS.achievement_unlock_failed.connect(_on_unlock_failed)
GodotBaaS.achievements_loaded.connect(_on_achievements_loaded)

# Friends System
GodotBaaS.friend_request_sent.connect(_on_friend_request_sent)
GodotBaaS.friend_request_received.connect(_on_friend_request_received)
GodotBaaS.friend_request_accepted.connect(_on_friend_request_accepted)
GodotBaaS.friend_request_declined.connect(_on_friend_request_declined)
GodotBaaS.friend_request_cancelled.connect(_on_friend_request_cancelled)
GodotBaaS.friends_loaded.connect(_on_friends_loaded)
GodotBaaS.friend_removed.connect(_on_friend_removed)
GodotBaaS.pending_requests_loaded.connect(_on_pending_requests_loaded)
GodotBaaS.sent_requests_loaded.connect(_on_sent_requests_loaded)
GodotBaaS.players_found.connect(_on_players_found)
GodotBaaS.player_blocked.connect(_on_player_blocked)
GodotBaaS.player_unblocked.connect(_on_player_unblocked)
GodotBaaS.blocked_players_loaded.connect(_on_blocked_players_loaded)
GodotBaaS.friend_leaderboard_loaded.connect(_on_friend_leaderboard_loaded)

# Errors
GodotBaaS.error.connect(_on_error)
```

## Offline Support

The plugin queues requests when offline and sends them when connection comes back. You don't need to do anything.

Turn it off if you want:

```gdscript
GodotBaaS.enable_offline_queue = false
```

## Player Data

After authentication, you get the player object. Store it somewhere:

```gdscript
var current_player = {}

func _on_authenticated(player):
    current_player = player
    print("Player ID: ", player.id)
    print("Username: ", player.username)
    print("Email: ", player.email)
    print("Device ID: ", player.deviceId)
    print("Is Anonymous: ", player.isAnonymous)
```

Check if they have an email linked:

```gdscript
func has_email():
    return current_player.get("email") != null

func is_anonymous():
    return current_player.get("isAnonymous", true)

func get_username():
    return current_player.get("username", "Guest")
```

Use this to show upgrade prompts or customize the UI.

## Configuration

```gdscript
# Required
GodotBaaS.api_key = "your_key"

# Optional
GodotBaaS.enable_retry = true                      # Retry failed requests
GodotBaaS.max_retries = 3                          # How many times
GodotBaaS.enable_offline_queue = true              # Queue when offline
```

## Examples

Check the `examples` folder:
- `full_test.tscn` - Interactive test scene with buttons for every feature
- `integration_test.gd` - Automated test script

Run them to see everything in action.

## Common Patterns

### Save on Exit

```gdscript
func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        save_game()
        await get_tree().create_timer(1.0).timeout
        get_tree().quit()

func save_game():
    GodotBaaS.save_data("autosave", get_game_state())
```

### Load on Start

```gdscript
func _ready():
    GodotBaaS.authenticated.connect(_on_login)
    GodotBaaS.data_loaded.connect(_on_data_loaded)
    GodotBaaS.login_with_device_id()

func _on_login(player):
    GodotBaaS.load_data("autosave")

func _on_data_loaded(key, data):
    if key == "autosave":
        restore_game_state(data)
```

### Prompt for Account Upgrade

```gdscript
var current_player = {}

func _on_authenticated(player):
    current_player = player
    
    # Show upgrade prompt if they don't have email
    if not current_player.get("email"):
        show_upgrade_dialog()

func show_upgrade_dialog():
    # Your UI code here
    upgrade_panel.show()

func on_upgrade_button_pressed():
    var email = email_input.text
    var password = password_input.text
    var username = username_input.text
    
    GodotBaaS.link_account(email, password, username)

func _on_account_linked(player):
    current_player = player
    print("Account upgraded! Email: ", player.email)
    upgrade_panel.hide()
```

## Troubleshooting

**"Not authenticated" errors**

Make sure you wait for the `authenticated` signal before making other calls.

**Data not loading**

Check that you're using the same key you saved with. Keys are case-sensitive.

**Leaderboard not found**

Create the leaderboard in the dashboard first. Set the slug to match what you're using in code.

**Offline queue not working**

The plugin checks network status every 5 seconds. If you need immediate retry, call `GodotBaaS._check_network_status()`.

## Support

Something broken? Open an issue on GitHub or check the docs at godotbaas.com.

## License

MIT - do whatever you want with it.


## API Reference

### Authentication

```gdscript
# Device ID login (recommended)
login_with_device_id()

# Email/password registration
register_player(email: String, password: String, username: String = "")

# Email/password login
login_player(email: String, password: String)

# Upgrade device/anonymous account to email/password
link_account(email: String, password: String, username: String = "")
```

### Cloud Saves

```gdscript
# Save data
save_data(key: String, value: Variant, version: int = 0)

# Load data
load_data(key: String)

# Delete data
delete_data(key: String)

# List all keys
list_data()

# Merge data (update specific fields without replacing everything)
merge_data(key: String, value: Variant, version: int = 0, strategy: String = "merge")
# Strategies: "merge", "append", "remove", "increment", "decrement"

# Add items to inventory (convenience method)
add_to_inventory(key: String, items: Array, version: int = 0)
```

### Leaderboards

```gdscript
# Submit score
submit_score(leaderboard_slug: String, score: int, metadata: Dictionary = {})

# Get leaderboard entries
get_leaderboard(leaderboard_slug: String, limit: int = 10, offset: int = 0)

# Get player's rank
get_player_rank(leaderboard_slug: String)
```

### Analytics

```gdscript
# Track event
track_event(event_name: String, properties: Dictionary = {})
```

### Achievements

```gdscript
# Grant achievement to player
grant_achievement(achievement_id: String)

# Update achievement progress
update_achievement_progress(achievement_id: String, progress: int, increment: bool = false)

# Get all achievements for player
get_achievements(include_hidden: bool = false)

# Get single achievement
get_achievement(achievement_id: String)
```

### Friends System

```gdscript
# Friend Requests
send_friend_request(player_identifier: String)  # Player ID or username
accept_friend_request(friendship_id: String)
decline_friend_request(friendship_id: String)
cancel_friend_request(friendship_id: String)

# Friend List
get_friends()
remove_friend(friend_id: String)
get_pending_requests()  # Requests received
get_sent_requests()     # Requests sent

# Player Search
search_players(query: String)  # Search by username or player ID

# Blocking
block_player(player_id: String, reason: String = "")
unblock_player(player_id: String)
get_blocked_players()

# Friend Leaderboards
get_friend_leaderboard(leaderboard_slug: String, limit: int = 100)
```

### Utility

```gdscript
# Get connection state
get_connection_state() -> ConnectionState

# Check if connected to backend
is_baas_connected() -> bool

# Check if network is online
is_online() -> bool

# Get queue size
get_queue_size() -> int

# Clear request queue
clear_queue()

# Cancel specific request
cancel_request(request_id: int) -> bool

# Cancel all requests
cancel_all_requests()
```

### Signals

```gdscript
# Authentication
authenticated(player_data: Dictionary)
auth_failed(error: String)

# Cloud saves
data_saved(key: String, version: int)
data_loaded(key: String, value: Variant)
data_conflict(key: String, server_version: int, server_data: Variant)

# Leaderboards
score_submitted(leaderboard: String, rank: int)
leaderboard_loaded(leaderboard: String, entries: Array)

# Achievements
achievement_unlocked(achievement: Dictionary)
achievement_progress_updated(achievement: Dictionary)
achievement_unlock_failed(error: String)
achievements_loaded(achievements: Array)

# Network
network_online()
network_offline()
request_queued(request_id: int)
queue_processed(successful: int, failed: int)

# Errors
error(error_message: String)
```

### Configuration Properties

```gdscript
# Required
api_key: String

# Optional
base_url: String = "https://api.godotbaas.com"
player_token: String  # Set automatically after login
enable_retry: bool = true
max_retries: int = 3
retry_delay_ms: int = 1000
enable_offline_queue: bool = true
max_queue_size: int = 50
queue_timeout_seconds: int = 300
```

### Enums

```gdscript
# Connection state
enum ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR
}

# Request priority (for internal use)
enum RequestPriority {
    LOW,      # Analytics, non-critical
    NORMAL,   # Regular requests
    HIGH,     # Authentication, critical saves
    CRITICAL  # Never queue, fail if offline
}
```
