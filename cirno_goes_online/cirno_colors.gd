extends RefCounted

# swaps the colors on cirnos texture so everyone can have their own hair, dress, bows and wings

const TEXTURE_PATH := "res://models/src/Cirno/Cirno_tex_cirno.png"
const SHADER := preload("res://cirno_goes_online/cirno_colors.gdshader")
const NOCULL_SHADER := preload("res://cirno_goes_online/cirno_colors_nocull.gdshader")

# has to be a var, with a const the glow never changes
static var wing_material = preload("res://models/src/Cirno/material_cirno_wing_stuff.tres")

# first color is the one you pick, the darker ones follow it
const REGIONS = {
	"hair": [Color("abeefe"), Color("4ca4e7"), Color("2764a4"), Color("1f3c7b")],
	"dress": [Color("2663ef"), Color("1734ab"), Color("17114b")],
	"bow": [Color("f64b4b"), Color("ab1e1e")],
	"back_bow": [Color("18936b"), Color("115344"), Color("102d26")],
	"wings": [Color("b4f7ef"), Color("92bbe6")],
}


static func default_colors() -> Dictionary:
	var colors = {}
	for region in REGIONS:
		colors[region] = REGIONS[region][0]
	return colors


static func apply(skeleton: Skeleton3D, colors: Dictionary) -> void:
	var old_colors := PackedColorArray()
	var new_colors := PackedColorArray()
	for region in REGIONS:
		var shades: Array = REGIONS[region]
		for shade in shades:
			old_colors.append(shade)
			new_colors.append(_shade_like(colors[region], shades[0], shade))

	for mesh in skeleton.get_children():
		if not mesh is MeshInstance3D:
			continue
		for i in mesh.get_surface_override_material_count():
			var material = mesh.get_active_material(i)
			if material is BaseMaterial3D and material.albedo_texture and material.albedo_texture.resource_path == TEXTURE_PATH:
				material = _make_material(material)
				mesh.set_surface_override_material(i, material)
			if material is ShaderMaterial and material.shader in [SHADER, NOCULL_SHADER]:
				material.set_shader_parameter("old_colors", old_colors)
				material.set_shader_parameter("new_colors", new_colors)


# the game brightens its wing material while floating, so we copy that onto ours every frame
static func copy_wing_glow(skeleton: Skeleton3D) -> void:
	var material = skeleton.get_node("Wings").get_surface_override_material(0)
	if material is ShaderMaterial:
		material.set_shader_parameter("glow", wing_material.albedo_color.srgb_to_linear().r)


static func _make_material(original: BaseMaterial3D) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	material.shader = NOCULL_SHADER if original.cull_mode == BaseMaterial3D.CULL_DISABLED else SHADER
	material.set_shader_parameter("albedo_texture", original.albedo_texture)
	return material


# keeps the hue, saturation and brightness steps between the original shades
static func _shade_like(picked: Color, base: Color, shade: Color) -> Color:
	var hue = fposmod(picked.h + shade.h - base.h, 1.0)
	var saturation = clampf(picked.s * shade.s / base.s, 0.0, 1.0)
	var value = clampf(picked.v * shade.v / base.v, 0.0, 1.0)
	return Color.from_hsv(hue, saturation, value)
