shader_type spatial;
render_mode world_vertex_coords, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://scripts/render/brick_common.gdshaderinc"

// Glass draws both sides, so where it rests on another piece its far face
// would share that piece's plane and flicker through the glass. Pulling every
// glass surface in a few millimetres keeps them apart; too little to see.
const float GLASS_INSET = 0.003;

void vertex() {
	brick_color = COLOR;
	VERTEX -= normalize(NORMAL) * GLASS_INSET;
	brick_vertex(VERTEX, INSTANCE_CUSTOM);
}

void fragment() {
	ALBEDO = brick_linear(brick_color.rgb);
	ALPHA = brick_color.a;
	ROUGHNESS = 0.06;
	SPECULAR = 0.75;
}
