# Godot BaaS Test Game

A comprehensive test game showcasing all features of the Godot BaaS (Backend-as-a-Service) plugin.

> **📋 Quick Links**: [Summary](SUMMARY.md) | [Quick Start](QUICK_START.md) | [Features](FEATURES.md) | [Structure](PROJECT_STRUCTURE.md) | [Troubleshooting](TROUBLESHOOTING.md) | [Index](INDEX.md)

## 🎮 Features Demonstrated

This test game demonstrates all major features of the Godot BaaS platform:

### 🔐 Authentication
- **Device ID Login**: Automatic anonymous authentication using device ID
- **Email/Password Registration**: Create new accounts with email and password
- **Email/Password Login**: Login to existing accounts
- **Account Linking**: Upgrade anonymous accounts to registered accounts

### ☁️ Cloud Saves
- **Save Progress**: Store player data (level, coins, high score) in the cloud
- **Load Progress**: Retrieve player data from the cloud
- **Auto-sync**: Automatically loads progress after authentication

### 🏆 Leaderboards
- **Global Leaderboards**: View top players worldwide
- **Friend Leaderboards**: Compare scores with friends only
- **Score Submission**: Submit scores with metadata
- **Rank Display**: See your current rank after submission

### 👥 Friends System
- **Search Players**: Find players by username or ID
- **Send Friend Requests**: Add friends to your network
- **Accept/Decline Requests**: Manage incoming friend requests
- **Friends List**: View all your friends
- **Remove Friends**: Unfriend players
- **Relationship Status**: See if players are already friends, blocked, or have pending requests

### 🏅 Achievements
- **View Achievements**: Browse all available achievements
- **Unlock Status**: See which achievements you've unlocked
- **Progress Tracking**: Track progress on incremental achievements
- **Rarity System**: Achievements have different rarity levels (Common, Rare, Epic, Legendary)
- **Points System**: Earn points for unlocking achievements

### 📊 Analytics
- **Event Tracking**: Automatically tracks gameplay events
- **Custom Properties**: Attach metadata to events

### 🎯 Simple Game
- **Click Game**: Simple clicker game to generate scores
- **Coin System**: Earn coins while playing
- **Score Tracking**: Track current score and high score
- **Achievement Integration**: Unlock achievements while playing

## 🚀 Getting Started

