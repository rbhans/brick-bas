shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// A studded LEGO baseplate drawn procedurally: studs every 0.5 m, centred on
// the stud lattice (multiples of 0.5 m). Optional plan grid lines every 2.5 m.

uniform vec3 plate_color : source_color = vec3(0.30, 0.52, 0.24);
uniform float stud_pitch = 0.5;
uniform float stud_radius = 0.15;
uniform float grid_pitch = 2.5;
uniform float grid_strength = 0.0;
uniform vec3 grid_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 light_dir = vec3(-0.55, 0.0, -0.45);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz / stud_pitch;
	vec2 cell = p - round(p);
	float r = length(cell) * stud_pitch;
	float px = max(fwidth(r), 0.0005);
	float body = 1.0 - smoothstep(stud_radius - px, stud_radius + px, r);
	// Soft contact shadow cast by the stud away from the key light.
	vec2 to_light = normalize(light_dir.xz);
	float shadow_r = length((cell - to_light * 0.1) * stud_pitch);
	float shadow = (1.0 - smoothstep(stud_radius, stud_radius + 0.07, shadow_r)) * (1.0 - body);
	// Bright rim on the lit side of each stud, dark rim on the far side.
	float rim = smoothstep(stud_radius - 0.035, stud_radius - 0.005, r) * body;
	float lit = dot(normalize(cell + vec2(0.0001)), -to_light);
	vec3 color = plate_color;
	color *= 1.0 - shadow * 0.28;
	color = mix(color, color * (1.12 + 0.28 * lit), rim);
	color = mix(color, color * 1.05, body * (1.0 - rim));
	// Distance fade keeps the far field calm instead of shimmering.
	float fade = smoothstep(0.018, 0.05, px);
	color = mix(color, plate_color * 0.98, fade);
	if (grid_strength > 0.0) {
		vec2 g = abs(fract(world_position.xz / grid_pitch + 0.5) - 0.5) * grid_pitch;
		float gw = max(fwidth(world_position.x), 0.002) * 1.2;
		float line = 1.0 - smoothstep(0.0, gw + 0.015, min(g.x, g.y));
		color = mix(color, grid_color, line * grid_strength);
	}
	ALBEDO = color;
	ROUGHNESS = 0.55;
	SPECULAR = 0.3;
}
