# Troubleshooting Guide

Common issues and how to fix them.

## 🔧 Setup Issues

### "Cannot find GodotBaaS" Error

**Problem**: The autoload isn't configured correctly.

**Solution**:
1. Check `project.godot` has this line:
   ```
   GodotBaaS="*res://../../godot_baas_client.gd"
   ```
2. Verify the path points to the correct location
3. Restart Godot Editor

### "Invalid API Key" Error

**Problem**: API key is incorrect or not set.

**Solutions**:
1. Open `scripts/game_manager.gd`
2. Check line 8: `const API_KEY = "..."`
3. Make sure it starts with `gb_live_` or `gb_dev_`
4. Copy the full key from your dashboard
5. No spaces or quotes inside the string

**Alternative**: Use the Settings screen in-game to update the API key.

### Project Won't Open

**Problem**: Godot version mismatch or corrupted project.

**Solutions**:
1. Make sure you're using Godot 4.3 or newer
2. Delete the `.godot/` folder and reopen
3. Check console for specific error messages

## 🔐 Authentication Issues

### "Not authenticated" When Trying Features

**Problem**: You haven't logged in yet.

**Solution**:
1. Go to Main Menu
2. Click "🚀 Quick Start" button
3. Wait for "Status: ✅ Connected"
4. Now try the feature again

### Device Login Not Working

**Problem**: Device ID generation or storage issue.

**Solutions**:
1. Check console for error messages
2. Make sure `user://` directory is writable
3. Try deleting `user://godot_baas_device_id.dat` and login again
4. Verify API key is correct

### Email Login Fails

**Problem**: Wrong credentials or account doesn't exist.

**Solutions**:
1. Double-check email and password
2. Try registering a new account first
3. Check console for specific error message
4. Verify API key is correct

### Account Linking Fails

**Problem**: Not logged in as anonymous or email already used.

**Solutions**:
1. Must be logged in with device ID first
2. Email must not be already registered
3. Password must be at least 8 characters
4. Check console for specific error

## ☁️ Cloud Save Issues

### Progress Not Saving

**Problem**: Not authenticated or network error.

**Solutions**:
1. Make sure you're logged in (green status)
2. Check console for error messages
3. Verify internet connection
4. Try again after a few seconds

### Progress Not Loading

**Problem**: No saved data or wrong player.

**Solutions**:
1. Save progress at least once first
2. Make sure you're logged in as the same player
3. Check console - might be loading but data is empty
4. Try saving new progress and loading again

### "Data conflict" Error

**Problem**: Version mismatch (rare in single-player).

**Solution**:
1. This is normal if playing on multiple devices
2. The game will show you the server version
3. Choose which version to keep
4. Save again with the correct version number

## 🏆 Leaderboard Issues

### "No entries yet"

**Problem**: No scores have been submitted.

**Solution**:
1. Play the game and click the button
2. Click "Submit Score"
3. Wait for confirmation
4. Refresh the leaderboard

### Leaderboard Not Loading

**Problem**: Leaderboard doesn't exist or wrong slug.

**Solutions**:
1. Check `leaderboard_screen.gd` line 3:
   ```gdscript
   const LEADERBOARD_SLUG = "test-leaderboard"
   ```
2. Create a leaderboard in your dashboard with this exact slug
3. Or change the slug to match your leaderboard
4. Restart the game

### Score Not Submitting

**Problem**: Not authenticated or score is 0.

**Solutions**:
1. Make sure you're logged in
2. Score must be greater than 0
3. Check console for error messages
4. Verify leaderboard exists in dashboard

### Friend Leaderboard Empty

**Problem**: No friends or friends haven't submitted scores.

**Solutions**:
1. Add some friends first
2. Have friends submit scores
3. Make sure you're on the "Friends" tab
4. Refresh the leaderboard

## 👥 Friends Issues

### Search Returns No Results

**Problem**: Player doesn't exist or wrong search term.

**Solutions**:
1. Try exact username (case-sensitive)
2. Try player ID instead
3. Make sure the player exists and is registered
4. Check that you're logged in

### Can't Add Friend

**Problem**: Already friends, blocked, or pending request.

**Solutions**:
1. Check relationship status in search results
2. If "Request sent", wait for them to accept
3. If "Already friends", check Friends tab
4. If "Blocked", unblock them first

### Pending Requests Not Showing

**Problem**: No pending requests or not refreshed.

**Solutions**:
1. Click "🔄 Refresh Pending Requests"
2. Make sure someone sent you a request
3. Check console for errors
4. Try logging out and back in

### Can't Remove Friend

**Problem**: Network error or not actually friends.

**Solutions**:
1. Refresh friends list first
2. Check console for error messages
3. Make sure you're logged in
4. Try again after a few seconds

## 🏅 Achievement Issues

### No Achievements Showing

**Problem**: No achievements created in dashboard.

**Solution**:
1. This is normal! Achievements are optional
2. Create achievements in your dashboard:
   - Go to dashboard → Achievements
   - Create achievement with ID: `first_clicks`
   - Create achievement with ID: `click_master`
   - Create achievement with ID: `click_progress` (type: Progress)
