shader_type spatial;
render_mode world_vertex_coords, cull_back, depth_draw_always, diffuse_burley, specular_schlick_ggx;

// Placement preview: the real bricks, washed toward a valid/invalid tint and
// slightly transparent, with a soft pulsing rim so the ghost reads as "not yet placed".

#include "res://scripts/render/brick_common.gdshaderinc"

uniform vec4 ghost_tint : source_color = vec4(0.35, 0.9, 0.55, 1.0);
uniform float tint_amount = 0.45;
uniform float opacity = 0.72;

void vertex() {
	brick_color = COLOR;
}

void fragment() {
	vec3 base = brick_linear(brick_color.rgb);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
	ALBEDO = mix(base, ghost_tint.rgb, tint_amount);
	EMISSION = ghost_tint.rgb * (0.12 + rim * (0.35 + 0.25 * pulse));
	ALPHA = opacity;
	ROUGHNESS = 0.5;
}
