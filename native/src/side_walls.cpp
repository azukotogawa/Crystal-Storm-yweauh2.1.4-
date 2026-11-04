// Side wall emission for chunk_manager.gd _emit_surface_side_walls_region.
// GDScript decides each side cell (spec, ramp, halo, wave lip checks) and passes
// an ordered op list; this builds the quad dictionaries in the same order with
// the same keys and value types as the script path.
#include "native_mesher.h"

using namespace godot;

// ops: stride 8 per op: kind, x, z, nz_differs(along_x), face_code, tile, y, dim_y
//   kind 0: plain quad (x, z ints; y, dim_y floats)
//   kind 1: strip op, uses heights[k*2n .. k*2n+2n) = n y_hi then n y_lo, k = strip index
Array CsNativeMesher::side_ops(const PackedFloat64Array &ops, const PackedFloat64Array &heights, int64_t n, double layer) const {
	Array out;
	const int64_t stride = 8;
	const int64_t count = ops.size() / stride;
	if (n <= 0) {
		return out;
	}
	const double *O = ops.ptr();
	const double *H = heights.ptr();
	const int64_t hs = heights.size();
	const String kx("x"), ky("y"), kz("z"), kdx("dim_x"), kdy("dim_y"), kdz("dim_z"), kuw("uv_w"), kuh("uv_h"),
			ktype("type"), kface("face_code"), kwr("wave_riser");
	const double nf = double(n);
	int64_t strip_k = 0;
	for (int64_t i = 0; i < count; i++) {
		const double *op = O + i * stride;
		const int64_t kind = int64_t(op[0]);
		const int64_t x = int64_t(op[1]);
		const int64_t z = int64_t(op[2]);
		const bool along_x = op[3] != 0.0;
		const int64_t face = int64_t(op[4]);
		const int64_t tile = int64_t(op[5]);
		if (kind == 0) {
			Dictionary d;
			d[kx] = x;
			d[ky] = op[6];
			d[kz] = z;
			d[kdx] = 1.0;
			d[kdy] = op[7];
			d[kdz] = 1.0;
			d[kuw] = 1.0;
			d[kuh] = op[7];
			d[ktype] = tile;
			d[kface] = face;
			out.push_back(d);
			continue;
		}
		const int64_t base = strip_k * 2 * n;
		strip_k++;
		if (base + 2 * n > hs) {
			break;
		}
		for (int64_t m = 0; m < n; m++) {
			const double y_hi = H[base + m];
			const double y_lo = H[base + n + m];
			if (y_hi - y_lo <= 0.02) {
				continue;
			}
			double qx = double(x);
			double qz = double(z);
			double dw = 1.0;
			double dd = 1.0;
			if (along_x) {
				qx = double(x) + double(m) / nf;
				dw = 1.0 / nf;
			} else {
				qz = double(z) + double(m) / nf;
				dd = 1.0 / nf;
			}
			Dictionary d;
			d[kx] = qx;
			d[ky] = y_lo;
			d[kz] = qz;
			d[kdx] = dw;
			d[kdy] = (y_hi - y_lo) / layer;
			d[kdz] = dd;
			d[kuw] = along_x ? dw : dd;
			d[kuh] = (y_hi - y_lo) / layer;
			d[ktype] = tile;
			d[kface] = face;
			if (y_hi - y_lo <= layer * 0.5 + 0.001) {
				d[kwr] = true;
			}
			out.push_back(d);
		}
	}
	return out;
}