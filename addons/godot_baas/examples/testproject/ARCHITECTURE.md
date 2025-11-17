# Architecture Overview

Visual guide to how the test game is structured and how components interact.

## 🏗️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │
│  │  Main    │ │   Auth   │ │Leaderboard│ │ Friends  │  ...  │
│  │  Menu    │ │  Screen  │ │  Screen   │ │  Screen  │       │
│  └────┬─────┘ └────┬─────┘ └────┬──────┘ └────┬─────┘       │
└───────┼────────────┼────────────┼─────────────┼─────────────┘
        │            │            │             │
        └────────────┴────────────┴─────────────┘
                     │
        ┌────────────▼────────────┐
        │    GameManager          │  ← Autoload Singleton
        │  (Global State)         │
        │  - Authentication       │
        │  - Player Data          │
        │  - Scores & Coins       │
        │  - Scene Management     │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────┐
        │   GodotBaaS Plugin      │  ← Autoload Singleton
        │  (API Client)           │
        │  - HTTP Requests        │
        │  - Signal Emissions     │
        │  - Error Handling       │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────┐
        │   Backend Server        │
        │  (Godot BaaS API)       │
        │  - Authentication       │
        │  - Database             │
        │  - Leaderboards         │
        │  - Friends System       │
        └─────────────────────────┘
```

## 🔄 Data Flow Diagram

### Authentication Flow

```
User clicks "Quick Start"
         │
         ▼
┌────────────────────┐
│  main_menu.gd      │
│  _on_quick_start() │
└────────┬───────────┘
         │ calls
         ▼
┌────────────────────┐
│  GameManager       │
│  auto_login()      │
└────────┬───────────┘
         │ calls
         ▼
┌────────────────────┐
│  GodotBaaS         │
│  login_with_       │
│  device_id()       │
└────────┬───────────┘
         │ HTTP Request
         ▼
┌────────────────────┐
│  Backend Server    │
│  POST /auth/device │
└────────┬───────────┘
         │ Response
         ▼
┌────────────────────┐
│  GodotBaaS         │
│  emits             │
│  authenticated     │
└────────┬───────────┘
         │ signal
         ▼
┌────────────────────┐
│  GameManager       │
│  _on_authenticated │
│  - Store token     │
│  - Load progress   │
└────────┬───────────┘
         │ emits
         ▼
┌────────────────────┐
│  main_menu.gd      │
│  _on_auth_changed  │
│  - Update UI       │
│  - Enable buttons  │
└────────────────────┘
```

### Cloud Save Flow

```
User clicks "Save Progress"
         │
         ▼
┌────────────────────┐
│  game_screen.gd    │
│  _on_save_pressed()│
└────────┬───────────┘
         │ calls
         ▼
┌────────────────────┐
│  GameManager       │
│  save_progress()   │
│  - Collect data    │
└────────┬───────────┘
         │ calls
         ▼
┌────────────────────┐
│  GodotBaaS         │
│  save_data()       │
└────────┬───────────┘
         │ HTTP Request
         ▼
┌────────────────────┐
│  Backend Server    │
│  POST /data/{key}  │
└────────┬───────────┘
         │ Response
         ▼
┌────────────────────┐
│  GodotBaaS         │
│  emits data_saved  │
└────────┬───────────┘
         │ signal
         ▼
┌────────────────────┐
│  game_screen.gd    │
│  _on_data_saved    │
│  - Show success    │
└────────────────────┘
```

## 🎯 Component Relationships

### Scene Hierarchy

```
Main Menu (Entry Point)
    │
    ├─→ Auth Screen
    │   ├─ Login Tab
    │   ├─ Register Tab
    │   └─ Link Account Tab
    │
    ├─→ Leaderboard Screen
    │   ├─ Global Tab
    │   └─ Friends Tab
    │
    ├─→ Friends Screen
    │   ├─ Friends Tab
    │   ├─ Pending Tab
    │   └─ Search Tab
    │
    ├─→ Achievements Screen
    │   ├─ Stats Panel
    │   └─ Achievements List
    │
    ├─→ Game Screen
    │   ├─ HUD (Score, Coins)
    │   ├─ Game Area
    │   └─ Actions Panel
    │
    └─→ Settings Screen
        ├─ Configuration
        ├─ Player Info
        └─ Resource Links
