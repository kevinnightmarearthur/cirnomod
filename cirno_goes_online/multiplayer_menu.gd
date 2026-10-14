extends Base_menu_with_transitions


func _ready() -> void:
	super._ready()
	back_button = %ButtonBack
	for button: Button in %Buttons.get_children():
		button.focus_entered.connect(func(): %SelectGraphic.target_y = button.global_position.y)
		button.mouse_entered.connect(button.grab_focus)
	%ButtonHost.pressed.connect(_on_host_pressed)
	%ButtonPlay.pressed.connect(_on_play_pressed)
	%ButtonInvite.pressed.connect(Online.invite_friends)
	%ButtonLeave.pressed.connect(Online.leave)
	%ButtonBack.pressed.connect(_on_back_pressed)
	Online.lobby_changed.connect(_refresh)
	Online.lobby_error.connect(_on_lobby_error)
	_refresh()


func _refresh() -> void:
	var in_lobby = Online.in_lobby()
	%ButtonHost.visible = SteamManager.STEAM_ENABLED and not in_lobby
	%ButtonHost.disabled = false
	%ButtonPlay.visible = in_lobby
	%ButtonInvite.visible = in_lobby
	%ButtonLeave.visible = in_lobby
	# play disables everything, turn leave back on in case it gets stuck
	%ButtonPlay.disabled = Online.waiting_for_world
	%ButtonBack.disabled = Online.waiting_for_world
	%ButtonInvite.disabled = false
	%ButtonLeave.disabled = false

	if not SteamManager.STEAM_ENABLED:
		%StatusLabel.text = "STEAM ISN'T RUNNING"
	elif not in_lobby:
		%StatusLabel.text = "PRESS HOST TO MAKE A LOBBY, OR STAY HERE AND WAIT TILL YOUR FRIEND SENDS INVITE IN CHAT"
	elif Online.waiting_for_world:
		%StatusLabel.text = "HOLD ON CHIEF"
	elif Online.is_host():
		%StatusLabel.text = "YOU ARE HOSTING"
	else:
		%StatusLabel.text = ("IN %s'S LOBBY" % Online.player_name(Steam.getLobbyOwner(Online.lobby_id))).to_upper()

	%PlayerList.text = ""
	if in_lobby:
		var names = PackedStringArray()
		for id in Online.members():
			names.append(Online.player_name(id))
		%PlayerList.text = "WUNKS (%d/%d)\n%s" % [names.size(), Online.MAX_PLAYERS, ", ".join(names)]

	# focus got hidden, move it
	var focused = get_viewport().gui_get_focus_owner()
	if focused == null or not focused.visible:
		for button: Button in %Buttons.get_children():
			if button.visible:
				button.grab_focus.call_deferred()
				break


func _on_lobby_error(message: String) -> void:
	_refresh()
	%StatusLabel.text = message.to_upper()


func _on_host_pressed() -> void:
	%ButtonHost.disabled = true
	%StatusLabel.text = "CREATING LOBBY..."
	Online.host()


func _on_play_pressed() -> void:
	for button: Button in %Buttons.get_children():
		button.disabled = true
	Globals.AUDIO_MANAGER.create_audio(SoundEffect.SOUND_EFFECT_TYPE.UI_START_GAME)
	Online.play()


func _on_back_pressed() -> void:
	if not transition_tween:
		_create_transition_tween(true, _switch_to_title)


func _switch_to_title() -> void:
	Globals.MENU_NODE.add_child(load("res://scenes/UI/menus/title_menu.tscn").instantiate())
	queue_free()
