# Project Structure Guide

Understanding how the test game is organized.

## 📂 Directory Structure

```
testproject/
│
├── 📄 project.godot          # Godot project configuration
├── 📄 icon.svg               # Project icon
├── 📄 README.md              # Full documentation
├── 📄 QUICK_START.md         # 5-minute setup guide
├── 📄 PROJECT_STRUCTURE.md   # This file
│
├── 📁 scenes/                # All game scenes (.tscn files)
│   ├── main_menu.tscn        # Entry point - navigation hub
│   ├── auth_screen.tscn      # Login/Register/Link account
│   ├── leaderboard_screen.tscn # Leaderboard viewer
│   ├── friends_screen.tscn   # Friends management
│   ├── achievements_screen.tscn # Achievements browser
│   ├── game_screen.tscn      # Simple clicker game
│   └── settings_screen.tscn  # Configuration screen
│
└── 📁 scripts/               # All game scripts (.gd files)
    ├── game_manager.gd       # 🌟 AUTOLOAD - Global state
    ├── main_menu.gd          # Main menu logic
    ├── auth_screen.gd        # Authentication logic
    ├── leaderboard_screen.gd # Leaderboard logic
    ├── friends_screen.gd     # Friends logic
    ├── achievements_screen.gd # Achievements logic
    ├── game_screen.gd        # Game logic
    └── settings_screen.gd    # Settings logic
```

## 🎯 Key Files Explained

### Core Files

#### `project.godot`
- Godot project configuration
- Defines autoloads (GodotBaaS, GameManager)
- Window settings and rendering options

#### `scripts/game_manager.gd` ⭐ IMPORTANT
- **Autoload singleton** - accessible from anywhere as `GameManager`
- Manages global game state (authentication, player data, scores, coins)
- Configures GodotBaaS (API key, base URL)
- Handles scene transitions
- **This is where you set your API key!**

### Scene Files (.tscn)

Each scene file defines the UI layout and node structure:

#### `scenes/main_menu.tscn`
- Entry point of the game
- Navigation hub to all features
- Shows authentication status
- Enables/disables buttons based on login state

#### `scenes/auth_screen.tscn`
- Three tabs: Login, Register, Link Account
- Form inputs for credentials
- Status labels for feedback

#### `scenes/leaderboard_screen.tscn`
- Two tabs: Global, Friends
- Scrollable leaderboard entries
- Score submission panel
- Refresh buttons

#### `scenes/friends_screen.tscn`
- Three tabs: Friends, Pending, Search
- Search bar for finding players
- Friend list with remove buttons
- Pending requests with accept/decline

#### `scenes/achievements_screen.tscn`
- Stats panel (unlocked count, total points)
- Scrollable achievements list
- Progress bars for incremental achievements
- Rarity badges

#### `scenes/game_screen.tscn`
- Top bar with score/coins/high score
- Large click button
- Action buttons (save, submit, reset)
- Status label for feedback

#### `scenes/settings_screen.tscn`
- API configuration inputs
- Player information display
- Resource links (docs, dashboard, GitHub)

### Script Files (.gd)

Each script file handles the logic for its corresponding scene:

#### `scripts/game_manager.gd` ⭐ AUTOLOAD
**Purpose**: Global game state and BaaS configuration

**Key Functions**:
- `auto_login()` - Login with device ID
- `login_with_email()` - Login with credentials
- `register_account()` - Create new account
- `link_to_email()` - Upgrade anonymous to registered
- `load_progress()` - Load player data from cloud
- `save_progress()` - Save player data to cloud
- `set_score()` - Update current score
- `add_coins()` - Add coins to player
- `change_scene()` - Navigate between scenes

**Signals**:
- `authentication_changed(authenticated: bool)`
- `player_data_updated(data: Dictionary)`
- `score_updated(score: int)`
- `coins_updated(coins: int)`

#### `scripts/main_menu.gd`
**Purpose**: Main menu navigation and status display

**Key Functions**:
- `_update_ui()` - Updates status labels and button states
- Button handlers for navigation

#### `scripts/auth_screen.gd`
**Purpose**: Handle authentication forms

**Key Functions**:
- `_on_login_button_pressed()` - Process login
- `_on_register_button_pressed()` - Process registration
- `_on_link_button_pressed()` - Process account linking
- Form validation and error display

#### `scripts/leaderboard_screen.gd`
**Purpose**: Display and manage leaderboards

**Key Functions**:
- `_load_global_leaderboard()` - Fetch global rankings
- `_load_friends_leaderboard()` - Fetch friend rankings
- `_create_entry_panel()` - Create leaderboard entry UI
- Score submission handling

#### `scripts/friends_screen.gd`
**Purpose**: Friends system management

**Key Functions**:
- `_load_friends()` - Fetch friends list
- `_load_pending()` - Fetch pending requests
- `_create_friend_panel()` - Create friend entry UI
- `_create_pending_panel()` - Create request entry UI
- `_create_search_result_panel()` - Create search result UI
- `_remove_friend()` - Remove a friend

#### `scripts/achievements_screen.gd`
**Purpose**: Display achievements

**Key Functions**:
- `_load_achievements()` - Fetch all achievements
- `_create_achievement_panel()` - Create achievement entry UI
- Stats calculation (unlocked count, total points)

#### `scripts/game_screen.gd`
**Purpose**: Simple clicker game logic

