# Quick Start Guide

Get up and running with the Godot BaaS Test Game in 5 minutes!

## ⚡ 5-Minute Setup

### Step 1: Get Your API Key (2 minutes)
1. Go to [dashboard.godotbaas.com](https://dashboard.godotbaas.com)
2. Sign up or login
3. Create a new project
4. Copy your API key (starts with `gb_live_`)

### Step 2: Configure the Project (1 minute)
1. Open `scripts/game_manager.gd`
2. Find line 8:
   ```gdscript
   const API_KEY = "gb_live_your_api_key_here"
   ```
3. Replace with your actual API key:
   ```gdscript
   const API_KEY = "gb_live_abc123xyz..."
   ```
4. Save the file

### Step 3: Run the Game (30 seconds)
1. Press **F5** or click the **Play** button
2. Click **"🚀 Quick Start"** on the main menu
3. You're logged in! ✅

### Step 4: Test Features (1.5 minutes)
1. **Play the Game**: Click "🎯 Play Game" → Click the button → Submit score
2. **View Leaderboard**: Click "🏆 Leaderboards" → See your score
3. **Check Achievements**: Click "🏅 Achievements" → View available achievements
4. **Add Friends**: Click "👥 Friends" → Search for players

## 🎯 What to Try First

### Test Authentication
```
Main Menu → Quick Start (Device Login)
✓ You're now logged in anonymously
```

### Test Cloud Saves
```
Play Game → Click 10 times → Save Progress
✓ Your progress is saved to the cloud
```

### Test Leaderboards
```
Play Game → Click 20 times → Submit Score
Leaderboards → View your rank
✓ You're on the leaderboard!
```

### Test Friends (Need 2 accounts)
```
Friends → Search for a username → Add Friend
✓ Friend request sent!
```

## 🔧 Optional: Create Test Data

### Create a Leaderboard
1. Go to your dashboard
2. Navigate to "Leaderboards"
3. Click "Create Leaderboard"
4. Set slug to: `test-leaderboard`
5. Choose reset period (or "Never")
6. Save

### Create Achievements
1. Go to your dashboard
2. Navigate to "Achievements"
3. Create these achievements:

**Achievement 1: First Clicks**
- ID: `first_clicks`
- Name: "First Clicks"
- Description: "Click 10 times"
- Type: Standard
- Points: 10

**Achievement 2: Click Master**
- ID: `click_master`
- Name: "Click Master"
- Description: "Click 100 times"
- Type: Standard
- Points: 50

**Achievement 3: Click Progress**
- ID: `click_progress`
- Name: "Click Progress"
- Description: "Click 1000 times"
- Type: Progress
- Target Value: 1000
- Points: 100

## 🎮 Game Controls

### Main Menu
- **Quick Start**: Login with device ID (instant)
- **Login/Register**: Create or login to email account
- **Leaderboards**: View global and friend scores
- **Friends**: Manage your friend list
- **Achievements**: View and track achievements
- **Play Game**: Simple clicker game
- **Settings**: Configure API key and view info

### Game Screen
- **Click Button**: Earn 10 points + 1 coin per click
- **Save Progress**: Save to cloud
- **Submit Score**: Add to leaderboard
- **Reset**: Start over

## 🐛 Common Issues

### "Not authenticated" error
**Solution**: Click "Quick Start" on the main menu first

### "Invalid API key" error
**Solution**: Check that you copied the full API key correctly

### Leaderboard shows "No entries"
**Solution**: Submit a score first by playing the game

### Achievements not appearing
**Solution**: Create achievements in your dashboard (optional)

## 📱 Testing on Multiple Devices

Want to test friends system?

1. **Device 1**: Login with device ID → Note the username
2. **Device 2**: Login with device ID → Search for Device 1's username → Add friend
3. **Device 1**: Go to Friends → Pending tab → Accept request
4. **Both devices**: Now you're friends! Test friend leaderboards

## 🚀 Next Steps

Once you're comfortable with the test game:

1. **Explore the Code**: Check out the scripts to see how features are implemented
2. **Customize**: Modify the game to fit your needs
3. **Build Your Game**: Use this as a template for your own project
4. **Read Full Docs**: Visit [godotbaas.com/docs](https://godotbaas.com/docs)

## 💡 Pro Tips

- **Auto-save**: The game automatically loads your progress after login
- **Analytics**: Every 10 clicks sends an analytics event
- **Achievements**: Play the game to unlock achievements automatically
- **Friend Leaderboards**: Add friends to see friend-only rankings
- **Account Linking**: Start with device ID, then link to email later

## 🆘 Need Help?

- **Documentation**: [godotbaas.com/docs](https://godotbaas.com/docs)
- **Dashboard**: [dashboard.godotbaas.com](https://dashboard.godotbaas.com)
- **GitHub Issues**: [github.com/GarretteAllen/godot-baas-plugin/issues](https://github.com/GarretteAllen/godot-baas-plugin/issues)

---

**Ready to build something amazing? Let's go! 🎮**
