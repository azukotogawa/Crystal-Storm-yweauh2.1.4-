extends SceneTree
## Author the Crystal Storm ruin_pillar landmark mesh + albedo atlas.
##
## Mesh is in voxel-column units (Y up from unraised ground).
## Runtime bind multiplies XZ by voxel_scale; Y stays 1.0 — a tall broken
## column, not a wall cap and not a gate arch.
##
## Usage: godot --headless --path . -s assets/structures/ruin_pillar/author_ruin_pillar.gd

const HERE := "res://assets/structures/ruin_pillar"
const SRC := HERE + "/src"

const UV_COL := Vector4(0.02, 0.02, 0.48, 0.98)
const UV_RUB := Vector4(0.52, 0.52, 0.98, 0.98)
const UV_MOSS := Vector4(0.52, 0.27, 0.98, 0.48)
const UV_DIRT := Vector4(0.52, 0.02, 0.98, 0.23)

var _v: Array[Vector3] = []
var _vt: Array[Vector2] = []
var _vn: Array[Vector3] = []
var _f: Array[Vector3i] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var abs_here := ProjectSettings.globalize_path(HERE)
	DirAccess.make_dir_recursive_absolute(abs_here)
	DirAccess.make_dir_recursive_absolute(abs_here.path_join("src"))
	_build_albedo(abs_here.path_join("ruin_pillar_albedo.png"), 256)
	_build_mesh()
	_write_obj(abs_here.path_join("ruin_pillar.obj"), abs_here.path_join("ruin_pillar.mtl"))
	quit(0)


func _build_albedo(path: String, size: int) -> void:
	var col := _load_src("column.jpg")
	var rub := _load_src("rubble.jpg")
	var moss := _load_src("moss.jpg")
	var dirt := _load_src("dirt.jpg")
	if col == null or rub == null or moss == null or dirt == null:
		push_error("ruin_pillar author: missing src")
		quit(1)
		return
	_make_seamless(col, 16)
	_make_seamless(rub, 16)
	_make_seamless(moss, 16)
	_make_seamless(dirt, 16)
	col.resize(size, size, Image.INTERPOLATE_LANCZOS)
	rub.resize(size, size, Image.INTERPOLATE_LANCZOS)
	moss.resize(size, size, Image.INTERPOLATE_LANCZOS)
	dirt.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var atlas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.42, 0.34, 0.26, 1.0))
	var half := size / 2
	var q := size / 4
	var face := col.duplicate()
	face.resize(half, size, Image.INTERPOLATE_LANCZOS)
	var rub_q := rub.duplicate()
	rub_q.resize(half, half, Image.INTERPOLATE_LANCZOS)
	var moss_q := moss.duplicate()
	moss_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	var dirt_q := dirt.duplicate()
	dirt_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	atlas.blit_rect(face, Rect2i(0, 0, half, size), Vector2i(0, 0))
	atlas.blit_rect(rub_q, Rect2i(0, 0, half, half), Vector2i(half, 0))
	atlas.blit_rect(moss_q, Rect2i(0, 0, half, q), Vector2i(half, half))
	atlas.blit_rect(dirt_q, Rect2i(0, 0, half, q), Vector2i(half, half + q))
	atlas.save_png(path)
	print("wrote albedo %s %dx%d" % [path, atlas.get_width(), atlas.get_height()])


