// Native mesher kernels for Crystal Storm (GDExtension, godot-cpp 4.5 API).
// Every call is independent: no globals, no statics, no caches.
#include "native_mesher.h"

#include <godot_cpp/core/class_db.hpp>
#include <vector>

using namespace godot;

void CsNativeMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("waved_tops", "x0", "z0", "cw", "ch", "n", "layer", "tiles", "atlas", "base_keys", "col_steps", "reps", "faces"),
			&CsNativeMesher::waved_tops);
	ClassDB::bind_method(D_METHOD("surface_arrays", "quads", "atlas", "grid", "chunk_ox", "chunk_oz", "voxel_s", "layer", "ao_on", "curve_strips"),
			&CsNativeMesher::surface_arrays);
	ClassDB::bind_method(D_METHOD("version"), &CsNativeMesher::version);
}

int64_t CsNativeMesher::version() const { return 2; }

// Mirrors chunk_manager.gd _emit_waved_tops (greedy merge part) and
// _emit_wave_risers/_append_wave_riser. Inputs per column (index lz*cw+lx):
//   tiles: tile id or -1 when the column has no top face
//   atlas: 2 ints per column (face atlas x,y)
//   base_keys: round(surface_y*1000)
//   col_steps: n*n per column, steps for rep pair (rx,rz) at [col*n*n + rz*n + rx]
//   reps: TerrainLook.wave_rep_micro(m) for m in n
//   faces: [FACE_TOP, FACE_NEG_X, FACE_POS_X, FACE_NEG_Z, FACE_POS_Z]
Array CsNativeMesher::waved_tops(int64_t x0, int64_t z0, int64_t cw, int64_t ch, int64_t n, double layer,
		const PackedInt32Array &tiles, const PackedInt32Array &atlas, const PackedInt32Array &base_keys,
		const PackedInt32Array &col_steps, const PackedInt32Array &reps, const PackedInt32Array &faces) const {
	Array out;
	if (cw <= 0 || ch <= 0 || n <= 0) {
		return out;
	}
	if (tiles.size() < cw * ch || atlas.size() < cw * ch * 2 || base_keys.size() < cw * ch ||
			col_steps.size() < cw * ch * n * n || reps.size() < n || faces.size() < 5) {
		return out;
	}
	const int32_t *T = tiles.ptr();
	const int32_t *A = atlas.ptr();
	const int32_t *B = base_keys.ptr();
	const int32_t *S = col_steps.ptr();
	const int32_t *R = reps.ptr();
	const int64_t FACE_TOP = faces[0], FACE_NEG_X = faces[1], FACE_POS_X = faces[2], FACE_NEG_Z = faces[3], FACE_POS_Z = faces[4];
	const double step = layer / double(n);
	const int64_t w = cw * n;
	const int64_t h = ch * n;
	std::vector<uint8_t> open(w * h);
	std::vector<int32_t> steps(w * h);
	std::vector<int32_t> bases(w * h);
	for (int64_t lz = 0; lz < ch; lz++) {
		for (int64_t lx = 0; lx < cw; lx++) {
			const int64_t ti = lz * cw + lx;
			const bool col_open = T[ti] >= 0;
			for (int64_t mz = 0; mz < n; mz++) {
				for (int64_t mx = 0; mx < n; mx++) {
					const int64_t idx = (lz * n + mz) * w + (lx * n + mx);
					if (!col_open) {
						open[idx] = 0;
						steps[idx] = 0;
						bases[idx] = 0;
					} else {
						open[idx] = 1;
						steps[idx] = S[ti * n * n + int64_t(R[mz]) * n + R[mx]];
						bases[idx] = B[ti];
					}
				}
			}
		}
	}
	const String kx("x"), ky("y"), kz("z"), kdx("dim_x"), kdy("dim_y"), kdz("dim_z"), kuw("uv_w"), kuh("uv_h"),
			ktype("type"), kface("face_code"), kws("wave_step"), kwb("wave_base"), kwr("wave_riser");
	auto tile_at = [&](int64_t ix, int64_t iz) -> int64_t { return T[(iz / n) * cw + (ix / n)]; };
	auto same_col = [&](int64_t ti, int64_t want_tile, int32_t ax, int32_t az) -> bool {
		return T[ti] == want_tile && A[ti * 2] == ax && A[ti * 2 + 1] == az;
	};
	std::vector<uint8_t> visited(w * h, 0);
	const double nf = double(n);
	for (int64_t iz = 0; iz < h; iz++) {
		for (int64_t ix = 0; ix < w; ix++) {
			const int64_t idx = iz * w + ix;
			if (visited[idx] != 0 || open[idx] == 0) {
				continue;
			}
			const int64_t ti = (iz / n) * cw + (ix / n);
			const int32_t want_step = steps[idx];
			const int32_t want_base = bases[idx];
			const int64_t want_tile = T[ti];
			const int32_t ax = A[ti * 2], az = A[ti * 2 + 1];
			int64_t run_x = 1;
			while (ix + run_x < w) {
				const int64_t j = iz * w + (ix + run_x);
				if (visited[j] != 0 || open[j] == 0 || steps[j] != want_step || bases[j] != want_base) {
					break;
				}
				if (!same_col((iz / n) * cw + ((ix + run_x) / n), want_tile, ax, az)) {
					break;
				}
				run_x++;
			}
			int64_t run_z = 1;
			bool growing = true;
			while (growing && iz + run_z < h) {
				for (int64_t k = 0; k < run_x; k++) {
					const int64_t j2 = (iz + run_z) * w + (ix + k);
					if (visited[j2] != 0 || open[j2] == 0 || steps[j2] != want_step || bases[j2] != want_base) {
						growing = false;
						break;
					}
					if (!same_col(((iz + run_z) / n) * cw + ((ix + k) / n), want_tile, ax, az)) {
						growing = false;
						break;
					}
				}
				if (growing) {
					run_z++;
				}
			}
			for (int64_t zz = 0; zz < run_z; zz++) {
				for (int64_t xx = 0; xx < run_x; xx++) {
					visited[(iz + zz) * w + (ix + xx)] = 1;
				}
			}
			Dictionary q;
			q[kx] = double(x0) + double(ix) / nf;
			q[ky] = double(want_base) / 1000.0 + double(want_step) * step;
			q[kz] = double(z0) + double(iz) / nf;
			q[kdx] = double(run_x) / nf;
			q[kdy] = 1.0;
			q[kdz] = double(run_z) / nf;
			q[kuw] = double(run_x) / nf;
			q[kuh] = double(run_z) / nf;
			q[ktype] = want_tile;
			q[kface] = FACE_TOP;
			if (want_step != 0) {
				q[kws] = int64_t(want_step);
				q[kwb] = double(want_base) / 1000.0;
			}
			out.push_back(q);
		}
	}
	auto riser = [&](int64_t ix, int64_t iz, int64_t run, int64_t sa, int64_t sb, int64_t base_key, int64_t tile, bool along_z) {
		const int64_t lo = sa < sb ? sa : sb;
		const int64_t hi = sa > sb ? sa : sb;
		const double y = double(base_key) / 1000.0 + layer + double(lo) * (layer / nf);
		const double dim_y = double(hi - lo) / nf;
		Dictionary q;
		if (along_z) {
			const bool left_higher = sa > sb;
			const int64_t src = left_higher ? ix : ix + 1;
			q[kx] = double(x0) + double(src) / nf;
			q[ky] = y;
			q[kz] = double(z0) + double(iz) / nf;
			q[kdx] = 1.0 / nf;
			q[kdy] = dim_y;
			q[kdz] = double(run) / nf;
			q[kuw] = double(run) / nf;
			q[kuh] = dim_y;
			q[ktype] = tile;
			q[kface] = left_higher ? FACE_POS_X : FACE_NEG_X;
		} else {
			const bool near_higher = sa > sb;
			const int64_t srcz = near_higher ? iz : iz + 1;
			q[kx] = double(x0) + double(ix) / nf;
			q[ky] = y;
			q[kz] = double(z0) + double(srcz) / nf;
			q[kdx] = double(run) / nf;
			q[kdy] = dim_y;
			q[kdz] = 1.0 / nf;
			q[kuw] = double(run) / nf;
			q[kuh] = dim_y;
			q[ktype] = tile;
			q[kface] = near_higher ? FACE_POS_Z : FACE_NEG_Z;
		}
		q[kwr] = true;
		out.push_back(q);
	};
	for (int64_t ix = 0; ix < w - 1; ix++) {
		int64_t iz = 0;
		while (iz < h) {
			const int64_t a = iz * w + ix, b = a + 1;
			if (open[a] == 0 || open[b] == 0 || steps[a] == steps[b] || bases[a] != bases[b]) {
				iz++;
				continue;
			}
			const int64_t sa = steps[a], sb = steps[b], base_key = bases[a];
			const int64_t src = sa > sb ? ix : ix + 1;
			const int64_t tile = tile_at(src, iz);
			int64_t run = 1;
			while (iz + run < h) {
				const int64_t a2 = (iz + run) * w + ix, b2 = a2 + 1;
				if (open[a2] == 0 || open[b2] == 0 || steps[a2] != sa || steps[b2] != sb || bases[a2] != base_key) {
					break;
				}
				if (tile_at(src, iz + run) != tile) {
					break;
				}
				run++;
			}
			riser(ix, iz, run, sa, sb, base_key, tile, true);
			iz += run;
		}
	}
	for (int64_t izb = 0; izb < h - 1; izb++) {
		int64_t ixb = 0;
		while (ixb < w) {
			const int64_t a3 = izb * w + ixb, b3 = a3 + w;
			if (open[a3] == 0 || open[b3] == 0 || steps[a3] == steps[b3] || bases[a3] != bases[b3]) {
				ixb++;
				continue;
			}
			const int64_t sa3 = steps[a3], sb3 = steps[b3], base3 = bases[a3];
			const int64_t srcz = sa3 > sb3 ? izb : izb + 1;
			const int64_t tile3 = tile_at(ixb, srcz);
			int64_t runz = 1;
			while (ixb + runz < w) {
				const int64_t a4 = izb * w + (ixb + runz), b4 = a4 + w;
				if (open[a4] == 0 || open[b4] == 0 || steps[a4] != sa3 || steps[b4] != sb3 || bases[a4] != base3) {
					break;
				}
				if (tile_at(ixb + runz, srcz) != tile3) {
					break;
				}
				runz++;
			}
			riser(ixb, izb, runz, sa3, sb3, base3, tile3, false);
			ixb += runz;
		}
	}
	return out;
}
