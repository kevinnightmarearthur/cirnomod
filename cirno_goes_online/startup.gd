extends Node

# runs before the game loads its settings and save. dont use game scripts in here, loading them this early breaks the controller icons

# same file the game uses, the normal save gets moved out of the way while playing online
const LEVEL_SAVE := "user://levelsave.icecold"
const SINGLE_PLAYER_SAVE := "user://levelsave_singleplayer.icecold"


func _init() -> void:
	# the action has to exist before the game loads the saved controls or a changed chat key doesnt stick
	var chat_key = InputEventKey.new()
	chat_key.physical_keycode = KEY_T
	ProjectSettings.set_setting("input/CHAT", {"deadzone": 0.5, "events": [chat_key]})
	InputMap.add_action("CHAT")
	InputMap.action_add_event("CHAT", chat_key)
	# game closed or crashed while online last time, put the normal save back
	if FileAccess.file_exists(SINGLE_PLAYER_SAVE):
		restore_single_player_save()


func move_single_player_save() -> void:
	# empty file means there wasnt a normal save
	if FileAccess.file_exists(LEVEL_SAVE):
		DirAccess.rename_absolute(LEVEL_SAVE, SINGLE_PLAYER_SAVE)
	else:
		FileAccess.open(SINGLE_PLAYER_SAVE, FileAccess.WRITE).close()


func restore_single_player_save() -> void:
	if FileAccess.file_exists(LEVEL_SAVE):
		DirAccess.remove_absolute(LEVEL_SAVE) # online progress doesnt get kept
	if FileAccess.get_file_as_bytes(SINGLE_PLAYER_SAVE).is_empty():
		DirAccess.remove_absolute(SINGLE_PLAYER_SAVE)
	else:
		DirAccess.rename_absolute(SINGLE_PLAYER_SAVE, LEVEL_SAVE)
