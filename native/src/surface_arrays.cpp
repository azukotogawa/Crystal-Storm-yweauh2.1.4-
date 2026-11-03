// Native terrain surface arrays for Crystal Storm. Mirrors
// helpers/chunk_surface_mesh_builder.gd build_surface_arrays_from_terrain_quads
// (_write_face_quad, TerrainVertexAO) and terrain_surface_cache.gd quad_key.
// Ramp faces (7, 8) are left to GDScript: their slots are reserved and reported.
// No globals, no statics, no caches.
#include "native_mesher.h"

#include <godot_cpp/variant/string.hpp>
#include <cmath>
#include <cstdio>
#include <vector>

using namespace godot;

namespace {
const double HEIGHT_MISSING = -9000.0;
const int GRID_LO = -2;
const int GRID_N = 20; // columns -2..17

struct Grid {
	const double *g = nullptr;
	bool oob = false;
	double at(int lx, int lz) {
		int ix = lx - GRID_LO, iz = lz - GRID_LO;
		if (ix < 0 || iz < 0 || ix >= GRID_N || iz >= GRID_N) {
			oob = true;
			return HEIGHT_MISSING;
		}
		return g[ix * GRID_N + iz];
	}
};

double corner_ao(bool a, bool b, bool c) {
	if (a && b) {
		return 0.50;
	}
	int level = int(a) + int(b) + int(c);
	double v = 1.0 - double(level) * 0.16;
	return v < 0.50 ? 0.50 : (v > 1.0 ? 1.0 : v);
}

bool occ(Grid &G, int lx, int lz, double face_surface, double layer) {
	double n = G.at(lx, lz);
	if (n <= HEIGHT_MISSING) {
		return false;
	}
	return n >= face_surface + layer * 0.75;
}

bool reaches(Grid &G, int lx, int lz, double height, double layer) {
	double s = G.at(lx, lz);
	if (s <= HEIGHT_MISSING) {
		return false;
	}
	return s + layer >= height - layer * 0.2;
}

double side_corner(Grid &G, int ox, int oz, int outx, int outz, int ax, int az, double h, double layer) {
	bool f = reaches(G, ox + outx, oz + outz, h, layer);
	bool s = reaches(G, ox + ax, oz + az, h, layer);
	bool c = reaches(G, ox + outx + ax, oz + outz + az, h, layer);
	return corner_ao(f, s, c);
}

void face_ao(Grid &G, bool ao_on, int fc, int cx, int cz, int dimx, int dimz, double fy, double dimy, double layer, float out[4]) {
	out[0] = out[1] = out[2] = out[3] = 1.0f;
	if (!ao_on) {
		return;
	}
	int dx = dimx > 1 ? dimx : 1;
	int dz = dimz > 1 ? dimz : 1;
	if (fc == 0) {
		bool a0 = occ(G, cx - 1, cz, fy, layer), b0 = occ(G, cx, cz - 1, fy, layer), c0 = occ(G, cx - 1, cz - 1, fy, layer);
		bool a1 = occ(G, cx + dx, cz, fy, layer), b1 = occ(G, cx + dx - 1, cz - 1, fy, layer), c1 = occ(G, cx + dx, cz - 1, fy, layer);
		bool a2 = occ(G, cx + dx, cz + dz - 1, fy, layer), b2 = occ(G, cx + dx - 1, cz + dz, fy, layer), c2 = occ(G, cx + dx, cz + dz, fy, layer);
		bool a3 = occ(G, cx - 1, cz + dz - 1, fy, layer), b3 = occ(G, cx, cz + dz, fy, layer), c3 = occ(G, cx - 1, cz + dz, fy, layer);
		out[0] = float(corner_ao(a0, b0, c0));
		out[1] = float(corner_ao(a1, b1, c1));
		out[2] = float(corner_ao(a2, b2, c2));
		out[3] = float(corner_ao(a3, b3, c3));
		return;
	}
	if (fc < 3 || fc > 6) {
		return;
	}
	double y0 = fy;
	double y1 = fy + (dimy > 0.001 ? dimy : 0.001) * layer;
	int x0 = cx, z0 = cz, x1 = cx + dx - 1, z1 = cz + dz - 1;
	double r[4];
	if (fc == 3) {
		r[0] = side_corner(G, x0, z1, -1, 0, 0, 1, y0, layer);
		r[1] = side_corner(G, x0, z1, -1, 0, 0, 1, y1, layer);
		r[2] = side_corner(G, x0, z0, -1, 0, 0, -1, y1, layer);
		r[3] = side_corner(G, x0, z0, -1, 0, 0, -1, y0, layer);
	} else if (fc == 4) {
		r[0] = side_corner(G, x1, z0, 1, 0, 0, -1, y0, layer);
		r[1] = side_corner(G, x1, z0, 1, 0, 0, -1, y1, layer);
		r[2] = side_corner(G, x1, z1, 1, 0, 0, 1, y1, layer);
		r[3] = side_corner(G, x1, z1, 1, 0, 0, 1, y0, layer);
	} else if (fc == 5) {
		r[0] = side_corner(G, x0, z0, 0, -1, -1, 0, y0, layer);
		r[1] = side_corner(G, x0, z0, 0, -1, -1, 0, y1, layer);
		r[2] = side_corner(G, x1, z0, 0, -1, 1, 0, y1, layer);
		r[3] = side_corner(G, x1, z0, 0, -1, 1, 0, y0, layer);
	} else {
		r[0] = side_corner(G, x1, z1, 0, 1, 1, 0, y0, layer);
		r[1] = side_corner(G, x1, z1, 0, 1, 1, 0, y1, layer);
		r[2] = side_corner(G, x0, z1, 0, 1, -1, 0, y1, layer);
		r[3] = side_corner(G, x0, z1, 0, 1, -1, 0, y0, layer);
	}
	for (int k = 0; k < 4; k++) {
		out[k] = float(r[k]);
	}
}

double fposmod(double x, double y) {
	double v = std::fmod(x, y);
	if ((v < 0 && y > 0) || (v > 0 && y < 0)) {
		v += y;
	}
	v += 0.0;
	return v;
}

double face_shade(int fc) {
	if (fc == 2) {
		return 0.48;
	}
	if (fc > 0 && fc < 7) {
		return 0.68;
	}
	return 0.96;
}

void fmt3(std::string &s, double v) {
	char b[64];
	std::snprintf(b, sizeof(b), "%.3f", std::fabs(v));
	if (std::signbit(v)) {
		s += '-';
	}
	s += b;
}


struct Keys {
	Variant face_code = "face_code", x = "x", y = "y", z = "z", dim_x = "dim_x", dim_y = "dim_y", dim_z = "dim_z",
			uv_w = "uv_w", uv_h = "uv_h", type = "type", wave_shade = "wave_shade", flank_a = "flank_a", flank_b = "flank_b";
};

double getd(const Dictionary &q, const Variant &k, double def) {
	if (!q.has(k)) {
		return def;
	}
	return double(q[k]);
}

int64_t geti(const Dictionary &q, const Variant &k, int64_t def) {
	if (!q.has(k)) {
		return def;
	}
	return int64_t(q[k]);
}
} // namespace

