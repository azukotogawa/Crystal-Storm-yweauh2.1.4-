extends RefCounted

const T_INT32 := 0
const T_INT64 := 1
const T_F32 := 2
const T_F64 := 3
const T_BOOL := 4
const T_VAR := 5


static func encode(plan: Array) -> PackedByteArray:
	var shapes: Array = []
	var shape_ids: Dictionary = {}
	var quad_shape := PackedInt32Array()
	quad_shape.resize(plan.size())
	var cols: Dictionary = {}
	for i in plan.size():
		var q: Dictionary = plan[i]
		var keys: Array = q.keys()
		var sig := var_to_str(keys)
		var sid: int = int(shape_ids.get(sig, -1))
		if sid < 0:
			sid = shapes.size()
			shape_ids[sig] = sid
			shapes.append(keys)
		quad_shape[i] = sid
		for k in keys:
			if not cols.has(k):
				cols[k] = []
			(cols[k] as Array).append(q[k])
	var key_list: Array = cols.keys()
	var packed_cols: Array = []
	for k in key_list:
		packed_cols.append(_pack(cols[k]))
	var payload := var_to_bytes([shapes, quad_shape, key_list, packed_cols])
	var comp := payload.compress(FileAccess.COMPRESSION_ZSTD)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, payload.size())
	out.encode_u32(4, comp.size())
	out.append_array(comp)
	return out


static func _pack(vals: Array) -> Array:
	if vals.is_empty():
		return [T_VAR, vals]
	var first: int = typeof(vals[0])
	for v in vals:
		if typeof(v) != first:
			return [T_VAR, vals]
	if first == TYPE_INT:
		for v in vals:
			if int(v) < -2147483648 or int(v) > 2147483647:
				return [T_INT64, PackedInt64Array(vals)]
		return [T_INT32, PackedInt32Array(vals)]
	if first == TYPE_FLOAT:
		var f32 := PackedFloat32Array(vals)
		for i in vals.size():
			if float(f32[i]) != float(vals[i]):
				return [T_F64, PackedFloat64Array(vals)]
		return [T_F32, f32]
	if first == TYPE_BOOL:
		var b := PackedByteArray()
		b.resize(vals.size())
		for i in vals.size():
			b[i] = 1 if bool(vals[i]) else 0
		return [T_BOOL, b]
	return [T_VAR, vals]


static func decode(buf: PackedByteArray) -> Array:
	if buf.size() < 8:
		return []
	var raw_n: int = buf.decode_u32(0)
	var comp_n: int = buf.decode_u32(4)
	if buf.size() < 8 + comp_n:
		return []
	var payload := buf.slice(8, 8 + comp_n).decompress(raw_n, FileAccess.COMPRESSION_ZSTD)
	if payload.size() != raw_n:
		return []
	var d = bytes_to_var(payload)
	if typeof(d) != TYPE_ARRAY or (d as Array).size() != 4:
		return []
	var shapes: Array = d[0]
	var quad_shape: PackedInt32Array = d[1]
	var key_list: Array = d[2]
	var packed_cols: Array = d[3]
	var key_index: Dictionary = {}
	var datas: Array = []
	var is_bool := PackedByteArray()
	is_bool.resize(key_list.size())
	for j in key_list.size():
		key_index[key_list[j]] = j
		datas.append(packed_cols[j][1])
		is_bool[j] = 1 if int(packed_cols[j][0]) == T_BOOL else 0
	var shape_cols: Array = []
	for s in shapes:
		var idx := PackedInt32Array()
		for k in s:
			idx.append(int(key_index[k]))
		shape_cols.append(idx)
	var cur := PackedInt32Array()
	cur.resize(key_list.size())
	cur.fill(0)
	var n: int = quad_shape.size()
	var plan: Array = []
	plan.resize(n)
	for i in n:
		var sid: int = quad_shape[i]
		var keys: Array = shapes[sid]
		var idx: PackedInt32Array = shape_cols[sid]
		var q := {}
		for j in keys.size():
			var c: int = idx[j]
			var v = datas[c][cur[c]]
			if is_bool[c] == 1:
				v = v != 0
			q[keys[j]] = v
			cur[c] += 1
		plan[i] = q
	return plan
