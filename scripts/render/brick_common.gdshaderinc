// Shared vertex logic for batched LDraw pieces.
//
// Instance colour carries the brick colour (one draw per part, not per colour).
// INSTANCE_CUSTOM describes wall cutaway behaviour:
//   r: 0 = never cut, 1 = collapse the whole piece when its wall is cut,
//      2 = clamp the piece to the cut height (door/window frames spanning it)
//   g: wall axis, 0 = runs along X (faces +/-Z), 1 = runs along Z (faces +/-X)
//   b, a: world X/Z of the wall edge centre, so a whole edge cuts together.
//
// wall_mode: 0 walls up, 1 cutaway around the focus, 2 walls down.

uniform int wall_mode = 0;
uniform vec3 cut_focus = vec3(0.0);
uniform vec2 cut_forward = vec2(0.0, -1.0);
uniform float cut_radius = 18.0;
uniform float cut_margin = 1.5;
uniform float cut_height = 0.62;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.42;
uniform float specular_value : hint_range(0.0, 1.0) = 0.45;

varying vec4 brick_color;

// Instance colours are authored in sRGB like every other Godot colour.
vec3 brick_linear(vec3 c) {
	return mix(c / 12.92, pow((c + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

bool brick_cut(vec4 custom) {
	if (custom.r < 0.5 || wall_mode == 0) {
		return false;
	}
	if (wall_mode == 2) {
		return true;
	}
	vec2 offset = custom.ba - cut_focus.xz;
	vec2 normal = custom.g < 0.5 ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
	float facing = abs(dot(normal, cut_forward));
	return facing > 0.3 && dot(offset, cut_forward) < cut_margin && length(offset) < cut_radius;
}

void brick_vertex(inout vec3 vertex, vec4 custom) {
	if (brick_cut(custom)) {
		if (custom.r < 1.5) {
			// Degenerate: every vertex of the piece meets at one point.
			vertex = vec3(custom.b, -500.0, custom.a);
		} else {
			vertex.y = min(vertex.y, cut_height);
		}
	}
}