Dictionary CsNativeMesher::surface_arrays(const Array &quads, const PackedInt32Array &atlas, const PackedFloat64Array &grid,
		double chunk_ox, double chunk_oz, double voxel_s, double layer, bool ao_on, int64_t curve_strips) const {
	Dictionary out;
	const int64_t nq = quads.size();
	if (atlas.size() < nq * 2 || grid.size() < GRID_N * GRID_N) {
		out["error"] = "bad_input";
		return out;
	}
	Keys k;
	Grid G;
	G.g = grid.ptr();
	const int32_t *A = atlas.ptr();
	// pass 1: slots
	std::vector<int32_t> fcs(nq);
	int64_t face_count = 0, extra = 0;
	for (int64_t i = 0; i < nq; i++) {
		Dictionary q = quads[i];
		int fc = int(geti(q, k.face_code, -1));
		fcs[i] = fc;
		if (fc < 7 || fc == 7 || fc == 8) {
			face_count++;
			if (fc == 7) {
				int64_t flank_n = geti(q, k.flank_a, 0) + geti(q, k.flank_b, 0);
				extra += (curve_strips - 1) + 1 + flank_n * curve_strips;
			} else if (fc == 8) {
				extra += 1;
			}
		}
	}
	const int64_t slots = face_count + extra;
	PackedVector3Array V, N;
	PackedVector2Array UV;
	PackedColorArray C;
	PackedInt32Array I;
	PackedInt32Array ramp_q, ramp_vi, ramp_ii;
	PackedInt64Array keys;
	if (face_count > 0) {
		V.resize(slots * 4);
		N.resize(slots * 4);
		UV.resize(slots * 4);
		C.resize(slots * 4);
		I.resize(slots * 6);
	}
	Vector3 *v = V.ptrw();
	Vector3 *nr = N.ptrw();
	Vector2 *uv = UV.ptrw();
	Color *col = C.ptrw();
	int32_t *ix = I.ptrw();
	int64_t vi = 0, ii = 0;
	for (int64_t i = 0; i < nq && face_count > 0; i++) {
		int fc = fcs[i];
		if (!(fc < 7 || fc == 7 || fc == 8)) {
			continue;
		}
		Dictionary q = quads[i];
		if (fc == 7) {
			int64_t flank_n = geti(q, k.flank_a, 0) + geti(q, k.flank_b, 0);
			ramp_q.push_back(int32_t(i));
			ramp_vi.push_back(int32_t(vi));
			ramp_ii.push_back(int32_t(ii));
			int64_t s = curve_strips + 1 + flank_n * curve_strips;
			vi += s * 4;
			ii += s * 6;
			continue;
		}
		if (fc == 8) {
			ramp_q.push_back(int32_t(i));
			ramp_vi.push_back(int32_t(vi));
			ramp_ii.push_back(int32_t(ii));
			vi += 8;
			ii += 12;
			continue;
		}
		double dim_x = getd(q, k.dim_x, 1.0), dim_y = getd(q, k.dim_y, 1.0), dim_z = getd(q, k.dim_z, 1.0);
		double surface_y = double(q[k.y]);
		double qx = double(q[k.x]), qz = double(q[k.z]);
		double ox = chunk_ox + qx * voxel_s;
		double oz = chunk_oz + qz * voxel_s;
		double sx = dim_x * voxel_s, sy = dim_y * voxel_s, sz = dim_z * voxel_s;
		double shade = face_shade(fc) * getd(q, k.wave_shade, 1.0);
		double uv_w = getd(q, k.uv_w, dim_x), uv_h = getd(q, k.uv_h, dim_z);
		double y0 = surface_y, y1 = surface_y + sy;
		Vector3 nm;
		bool ok = true;
		switch (fc) {
			case 0:
				nm = Vector3(0, 1, 0);
				v[vi] = Vector3(ox, y1, oz); v[vi + 1] = Vector3(ox + sx, y1, oz);
				v[vi + 2] = Vector3(ox + sx, y1, oz + sz); v[vi + 3] = Vector3(ox, y1, oz + sz);
				break;
			case 2:
				nm = Vector3(0, -1, 0);
				v[vi] = Vector3(ox, y0, oz + sz); v[vi + 1] = Vector3(ox + sx, y0, oz + sz);
				v[vi + 2] = Vector3(ox + sx, y0, oz); v[vi + 3] = Vector3(ox, y0, oz);
				break;
			case 3:
				nm = Vector3(-1, 0, 0);
				v[vi] = Vector3(ox, y0, oz + sz); v[vi + 1] = Vector3(ox, y1, oz + sz);
				v[vi + 2] = Vector3(ox, y1, oz); v[vi + 3] = Vector3(ox, y0, oz);
				break;
			case 4:
				nm = Vector3(1, 0, 0);
				v[vi] = Vector3(ox + sx, y0, oz); v[vi + 1] = Vector3(ox + sx, y1, oz);
				v[vi + 2] = Vector3(ox + sx, y1, oz + sz); v[vi + 3] = Vector3(ox + sx, y0, oz + sz);
				break;
			case 5:
				nm = Vector3(0, 0, -1);
				v[vi] = Vector3(ox, y0, oz); v[vi + 1] = Vector3(ox, y1, oz);
				v[vi + 2] = Vector3(ox + sx, y1, oz); v[vi + 3] = Vector3(ox + sx, y0, oz);
				break;
			case 6:
				nm = Vector3(0, 0, 1);
				v[vi] = Vector3(ox + sx, y0, oz + sz); v[vi + 1] = Vector3(ox + sx, y1, oz + sz);
				v[vi + 2] = Vector3(ox, y1, oz + sz); v[vi + 3] = Vector3(ox, y0, oz + sz);
				break;
			default:
				ok = false;
		}
		if (ok) {
			float tr = float(double(A[i * 2]) / 255.0), tg = float(double(A[i * 2 + 1]) / 255.0), tb = float(shade);
			float ao[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
			if (fc != 2) {
				int cdx = int(std::round(dim_x)); cdx = cdx > 1 ? cdx : 1;
				int cdz = int(std::round(dim_z)); cdz = cdz > 1 ? cdz : 1;
				face_ao(G, ao_on, fc, int(std::round(qx)), int(std::round(qz)), cdx, cdz, surface_y, dim_y, layer, ao);
			}
			for (int t = 0; t < 4; t++) {
				nr[vi + t] = nm;
			}
			if (fc == 0) {
				double u0 = fposmod(ox / voxel_s, 1.0), v0 = fposmod(oz / voxel_s, 1.0);
				double u1 = u0 + sx / voxel_s, v1 = v0 + sz / voxel_s;
				uv[vi] = Vector2(u0, v0); uv[vi + 1] = Vector2(u1, v0);
				uv[vi + 2] = Vector2(u1, v1); uv[vi + 3] = Vector2(u0, v1);
			} else if (fc == 2) {
				uv[vi] = Vector2(0.0, 0.0); uv[vi + 1] = Vector2(uv_w, 0.0);
				uv[vi + 2] = Vector2(uv_w, uv_h); uv[vi + 3] = Vector2(0.0, uv_h);
			} else {
				bool along_x = fc == 5 || fc == 6;
				double y_top = std::ceil((surface_y + sy) / voxel_s - 0.001) * voxel_s;
				for (int t = 0; t < 4; t++) {
					const Vector3 &p = v[vi + t];
					double h = along_x ? double(p.x) : double(p.z);
					uv[vi + t] = Vector2(h / voxel_s, (y_top - double(p.y)) / voxel_s);
				}
			}
			for (int t = 0; t < 4; t++) {
				col[vi + t] = Color(tr, tg, tb, ao[t]);
			}
			ix[ii] = int32_t(vi); ix[ii + 1] = int32_t(vi + 1); ix[ii + 2] = int32_t(vi + 2);
			ix[ii + 3] = int32_t(vi); ix[ii + 4] = int32_t(vi + 2); ix[ii + 5] = int32_t(vi + 3);
		}
		vi += 4;
		ii += 6;
	}
	if (G.oob) {
		out["error"] = "grid_oob";
		return out;
	}
	// face keys (terrain_surface_cache.gd quad_key over is_terrain_quad, capped at slot count)
	int64_t kn = slots < nq ? slots : nq;
	if (face_count == 0) {
		kn = 0;
	}
	keys.resize(kn);
	int64_t ki = 0;
	std::string s;
	for (int64_t i = 0; i < nq && ki < kn; i++) {
		Dictionary q = quads[i];
		int fc = int(geti(q, k.face_code, 99));
		if (!(fc < 7 || fc == 7 || fc == 8)) {
			continue;
		}
		s.clear();
		char b[32];
		std::snprintf(b, sizeof(b), "%lld:%lld:", (long long)geti(q, k.x, 0), (long long)geti(q, k.z, 0));
		s += b;
		fmt3(s, getd(q, k.y, 0.0));
		std::snprintf(b, sizeof(b), ":%d:", fc);
		s += b;
		fmt3(s, getd(q, k.dim_x, 1.0));
		s += ':';
		fmt3(s, getd(q, k.dim_z, 1.0));
		s += ':';
		fmt3(s, getd(q, k.dim_y, 1.0));
		std::snprintf(b, sizeof(b), ":%lld:", (long long)geti(q, k.type, 0));
		s += b;
		fmt3(s, getd(q, k.uv_w, 1.0));
		s += ':';
		fmt3(s, getd(q, k.uv_h, 1.0));
		keys.set(ki, int64_t(String::utf8(s.c_str()).hash()));
		ki++;
	}
	out["vertices"] = V;
	out["normals"] = N;
	out["uvs"] = UV;
	out["colors"] = C;
	out["indices"] = I;
	out["triangle_count"] = face_count > 0 ? slots * 2 : 0;
	out["face_keys"] = keys;
	out["ramp_q"] = ramp_q;
	out["ramp_vi"] = ramp_vi;
	out["ramp_ii"] = ramp_ii;
	return out;
}