extends SceneTree

const _B = preload("res://helpers/chunk_surface_mesh_builder.gd")

var _failed: int = 0
var _faces: int = 0


func _init() -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		_check_flanks(d)
	for a in [Vector2i(1, 0), Vector2i(-1, 0)]:
		for b in [Vector2i(0, 1), Vector2i(0, -1)]:
			_check_corner(a, b)
	print("faces checked=%d failed=%d" % [_faces, _failed])
	if _failed == 0:
		print("All ramp UV tests OK")
		quit(0)
	else:
		push_error("verify_ramp_uvs: %d failure(s)" % _failed)
		quit(1)


func _arrays(n: int) -> Array:
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var ix := PackedInt32Array()
	v.resize(n * 4)
	nr.resize(n * 4)
	uv.resize(n * 4)
	c.resize(n * 4)
	ix.resize(n * 6)
	return [v, nr, uv, c, ix]


func _check_face(label: String, v: PackedVector3Array, uv: PackedVector2Array, base: int) -> void:
	var plo := Vector3(INF, INF, INF)
	var phi := -plo
	var ulo := Vector2(INF, INF)
	var uhi := -ulo
	for k in 4:
		plo = plo.min(v[base + k])
		phi = phi.max(v[base + k])
		ulo = ulo.min(uv[base + k])
		uhi = uhi.max(uv[base + k])
	var ext := phi - plo
	var dims := 0
	for e in [ext.x, ext.y, ext.z]:
		if e > 0.01:
			dims += 1
	if dims < 2:
		return
	_faces += 1
	var span := uhi - ulo
	if span.x < 0.01 or span.y < 0.01:
		_failed += 1
		print("STRIPE %s face@%d ext=%s uv_span=%s" % [label, base, ext, span])


func _check_flanks(d: Vector2i) -> void:
	var a := _arrays(64)
	var n: int = _B._write_cardinal_flanks(a[0], a[1], a[2], a[3], a[4], 0, 0, 10.0, -6.0, 2.0, 2.0, 2.0, 4.0, d, Vector2i(1, 1), 1.0, true, true)
	for i in n:
		_check_face("flank%s" % d, a[0], a[2], i * 4)


func _check_corner(da: Vector2i, db: Vector2i) -> void:
	var a := _arrays(2)
	_B._write_corner_ramp(a[0], a[1], a[2], a[3], a[4], 0, 0, 10.0, -6.0, 2.0, 2.0, 2.0, 4.0, da, db, Vector2i(1, 1), 1.0)
	_check_face("corner_top%s%s" % [da, db], a[0], a[2], 0)
	_check_face("corner_wall%s%s" % [da, db], a[0], a[2], 4)
