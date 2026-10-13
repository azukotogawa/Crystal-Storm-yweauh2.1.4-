extends SceneTree
## Author the Crystal Storm stone_wall battlement mesh + albedo atlas.
##
## Mesh is in voxel-column units (width ≈ 1 column, Y up from ground).
## Runtime bind multiplies XZ by WorldSettings.voxel_scale and uses a short Y cap.
##
## Usage: godot --headless --path . -s assets/structures/stone_wall/author_stone_wall.gd
##
## This is a real authored asset (running-bond masonry, crenellations, collar),
## not a runtime multi-box silhouette.

const HERE := "res://assets/structures/stone_wall"
const SRC := HERE + "/src"

# Atlas UV regions in OpenGL space (v=0 bottom), matching wood_wall layout.
const UV_FACE := Vector4(0.02, 0.02, 0.48, 0.98)
const UV_CAP := Vector4(0.52, 0.52, 0.98, 0.98)
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
	_build_albedo(abs_here.path_join("stone_wall_albedo.png"), 256)
	_build_mesh()
	_write_obj(abs_here.path_join("stone_wall.obj"), abs_here.path_join("stone_wall.mtl"))
	quit(0)


func _build_albedo(path: String, size: int) -> void:
	var field := _load_src("fieldstone.jpg")
	var cap := _load_src("capstone.jpg")
	var moss := _load_src("moss.jpg")
	var dirt := _load_src("dirt.jpg")
	if field == null or cap == null or moss == null or dirt == null:
		push_error("stone_wall author: missing src texture")
		quit(1)
		return
	_make_seamless(field, 20)
	_make_seamless(cap, 16)
	_make_seamless(moss, 18)
	_make_seamless(dirt, 16)
	field.resize(size, size, Image.INTERPOLATE_LANCZOS)
	cap.resize(size, size, Image.INTERPOLATE_LANCZOS)
	moss.resize(size, size, Image.INTERPOLATE_LANCZOS)
	dirt.resize(size, size, Image.INTERPOLATE_LANCZOS)

	var atlas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.28, 0.28, 0.30, 1.0))
	var half := size / 2
	var q := size / 4
	var face := field.duplicate()
	face.resize(half, size, Image.INTERPOLATE_LANCZOS)
	var cap_q := cap.duplicate()
	cap_q.resize(half, half, Image.INTERPOLATE_LANCZOS)
	var moss_q := moss.duplicate()
	moss_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	var dirt_q := dirt.duplicate()
	dirt_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	atlas.blit_rect(face, Rect2i(0, 0, half, size), Vector2i(0, 0))
	atlas.blit_rect(cap_q, Rect2i(0, 0, half, half), Vector2i(half, 0))
	atlas.blit_rect(moss_q, Rect2i(0, 0, half, q), Vector2i(half, half))
	atlas.blit_rect(dirt_q, Rect2i(0, 0, half, q), Vector2i(half, half + q))
	# Lift the face slightly so mortar/stone contrast survives mipmaps at iso zoom.
	_tint_rect(atlas, Rect2i(0, 0, half, size), Color(0.88, 0.90, 0.95), 0.10)
	atlas.save_png(path)
	print("wrote albedo %s %dx%d" % [path, atlas.get_width(), atlas.get_height()])


func _load_src(name: String) -> Image:
	var res_path := SRC + "/" + name
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		push_error("missing %s" % abs_path)
		return null
	var img := Image.load_from_file(abs_path)
	if img == null:
		push_error("failed to load %s" % abs_path)
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
			var a := im.get_pixel(x, y)
			var b := im.get_pixel(w - blend + x, y)
			im.set_pixel(x, y, a.lerp(b, t * 0.55))
	for y in blend:
		var t := 1.0 - float(y) / float(blend)
		for x in w:
			var a := im.get_pixel(x, y)
			var b := im.get_pixel(x, h - blend + y)
			im.set_pixel(x, y, a.lerp(b, t * 0.55))


func _tint_rect(im: Image, r: Rect2i, tint: Color, amount: float) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if x < 0 or y < 0 or x >= im.get_width() or y >= im.get_height():
				continue
			im.set_pixel(x, y, im.get_pixel(x, y).lerp(tint, amount))


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


