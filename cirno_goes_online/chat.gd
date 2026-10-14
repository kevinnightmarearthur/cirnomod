extends Control

const MAX_LINES := 8
const VISIBLE_SECONDS := 9.0
const SYSTEM_COLOR := Color(0.8, 0.8, 0.8)

var typing := false

var _lines = PackedStringArray()
var _idle_time = 0.0


func _ready() -> void:
	%Input.text_submitted.connect(_on_input_submitted)
	var key = InputHelper.get_label_for_input(InputHelper.get_keyboard_input_for_action("CHAT"))
	add_system_message("Press " + key + " to chat.")


func add_message(sender: String, color: Color, text: String) -> void:
	_add_line("[color=#%s]%s[/color]: %s" % [color.to_html(false), _escape(sender), _escape(text)])


func add_system_message(text: String) -> void:
	_add_line("[color=#%s]%s[/color]" % [SYSTEM_COLOR.to_html(false), _escape(text)])


func _add_line(line: String) -> void:
	_lines.append(line)
	if _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	%Lines.text = "\n".join(_lines)
	_idle_time = 0.0


# stops people putting colors and stuff in their messages
func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _process(delta: float) -> void:
	if typing and Globals.CURRENT_GAME_STATE != Globals.GAME_STATE.IN_GAME:
		_close()
	_idle_time = 0.0 if typing else _idle_time + delta
	%Lines.modulate.a = clampf(1.0 - (_idle_time - VISIBLE_SECONDS), 0.0, 1.0)


# _input runs before the game sees the key, so esc closes chat instead of pausing
func _input(event: InputEvent) -> void:
	if typing:
		if event.is_action_pressed("PAUSE"):
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("CHAT") and Globals.CURRENT_GAME_STATE == Globals.GAME_STATE.IN_GAME:
		get_viewport().set_input_as_handled() # otherwise the key ends up in the box
		_open()


func _open() -> void:
	typing = true
	%InputPanel.show()
	%Input.clear()
	%Input.grab_focus()
	Online.update_player_controls()


func _close() -> void:
	typing = false
	%InputPanel.hide()
	%Input.release_focus()
	Online.update_player_controls()


func _on_input_submitted(text: String) -> void:
	_close()
	text = text.strip_edges()
	if text != "":
		Online.send_chat(text)

