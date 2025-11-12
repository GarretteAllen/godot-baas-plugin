# Godot BaaS Plugin

Backend services for your Godot game without the headache.

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
