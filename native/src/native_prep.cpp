// Native prep for CsNativeMesher.surface_arrays: the per-quad atlas cells
// (helpers/chunk_surface_mesh_builder.gd _quad_atlas + helpers/voxel_types.gd
// face_atlas, ported exactly) and the 20x20 AO height grid read from the chunk
// halo (terrain_vertex_ao.gd sample_surface). Cells the halo cannot answer are
// returned in "need" so GDScript fills them with sample_surface. No state.
#include "native_mesher.h"

#include <cmath>
#include <cstdint>

using namespace godot;

namespace {
struct C2 {
	int32_t x, y;
	bool operator==(const C2 &o) const { return x == o.x && y == o.y; }
	bool operator!=(const C2 &o) const { return !(*this == o); }
};

enum : int {
	OCEAN = 0, OCEAN2, OCEAN3, BEACH, BEACH2, BEACH3, GRASSLAND, GRASSLAND2, GRASSLAND3, GRASSLAND4, GRASSLAND5,
	HILLS, HILLS2, HILLS3, HILLS4, MOUNTAIN, MOUNTAIN2, MOUNTAIN3, MOUNTAIN4, MOUNTAIN5, MOUNTAIN6, MOUNTAIN7,
	SNOW, SNOW2, SNOW3, VALLEY, VALLEY2, VALLEY3, DESERT, DESERT2, DESERT3, TUNDRA, TUNDRA2, TUNDRA3,
	BASIN, BASIN2, BASIN3, RIVER, WATER, STONE, STONE2, DIRT, DIRT2, CAVE_STONE, CRYSTAL,
	GRASS_TUFT = 45, BUSH = 46, TREE_TRUNK = 47, FARMLAND = 48, TOWN_PATH = 49,
	CRYSTAL_VEIN = 50, CRYSTAL_SHARD_GROUND = 51, CRYSTAL_SCAR = 52, AIR = 255
};

const C2 ATLAS[53] = {
	{ 0, 0 }, { 0, 0 }, { 0, 0 }, // ocean
	{ 0, 1 }, { 1, 1 }, { 2, 1 }, // beach
	{ 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 1 }, { 4, 2 }, // grassland
	{ 0, 3 }, { 1, 3 }, { 1, 3 }, { 4, 3 }, // hills
	{ 0, 4 }, { 1, 4 }, { 3, 5 }, { 3, 4 }, { 4, 4 }, { 5, 4 }, { 6, 4 }, // mountain
	{ 0, 5 }, { 1, 5 }, { 2, 5 }, // snow
	{ 0, 6 }, { 1, 6 }, { 2, 6 }, // valley
	{ 0, 7 }, { 1, 7 }, { 2, 7 }, // desert
	{ 0, 8 }, { 1, 8 }, { 2, 8 }, // tundra
	{ 0, 9 }, { 1, 9 }, { 2, 9 }, // basin
	{ 1, 0 }, { 1, 0 }, // river, water
	{ 0, 4 }, { 2, 4 }, // stone, stone2
	{ 3, 2 }, { 0, 6 }, // dirt, dirt2
	{ 4, 4 }, // cave stone
	{ 6, 2 }, // crystal (44)
	{ 4, 2 }, { 4, 3 }, { 1, 3 }, { 4, 1 }, { 5, 1 }, // 45..49
	{ 6, 1 }, { 6, 3 }, { 6, 5 }, // 50..52
};

typedef C2 V3[3];
const V3 GRASS_TOP = { { 0, 2 }, { 1, 2 }, { 2, 2 } };
const V3 DIRT_V = { { 3, 2 }, { 0, 6 }, { 5, 6 } };
const V3 STONE_V = { { 0, 4 }, { 1, 4 }, { 2, 4 } };
const V3 ORE_V = { { 6, 1 }, { 4, 5 }, { 5, 5 } };
const V3 CAVE_V = { { 3, 6 }, { 4, 6 }, { 6, 6 } };
const V3 SAND_V = { { 0, 7 }, { 1, 7 }, { 2, 7 } };
const V3 BEACH_V = { { 0, 1 }, { 1, 1 }, { 2, 1 } };
const V3 LEAF_V = { { 0, 3 }, { 2, 3 }, { 4, 3 } };
const V3 WOOD_V = { { 1, 3 }, { 3, 3 }, { 5, 3 } };
const V3 SNOW_V = { { 0, 5 }, { 1, 5 }, { 2, 5 } };
const V3 TUNDRA_V = { { 0, 8 }, { 1, 8 }, { 2, 8 } };
const V3 BASIN_V = { { 0, 9 }, { 1, 9 }, { 2, 9 } };
const V3 VALLEY_V = { { 1, 6 }, { 2, 6 }, { 3, 9 } };
const V3 DRY_V = { { 3, 1 }, { 4, 2 }, { 5, 2 } };
const V3 FARM_V = { { 4, 1 }, { 4, 8 }, { 5, 8 } };
const V3 PATH_V = { { 5, 1 }, { 6, 8 }, { 6, 9 } };
const V3 OCEAN_V = { { 0, 0 }, { 2, 0 }, { 4, 0 } };
const V3 RIVER_V = { { 1, 0 }, { 3, 0 }, { 5, 0 } };

const C2 SOIL_BOTTOM = { 6, 7 }, ROCK_BOTTOM = { 5, 7 }, SAND_BOTTOM = { 4, 7 }, CRYSTAL_BOTTOM = { 3, 8 },
		CRYSTAL_SIDE = { 4, 9 };

C2 atlas_coord(int t) {
	if (t >= 0 && t < 53) {
		return ATLAS[t];
	}
	return C2{ 6, 0 }; // AIR and unknown
}

// GDScript int is int64 with wrapping arithmetic; >> is arithmetic.
inline int64_t wmul(int64_t a, int64_t b) { return int64_t(uint64_t(a) * uint64_t(b)); }
inline int64_t wadd(int64_t a, int64_t b) { return int64_t(uint64_t(a) + uint64_t(b)); }

int pick_index(int64_t wx, int64_t wz, int64_t salt) {
	int64_t n = wadd(wadd(wmul(wx, 374761393), wmul(wz, 668265263)), wmul(salt, 1442695041));
	n = wmul(n ^ (n >> 13), 1274126177);
	n = n ^ (n >> 16);
	if (n < 0) {
		n = int64_t(0 - uint64_t(n));
	}
	int64_t m = n % 3; // GDScript % truncates; a negative index counts from the end
	if (m < 0) {
		m += 3;
	}
	return int(m);
}

C2 pick(const V3 &c, int64_t wx, int64_t wz, int64_t salt) { return c[pick_index(wx, wz, salt)]; }

C2 pick_other(const V3 &c, int64_t wx, int64_t wz, int64_t salt, C2 avoid) {
	int at = pick_index(wx, wz, salt);
	if (c[at] != avoid) {
		return c[at];
	}
	int first = 0;
	while (first < 3 && c[first] != c[at]) {
		first++;
	}
	return c[(first + 1) % 3];
}

bool green_grass_top(int t) { return t == GRASSLAND || t == GRASSLAND2 || t == GRASSLAND3; }
bool column_rock(int t) {
	return t == STONE || t == STONE2 || t == MOUNTAIN || t == MOUNTAIN2 || t == MOUNTAIN3 || t == MOUNTAIN4 ||
			t == MOUNTAIN5 || t == MOUNTAIN6 || t == MOUNTAIN7;
}
bool grass_surface(int t) {
	return t == GRASSLAND || t == GRASSLAND2 || t == GRASSLAND3 || t == GRASSLAND4 || t == GRASSLAND5 ||
			t == GRASS_TUFT || t == FARMLAND || t == TOWN_PATH;
}
bool forest_surface(int t) { return t == HILLS || t == HILLS2 || t == HILLS3 || t == HILLS4; }
bool snow_only(int t) { return t == SNOW || t == SNOW2 || t == SNOW3; }
bool tundra(int t) { return t == TUNDRA || t == TUNDRA2 || t == TUNDRA3; }
bool snow_surface(int t) { return snow_only(t) || tundra(t); }
bool beach(int t) { return t == BEACH || t == BEACH2 || t == BEACH3; }
bool basin(int t) { return t == BASIN || t == BASIN2 || t == BASIN3; }
bool valley(int t) { return t == VALLEY || t == VALLEY2 || t == VALLEY3; }
bool dry_grass(int t) { return t == GRASSLAND4 || t == GRASSLAND5 || t == GRASS_TUFT; }
bool ocean(int t) { return t == OCEAN || t == OCEAN2 || t == OCEAN3; }
bool stone_surface(int t) {
	return (t >= MOUNTAIN && t <= MOUNTAIN7) || t == STONE || t == STONE2 || t == CAVE_STONE || valley(t) || basin(t);
}
bool desert_surface(int t) { return t == DESERT || t == DESERT2 || t == DESERT3; }

C2 bottom_for(int t) {
	if (t == CRYSTAL || t == CRYSTAL_VEIN || t == CRYSTAL_SHARD_GROUND || t == CRYSTAL_SCAR) {
		return CRYSTAL_BOTTOM;
	}
	if (snow_only(t) || column_rock(t) || t == CAVE_STONE || stone_surface(t)) {
		return ROCK_BOTTOM;
	}
	if (desert_surface(t) || beach(t)) {
		return SAND_BOTTOM;
	}
	return SOIL_BOTTOM;
}

C2 coord_for_face(int t, int fc) {
	if (fc <= 0 || fc >= 7) {
		return atlas_coord(t);
	}
	if (fc == 2) {
		return bottom_for(t);
	}
	if (grass_surface(t)) {
		return fc >= 3 ? atlas_coord(DIRT) : atlas_coord(t);
	}
	if (forest_surface(t)) {
		return fc >= 3 ? atlas_coord(TREE_TRUNK) : atlas_coord(t);
	}
	if (snow_surface(t)) {
		return fc >= 3 ? atlas_coord(STONE2) : atlas_coord(t);
	}
	if (t == DIRT || t == DIRT2) {
		return fc >= 3 ? C2{ 5, 6 } : atlas_coord(t);
	}
	if (t == CRYSTAL_VEIN) {
		return fc >= 3 ? C2{ 4, 5 } : atlas_coord(t);
	}
	if (t == CRYSTAL || t == CRYSTAL_SHARD_GROUND || t == CRYSTAL_SCAR) {
		return fc >= 3 ? CRYSTAL_SIDE : atlas_coord(t);
	}
	if (column_rock(t)) {
		if (fc >= 3) {
			return atlas_coord(t) == C2{ 2, 4 } ? C2{ 0, 4 } : C2{ 2, 4 };
		}
		return atlas_coord(t);
	}
	if (desert_surface(t)) {
		if (fc >= 3) {
			return atlas_coord(t) == C2{ 2, 7 } ? C2{ 0, 7 } : C2{ 2, 7 };
		}
		return atlas_coord(t);
	}
	return atlas_coord(t);
}

C2 face_atlas(int t, int face_code, int64_t wx, int64_t wz) {
	int face = face_code >= 7 ? 0 : face_code;
	if (face == 2) {
		return bottom_for(t);
	}
	if (green_grass_top(t) && face == 0) {
		return pick(GRASS_TOP, wx, wz, 11);
	}
	if ((t == DIRT || t == DIRT2) && face == 0) {
		return pick(DIRT_V, wx, wz, 29);
	}
	if ((t == DIRT || t == DIRT2) && face >= 3) {
		return pick_other(DIRT_V, wx, wz, 31, pick(DIRT_V, wx, wz, 29));
	}
	if (grass_surface(t) && face >= 3) {
		return pick(DIRT_V, wx, wz, 29);
	}
	if (t == CAVE_STONE) {
		C2 top = pick(CAVE_V, wx, wz, 83);
		return face >= 3 ? pick_other(CAVE_V, wx, wz, 89, top) : top;
	}
	if (t == CRYSTAL_VEIN) {
		C2 top = pick(ORE_V, wx, wz, 67);
		return face >= 3 ? pick_other(ORE_V, wx, wz, 71, top) : top;
	}
	if (t == CRYSTAL || t == CRYSTAL_SHARD_GROUND || t == CRYSTAL_SCAR) {
		return face >= 3 ? CRYSTAL_SIDE : atlas_coord(t);
	}
	if (column_rock(t)) {
		C2 top = pick(STONE_V, wx, wz, 41);
		return face >= 3 ? pick_other(STONE_V, wx, wz, 43, top) : top;
	}
	if (desert_surface(t)) {
		C2 top = pick(SAND_V, wx, wz, 101);
		return face >= 3 ? pick_other(SAND_V, wx, wz, 103, top) : top;
	}
	if (beach(t)) {
		return pick(BEACH_V, wx, wz, 103);
	}
	if (forest_surface(t) && face == 0) {
		return pick(LEAF_V, wx, wz, 107);
	}
	if (forest_surface(t) && face >= 3) {
		return pick(WOOD_V, wx, wz, 109);
	}
	if (t == TREE_TRUNK) {
		return pick(WOOD_V, wx, wz, 109);
	}
	if (t == BUSH && face == 0) {
		return pick(LEAF_V, wx, wz, 107);
	}
	if (tundra(t) && face == 0) {
		return pick(TUNDRA_V, wx, wz, 113);
	}
	if (tundra(t) && face >= 3) {
		return pick(STONE_V, wx, wz, 41);
	}
	if (snow_only(t) && face == 0) {
		return pick(SNOW_V, wx, wz, 127);
	}
	if (snow_only(t) && face >= 3) {
		return pick(STONE_V, wx, wz, 41);
	}
	if (basin(t)) {
		return pick(BASIN_V, wx, wz, 131);
	}
	if (valley(t)) {
		return pick(VALLEY_V, wx, wz, 137);
	}
	if (dry_grass(t) && face == 0) {
		return pick(DRY_V, wx, wz, 139);
	}
	if (t == FARMLAND && face == 0) {
		return pick(FARM_V, wx, wz, 149);
	}
	if (t == TOWN_PATH && face == 0) {
		return pick(PATH_V, wx, wz, 151);
	}
	if (ocean(t)) {
		return pick(OCEAN_V, wx, wz, 157);
	}
	if (t == RIVER || t == WATER) {
		return pick(RIVER_V, wx, wz, 163);
	}
	return coord_for_face(t, face_code);
}
} // namespace

