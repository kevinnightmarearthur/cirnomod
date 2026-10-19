shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, shadows_disabled, ambient_light_disabled;

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 old_colors[9];
uniform vec4 new_colors[9];

void fragment() {
	vec3 color = texture(albedo_texture, UV).rgb;
	for (int i = 0; i < old_colors.length(); i++) {
		if (all(lessThan(abs(color - old_colors[i].rgb), vec3(0.015)))) {
			color = new_colors[i].rgb;
			break;
		}
	}
	ALBEDO = color;
}
