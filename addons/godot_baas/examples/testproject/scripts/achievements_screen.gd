extends Control

@onready var unlocked_label: Label = $MarginContainer/VBoxContainer/StatsPanel/MarginContainer/HBoxContainer/UnlockedLabel
@onready var points_label: Label = $MarginContainer/VBoxContainer/StatsPanel/MarginContainer/HBoxContainer/PointsLabel
@onready var achievements_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/AchievementsList

func _ready() -> void:
	# Connect to GodotBaaS signals
	GodotBaaS.achievements_loaded.connect(_on_achievements_loaded)
	GodotBaaS.achievement_unlocked.connect(_on_achievement_unlocked)
	GodotBaaS.error.connect(_on_error)
	
	# Load achievements on start
	_load_achievements()

func _load_achievements() -> void:
	_clear_list()
	_add_loading_label()
	GodotBaaS.get_achievements(false)

func _clear_list() -> void:
	for child in achievements_list.get_children():
		child.queue_free()

func _add_loading_label() -> void:
	var label = Label.new()
	label.text = "⏳ Loading achievements..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	achievements_list.add_child(label)

func _create_achievement_panel(achievement: Dictionary) -> PanelContainer:
	var is_unlocked = achievement.get("isUnlocked", false)
	var has_progress = achievement.get("hasProgress", false)
	
	var panel = PanelContainer.new()
	
	# Style based on unlock status
	if is_unlocked:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.4, 0.2, 0.3)
		panel.add_theme_stylebox_override("panel", style)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	# Title row
	var title_hbox = HBoxContainer.new()
	vbox.add_child(title_hbox)
	
	var icon = "🔓" if is_unlocked else "🔒"
	var title_label = Label.new()
	title_label.text = icon + " " + achievement.get("name", "Unknown")
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_label)
	
	var points_label = Label.new()
	points_label.text = str(achievement.get("points", 0)) + " pts"
	points_label.add_theme_font_size_override("font_size", 16)
	points_label.add_theme_color_override("font_color", Color.GOLD)
	title_hbox.add_child(points_label)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = achievement.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)
	
	# Progress bar (if applicable)
	if has_progress:
		var progress = achievement.get("progress", 0)
		var target = achievement.get("targetValue", 100)
		
		var progress_hbox = HBoxContainer.new()
		progress_hbox.add_theme_constant_override("separation", 10)
		vbox.add_child(progress_hbox)
		
		var progress_bar = ProgressBar.new()
		progress_bar.min_value = 0
		progress_bar.max_value = target
		progress_bar.value = progress
		progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress_bar.custom_minimum_size = Vector2(0, 25)
		progress_hbox.add_child(progress_bar)
		
		var progress_label = Label.new()
		progress_label.text = str(progress) + "/" + str(target)
		progress_hbox.add_child(progress_label)
	
	# Rarity badge
	var rarity = achievement.get("rarity", "COMMON")
	var rarity_label = Label.new()
	rarity_label.text = rarity
	rarity_label.add_theme_font_size_override("font_size", 12)
	match rarity:
		"COMMON":
			rarity_label.add_theme_color_override("font_color", Color.GRAY)
		"RARE":
			rarity_label.add_theme_color_override("font_color", Color.DODGER_BLUE)
		"EPIC":
			rarity_label.add_theme_color_override("font_color", Color.PURPLE)
		"LEGENDARY":
			rarity_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(rarity_label)
	
	return panel

func _on_achievements_loaded(achievements: Array) -> void:
	_clear_list()
	
	if achievements.is_empty():
		var label = Label.new()
		label.text = "No achievements configured.\nCreate achievements in your dashboard!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		achievements_list.add_child(label)
		return
	
	# Calculate stats
	var unlocked_count = 0
	var total_points = 0
	
	for achievement in achievements:
		if achievement.get("isUnlocked", false):
			unlocked_count += 1
			total_points += achievement.get("points", 0)
		
		var panel = _create_achievement_panel(achievement)
		achievements_list.add_child(panel)
	
	# Update stats
	unlocked_label.text = "Unlocked: " + str(unlocked_count) + "/" + str(achievements.size())
	points_label.text = "Total Points: " + str(total_points)

func _on_achievement_unlocked(achievement: Dictionary) -> void:
	print("[Achievements] Achievement unlocked: ", achievement.get("name", "Unknown"))
	# Refresh list to show new unlock
	_load_achievements()

func _on_error(error_message: String) -> void:
	push_error("[Achievements] Error: " + error_message)

func _on_refresh_pressed() -> void:
	_load_achievements()

func _on_back_pressed() -> void:
	GameManager.change_scene("res://scenes/main_menu.tscn")
