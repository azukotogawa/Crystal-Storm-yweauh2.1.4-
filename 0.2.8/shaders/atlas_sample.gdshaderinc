// Sample one Cube.png cell (32px, atlas_grid 7x10).
// Greedy faces fract() once per block. texture() then takes a mip from
// that derivative spike and blends neighboring cells into a dark grid.
// The old 1/32 inset also landed on an integer texel edge, which the
// nearest sampler can resolve as the next cell. Stay on the center of
// the inner texels and lock mip 0.

vec4 cs_sample_atlas(sampler2D atlas, vec2 atlas_grid, vec2 col_row, vec2 tile_uv) {
	float tile_px = 32.0;
	vec2 uv = fract(tile_uv);
	vec2 local_uv = (vec2(1.5) + uv * (tile_px - 3.0)) / tile_px;
	vec2 tile_size = 1.0 / atlas_grid;
	vec2 atlas_uv = col_row * tile_size + local_uv * tile_size;
	return textureLod(atlas, atlas_uv, 0.0);
}
