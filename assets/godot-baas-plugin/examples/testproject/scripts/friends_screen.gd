extends Control

@onready var search_input: LineEdit = $MarginContainer/VBoxContainer/SearchPanel/MarginContainer/HBoxContainer/SearchInput
@onready var friends_list: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/Friends/ScrollContainer/FriendsList
@onready var pending_list: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/Pending/ScrollContainer/PendingList
@onready var search_list: VBoxContainer = $MarginContainer/VBoxContainer/TabContainer/Search/ScrollContainer/SearchList
@onready var tab_container: TabContainer = $MarginContainer/VBoxContainer/TabContainer

func _ready() -> void:
	# Connect to GodotBaaS signals
	GodotBaaS.friends_loaded.connect(_on_friends_loaded)
	GodotBaaS.pending_requests_loaded.connect(_on_pending_requests_loaded)
	GodotBaaS.players_found.connect(_on_players_found)
	GodotBaaS.friend_request_sent.connect(_on_friend_request_sent)
	GodotBaaS.friend_request_accepted.connect(_on_friend_request_accepted)
	GodotBaaS.friend_request_declined.connect(_on_friend_request_declined)
	GodotBaaS.friend_removed.connect(_on_friend_removed)
	GodotBaaS.error.connect(_on_error)
	
	# Connect to tab change signal
	tab_container.tab_changed.connect(_on_tab_changed)
	
	# Load friends on start
	_load_friends()

func _load_friends() -> void:
	_clear_list(friends_list)
	_add_loading_label(friends_list)
	GodotBaaS.get_friends()

func _load_pending() -> void:
	_clear_list(pending_list)
	_add_loading_label(pending_list)
	GodotBaaS.get_pending_requests()

func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()

func _add_loading_label(list: VBoxContainer) -> void:
	var label = Label.new()
	label.text = "⏳ Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(label)

func _create_friend_panel(friend_data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	margin.add_child(hbox)
	
	# Username
	var name_label = Label.new()
	name_label.text = friend_data.get("username", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_label)
	
	# Remove button
	var remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func(): _remove_friend(friend_data.get("id", "")))
	hbox.add_child(remove_btn)
	
	return panel

func _create_pending_panel(request_data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	margin.add_child(hbox)
	
	# Username
	var requester = request_data.get("requester", {})
	var name_label = Label.new()
	name_label.text = requester.get("username", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_label)
	
	# Accept button
	var accept_btn = Button.new()
	accept_btn.text = "✓ Accept"
	var friendship_id = request_data.get("id", "")
	accept_btn.pressed.connect(func(): GodotBaaS.accept_friend_request(friendship_id))
	hbox.add_child(accept_btn)
	
	# Decline button
	var decline_btn = Button.new()
	decline_btn.text = "✗ Decline"
	decline_btn.pressed.connect(func(): GodotBaaS.decline_friend_request(friendship_id))
	hbox.add_child(decline_btn)
	
	return panel

func _create_search_result_panel(player_data: Dictionary) -> PanelContainer:
	var panel = PanelContainer.new()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	margin.add_child(hbox)
	
	# Username
	var name_label = Label.new()
	name_label.text = player_data.get("username", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_label)
	
	# Status/Action
	var relationship = player_data.get("relationshipStatus", "none")
	match relationship:
		"friend":
			var label = Label.new()
			label.text = "✓ Already friends"
			label.add_theme_color_override("font_color", Color.GREEN)
			hbox.add_child(label)
		"pending_sent":
			var label = Label.new()
			label.text = "⏳ Request sent"
			label.add_theme_color_override("font_color", Color.ORANGE)
			hbox.add_child(label)
		"pending_received":
			var label = Label.new()
			label.text = "Accept in Pending tab"
			label.add_theme_color_override("font_color", Color.CYAN)
			hbox.add_child(label)
		"blocked":
			var label = Label.new()
			label.text = "🚫 Blocked"
			label.add_theme_color_override("font_color", Color.RED)
			hbox.add_child(label)
		_:
			var add_btn = Button.new()
			add_btn.text = "+ Add Friend"
			var player_id = player_data.get("id", "")
			add_btn.pressed.connect(func(): GodotBaaS.send_friend_request(player_id))
			hbox.add_child(add_btn)
	
	return panel

func _remove_friend(friend_id: String) -> void:
	GodotBaaS.remove_friend(friend_id)

func _on_friends_loaded(friends: Array, _count: int) -> void:
	_clear_list(friends_list)
	
	if friends.is_empty():
		var label = Label.new()
		label.text = "No friends yet. Search for players to add!"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		friends_list.add_child(label)
		return
	
	for friend in friends:
		var panel = _create_friend_panel(friend)
		friends_list.add_child(panel)

func _on_pending_requests_loaded(requests: Array) -> void:
	_clear_list(pending_list)
	
	if requests.is_empty():
		var label = Label.new()
		label.text = "No pending friend requests"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pending_list.add_child(label)
		return
	
	for request in requests:
		var panel = _create_pending_panel(request)
		pending_list.add_child(panel)

func _on_players_found(players: Array) -> void:
	_clear_list(search_list)
	
	# Switch to search tab
	tab_container.current_tab = 2
	
	if players.is_empty():
		var label = Label.new()
		label.text = "No players found"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		search_list.add_child(label)
		return
	
	for player in players:
		var panel = _create_search_result_panel(player)
		search_list.add_child(panel)

func _on_friend_request_sent(_friendship: Dictionary) -> void:
	print("[Friends] Friend request sent!")
	# Refresh search to update status
	if search_input.text != "":
		GodotBaaS.search_players(search_input.text)

func _on_friend_request_accepted(_friend: Dictionary) -> void:
	print("[Friends] Friend request accepted!")
	_load_friends()
	_load_pending()

func _on_friend_request_declined() -> void:
	print("[Friends] Friend request declined")
	_load_pending()

func _on_friend_removed() -> void:
	print("[Friends] Friend removed")
	_load_friends()

func _on_error(error_message: String) -> void:
	push_error("[Friends] Error: " + error_message)

func _on_search_pressed() -> void:
	var query = search_input.text.strip_edges()
	if query == "":
		return
	
	_clear_list(search_list)
	_add_loading_label(search_list)
	tab_container.current_tab = 2
	
	GodotBaaS.search_players(query)

func _on_refresh_friends_pressed() -> void:
	_load_friends()

func _on_refresh_pending_pressed() -> void:
	_load_pending()

func _on_tab_changed(tab: int) -> void:
	# Auto-load data when switching tabs
	match tab:
		0:  # Friends tab
			_load_friends()
		1:  # Pending tab
			_load_pending()
		2:  # Search tab
			pass  # Search is manual

func _on_back_pressed() -> void:
	GameManager.change_scene("res://scenes/main_menu.tscn")
