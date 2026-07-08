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
		out[vec2i_from_key(str(key))] = src[key]
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
	if value is Array and value.size() == 2 and value[0] is int and value[1] is int:
		return Vector2i(int(value[0]), int(value[1]))
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