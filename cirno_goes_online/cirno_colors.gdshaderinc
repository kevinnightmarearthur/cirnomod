uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 old_colors[14];
uniform vec4 new_colors[14];
uniform float glow = 1.0;

void fragment() {
	vec3 color = texture(albedo_texture, UV).rgb;
	for (int i = 0; i < old_colors.length(); i++) {
		if (all(lessThan(abs(color - old_colors[i].rgb), vec3(0.015)))) {
			color = new_colors[i].rgb;
			break;
		}
	}
	ALBEDO = color * glow;

	// same up close fade as the game's cirno material
	float fade = smoothstep(1.0, 1.25, length(VERTEX));
	const vec3 dither = vec3(0.06711056, 0.00583715, 52.9829189);
	if (fade < 0.001 || fade < fract(dither.z * fract(dot(FRAGCOORD.xy, dither.xy)))) {
		discard;
	}
}
