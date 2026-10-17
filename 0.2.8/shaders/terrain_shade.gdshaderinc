// Cheap terrain lighting. Crystal glow is atlas column 6, rows 1, 2, 3, and 5 only.
// Corner darkening is the product of both axes. One axis alone reads as a grid line.

global uniform float terrain_ao_strength;
global uniform vec3 terrain_sun_dir;
global uniform float terrain_detail;
global uniform float terrain_cave_fog;
global uniform float terrain_corner_darken;
global uniform float terrain_cell_size;
global uniform float terrain_shadow_darken;

float cs_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cs_crystal_cell(vec2 col_row) {
	float col_ok = 1.0 - step(0.5, abs(col_row.x - 6.0));
	float row = col_row.y;
	float row_ok = 0.0;
	if (abs(row - 1.0) < 0.5 || abs(row - 2.0) < 0.5 || abs(row - 3.0) < 0.5 || abs(row - 5.0) < 0.5) {
		row_ok = 1.0;
	}
	return col_ok * row_ok;
}

vec3 cs_finish(vec3 albedo, vec3 world_n, vec2 repeated_uv, vec3 world_pos, float ao, float crystal) {
	vec3 n = world_n;
	if (dot(n, n) < 0.001) {
		n = vec3(0.0, 1.0, 0.0);
	} else {
		n = normalize(n);
	}
	vec3 sun = terrain_sun_dir;
	if (dot(sun, sun) < 0.001) {
		sun = vec3(0.55, 0.82, 0.38);
	}
	sun = normalize(sun);
	float ndl = clamp(dot(n, sun), 0.0, 1.0);
	float hemi = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	float light = 0.60 + 0.22 * hemi + 0.20 * ndl;
	vec3 tint = vec3(0.92, 0.94, 0.98);
	if (n.y > 0.65) {
		tint = vec3(1.04, 1.02, 0.96);
	} else if (n.y < -0.65) {
		tint = vec3(0.80, 0.84, 0.92);
		light *= 0.84;
	}
	vec3 col = albedo * tint * light;
	float detail = clamp(terrain_detail, 0.0, 1.0);
	float noise = mix(0.94, 1.06, cs_hash(floor(world_pos.xz * 0.5)));
	col *= mix(1.0, noise, detail);
	// Do not darken tile borders. A per-block edge multiply reads as a grid
	// on every face. repeated_uv stays in the signature for callers.
	col *= 1.0 + min(repeated_uv.x, repeated_uv.y) * 0.0;
	if (crystal > 0.5) {
		vec3 glow = albedo * vec3(1.28, 0.78, 1.48) + vec3(0.10, 0.02, 0.14);
		col = mix(col, glow, 0.70 * detail);
	}
	float ao_f = ao;
	if (ao_f < 0.02) {
		ao_f = 1.0;
	}
	col *= mix(1.0, ao_f, clamp(terrain_ao_strength, 0.0, 1.0));
	float below = clamp((cutaway_player.y - world_pos.y) / 14.0, 0.0, 1.0);
	float far_d = length(world_pos - cutaway_camera);
	float far = clamp((far_d - 28.0) / 100.0, 0.0, 1.0);
	float fog = max(below * 0.55, far * 0.22) * clamp(terrain_cave_fog, 0.0, 1.0);
	col = mix(col, vec3(0.58, 0.64, 0.74), fog);
	return col;
}

float cs_corner_mask(vec3 world_pos, vec3 world_n) {
	float cell = terrain_cell_size;
	if (cell < 0.05) {
		cell = 2.0;
	}
	vec3 n = world_n;
	if (dot(n, n) < 0.001) {
		n = vec3(0.0, 1.0, 0.0);
	} else {
		n = normalize(n);
	}
	vec3 p = world_pos / cell;
	vec2 axes = fract(p.xz);
	if (abs(n.y) <= 0.65) {
		if (abs(n.x) > abs(n.z)) {
			axes = fract(p.zy);
		} else {
			axes = fract(p.xy);
		}
	}
	vec2 q = min(axes, vec2(1.0) - axes);
	float cx = 1.0 - smoothstep(0.0, 0.22, q.x);
	float cy = 1.0 - smoothstep(0.0, 0.22, q.y);
	return cx * cy;
}

vec3 cs_depth(vec3 albedo, vec3 world_n, vec3 world_pos, float ao) {
	float ao_f = ao;
	if (ao_f < 0.02) {
		ao_f = 1.0;
	}
	vec3 col = albedo * mix(1.0, ao_f, clamp(terrain_ao_strength, 0.0, 1.0));
	float mask = cs_corner_mask(world_pos, world_n);
	col *= 1.0 - mask * clamp(terrain_corner_darken, 0.0, 0.75);
	return col;
}
