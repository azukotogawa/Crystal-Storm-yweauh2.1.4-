#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {
class CsNativeMesher : public RefCounted {
	GDCLASS(CsNativeMesher, RefCounted)
protected:
	static void _bind_methods();
public:
	int64_t version() const;
	Array waved_tops(int64_t x0, int64_t z0, int64_t cw, int64_t ch, int64_t n, double layer,
			const PackedInt32Array &tiles, const PackedInt32Array &atlas, const PackedInt32Array &base_keys,
			const PackedInt32Array &col_steps, const PackedInt32Array &reps, const PackedInt32Array &faces) const;
};
}
