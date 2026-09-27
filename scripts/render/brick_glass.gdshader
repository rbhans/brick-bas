shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://scripts/render/brick_common.gdshaderinc"

void vertex() {
	brick_color = COLOR;
	brick_vertex(VERTEX, INSTANCE_CUSTOM);
}

void fragment() {
	ALBEDO = brick_linear(brick_color.rgb);
	ALPHA = brick_color.a;
	ROUGHNESS = 0.06;
	SPECULAR = 0.75;
}