func _hash01(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


## Beveled ashlar block. Size is full extents. Bevel insets the top face.
func add_block(center: Vector3, size: Vector3, region: Vector4, uv_shift: Vector2, bevel: float = 0.012, top_region: Vector4 = Vector4.ZERO) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, minf(hy, hz)) * 0.45)
	var y0 := center.y - hy
	var y1 := center.y + hy
	var x0 := center.x - hx
	var x1 := center.x + hx
	var z0 := center.z - hz
	var z1 := center.z + hz
	# Bottom rectangle
	var b00 := Vector3(x0, y0, z0)
	var b10 := Vector3(x1, y0, z0)
	var b11 := Vector3(x1, y0, z1)
	var b01 := Vector3(x0, y0, z1)
	# Top rectangle inset
	var t00 := Vector3(x0 + b, y1, z0 + b)
	var t10 := Vector3(x1 - b, y1, z0 + b)
	var t11 := Vector3(x1 - b, y1, z1 - b)
	var t01 := Vector3(x0 + b, y1, z1 - b)
	# Mid ring at near-top (for a lip)
	var m00 := Vector3(x0, y1 - b, z0)
	var m10 := Vector3(x1, y1 - b, z0)
	var m11 := Vector3(x1, y1 - b, z1)
	var m01 := Vector3(x0, y1 - b, z1)

	# Large UV window so each face shows a few big stones, not a pebble field.
	var su := clampf(size.x * 0.55, 0.22, 0.55)
	var sv := clampf(size.y * 0.50, 0.18, 0.50)
	var u0 := fposmod(uv_shift.x, 0.35)
	var v0 := fposmod(uv_shift.y, 0.35)
	var u1 := u0 + su
	var v1 := v0 + sv

	# -Z face (back)
	_add_quad(b00, b10, m10, m00, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	# +Z face (front — iso readable)
	_add_quad(b11, b01, m01, m11, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	# -X
	_add_quad(b01, b00, m00, m01, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	# +X
	_add_quad(b10, b11, m11, m10, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	# Bottom
	_add_quad(b01, b11, b10, b00, _remap(0.15, 0.15, UV_DIRT), _remap(0.85, 0.15, UV_DIRT), _remap(0.85, 0.85, UV_DIRT), _remap(0.15, 0.85, UV_DIRT))
	# Bevel ring to top
	_add_quad(m00, m10, t10, t00, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m10, m11, t11, t10, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m11, m01, t01, t11, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m01, m00, t00, t01, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	# Top
	var top_r := top_region if top_region != Vector4.ZERO else UV_CAP
	_add_quad(t00, t10, t11, t01, _remap(0.08 + uv_shift.x * 0.2, 0.08, top_r), _remap(0.92, 0.08, top_r), _remap(0.92, 0.92, top_r), _remap(0.08, 0.92, top_r))


func add_earth_collar() -> void:
	var rings := 4
	var segs := 16
	var radii := [0.16, 0.30, 0.40, 0.50]
	var heights := [0.10, 0.075, 0.04, 0.0]
	var pts: Array = []
	for ri in rings:
		var r: float = radii[ri]
		var h: float = heights[ri]
		var ring: Array[Vector3] = []
		for s in segs:
			var a := float(s) / float(segs) * TAU
			var rx := r * 1.08
			var rz := r * 0.78
			var jitter := 0.014 * sin(a * 3.0 + r * 9.0)
			ring.append(Vector3(cos(a) * (rx + jitter), h, sin(a) * (rz + jitter * 0.45)))
		pts.append(ring)
	for ri in range(rings - 1):
		var v0 := float(ri) / float(rings - 1)
		var v1 := float(ri + 1) / float(rings - 1)
		var region := UV_DIRT if ri >= 1 else UV_MOSS
		for s in segs:
			var s1 := (s + 1) % segs
			var u0 := float(s) / float(segs)
			var u1 := float(s + 1) / float(segs)
			_add_quad(
				pts[ri][s], pts[ri][s1], pts[ri + 1][s1], pts[ri + 1][s],
				_remap(u0, v0, region), _remap(u1, v0, region),
				_remap(u1, v1, region), _remap(u0, v1, region)
			)
	var center := Vector3(0.0, heights[0], 0.0)
	for s in segs:
		var s1 := (s + 1) % segs
		_add_tri(
			center, pts[0][s], pts[0][s1],
			_remap(0.5, 0.5, UV_MOSS),
			_remap(0.5 + 0.4 * cos(float(s) / float(segs) * TAU), 0.5 + 0.4 * sin(float(s) / float(segs) * TAU), UV_MOSS),
			_remap(0.5 + 0.4 * cos(float(s1) / float(segs) * TAU), 0.5 + 0.4 * sin(float(s1) / float(segs) * TAU), UV_MOSS)
		)


func _course_blocks(y0: float, y1: float, count: int, offset: bool, z_half: float, course_i: int) -> void:
	var x_min := -0.475
	var x_max := 0.475
	var gap := 0.016
	var span := x_max - x_min
	var usable := span - gap * float(count - 1)
	var base_w := usable / float(count)
	# Running bond: shift the first block so joints do not stack.
	var shift := (base_w * 0.38) if offset else 0.0
	var x := x_min + shift * 0.15
	# If offset, first block is shorter so the last still fits.
	for i in count:
		var t := float(i)
		var w_jit := 1.0 + (_hash01(course_i, t) - 0.5) * 0.18
		var z_jit := 1.0 + (_hash01(t, course_i + 3.0) - 0.5) * 0.16
		var y_jit := (_hash01(t + 2.0, course_i) - 0.5) * 0.012
		var remain := x_max - x - gap * float(count - 1 - i)
		var slots_left := count - i
		var w := clampf(base_w * w_jit, base_w * 0.72, remain - base_w * 0.55 * float(slots_left - 1))
		if i == count - 1:
			w = x_max - x
		var h := (y1 - y0) + y_jit
		var z_ext := z_half * z_jit
		# Front-face push so the iso camera reads individual stones, not a slab.
		var z_push := (_hash01(course_i + 7.0, t) - 0.35) * 0.018
		var cx := x + w * 0.5
		var cy := y0 + h * 0.5
		var cz := z_push
		add_block(
			Vector3(cx, cy, cz),
			Vector3(w, h, z_ext * 2.0),
			UV_FACE,
			Vector2(_hash01(t, course_i), _hash01(course_i, t + 4.0)),
			0.011,
			UV_CAP if course_i >= 3 else UV_FACE
		)
		x += w + gap


func _build_mesh() -> void:
	_v.clear()
	_vt.clear()
	_vn.clear()
	_f.clear()
	add_earth_collar()
	# Plinth — wider, heavier base (defensive footing).
	add_block(
		Vector3(-0.24, 0.075, 0.0),
		Vector3(0.47, 0.15, 0.50),
		UV_FACE,
		Vector2(0.1, 0.05),
		0.014,
		UV_DIRT
	)
	add_block(
		Vector3(0.24, 0.072, 0.01),
		Vector3(0.47, 0.144, 0.48),
		UV_FACE,
		Vector2(0.4, 0.2),
		0.014,
		UV_DIRT
	)
	# Three chunky courses (running bond). Big stones read at iso zoom.
	_course_blocks(0.16, 0.54, 2, false, 0.215, 0)
	_course_blocks(0.54, 0.92, 3, true, 0.200, 1)
	_course_blocks(0.92, 1.22, 2, false, 0.190, 2)
	# Wall-walk slab (flat top the merlons sit on).
	add_block(
		Vector3(0.0, 1.245, 0.0),
		Vector3(0.96, 0.055, 0.42),
		UV_CAP,
		Vector2(0.2, 0.15),
		0.008,
		UV_CAP
	)
	# Two wide merlons + one center embrasure — reads as a battlement, not a comb.
	var merlons := [
		{"x": -0.27, "w": 0.38, "h": 0.64, "z": 0.44},
		{"x": 0.27, "w": 0.38, "h": 0.56, "z": 0.43},
	]
	for i in merlons.size():
		var m: Dictionary = merlons[i]
		var h: float = float(m.h)
		var y0 := 1.28
		add_block(
			Vector3(float(m.x), y0 + h * 0.5, 0.0),
			Vector3(float(m.w), h, float(m.z)),
			UV_FACE,
			Vector2(0.15 * float(i), 0.55),
			0.013,
			UV_CAP
		)
		# Capstone lid, slightly oversized — reads as dressed coping.
		add_block(
			Vector3(float(m.x), y0 + h + 0.028, 0.0),
			Vector3(float(m.w) + 0.04, 0.055, float(m.z) + 0.04),
			UV_CAP,
			Vector2(0.3 * float(i), 0.1),
			0.006,
			UV_CAP
		)


func _write_obj(obj_path: String, mtl_path: String) -> void:
	var mtl := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mtl == null:
		push_error("cannot write %s" % mtl_path)
		quit(1)
		return
	mtl.store_string("newmtl stone_wall_mat\nKd 1.00 1.00 1.00\nmap_Kd stone_wall_albedo.png\n")
	mtl.close()
	var f := FileAccess.open(obj_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % obj_path)
		quit(1)
		return
	f.store_line("# Crystal Storm authored stone_wall battlement")
	f.store_line("mtllib stone_wall.mtl")
	f.store_line("usemtl stone_wall_mat")
	f.store_line("o StoneWall")
	f.store_line("g stone_wall")
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