func _load_src(name: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(SRC + "/" + name)
	if not FileAccess.file_exists(abs_path):
		push_error("missing %s" % abs_path)
		return null
	var img := Image.load_from_file(abs_path)
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _make_seamless(im: Image, blend: int) -> void:
	var w := im.get_width()
	var h := im.get_height()
	blend = mini(blend, mini(w, h) / 4)
	for x in blend:
		var t := 1.0 - float(x) / float(blend)
		for y in h:
			im.set_pixel(x, y, im.get_pixel(x, y).lerp(im.get_pixel(w - blend + x, y), t * 0.55))
	for y in blend:
		var t := 1.0 - float(y) / float(blend)
		for x in w:
			im.set_pixel(x, y, im.get_pixel(x, y).lerp(im.get_pixel(x, h - blend + y), t * 0.55))


func _remap(u: float, v: float, region: Vector4) -> Vector2:
	return Vector2(lerpf(region.x, region.z, u), lerpf(region.y, region.w, v))


func _add_tri(p0: Vector3, p1: Vector3, p2: Vector3, uv0: Vector2, uv1: Vector2, uv2: Vector2) -> void:
	var n := (p1 - p0).cross(p2 - p0)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var i0 := _v.size() + 1
	_v.append(p0)
	_v.append(p1)
	_v.append(p2)
	_vt.append(uv0)
	_vt.append(uv1)
	_vt.append(uv2)
	_vn.append(n)
	_vn.append(n)
	_vn.append(n)
	_f.append(Vector3i(i0, i0 + 1, i0 + 2))


func _add_quad(p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3, uv00: Vector2, uv10: Vector2, uv11: Vector2, uv01: Vector2) -> void:
	_add_tri(p00, p10, p11, uv00, uv10, uv11)
	_add_tri(p00, p11, p01, uv00, uv11, uv01)


func add_block(center: Vector3, size: Vector3, region: Vector4, uv_shift: Vector2, bevel: float = 0.01, top_region: Vector4 = Vector4.ZERO) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, minf(hy, hz)) * 0.4)
	var y0 := center.y - hy
	var y1 := center.y + hy
	var x0 := center.x - hx
	var x1 := center.x + hx
	var z0 := center.z - hz
	var z1 := center.z + hz
	var b00 := Vector3(x0, y0, z0)
	var b10 := Vector3(x1, y0, z0)
	var b11 := Vector3(x1, y0, z1)
	var b01 := Vector3(x0, y0, z1)
	var t00 := Vector3(x0 + b, y1, z0 + b)
	var t10 := Vector3(x1 - b, y1, z0 + b)
	var t11 := Vector3(x1 - b, y1, z1 - b)
	var t01 := Vector3(x0 + b, y1, z1 - b)
	var m00 := Vector3(x0, y1 - b, z0)
	var m10 := Vector3(x1, y1 - b, z0)
	var m11 := Vector3(x1, y1 - b, z1)
	var m01 := Vector3(x0, y1 - b, z1)
	var su := clampf(size.x * 0.7, 0.2, 0.9)
	var sv := clampf(size.y * 0.7, 0.15, 0.9)
	var u0 := fposmod(uv_shift.x, 0.3)
	var v0 := fposmod(uv_shift.y, 0.3)
	var u1 := u0 + su
	var v1 := v0 + sv
	_add_quad(b00, b10, m10, m00, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b11, b01, m01, m11, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b01, b00, m00, m01, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b10, b11, m11, m10, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b01, b11, b10, b00, _remap(0.2, 0.2, UV_DIRT), _remap(0.8, 0.2, UV_DIRT), _remap(0.8, 0.8, UV_DIRT), _remap(0.2, 0.8, UV_DIRT))
	_add_quad(m00, m10, t10, t00, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m10, m11, t11, t10, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m11, m01, t01, t11, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m01, m00, t00, t01, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	var top_r := top_region if top_region != Vector4.ZERO else UV_RUB
	_add_quad(t00, t10, t11, t01, _remap(0.1, 0.1, top_r), _remap(0.9, 0.1, top_r), _remap(0.9, 0.9, top_r), _remap(0.1, 0.9, top_r))


func add_shaft(cx: float, cz: float, r0: float, r1: float, y0: float, y1: float, lean_x: float, lean_z: float, sides: int = 8) -> void:
	var rings := 7
	var pts: Array = []
	var ys: Array[float] = []
	for i in rings:
		var t := float(i) / float(rings - 1)
		var y := lerpf(y0, y1, t)
		var r := lerpf(r0, r1, t)
		ys.append(y)
		var ring: Array[Vector3] = []
		for s in sides:
			var a := (float(s) / float(sides)) * TAU + 0.2
			var px := cx + lean_x * t + cos(a) * r
			var pz := cz + lean_z * t + sin(a) * r
			ring.append(Vector3(px, y, pz))
		pts.append(ring)
	for ri in range(rings - 1):
		var v0 := ys[ri] / maxf(y1, 0.01)
		var v1 := ys[ri + 1] / maxf(y1, 0.01)
		for s in sides:
			var s1 := (s + 1) % sides
			var u0 := float(s) / float(sides)
			var u1 := float(s + 1) / float(sides)
			_add_quad(
				pts[ri][s], pts[ri][s1], pts[ri + 1][s1], pts[ri + 1][s],
				_remap(u0, v0, UV_COL), _remap(u1, v0, UV_COL),
				_remap(u1, v1, UV_COL), _remap(u0, v1, UV_COL)
			)
	# Bottom cap
	var c0 := Vector3(cx, y0, cz)
	for s in sides:
		var s1 := (s + 1) % sides
		_add_tri(c0, pts[0][s1], pts[0][s], _remap(0.5, 0.5, UV_RUB), _remap(0.8, 0.2, UV_RUB), _remap(0.2, 0.2, UV_RUB))
	# Jagged broken top — skip a couple of sides so it is not a flat cut.
	var c1 := Vector3(cx + lean_x, y1, cz + lean_z)
	for s in sides:
		if s == 2 or s == 3:
			continue
		var s1 := (s + 1) % sides
		_add_tri(c1, pts[rings - 1][s], pts[rings - 1][s1], _remap(0.5, 0.5, UV_RUB), _remap(0.8, 0.8, UV_RUB), _remap(0.2, 0.8, UV_RUB))


func _build_mesh() -> void:
	_v.clear()
	_vt.clear()
	_vn.clear()
	_f.clear()

	# Rubble collar — wider than the shaft, not a wall slab.
	add_block(Vector3(0.02, 0.08, 0.00), Vector3(0.72, 0.16, 0.70), UV_RUB, Vector2(0.1, 0.1), 0.02, UV_MOSS)
	add_block(Vector3(-0.28, 0.07, 0.18), Vector3(0.22, 0.14, 0.20), UV_RUB, Vector2(0.4, 0.2), 0.012, UV_DIRT)
	add_block(Vector3(0.30, 0.06, -0.16), Vector3(0.20, 0.12, 0.18), UV_RUB, Vector2(0.2, 0.5), 0.01, UV_DIRT)
	add_block(Vector3(0.18, 0.05, 0.28), Vector3(0.16, 0.10, 0.16), UV_MOSS, Vector2(0.0, 0.3), 0.008, UV_MOSS)

	# Main broken column — thin, leaning, taller than a gate.
	add_shaft(-0.06, 0.04, 0.22, 0.155, 0.16, 2.18, 0.10, -0.05, 8)
	# Capital ring near the break.
	add_block(Vector3(0.02, 1.72, 0.00), Vector3(0.42, 0.10, 0.42), UV_COL, Vector2(0.3, 0.6), 0.012, UV_RUB)
	# Jagged remaining teeth at the break.
	add_block(Vector3(-0.04, 2.28, 0.02), Vector3(0.16, 0.22, 0.14), UV_COL, Vector2(0.1, 0.8), 0.01, UV_RUB)
	add_block(Vector3(0.10, 2.22, -0.06), Vector3(0.12, 0.14, 0.12), UV_RUB, Vector2(0.5, 0.2), 0.008, UV_RUB)
	# Fallen fragment at the foot — landmark rubble, not a merlon.
	add_block(Vector3(0.34, 0.16, 0.08), Vector3(0.28, 0.18, 0.16), UV_COL, Vector2(0.2, 0.1), 0.012, UV_RUB)
	add_block(Vector3(0.38, 0.28, 0.02), Vector3(0.18, 0.12, 0.14), UV_RUB, Vector2(0.4, 0.4), 0.008, UV_MOSS)


func _write_obj(obj_path: String, mtl_path: String) -> void:
	var mtl := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mtl == null:
		push_error("cannot write %s" % mtl_path)
		quit(1)
		return
	mtl.store_string("newmtl ruin_pillar_mat\nKd 1.00 1.00 1.00\nmap_Kd ruin_pillar_albedo.png\n")
	mtl.close()
	var f := FileAccess.open(obj_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % obj_path)
		quit(1)
		return
	f.store_line("# Crystal Storm authored ruin_pillar landmark")
	f.store_line("mtllib ruin_pillar.mtl")
	f.store_line("usemtl ruin_pillar_mat")
	f.store_line("o RuinPillar")
	f.store_line("g ruin_pillar")
	for p in _v:
		f.store_line("v %.6f %.6f %.6f" % [p.x, p.y, p.z])
	for uv in _vt:
		f.store_line("vt %.6f %.6f" % [uv.x, uv.y])
	for n in _vn:
		f.store_line("vn %.6f %.6f %.6f" % [n.x, n.y, n.z])
	for tri in _f:
		f.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [
			tri.x, tri.x, tri.x, tri.y, tri.y, tri.y, tri.z, tri.z, tri.z
		])
	f.close()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for p in _v:
		mn = mn.min(p)
		mx = mx.max(p)
	print(
		"wrote %s verts=%d tris=%d aabb=(%.3f,%.3f,%.3f)-(%.3f,%.3f,%.3f)"
		% [obj_path, _v.size(), _f.size(), mn.x, mn.y, mn.z, mx.x, mx.y, mx.z]
	)
