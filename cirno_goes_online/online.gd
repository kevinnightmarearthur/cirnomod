extends Node

# steam lobby co-op stuff

signal lobby_changed
signal lobby_error(message: String)

const MOD_VERSION := "3.0.0"
const MAX_PLAYERS := 8
const SEND_RATE = 30.0
const SILENCE_TIMEOUT_MS = 3000 # menus, loading, or they left
const SETTINGS_PATH := "user://cirno_goes_online.cfg"
const BUMP_RANGE = 0.6 # cirnos hitbox is 0.6 wide and 1.5 tall
const BUMP_PUSH = 8.0

const STATE_CHANNEL := 0
const EVENT_CHANNEL := 1

const OWN_COLOR := Color(0.55, 0.85, 1.0)
const OTHER_PLAYER_COLORS = [
	Color(0.6, 1.0, 0.65),
	Color(1.0, 0.95, 0.55),
	Color(0.85, 0.7, 1.0),
	Color(1.0, 0.6, 0.7),
	Color(0.6, 1.0, 1.0),
	Color(1.0, 0.8, 0.5),
	Color(0.8, 0.9, 0.5),
	Color(0.9, 0.9, 0.9),
]
const SHARED_PROGRESS_KEYS = [
	"items_collected", "counter_power_items_collected", "counter_score_items_collected",
	"counter_special_items_collected", "frogs_collected",
]

const RemoteCirnoScene := preload("res://cirno_goes_online/remote_cirno.tscn")
const NameTagScene := preload("res://cirno_goes_online/name_tag.tscn")
const MultiplayerMenuScene := preload("res://cirno_goes_online/multiplayer_menu.tscn")
const ChatScene := preload("res://cirno_goes_online/chat.tscn")
const MenuPatches := preload("res://cirno_goes_online/menu_patches.gd")
const CirnoColors := preload("res://cirno_goes_online/cirno_colors.gd")
const PLAYER_SCENE := "res://scenes/player/player/player.tscn"

var lobby_id := 0
var remote_cirnos := {}  # steam id -> their cirno
var waiting_for_world := false

var nickname := ""
var show_name_tags := true
var cirno_colors := CirnoColors.default_colors()

var _send_cooldown = 0.0
var _own_tag: Node3D
var _chat: Control
var _host_id = 0
var _known_names = {}
var _playing_online = false
var _lobby_to_join = 0
var _world_source = 0
var _pickups_sent = 0
var _remote_pickups = {} # so we dont send their pickups back to them
var _items_by_id = {}
var _frogs_sent = 0
var _remote_frogs = {}
var _colors = {}
var _controls_locked := false
var _flying_items = {} # item -> the cirno it flies to
var _bump_cooldown = 0.0
var _bump_sound: AudioStreamPlayer
var _head_jump_sound: AudioStreamPlayer
var _remote_ice_platforms = {} # steam id -> their ice platform
var _sent_ice_platform: Node3D
var _sent_ice_message = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100 # after the items, so other peoples pickups fly to them
	_load_settings()
	# the game only saves keys for actions in this list
	input_menu.input_actions["CHAT"] = "CHAT"
	add_child(MenuPatches.new())
	get_tree().node_added.connect(_on_node_added)
	_bump_sound = _make_sound("bump.mp3")
	_head_jump_sound = _make_sound("headjump.mp3")
	# wait for the main scene, a steam invite opens the lobby menu straight away
	_connect_steam.call_deferred()


# our mp3s arent imported like game sounds so we load it via file
func _make_sound(file_name: String) -> AudioStreamPlayer:
	var sound = AudioStreamPlayer.new()
	sound.stream = AudioStreamMP3.load_from_file("res://cirno_goes_online/" + file_name)
	sound.bus = "SoundEffects" # so the sfx volume slider works on it
	add_child(sound)
	return sound


func _connect_steam() -> void:
	if not SteamManager.STEAM_ENABLED:
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.join_requested.connect(_on_join_requested)
	Steam.network_messages_session_request.connect(_on_session_request)
	GlobalEventBus.game_state_changed.connect(_on_game_state_changed)

	# opened from a steam invite
	var args = OS.get_cmdline_args()
	var i = args.find("+connect_lobby")
	if i != -1 and i + 1 < args.size():
		join(int(args[i + 1]))