### Prerequisites
1. **Godot 4.3+** installed
2. **Godot BaaS Account**: Sign up at [dashboard.godotbaas.com](https://dashboard.godotbaas.com)
3. **API Key**: Get your API key from the dashboard

### Setup Instructions

1. **Open the Project**
   - Open Godot Engine
   - Click "Import"
   - Navigate to `godot-plugin/examples/testproject/`
   - Select `project.godot`
   - Click "Import & Edit"

2. **Configure API Key**
   - Open `scripts/game_manager.gd`
   - Replace `gb_live_your_api_key_here` with your actual API key:
     ```gdscript
     const API_KEY = "gb_live_your_actual_api_key"
     ```
   - Or use the in-game Settings screen to configure it

3. **Create Test Leaderboard** (Optional)
   - Go to your dashboard
   - Create a leaderboard with slug: `test-leaderboard`
   - Set reset period as desired (daily/weekly/monthly/never)

4. **Create Test Achievements** (Optional)
   - Go to your dashboard
   - Create achievements with these IDs:
     - `first_clicks` - Unlocked after 10 clicks
     - `click_master` - Unlocked after 100 clicks
     - `click_progress` - Progress achievement (target: 1000)

5. **Run the Game**
   - Press F5 or click the Play button
   - Click "Quick Start" to login with device ID
   - Explore all features!

## 📁 Project Structure

```
testproject/
├── scenes/                    # All game scenes
│   ├── main_menu.tscn        # Main menu with navigation
│   ├── auth_screen.tscn      # Login/Register/Link account
│   ├── leaderboard_screen.tscn # Global and friend leaderboards
│   ├── friends_screen.tscn   # Friends management
│   ├── achievements_screen.tscn # Achievements browser
│   ├── game_screen.tscn      # Simple clicker game
│   └── settings_screen.tscn  # Configuration and info
├── scripts/                   # All game scripts
│   ├── game_manager.gd       # Global game state (Autoload)
│   ├── main_menu.gd
│   ├── auth_screen.gd
│   ├── leaderboard_screen.gd
│   ├── friends_screen.gd
│   ├── achievements_screen.gd
│   ├── game_screen.gd
│   └── settings_screen.gd
├── project.godot             # Godot project file
├── icon.svg                  # Project icon
└── README.md                 # This file
```

## 🎯 How to Use Each Feature

### Authentication
1. **Quick Start**: Click "Quick Start" on main menu for instant device ID login
2. **Register**: Click "Login/Register" → "Register" tab → Fill form → Register
3. **Login**: Click "Login/Register" → "Login" tab → Enter credentials → Login
4. **Link Account**: Login with device ID first → "Login/Register" → "Link Account" tab

### Leaderboards
1. Navigate to "Leaderboards" from main menu
2. **Submit Score**: Enter a score → Click "Submit Score"
3. **View Global**: See top 50 players worldwide
4. **View Friends**: Switch to "Friends" tab to see friend scores only

### Friends
1. Navigate to "Friends" from main menu
2. **Search**: Enter username in search box → Click "Search"
3. **Add Friend**: Click "+ Add Friend" on search results
4. **Accept Requests**: Go to "Pending" tab → Click "Accept"
5. **View Friends**: "Friends" tab shows all your friends

### Achievements
1. Navigate to "Achievements" from main menu
2. View all achievements with unlock status
3. See progress bars for incremental achievements
4. Play the game to unlock achievements automatically

### Game
1. Navigate to "Play Game" from main menu
2. Click the "CLICK ME!" button to earn points and coins
3. Click "Save Progress" to save to cloud
4. Click "Submit Score" to add to leaderboard
5. Achievements unlock automatically as you play

### Settings
1. Navigate to "Settings" from main menu
2. Update API Key and Base URL if needed
3. View your player information
4. Access documentation and dashboard links

## 🔧 Customization

### Changing the Leaderboard
Edit `leaderboard_screen.gd`:
```gdscript
const LEADERBOARD_SLUG = "your-leaderboard-slug"
```

### Adding More Achievements
Edit `game_screen.gd` to add achievement checks:
```gdscript
if click_count == 50:
    GodotBaaS.grant_achievement("your_achievement_id")
```

### Modifying Game Logic
Edit `game_screen.gd` to change:
- Points per click
- Coins per click
- Achievement triggers
- Analytics events

### Styling
All scenes use Godot's built-in theming. You can:
- Add custom themes in project settings
- Modify colors in scene files
- Add custom fonts and styles

## 📚 Code Examples

### Authenticating a Player
```gdscript
# Device ID (anonymous)
GodotBaaS.login_with_device_id()

# Email/Password
GodotBaaS.login_player("user@example.com", "password123")

# Register
GodotBaaS.register_player("user@example.com", "password123", "Username")
```

### Saving/Loading Data
```gdscript
# Save
var data = {"level": 5, "coins": 100}
GodotBaaS.save_data("player_progress", data, 0)

# Load
GodotBaaS.load_data("player_progress")

# Handle loaded data
func _on_data_loaded(key: String, value: Variant):
    if key == "player_progress":
        var level = value.get("level", 1)
        var coins = value.get("coins", 0)
```

### Submitting Scores
```gdscript
var score = 1000
var metadata = {"platform": OS.get_name()}
GodotBaaS.submit_score("test-leaderboard", score, metadata)
```

### Managing Friends
```gdscript
# Search
GodotBaaS.search_players("username")

# Send request
GodotBaaS.send_friend_request("player_id")

# Accept request
GodotBaaS.accept_friend_request("friendship_id")

# Get friends
GodotBaaS.get_friends()
```

### Unlocking Achievements
```gdscript
# Grant achievement
GodotBaaS.grant_achievement("achievement_id")

# Update progress
GodotBaaS.update_achievement_progress("achievement_id", 50, false)

# Increment progress
GodotBaaS.update_achievement_progress("achievement_id", 10, true)
```

## 🐛 Troubleshooting

### "Not authenticated" errors
- Make sure you've clicked "Quick Start" or logged in
- Check that your API key is correct in `game_manager.gd`

### Leaderboard not loading
- Verify the leaderboard slug exists in your dashboard
- Check the `LEADERBOARD_SLUG` constant in `leaderboard_screen.gd`

### Achievements not unlocking
- Create achievements in your dashboard with matching IDs
- Check console for error messages
- Verify you're authenticated before trying to unlock

### Friends search not working
- Make sure both players are authenticated
- Try searching by exact username
- Check that players aren't already friends or blocked

## 📖 Additional Resources

- **Documentation**: [godotbaas.com/docs](https://godotbaas.com/docs)
- **Dashboard**: [dashboard.godotbaas.com](https://dashboard.godotbaas.com)
- **GitHub**: [github.com/GarretteAllen/godot-baas-plugin](https://github.com/GarretteAllen/godot-baas-plugin)
- **Plugin README**: See `../../README.md` for plugin documentation

## 📝 License

This test project is provided as an example for the Godot BaaS plugin. Feel free to use it as a starting point for your own games!

## 🤝 Contributing

Found a bug or want to improve the test game? Feel free to submit issues or pull requests to the main repository.

---

**Happy Testing! 🎮**