```

### Script Dependencies

```
┌─────────────────────────────────────────────┐
│           game_manager.gd (Autoload)        │
│  - Depends on: GodotBaaS                    │
│  - Used by: All screens                     │
│  - Provides: Global state, scene management │
└─────────────────────────────────────────────┘
                     ▲
                     │ depends on
        ┌────────────┴────────────┐
        │                         │
┌───────┴────────┐    ┌──────────┴─────────┐
│ main_menu.gd   │    │ auth_screen.gd     │
│ - Navigation   │    │ - Forms            │
│ - Status       │    │ - Validation       │
└────────────────┘    └────────────────────┘
        │                         │
        │             ┌───────────┴───────────┐
        │             │                       │
┌───────┴────────┐    ┌──────────┴─────────┐ │
│leaderboard_    │    │ friends_screen.gd  │ │
│screen.gd       │    │ - Search           │ │
│ - Rankings     │    │ - Requests         │ │
└────────────────┘    └────────────────────┘ │
        │                         │           │
        │             ┌───────────┴───────────┘
        │             │
┌───────┴────────┐    ┌──────────┴─────────┐
│achievements_   │    │ game_screen.gd     │
│screen.gd       │    │ - Game logic       │
│ - Display      │    │ - Scoring          │
└────────────────┘    └────────────────────┘
        │                         │
        └────────────┬────────────┘
                     │
        ┌────────────┴────────────┐
        │   settings_screen.gd    │
        │   - Configuration       │
        └─────────────────────────┘
```

## 📡 Signal Flow

### GameManager Signals

```
GameManager
    │
    ├─ authentication_changed(bool)
    │   ├─→ main_menu.gd
    │   ├─→ auth_screen.gd
    │   └─→ settings_screen.gd
    │
    ├─ player_data_updated(Dictionary)
    │   ├─→ main_menu.gd
    │   └─→ settings_screen.gd
    │
    ├─ score_updated(int)
    │   └─→ game_screen.gd
    │
    └─ coins_updated(int)
        └─→ game_screen.gd
```

### GodotBaaS Signals

```
GodotBaaS
    │
    ├─ authenticated(Dictionary)
    │   └─→ GameManager
    │
    ├─ auth_failed(String)
    │   ├─→ GameManager
    │   └─→ auth_screen.gd
    │
    ├─ data_saved(String, int)
    │   ├─→ GameManager
    │   └─→ game_screen.gd
    │
    ├─ data_loaded(String, Variant)
    │   └─→ GameManager
    │
    ├─ score_submitted(String, int)
    │   ├─→ leaderboard_screen.gd
    │   └─→ game_screen.gd
    │
    ├─ leaderboard_loaded(String, Array)
    │   └─→ leaderboard_screen.gd
    │
    ├─ friends_loaded(Array, int)
    │   └─→ friends_screen.gd
    │
    ├─ achievements_loaded(Array)
    │   └─→ achievements_screen.gd
    │
    └─ error(String)
        └─→ All screens
```

## 🗂️ File Organization

### By Feature

```
Authentication
├─ scenes/auth_screen.tscn
├─ scripts/auth_screen.gd
└─ scripts/game_manager.gd (auth methods)

Cloud Saves
├─ scripts/game_manager.gd (save/load)
└─ scripts/game_screen.gd (trigger save)

Leaderboards
├─ scenes/leaderboard_screen.tscn
└─ scripts/leaderboard_screen.gd

Friends
├─ scenes/friends_screen.tscn
└─ scripts/friends_screen.gd

Achievements
├─ scenes/achievements_screen.tscn
└─ scripts/achievements_screen.gd

Game
├─ scenes/game_screen.tscn
└─ scripts/game_screen.gd

Settings
├─ scenes/settings_screen.tscn
└─ scripts/settings_screen.gd

Navigation
├─ scenes/main_menu.tscn
└─ scripts/main_menu.gd
```

## 🔌 Plugin Integration

### How Screens Use GodotBaaS

```
Screen Script
    │
    ├─ _ready()
    │   └─ Connect to GodotBaaS signals
    │
    ├─ User Action
    │   └─ Call GodotBaaS method
    │
    └─ Signal Handler
        └─ Update UI