func in_lobby() -> bool:
	return lobby_id != 0


func is_host() -> bool:
	return in_lobby() and Steam.getLobbyOwner(lobby_id) == SteamManager.STEAM_USER_ID


func members() -> Array[int]:
	var ids: Array[int] = []
	for i in Steam.getNumLobbyMembers(lobby_id):
		ids.append(Steam.getLobbyMemberByIndex(lobby_id, i))
	return ids


func player_name(id: int) -> String:
	var n: String = Steam.getLobbyMemberData(lobby_id, id, "name")
	if n != "":
		_known_names[id] = n # for the "left the game" message
	return _known_names.get(id, Steam.getFriendPersonaName(id))


func player_color(id: int) -> Color:
	if id == SteamManager.STEAM_USER_ID:
		return OWN_COLOR
	if not _colors.has(id):
		for c in OTHER_PLAYER_COLORS:
			if not c in _colors.values():
				_colors[id] = c
				break
	return _colors[id]


func own_name() -> String:
	if nickname != "" or not SteamManager.STEAM_ENABLED:
		return nickname
	return Steam.getPersonaName()


func host() -> void:
	leave()
	Steam.createLobby(Steam.LOBBY_TYPE_FRIENDS_ONLY, MAX_PLAYERS)


func join(id: int) -> void:
	if Globals.CURRENT_GAME_STATE != Globals.GAME_STATE.MAIN_MENU:
		_lobby_to_join = id
		SaveFileManager.level_state_save()
		Globals.MAIN_NODE.switch_to_main_menu()
		return
	leave()
	Steam.joinLobby(id)


func leave() -> void:
	if not in_lobby():
		return
	for id in members():
		if id != SteamManager.STEAM_USER_ID:
			Steam.closeSessionWithUser(id)
	Steam.leaveLobby(lobby_id)
	lobby_id = 0
	waiting_for_world = false
	Steam.setRichPresence("connect", "")
	for id in remote_cirnos.keys():
		_remove_remote_cirno(id)
	_colors.clear()
	if is_instance_valid(_chat):
		_chat.queue_free()
	if _playing_online:
		_use_single_player_save()
	lobby_changed.emit()


func invite_friends() -> void:
	Steam.activateGameOverlayInviteDialog(lobby_id)


func send_chat(text: String) -> void:
	_send_to_others(EVENT_CHANNEL, {"chat": text})
	_chat.add_message(own_name(), player_color(SteamManager.STEAM_USER_ID), text)


func play() -> void:
	_world_source = 0
	for id in members():
		if id != SteamManager.STEAM_USER_ID and Steam.getLobbyMemberData(lobby_id, id, "in_game") == "1":
			_world_source = id
			break
	if _world_source == 0:
		_start_online_game({})
	else:
		waiting_for_world = true
		_send(_world_source, EVENT_CHANNEL, {"world_request": true})
		lobby_changed.emit()


func set_nickname(new_nickname: String) -> void:
	nickname = new_nickname.strip_edges()
	_settings_changed()


func set_show_name_tags(shown: bool) -> void:
	show_name_tags = shown
	_settings_changed()


# the game doesnt really pause online so cirno has to be locked in the pause menu, and while typing in chat
func update_player_controls() -> void:
	var player = Globals.PLAYER
	if !is_instance_valid(player):
		return
	var locked = Globals.CURRENT_GAME_STATE == Globals.GAME_STATE.PAUSE_MENU or (is_instance_valid(_chat) and _chat.typing)
	if locked:
		player.disable_input = true
	elif _controls_locked:
		player.disable_input = false # only unlock if we locked it, the ending turns input off too
	_controls_locked = locked
	player.get_node("CameraFollowPosition/CameraPivot").set_process(not locked)


func _settings_changed() -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("player", "nickname", nickname)
	cfg.set_value("player", "show_name_tags", show_name_tags)
	for region in cirno_colors:
		cfg.set_value("colors", region, cirno_colors[region])
	var err = cfg.save(SETTINGS_PATH)
	if err != OK:
		push_error("Cirno Goes Online: couldn't save settings, error " + str(err))
	if in_lobby():
		Steam.setLobbyMemberData(lobby_id, "name", own_name())
		_update_name_tags()