PackedInt32Array CsNativeMesher::quad_atlas(const Array &quads, int64_t base_x, int64_t base_z) const {
	const Variant K_FC = "face_code", K_TYPE = "type", K_X = "x", K_Z = "z", K_WR = "wave_riser";
	PackedInt32Array out;
	const int64_t n = quads.size();
	out.resize(n * 2);
	int32_t *o = out.ptrw();
	for (int64_t i = 0; i < n * 2; i++) {
		o[i] = 0;
	}
	for (int64_t i = 0; i < n; i++) {
		Dictionary q = quads[i];
		int fc = q.has(K_FC) ? int(int64_t(q[K_FC])) : -1;
		if (!(fc < 7 || fc == 7 || fc == 8)) {
			continue;
		}
		if (!q.has(K_X) || !q.has(K_Z)) {
			return PackedInt32Array(); // caller falls back to GDScript
		}
		int t = q.has(K_TYPE) ? int(int64_t(q[K_TYPE])) : AIR;
		int face = q.has(K_WR) ? 0 : fc;
		int sample = face >= 7 ? 0 : face;
		int64_t wx = int64_t(std::floor(double(q[K_X]) + 0.001)) + base_x;
		int64_t wz = int64_t(std::floor(double(q[K_Z]) + 0.001)) + base_z;
		C2 a = face_atlas(t, sample, wx, wz);
		o[i * 2] = a.x;
		o[i * 2 + 1] = a.y;
	}
	return out;
}

Dictionary CsNativeMesher::ao_grid(const Array &halo, bool has_halo, int64_t size) const {
	const int N = 20, LO = -2, HALO = 1;
	PackedFloat64Array grid;
	grid.resize(N * N);
	double *g = grid.ptrw();
	PackedInt32Array need;
	for (int gx = 0; gx < N; gx++) {
		int lx = gx + LO;
		int ix = lx + HALO;
		Array row;
		bool row_ok = has_halo && ix >= 0 && ix < halo.size();
		if (row_ok) {
			row = halo[ix];
		}
		for (int gz = 0; gz < N; gz++) {
			int lz = gz + LO;
			int iz = lz + HALO;
			double h = -9999.0;
			if (row_ok && iz >= 0 && iz < row.size()) {
				h = double(row[iz]);
			}
			int idx = gx * N + gz;
			if (h > -9000.0) {
				g[idx] = h;
			} else if (lx < 0 || lz < 0 || lx >= size || lz >= size) {
				g[idx] = -9000.0;
			} else {
				g[idx] = -9000.0;
				need.push_back(idx);
			}
		}
	}
	Dictionary out;
	out["grid"] = grid;
	out["need"] = need;
	return out;
}