3. Refresh the achievements screen

### Achievements Not Unlocking

**Problem**: Achievement doesn't exist or wrong ID.

**Solutions**:
1. Check achievement IDs in dashboard match code
2. In `game_screen.gd`, check lines 60-65:
   ```gdscript
   if click_count == 10:
       GodotBaaS.grant_achievement("first_clicks")
   ```
3. Make sure achievement exists with exact ID
4. Check console for "achievement not found" errors
5. Try creating the achievement in dashboard

### Progress Not Updating

**Problem**: Achievement isn't a progress type.

**Solutions**:
1. Make sure achievement type is "Progress" in dashboard
2. Set a target value (e.g., 1000)
3. Check console for errors
4. Refresh achievements screen

## 🎮 Game Issues

### Clicks Not Registering

**Problem**: Button not responding or script error.

**Solutions**:
1. Check console for script errors
2. Make sure you're on the game screen
3. Try clicking different parts of the button
4. Restart the game

### Score Not Increasing

**Problem**: Script error or not clicking button.

**Solutions**:
1. Check console for errors
2. Make sure you're clicking the "CLICK ME!" button
3. Watch the score label at the top
4. Try resetting the game

### Coins Not Adding

**Problem**: Similar to score issue.

**Solutions**:
1. Check console for errors
2. Each click should add 1 coin
3. Watch the coins label at the top
4. Try resetting the game

## 🌐 Network Issues

### "Network error" Messages

**Problem**: No internet or server down.

**Solutions**:
1. Check your internet connection
2. Try accessing dashboard.godotbaas.com in browser
3. Wait a few minutes and try again
4. Check console for specific error code

### "Request timeout" Error

**Problem**: Slow connection or server overload.

**Solutions**:
1. Check your internet speed
2. Try again after a few seconds
3. Increase timeout in `godot_baas_client.gd` if needed
4. Check if other apps can access internet

### "Cannot connect to server"

**Problem**: Wrong base URL or server down.

**Solutions**:
1. Check `game_manager.gd` line 9:
   ```gdscript
   const BASE_URL = "https://api.godotbaas.com"
   ```
2. Make sure URL is correct (no trailing slash)
3. Try accessing URL in browser
4. Check dashboard status page

## 🎨 UI Issues

### Text Cut Off or Overlapping

**Problem**: Window too small or UI scaling issue.

**Solutions**:
1. Resize the game window
2. Check Project Settings → Display → Window
3. Adjust minimum window size
4. Some text uses autowrap - might need larger window

### Buttons Not Clickable

**Problem**: UI layer issue or button disabled.

**Solutions**:
1. Check if button is grayed out (disabled)
2. Make sure you're logged in (some buttons require auth)
3. Try clicking different parts of the button
4. Check console for errors

### Lists Not Scrolling

**Problem**: Not enough content or scroll container issue.

**Solutions**:
1. Add more items to the list
2. Make sure ScrollContainer is configured correctly
3. Try mouse wheel or drag scrollbar
4. Check if content exceeds container height

## 🔍 Debugging Tips

### Enable Verbose Logging

Add this to `game_manager.gd` `_ready()`:
```gdscript
GodotBaaS.enable_debug_logging = true  # If this property exists
```

### Check Console Output

1. Run game from editor (F5)
2. Watch the Output panel at bottom
3. Look for `[GodotBaaS]` or `[GameManager]` messages
4. Red text = errors, yellow = warnings

### Test in Isolation

1. Test one feature at a time
2. Start with authentication
3. Then try cloud saves
4. Then leaderboards, etc.

### Verify Dashboard Setup

1. Login to dashboard
2. Check your project exists
3. Verify API key is active
4. Check leaderboards/achievements are created

## 📱 Platform-Specific Issues

### Windows

- Make sure Windows Defender isn't blocking network access
- Check firewall settings
- Try running as administrator if file access fails

### macOS

- Grant network permissions if prompted
- Check System Preferences → Security & Privacy
- Try running from Applications folder

### Linux

- Check file permissions on project directory
- Verify network access isn't blocked
- Try running from terminal to see errors

### Web (HTML5)

- CORS might block API requests
- Use development API key for testing
- Check browser console for errors
- Some features might not work in browser

## 🆘 Still Having Issues?

### Gather Information

1. Godot version: `Help → About`
2. Operating system and version
3. Console error messages (copy full text)
4. Steps to reproduce the issue
5. Screenshots if relevant

### Get Help

1. **Documentation**: [godotbaas.com/docs](https://godotbaas.com/docs)
2. **Dashboard Support**: Check dashboard for support options
3. **GitHub Issues**: [github.com/GarretteAllen/godot-baas-plugin/issues](https://github.com/GarretteAllen/godot-baas-plugin/issues)
4. **Community**: Check if others have the same issue

### Report a Bug

When reporting issues, include:
- Godot version
- Operating system
- Plugin version
- Steps to reproduce
- Error messages from console
- Expected vs actual behavior

---

**Most issues are quick fixes! Don't give up! 💪**