func _load_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		nickname = cfg.get_value("player", "nickname", "")
		show_name_tags = cfg.get_value("player", "show_name_tags", true)
		for region in cirno_colors:
			cirno_colors[region] = cfg.get_value("colors", region, cirno_colors[region])


func _on_node_added(node: Node) -> void:
	if node.scene_file_path == PLAYER_SCENE:
		node.ready.connect(_recolor_own_cirno.bind(node), CONNECT_ONE_SHOT)


func _recolor_own_cirno(player: Node) -> void:
	CirnoColors.apply(player.get_node("%Skin/Armature/Skeleton3D"), cirno_colors)


func _update_name_tags() -> void:
	for id in remote_cirnos:
		var remote_cirno = remote_cirnos[id]
		if is_instance_valid(remote_cirno):
			remote_cirno.name_tag.show_player(player_name(id), player_color(id))

	# your own tag only shows when someone else is here
	var show_own = not remote_cirnos.is_empty() and is_instance_valid(Globals.PLAYER)
	if show_own and not is_instance_valid(_own_tag):
		_own_tag = NameTagScene.instantiate()
		Globals.PLAYER.add_child(_own_tag)
	if is_instance_valid(_own_tag):
		_own_tag.show_player(own_name(), player_color(SteamManager.STEAM_USER_ID))
		_own_tag.visible = show_own and show_name_tags


func _start_online_game(world: Dictionary) -> void:
	waiting_for_world = false
	if not _playing_online:
		_playing_online = true
		OnlineStartup.move_single_player_save()
	SaveFileManager.delete_level_state()
	for key in SHARED_PROGRESS_KEYS:
		if world.has(key):
			SaveFileManager.LEVEL_SAVE_CONTENT[key] = world[key]
	Globals.MAIN_NODE.reset_game_variables()
	Globals.MAIN_NODE.game_power = world.get("power", 0.0)
	Globals.MAIN_NODE.game_score = world.get("score", 0.0)
	_pickups_sent = SaveFileManager.LEVEL_SAVE_CONTENT.items_collected.size()
	_remote_pickups.clear()
	_frogs_sent = SaveFileManager.LEVEL_SAVE_CONTENT.frogs_collected.size()
	_remote_frogs.clear()
	Globals.MAIN_NODE.on_start_game()


func _use_single_player_save() -> void:
	_playing_online = false
	OnlineStartup.restore_single_player_save()
	SaveFileManager.LEVEL_SAVE_CONTENT = SaveFileManager.LEVEL_SAVE_DEFAULTS.duplicate(true)
	SaveFileManager.PREVIOUS_LEVEL_SAVE_EXISTS = false
	SaveFileManager.level_state_load()
	# game only loads these on startup
	Globals.MAIN_NODE.reset_game_variables()
	Globals.MAIN_NODE.game_power = SaveFileManager.LEVEL_SAVE_CONTENT.power
	Globals.MAIN_NODE.game_score = SaveFileManager.LEVEL_SAVE_CONTENT.score


func _shared_world() -> Dictionary:
	var world = {"power": Globals.MAIN_NODE.game_power, "score": Globals.MAIN_NODE.game_score + Globals.MAIN_NODE.game_score_to_add}
	for key in SHARED_PROGRESS_KEYS:
		world[key] = SaveFileManager.LEVEL_SAVE_CONTENT[key]
	return world


func _on_lobby_created(result: int, id: int) -> void:
	if result != Steam.RESULT_OK:
		lobby_error.emit("Couldn't create a lobby (Steam result %d)" % result)
		return
	Steam.setLobbyData(id, "cirno_goes_online_version", MOD_VERSION)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_error.emit("Couldn't join the lobby (Steam response %d)" % response)
		return
	lobby_id = id
	_host_id = Steam.getLobbyOwner(id)
	_show_multiplayer_menu() # before the version check so the error has somewhere to show

	if not is_host() and Steam.getLobbyData(id, "cirno_goes_online_version") != MOD_VERSION:
		leave()
		lobby_error.emit("your thingy is outdated, there's a new build out probably.")
		return

	Steam.setRichPresence("connect", "+connect_lobby %d" % id)
	Steam.setLobbyMemberData(id, "name", own_name())
	lobby_changed.emit()


