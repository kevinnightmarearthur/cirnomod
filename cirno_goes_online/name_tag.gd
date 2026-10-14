extends Label3D


func show_player(player_name: String, color: Color) -> void:
	text = player_name
	modulate = color
	visible = Online.show_name_tags