```

### Example: Leaderboard Screen

```gdscript
func _ready():
    # Connect signals
    GodotBaaS.leaderboard_loaded.connect(_on_leaderboard_loaded)
    GodotBaaS.error.connect(_on_error)
    
    # Load data
    _load_leaderboard()

func _load_leaderboard():
    # Call plugin
    GodotBaaS.get_leaderboard("test-leaderboard", 50)

func _on_leaderboard_loaded(slug: String, entries: Array):
    # Update UI
    for entry in entries:
        var panel = _create_entry_panel(entry)
        list.add_child(panel)
```

## 🎨 UI Component Pattern

### Reusable Panel Creation

```
_create_panel(data: Dictionary) → PanelContainer
    │
    ├─ Create PanelContainer
    │   └─ Style (colors, borders)
    │
    ├─ Create MarginContainer
    │   └─ Margins (padding)
    │
    ├─ Create HBoxContainer
    │   └─ Layout (horizontal)
    │
    ├─ Add Labels
    │   └─ Display data
    │
    ├─ Add Buttons
    │   └─ Connect actions
    │
    └─ Return panel
```

### Used In
- Leaderboard entries
- Friend list items
- Pending request items
- Search result items
- Achievement items

## 🔄 State Management

### GameManager State

```
GameManager (Singleton)
    │
    ├─ Authentication State
    │   ├─ is_authenticated: bool
    │   ├─ player_data: Dictionary
    │   ├─ player_id: String
    │   ├─ player_username: String
    │   └─ is_anonymous: bool
    │
    ├─ Game State
    │   ├─ current_score: int
    │   ├─ high_score: int
    │   ├─ coins: int
    │   └─ level: int
    │
    └─ Configuration
        ├─ API_KEY: String
        └─ BASE_URL: String
```

### State Updates

```
User Action
    │
    ▼
Update GameManager State
    │
    ▼
Emit Signal
    │
    ▼
UI Updates
```

## 🎯 Request Flow

### Typical API Request

```
1. User Action
   └─ Button click, form submit, etc.

2. UI Script
   └─ Validate input
   └─ Show loading state

3. GameManager (optional)
   └─ Prepare data
   └─ Add context

4. GodotBaaS Plugin
   └─ Build HTTP request
   └─ Add headers (API key, token)
   └─ Send request

5. Backend Server
   └─ Validate request
   └─ Process data
   └─ Return response

6. GodotBaaS Plugin
   └─ Parse response
   └─ Emit signal

7. UI Script
   └─ Handle response
   └─ Update UI
   └─ Show feedback
```

## 🧩 Design Patterns Used

### Singleton Pattern
- **GameManager**: Global state
- **GodotBaaS**: API client

### Observer Pattern
- **Signals**: Event notifications
- **Connections**: Loose coupling

### Factory Pattern
- **Panel Creation**: Reusable UI components

### Strategy Pattern
- **Scene Management**: Different screens for different features

### Template Method Pattern
- **Screen Scripts**: Common structure, different implementations

## 🔐 Security Architecture

```
Client (Game)
    │
    ├─ API Key (configured)
    │   └─ Sent with every request
    │
    ├─ Player Token (after auth)
    │   └─ Sent with authenticated requests
    │
    └─ No Passwords Stored
        └─ Only sent during auth

Backend Server
    │
    ├─ Validates API Key
    │   └─ Identifies project
    │
    ├─ Validates Player Token
    │   └─ Identifies player
    │
    └─ Processes Request
        └─ Returns data
```

## 📊 Performance Considerations

### Efficient Updates
- Only update UI when data changes
- Use signals for reactive updates
- Avoid polling, use event-driven

### Memory Management
- Clear lists before repopulating
- Free unused nodes
- Reuse UI components where possible

### Network Optimization
- Batch requests when possible
- Cache data locally (GameManager)
- Show loading states
- Handle errors gracefully

## 🎓 Learning the Architecture

### Start Here
1. **Main Menu** - Simple navigation
2. **GameManager** - Global state
3. **Auth Screen** - Form handling

### Then Study
1. **Leaderboard Screen** - Dynamic UI
2. **Friends Screen** - Complex state
3. **Game Screen** - Integration

### Finally Master
1. **Signal Flow** - Event system
2. **Data Flow** - Request/response
3. **Patterns** - Reusable code

---

**Understanding the architecture helps you build better games! 🏗️**