func _on_lobby_chat_update(id: int, changed_id: int, _making_change_id: int, chat_state: int) -> void:
	if id != lobby_id:
		return
	var joined = chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED
	if not joined and changed_id == _host_id:
		_on_host_left()
		return
	if is_instance_valid(_chat):
		_chat.add_system_message("%s %s the game." % [player_name(changed_id), "joined" if joined else "left"])
	if not joined:
		Steam.closeSessionWithUser(changed_id)
		_remove_remote_cirno(changed_id)
		_colors.erase(changed_id)
		if waiting_for_world and changed_id == _world_source:
			play()
	_update_name_tags()
	lobby_changed.emit()


func _on_host_left() -> void:
	if Globals.CURRENT_GAME_STATE == Globals.GAME_STATE.MAIN_MENU:
		leave()
	else:
		SaveFileManager.level_state_save()
		Globals.MAIN_NODE.switch_to_main_menu()


func _on_lobby_data_update(_success: bool, id: int, _member_id: int) -> void:
	if id == lobby_id:
		_update_name_tags()
		lobby_changed.emit()


func _on_join_requested(id: int, _friend_id: int) -> void:
	join(id)


func _on_session_request(remote_id: int) -> void:
	if in_lobby() and remote_id in members():
		Steam.acceptSessionWithUser(remote_id)


func _on_game_state_changed(new_state: Globals.GAME_STATE) -> void:
	if new_state == Globals.GAME_STATE.MAIN_MENU:
		leave()
		if _lobby_to_join != 0:
			Steam.joinLobby(_lobby_to_join)
			_lobby_to_join = 0
	elif in_lobby():
		if not _playing_online:
			leave() # started a normal game from the title screen
		else:
			Steam.setLobbyMemberData(lobby_id, "in_game", "1")
			if not is_instance_valid(_chat):
				_chat = ChatScene.instantiate()
				Globals.GAME_HUD_NODE.add_child(_chat)
			if new_state == Globals.GAME_STATE.PAUSE_MENU:
				# everyone else is still playing so dont freeze the game. has to be deferred or the pause menu gets weird
				get_tree().set_deferred("paused", false)
			update_player_controls()


func _show_multiplayer_menu() -> void:
	for menu in Globals.MENU_NODE.get_children():
		if menu.scene_file_path == MultiplayerMenuScene.resource_path:
			return
		menu.queue_free()
	Globals.MENU_NODE.add_child(MultiplayerMenuScene.instantiate())


# for testing purposes
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_KP_7:
		if is_host() and Globals.CURRENT_GAME_STATE == Globals.GAME_STATE.IN_GAME:
			Globals.MAIN_NODE.game_power = 4.0
			Globals.PLAYER._determine_max_energy() # unlocks the abilities like picking up power does


func _physics_process(delta: float) -> void:
	if not in_lobby():
		return
	_receive_events()
	_receive_states()
	if Globals.CURRENT_GAME_STATE != Globals.GAME_STATE.MAIN_MENU and is_instance_valid(Globals.PLAYER):
		_send_new_pickups()
		_send_new_frogs()
		_send_ice_platform()
		_check_bumps(delta)
		_send_cooldown -= delta
		if _send_cooldown <= 0.0:
			_send_cooldown = 1.0 / SEND_RATE
			_send_state()
	_remove_silent_cirnos()
	_move_flying_items()


# the item code moves picked up items onto our cirno every frame, this moves them over to whoever got it
func _move_flying_items() -> void:
	for item in _flying_items.keys():
		var target = _flying_items[item]
		if not is_instance_valid(item) or not is_instance_valid(target):
			_flying_items.erase(item)
		else:
			item.global_position = target.global_position


# other cirnos have no collision so we check against them
func _check_bumps(delta: float) -> void:
	_bump_cooldown -= delta
	var player = Globals.PLAYER
	for id in remote_cirnos:
		var other = remote_cirnos[id]
		if not is_instance_valid(other):
			continue
		var offset = player.global_position - other.global_position
		var height = offset.y
		offset.y = 0.0
		if offset.length() > BUMP_RANGE:
			continue
		# landing on their head works like an extra jump
		if height > 0.75 and height < 1.7 and player.velocity.y <= 0.0 and not player.is_on_floor():
			player.set_state(PlayerStates.State.JUMPING)
			_head_jump_sound.play()
		elif abs(height) < 0.75 and _bump_cooldown <= 0.0:
			_bump_away_from(other)


