shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 active_color : source_color = vec4(0.2, 0.65, 0.95, 1.0);
uniform vec4 idle_color : source_color = vec4(0.30, 0.34, 0.36, 1.0);
uniform float fill_level : hint_range(0.0, 1.0) = 0.0;
uniform float minimum_x = -0.5;
uniform float width_x = 1.0;
varying float across;

void vertex() {
	across = (VERTEX.x - minimum_x) / max(width_x, 0.001);
}

void fragment() {
	float filled = step(across, fill_level) * step(0.001, fill_level);
	ALBEDO = mix(idle_color.rgb, active_color.rgb, filled);
	ROUGHNESS = 0.8;
	SPECULAR = 0.15;
}
