shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

// Build-mode plan grid drawn just above floor level. Lines fade with distance
// from the cursor so the grid reads as a tool, not a texture.

uniform vec3 line_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float strength = 0.35;
uniform float pitch = 2.5;
uniform vec3 cursor = vec3(0.0);
uniform float radius = 22.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = abs(fract(world_position.xz / pitch + 0.5) - 0.5) * pitch;
	float width = max(fwidth(world_position.x), 0.002) * 1.1 + 0.012;
	float line = 1.0 - smoothstep(0.0, width, min(g.x, g.y));
	float falloff = 1.0 - smoothstep(radius * 0.35, radius, length(world_position.xz - cursor.xz));
	ALBEDO = line_color;
	ALPHA = line * strength * (0.35 + 0.65 * falloff);
}