func _bump_away_from(other: Node3D) -> void:
	var player = Globals.PLAYER
	var away = player.global_position - other.global_position
	away.y = 0.0
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.apply_impulse(away.normalized() * BUMP_PUSH)
	player._skin_parent.set_looney_curve(player.looney_bouncy_curve_0, 0.66, -0.5, "y") # same squish as bonking a wall
	_bump_sound.play()
	_bump_cooldown = 0.5


func _send(id: int, channel: int, message: Dictionary) -> void:
	var flags = Steam.NETWORKING_SEND_RELIABLE
	if channel == STATE_CHANNEL:
		flags = Steam.NETWORKING_SEND_UNRELIABLE
	Steam.sendMessageToUser(id, var_to_bytes(message), flags | Steam.NETWORKING_SEND_AUTORESTART_BROKEN_SESSION, channel)


func _send_to_others(channel: int, message: Dictionary) -> void:
	for id in members():
		if id != SteamManager.STEAM_USER_ID:
			_send(id, channel, message)


func _send_state() -> void:
	var skin: Node3D = Globals.PLAYER.get_node("%Skin")
	var anim: AnimationPlayer = skin.get_node("AnimationPlayer")
	_send_to_others(STATE_CHANNEL, {
		"position": skin.global_position,
		"rotation": skin.global_basis.get_rotation_quaternion(),
		"scale": skin.global_basis.get_scale(),
		"animation": anim.current_animation,
		"animation_speed": anim.speed_scale,
	})


# frog items are -1 so skip those, the frog itself gets sent
func _send_new_pickups() -> void:
	var collected: Array = SaveFileManager.LEVEL_SAVE_CONTENT.items_collected
	while _pickups_sent < collected.size():
		var id: int = collected[_pickups_sent]
		_pickups_sent += 1
		if id > 0 and not _remote_pickups.has(id):
			_send_to_others(EVENT_CHANNEL, {"pickup": id})


func _send_new_frogs() -> void:
	var collected: Array = SaveFileManager.LEVEL_SAVE_CONTENT.frogs_collected
	while _frogs_sent < collected.size():
		var frog_id: int = collected[_frogs_sent]
		_frogs_sent += 1
		if not _remote_frogs.has(frog_id):
			_send_to_others(EVENT_CHANNEL, {"frog": frog_id})


func _send_ice_platform() -> void:
	var platform = Globals.PLAYER.current_ice_platform
	if is_instance_valid(platform) and platform != _sent_ice_platform:
		platform.get_node("Geometry").suicide_available_time = INF # cant press special to delete it online, others would still see it
		_sent_ice_platform = platform
		_sent_ice_message = {
			"ice_platform": platform.global_position,
			"ice_look": Globals.PLAYER.ice_platforms.find(load(platform.scene_file_path)),
			"ice_turn": platform.get_node("Geometry").rotation.y,
		}
		_send_to_others(EVENT_CHANNEL, _sent_ice_message)


func _receive_events() -> void:
	for message in Steam.receiveMessagesOnChannel(EVENT_CHANNEL, 64):
		var sender: int = message["identity"]
		var data = bytes_to_var(message["payload"])
		if not data is Dictionary or not sender in members():
			continue
		if data.has("pickup"):
			_collect_for(sender, data.pickup)
		elif data.has("frog"):
			_open_frog(data.frog)
		elif data.has("ice_platform"):
			_place_ice_platform(sender, data)
		elif data.has("chat") and is_instance_valid(_chat):
			_chat.add_message(player_name(sender), player_color(sender), str(data.chat).left(140))
		elif data.has("world_request") and _playing_online:
			_send(sender, EVENT_CHANNEL, {"world": _shared_world()})
		elif data.has("world") and waiting_for_world:
			_start_online_game(data.world)


