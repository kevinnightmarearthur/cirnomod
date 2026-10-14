extends Node

# adds the multiplayer button and the online settings to the game's menus when they open

const MultiplayerMenuScene := preload("res://cirno_goes_online/multiplayer_menu.tscn")
const UI_THEME := preload("res://theme_stuff/themes/UITheme.tres")
const LABEL_SETTINGS := preload("res://theme_stuff/label_settings/ui_label_default.tres")
const FONT := preload("res://theme_stuff/fonts/base_fonts/Unispace Rg.otf")


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node.scene_file_path == "res://scenes/UI/menus/title_menu.tscn":
		node.ready.connect(_add_multiplayer_button.bind(node), CONNECT_ONE_SHOT)
	elif node.scene_file_path == "res://scenes/UI/menus/gameplay/gameplay_menu.tscn":
		node.ready.connect(_add_online_settings.bind(node), CONNECT_ONE_SHOT)


func _add_multiplayer_button(menu: Control) -> void:
	var button = Button.new()
	button.text = "MULTIPLAYER"
	button.theme = UI_THEME
	button.custom_minimum_size = Vector2(0, 66)
	button.pivot_offset = Vector2(225, 32)
	menu.add_child(button)
	_place_button(button, 0.5972)
	# push options and credits down to make room
	_place_button(menu.get_node("%ButtonOptions"), 0.6944)
	_place_button(menu.get_node("%ButtonCredits"), 0.7917)

	# the title menu turns its buttons on after the loading screen
	button.disabled = menu.get_node("%ButtonStart").disabled
	Globals.TRANSITION_NODE.fake_loading_done.connect(button.set.bind("disabled", false))
	button.focus_entered.connect(func(): menu.get_node("%SelectGraphic").target_y = button.global_position.y)
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(func():
		if !menu.transition_tween:
			menu._create_transition_tween(true, _open_multiplayer_menu.bind(menu))
	)


func _place_button(button: Control, height: float) -> void:
	button.anchor_left = 0.5
	button.anchor_right = 0.5
	button.anchor_top = height
	button.anchor_bottom = height
	button.offset_left = -91.5
	button.offset_right = 91.5
	button.offset_top = -33.0
	button.offset_bottom = 33.0
	button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	button.grow_vertical = Control.GROW_DIRECTION_BOTH


func _open_multiplayer_menu(menu: Control) -> void:
	Globals.MENU_NODE.add_child(MultiplayerMenuScene.instantiate())
	menu.queue_free()


func _add_online_settings(menu: Control) -> void:
	var options = menu.get_node("MarginContainer/VBoxContainer/ScrollContainer/OptionsContainer")

	var nickname = LineEdit.new()
	nickname.max_length = 16
	nickname.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nickname.context_menu_enabled = false
	nickname.add_theme_color_override("font_color", Color.WHITE)
	nickname.add_theme_color_override("caret_color", Color(0.55, 0.85, 1))
	nickname.add_theme_font_override("font", FONT)
	nickname.add_theme_font_size_override("font_size", 32)
	nickname.add_theme_stylebox_override("normal", _nickname_box(Color(1, 1, 1, 0.6)))
	nickname.add_theme_stylebox_override("focus", _nickname_box(Color(0.55, 0.85, 1)))
	var name_tags = CheckBox.new()
	_add_row(options, "NICKNAME", nickname)
	_add_row(options, "NAME TAGS", name_tags)

	var refresh = func():
		nickname.text = Online.nickname
		nickname.placeholder_text = Online.own_name() if Online.nickname == "" else ""
		name_tags.set_pressed_no_signal(Online.show_name_tags)
	refresh.call()

	nickname.text_submitted.connect(func(_text): nickname.release_focus())
	nickname.focus_exited.connect(func():
		Online.set_nickname(nickname.text)
		refresh.call()
	)
	name_tags.toggled.connect(Online.set_show_name_tags)
	for control in [nickname, name_tags]:
		control.focus_entered.connect(func(): menu._belated_move.call_deferred(control.global_position.y))
		control.mouse_entered.connect(control.grab_focus)

	menu.get_node("%ButtonReset").pressed.connect(func():
		Online.set_nickname("")
		Online.set_show_name_tags(true)
		refresh.call()
	)

	# guide light used to be the last option, so hook the new ones into the controller/keyboard order
	var guide_light = menu.get_node("%GuideLightCheck")
	var reset = menu.get_node("%ButtonReset")
	var delete_save = menu.get_node("%ButtonDeleteSave")
	guide_light.focus_neighbor_bottom = guide_light.get_path_to(nickname)
	name_tags.focus_neighbor_bottom = name_tags.get_path_to(reset)
	reset.focus_neighbor_top = reset.get_path_to(name_tags)
	delete_save.focus_neighbor_top = delete_save.get_path_to(name_tags)


func _add_row(options: Control, text: String, control: Control) -> void:
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = text
	label.label_settings = LABEL_SETTINGS
	label.custom_minimum_size = Vector2(512, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.custom_minimum_size = Vector2(450, 64)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if control is CheckBox:
		control.theme = UI_THEME
	row.add_child(label)
	row.add_child(control)
	options.add_child(row)


func _nickname_box(border: Color) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.06, 0.12, 0.9)
	box.set_border_width_all(3)
	box.border_color = border
	return box
