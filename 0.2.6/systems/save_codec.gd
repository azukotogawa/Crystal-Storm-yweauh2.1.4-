class_name SaveCodec
extends RefCounted

## Shared JSON-safe encoding for save snapshots.


static func vec2i_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


static func vec2i_from_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


static func encode_vec2i_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for key_variant in src.keys():
		var key: Vector2i = key_variant
		out[vec2i_key(key)] = src[key_variant]
	return out


static func decode_vec2i_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for key in src.keys():
		var v = src[key]
		# JSON.parse turns ints into floats; keep ints for layer/tile maps when whole.
		if v is float and is_equal_approx(float(v), roundf(float(v))):
			out[vec2i_from_key(str(key))] = int(roundf(float(v)))
		else:
			out[vec2i_from_key(str(key))] = v
	return out


static func encode_vec2i_array(cells: Array) -> Array:
	var out: Array = []
	for cell_variant in cells:
		var cell: Vector2i = cell_variant
		out.append([cell.x, cell.y])
	return out


static func decode_vec2i_array(data: Array) -> Array:
	var out: Array = []
	for entry in data:
		if entry is Array and entry.size() >= 2:
			out.append(Vector2i(int(entry[0]), int(entry[1])))
	return out


static func _is_numeric_pair_component(v: Variant) -> bool:
	return v is int or v is float


## True when value is a 2-element numeric pair (JSON-safe Vector2i after parse).
static func is_vec2i_pair(value: Variant) -> bool:
	if value is Vector2i:
		return true
	if value is Array and value.size() == 2 \
			and _is_numeric_pair_component(value[0]) \
			and _is_numeric_pair_component(value[1]):
		return true
	return false


static func to_vec2i(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(int(value.x), int(value.y))
	if value is Array and value.size() >= 2 \
			and _is_numeric_pair_component(value[0]) \
			and _is_numeric_pair_component(value[1]):
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


static func sanitize_feature_value(value: Variant) -> Variant:
	if value is Vector2i:
		return [value.x, value.y]
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			out[k] = sanitize_feature_value(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(sanitize_feature_value(item))
		return arr
	return value


static func restore_feature_value(value: Variant) -> Variant:
	# JSON.parse yields floats for numbers — accept int|float pairs as Vector2i.
	if is_vec2i_pair(value) and value is Array:
		return to_vec2i(value)
	if value is Dictionary:
		var out := {}
		for k in value.keys():
			out[k] = restore_feature_value(value[k])
		return out
	if value is Array:
		var arr: Array = []
		for item in value:
			arr.append(restore_feature_value(item))
		return arr
	return value