# goes through the normal pickup code so unlocks and sounds work
func _collect_for(collector_id: int, item_id: int) -> void:
	if not _playing_online or not is_instance_valid(Globals.PLAYER):
		return
	if item_id in SaveFileManager.LEVEL_SAVE_CONTENT.items_collected:
		return
	var item = _find_item(item_id)
	if item == null or item.collected:
		return
	_flying_items[item] = remote_cirnos.get(collector_id)
	_remote_pickups[item_id] = true
	Globals.PLAYER._on_item_collection_area_area_entered(item.get_node("%ItemCollectionRange"))


func _open_frog(frog_id: int) -> void:
	if not _playing_online or not is_instance_valid(Globals.PLAYER):
		return
	if frog_id in SaveFileManager.LEVEL_SAVE_CONTENT.frogs_collected:
		return
	for frog in get_tree().get_nodes_in_group("Frog"):
		if frog.item_id == frog_id and not frog.is_giving_items:
			_remote_frogs[frog_id] = true
			# fake looking at it long enough. set_status wakes it up if youre far away
			frog.set_status(true)
			frog.current_look_time = frog.look_time_req + 1.0
			return


func _place_ice_platform(owner_id: int, data: Dictionary) -> void:
	if not _playing_online or not is_instance_valid(Globals.PLAYER):
		return
	_remove_ice_platform(owner_id) # the game only keeps one ice platform per cirno
	var platform = Globals.PLAYER.ice_platforms[data.ice_look].instantiate()
	Globals.LEVEL_NODE.add_child(platform)
	platform.global_position = data.ice_platform
	var geometry = platform.get_node("Geometry")
	geometry.rotation.y = data.ice_turn # has to be after add_child or the game picks a random one
	geometry.suicide_available_time = INF # otherwise pressing special deletes it on our screen
	_remote_ice_platforms[owner_id] = platform
	if not data.has("ice_quiet"):
		Globals.AUDIO_MANAGER.create_audio(SoundEffect.SOUND_EFFECT_TYPE.ICE_PLATFORM, null, null, null, platform.global_position)


func _remove_ice_platform(owner_id: int) -> void:
	var platform = _remote_ice_platforms.get(owner_id)
	if is_instance_valid(platform):
		platform.get_node("Geometry").krill_yourself()
	_remote_ice_platforms.erase(owner_id)


func _find_item(item_id: int) -> Item:
	var item = _items_by_id.get(item_id)
	if is_instance_valid(item):
		return item
	# level gets rebuilt after the menu
	_items_by_id.clear()
	for node in Globals.LEVEL_NODE.find_children("*", "Node3D", true, false):
		if node is Item and node.item_id > 0:
			_items_by_id[node.item_id] = node
	return _items_by_id.get(item_id)


func _receive_states() -> void:
	var in_game = Globals.CURRENT_GAME_STATE != Globals.GAME_STATE.MAIN_MENU and is_instance_valid(Globals.LEVEL_NODE)
	for message in Steam.receiveMessagesOnChannel(STATE_CHANNEL, 64):
		var sender: int = message["identity"]
		var state = bytes_to_var(message["payload"])
		if not in_game or not state is Dictionary:
			continue
		var remote_cirno = remote_cirnos.get(sender)
		if not is_instance_valid(remote_cirno):
			if not sender in members():
				continue
			remote_cirno = RemoteCirnoScene.instantiate()
			Globals.LEVEL_NODE.add_child(remote_cirno)
			remote_cirnos[sender] = remote_cirno
			_update_name_tags()
			# they missed our ice platform if they just got here
			if is_instance_valid(_sent_ice_platform):
				_send(sender, EVENT_CHANNEL, _sent_ice_message.merged({"ice_quiet": true}))
		remote_cirno.apply_state(state)


func _remove_silent_cirnos() -> void:
	var now = Time.get_ticks_msec()
	for id in remote_cirnos.keys():
		var c = remote_cirnos[id]
		if not is_instance_valid(c) or now - c.last_heard_ms > SILENCE_TIMEOUT_MS:
			_remove_remote_cirno(id)


func _remove_remote_cirno(id: int) -> void:
	var remote_cirno = remote_cirnos.get(id)
	if is_instance_valid(remote_cirno):
		remote_cirno.queue_free()
	remote_cirnos.erase(id)
	_remove_ice_platform(id)
	_update_name_tags()
