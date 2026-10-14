extends Node3D

const SMOOTHING := 15.0

const NOCULL_MATERIAL := preload("res://models/src/Cirno/material_cirno_nocull.tres")
const WING_MATERIAL := preload("res://models/src/Cirno/material_cirno_wing_stuff.tres")

var last_heard_ms := 0

var target_pos = Vector3.ZERO
var target_rot = Quaternion.IDENTITY
var target_scale = Vector3.ONE

@onready var name_tag: Label3D = $NameTag
@onready var skin: Node3D = $Skin
@onready var anim: AnimationPlayer = $Skin/AnimationPlayer


func _ready() -> void:
	var skeleton = $Skin/Armature/Skeleton3D
	for mesh in skeleton.get_children():
		if mesh is MeshInstance3D:
			mesh.layers = 2 # no blob shadow on her
	# same materials the real cirno swaps in
	skeleton.get_node("Legs").set_surface_override_material(0, NOCULL_MATERIAL)
	skeleton.get_node("Skirt").set_surface_override_material(0, NOCULL_MATERIAL)
	skeleton.get_node("Wings").set_surface_override_material(0, WING_MATERIAL)
	anim.playback_default_blend_time = 0.18


func apply_state(state: Dictionary) -> void:
	target_pos = state.position
	target_rot = state.rotation
	target_scale = state.scale
	if state.animation != anim.current_animation and anim.has_animation(state.animation):
		anim.play(state.animation)
	anim.speed_scale = state.animation_speed

	# first update, just snap there
	if last_heard_ms == 0:
		global_position = target_pos
		skin.basis = Basis(target_rot) * Basis.from_scale(target_scale)
	last_heard_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	var t = 1.0 - exp(-SMOOTHING * delta)
	global_position = global_position.lerp(target_pos, t)
	var rot = skin.basis.get_rotation_quaternion().slerp(target_rot, t)
	skin.basis = Basis(rot) * Basis.from_scale(skin.basis.get_scale().lerp(target_scale, t))