**Key Functions**:
- `_on_click_button_pressed()` - Handle clicks, update score/coins
- `_on_save_pressed()` - Save progress to cloud
- `_on_submit_pressed()` - Submit score to leaderboard
- `_on_reset_pressed()` - Reset game state
- Achievement unlock triggers
- Analytics event tracking

#### `scripts/settings_screen.gd`
**Purpose**: Configuration and information

**Key Functions**:
- `_update_player_info()` - Display player details
- `_on_save_config_pressed()` - Update API configuration
- Link buttons to external resources

## 🔄 Data Flow

### Authentication Flow
```
User clicks "Quick Start"
    ↓
main_menu.gd calls GameManager.auto_login()
    ↓
GameManager calls GodotBaaS.login_with_device_id()
    ↓
GodotBaaS emits authenticated signal
    ↓
GameManager._on_authenticated() receives player data
    ↓
GameManager emits authentication_changed signal
    ↓
main_menu.gd updates UI (enables buttons)
    ↓
GameManager.load_progress() auto-loads cloud data
```

### Save/Load Flow
```
User clicks "Save Progress"
    ↓
game_screen.gd calls GameManager.save_progress()
    ↓
GameManager calls GodotBaaS.save_data()
    ↓
GodotBaaS emits data_saved signal
    ↓
game_screen.gd shows success message
```

### Leaderboard Flow
```
User clicks "Submit Score"
    ↓
game_screen.gd calls GodotBaaS.submit_score()
    ↓
GodotBaaS emits score_submitted signal with rank
    ↓
game_screen.gd shows rank in status label
```

### Friends Flow
```
User searches for player
    ↓
friends_screen.gd calls GodotBaaS.search_players()
    ↓
GodotBaaS emits players_found signal
    ↓
friends_screen.gd displays results with "Add Friend" buttons
    ↓
User clicks "Add Friend"
    ↓
friends_screen.gd calls GodotBaaS.send_friend_request()
    ↓
GodotBaaS emits friend_request_sent signal
    ↓
friends_screen.gd refreshes search to show "Request sent"
```

## 🎨 UI Patterns

### Panel Creation Pattern
Most screens use a similar pattern for creating list entries:

```gdscript
func _create_entry_panel(data: Dictionary) -> PanelContainer:
    var panel = PanelContainer.new()
    var margin = MarginContainer.new()
    # ... add margins
    panel.add_child(margin)
    
    var hbox = HBoxContainer.new()
    margin.add_child(hbox)
    
    # Add labels and buttons
    var label = Label.new()
    label.text = data.get("name", "Unknown")
    hbox.add_child(label)
    
    var button = Button.new()
    button.text = "Action"
    button.pressed.connect(func(): _do_action(data.get("id")))
    hbox.add_child(button)
    
    return panel
```

### Loading State Pattern
```gdscript
func _load_data():
    _clear_list(list_container)
    _add_loading_label(list_container)
    GodotBaaS.fetch_data()

func _on_data_loaded(data: Array):
    _clear_list(list_container)
    for item in data:
        var panel = _create_panel(item)
        list_container.add_child(panel)
```

### Status Message Pattern
```gdscript
func _show_status(message: String, color: Color):
    status_label.text = message
    status_label.add_theme_color_override("font_color", color)

# Usage:
_show_status("✅ Success!", Color.GREEN)
_show_status("⚠️ Warning", Color.ORANGE)
_show_status("❌ Error", Color.RED)
```

## 🔌 GodotBaaS Integration

### Signal Connections
All screens connect to relevant GodotBaaS signals in `_ready()`:

```gdscript
func _ready():
    GodotBaaS.signal_name.connect(_on_signal_handler)
```

### Common Signals Used
- `authenticated` - Player logged in
- `auth_failed` - Login failed
- `data_saved` - Cloud save completed
- `data_loaded` - Cloud data retrieved
- `score_submitted` - Score added to leaderboard
- `leaderboard_loaded` - Leaderboard entries received
- `friends_loaded` - Friends list received
- `achievement_unlocked` - Achievement granted
- `error` - General error occurred

## 🎓 Learning Path

### Beginner
1. Start with `main_menu.gd` - Simple navigation
2. Look at `game_manager.gd` - See how autoloads work
3. Check `auth_screen.gd` - Form handling basics

### Intermediate
1. Study `leaderboard_screen.gd` - Dynamic UI creation
2. Explore `friends_screen.gd` - Complex state management
3. Review `achievements_screen.gd` - Data visualization

### Advanced
1. Understand `game_manager.gd` signal system
2. Implement your own features using the patterns
3. Extend the game with new screens and functionality

## 💡 Best Practices Used

1. **Separation of Concerns**: Each screen handles its own UI logic
2. **Global State**: GameManager handles shared state
3. **Signal-Driven**: Loose coupling between components
4. **Consistent Patterns**: Similar code structure across screens
5. **Error Handling**: All API calls have error handlers
6. **User Feedback**: Status labels for all actions
7. **Loading States**: Show loading indicators during API calls
8. **Null Safety**: Check for empty/null values before use

## 🚀 Extending the Project

### Adding a New Screen
1. Create scene file in `scenes/`
2. Create script file in `scripts/`
3. Add navigation button in `main_menu.tscn`
4. Add handler in `main_menu.gd`
5. Connect GodotBaaS signals in new script
6. Follow existing UI patterns

### Adding New Features
1. Check if GodotBaaS supports it (see plugin docs)
2. Add function to `game_manager.gd` if needed
3. Create UI in relevant scene
4. Connect signals and handle responses
5. Add error handling and user feedback

---

**Now you understand how everything fits together! 🎯**
