#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {
class CsNativeMesher : public RefCounted {
	GDCLASS(CsNativeMesher, RefCounted)
protected:
	static void _bind_methods();
public:
	int64_t version() const;
	PackedInt32Array quad_atlas(const Array &quads, int64_t base_x, int64_t base_z) const;
	Dictionary ao_grid(const Array &halo, bool has_halo, int64_t size) const;
	Array waved_tops(int64_t x0, int64_t z0, int64_t cw, int64_t ch, int64_t n, double layer,
			const PackedInt32Array &tiles, const PackedInt32Array &atlas, const PackedInt32Array &base_keys,
			const PackedInt32Array &col_steps, const PackedInt32Array &reps, const PackedInt32Array &faces) const;
	Dictionary surface_arrays(const Array &quads, const PackedInt32Array &atlas, const PackedFloat64Array &grid,
			double chunk_ox, double chunk_oz, double voxel_s, double layer, bool ao_on, int64_t curve_strips) const;
};
}
