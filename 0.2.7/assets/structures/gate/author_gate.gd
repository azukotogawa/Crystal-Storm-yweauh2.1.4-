extends SceneTree
## Author the Crystal Storm gate passage mesh + albedo atlas.
##
## Mesh is in voxel-column units (width ≈ 1 column, Y up from ground).
## Runtime bind multiplies XZ by voxel_scale. Y stays 1.0 — gate does not
## raise terrain, so this is a full-height arch, not a short wall cap.
##
## Usage: godot --headless --path . -s assets/structures/gate/author_gate.gd
##
## Open passage (two dressed posts + heavy lintel). Not a palisade,
## not a masonry wall, not a runtime multi-box.

const HERE := "res://assets/structures/gate"
const SRC := HERE + "/src"

# Atlas UV regions in OpenGL space (v=0 bottom), same layout as wood/stone.
const UV_WOOD := Vector4(0.02, 0.02, 0.48, 0.98)
const UV_END := Vector4(0.52, 0.52, 0.98, 0.98)
const UV_IRON := Vector4(0.52, 0.27, 0.98, 0.48)
const UV_ROPE := Vector4(0.52, 0.02, 0.98, 0.23)

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
	_build_albedo(abs_here.path_join("gate_albedo.png"), 256)
	_build_mesh()
	_write_obj(abs_here.path_join("gate.obj"), abs_here.path_join("gate.mtl"))
	quit(0)


func _build_albedo(path: String, size: int) -> void:
	var wood := _load_src("timber.jpg")
	var endg := _load_src("endgrain.jpg")
	var iron := _load_src("iron.jpg")
	var rope := _load_src("rope.jpg")
	if wood == null or endg == null or iron == null or rope == null:
		push_error("gate author: missing src texture")
		quit(1)
		return
	_make_seamless(wood, 18)
	_make_seamless(endg, 16)
	_make_seamless(iron, 14)
	_make_seamless(rope, 16)
	wood.resize(size, size, Image.INTERPOLATE_LANCZOS)
	endg.resize(size, size, Image.INTERPOLATE_LANCZOS)
	iron.resize(size, size, Image.INTERPOLATE_LANCZOS)
	rope.resize(size, size, Image.INTERPOLATE_LANCZOS)

	var atlas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.42, 0.28, 0.12, 1.0))
	var half := size / 2
	var q := size / 4
	var face := wood.duplicate()
	face.resize(half, size, Image.INTERPOLATE_LANCZOS)
	var end_q := endg.duplicate()
	end_q.resize(half, half, Image.INTERPOLATE_LANCZOS)
	var iron_q := iron.duplicate()
	iron_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	var rope_q := rope.duplicate()
	rope_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	atlas.blit_rect(face, Rect2i(0, 0, half, size), Vector2i(0, 0))
	atlas.blit_rect(end_q, Rect2i(0, 0, half, half), Vector2i(half, 0))
	atlas.blit_rect(iron_q, Rect2i(0, 0, half, q), Vector2i(half, half))
	atlas.blit_rect(rope_q, Rect2i(0, 0, half, q), Vector2i(half, half + q))
	# Warm lift so it stays honey-amber next to the darker palisade.
	_tint_rect(atlas, Rect2i(0, 0, half, size), Color(1.0, 0.82, 0.45), 0.12)
	atlas.save_png(path)
	print("wrote albedo %s %dx%d" % [path, atlas.get_width(), atlas.get_height()])


func _load_src(name: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(SRC + "/" + name)
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
	var su := clampf(size.x * 0.7, 0.25, 0.85)
	var sv := clampf(size.y * 0.7, 0.2, 0.9)
	var u0 := fposmod(uv_shift.x, 0.3)
	var v0 := fposmod(uv_shift.y, 0.3)
	var u1 := u0 + su
	var v1 := v0 + sv
	_add_quad(b00, b10, m10, m00, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b11, b01, m01, m11, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b01, b00, m00, m01, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b10, b11, m11, m10, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b01, b11, b10, b00, _remap(0.2, 0.2, UV_END), _remap(0.8, 0.2, UV_END), _remap(0.8, 0.8, UV_END), _remap(0.2, 0.8, UV_END))
	_add_quad(m00, m10, t10, t00, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m10, m11, t11, t10, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m11, m01, t01, t11, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m01, m00, t00, t01, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	var top_r := top_region if top_region != Vector4.ZERO else UV_END
	_add_quad(t00, t10, t11, t01, _remap(0.1, 0.1, top_r), _remap(0.9, 0.1, top_r), _remap(0.9, 0.9, top_r), _remap(0.1, 0.9, top_r))


## Dressed octagonal post — not a pointed palisade stake.
func add_post(x: float, z: float, r_bot: float, r_top: float, y0: float, y1: float, sides: int = 8) -> void:
	var rings := 6
	var pts: Array = []
	var ys: Array[float] = []
	for i in rings:
		var t := float(i) / float(rings - 1)
		var y := lerpf(y0, y1, t)
		var r := lerpf(r_bot, r_top, t)
		ys.append(y)
		var ring: Array[Vector3] = []
		for s in sides:
			var a := (float(s) / float(sides)) * TAU + PI * 0.125
			ring.append(Vector3(x + cos(a) * r, y, z + sin(a) * r))
		pts.append(ring)
	for ri in range(rings - 1):
		var v0 := ys[ri] / y1
		var v1 := ys[ri + 1] / y1
		for s in sides:
			var s1 := (s + 1) % sides
			var u0 := float(s) / float(sides)
			var u1 := float(s + 1) / float(sides)
			_add_quad(
				pts[ri][s], pts[ri][s1], pts[ri + 1][s1], pts[ri + 1][s],
				_remap(u0, v0, UV_WOOD), _remap(u1, v0, UV_WOOD),
				_remap(u1, v1, UV_WOOD), _remap(u0, v1, UV_WOOD)
			)
	# Top cap (end grain)
	var c1 := Vector3(x, y1, z)
	for s in sides:
		var s1 := (s + 1) % sides
		_add_tri(
			c1, pts[rings - 1][s], pts[rings - 1][s1],
			_remap(0.5, 0.5, UV_END),
			_remap(0.5 + 0.4 * cos(float(s) / float(sides) * TAU), 0.5 + 0.4 * sin(float(s) / float(sides) * TAU), UV_END),
			_remap(0.5 + 0.4 * cos(float(s1) / float(sides) * TAU), 0.5 + 0.4 * sin(float(s1) / float(sides) * TAU), UV_END)
		)
	# Bottom cap
	var c0 := Vector3(x, y0, z)
	for s in sides:
		var s1 := (s + 1) % sides
		_add_tri(
			c0, pts[0][s1], pts[0][s],
			_remap(0.5, 0.5, UV_END),
			_remap(0.5 + 0.4 * cos(float(s1) / float(sides) * TAU), 0.5 + 0.4 * sin(float(s1) / float(sides) * TAU), UV_END),
			_remap(0.5 + 0.4 * cos(float(s) / float(sides) * TAU), 0.5 + 0.4 * sin(float(s) / float(sides) * TAU), UV_END)
		)


func add_iron_band(x: float, z: float, y: float, radius: float, thick: float, sides: int = 10) -> void:
	var r0 := radius
	var r1 := radius + 0.012
	var y0 := y - thick * 0.5
	var y1 := y + thick * 0.5
	var bot: Array[Vector3] = []
	var top: Array[Vector3] = []
	var bot_o: Array[Vector3] = []
	var top_o: Array[Vector3] = []
	for s in sides:
		var a := (float(s) / float(sides)) * TAU
		bot.append(Vector3(x + cos(a) * r0, y0, z + sin(a) * r0))
		top.append(Vector3(x + cos(a) * r0, y1, z + sin(a) * r0))
		bot_o.append(Vector3(x + cos(a) * r1, y0, z + sin(a) * r1))
		top_o.append(Vector3(x + cos(a) * r1, y1, z + sin(a) * r1))
	for s in sides:
		var s1 := (s + 1) % sides
		var u0 := float(s) / float(sides)
		var u1 := float(s + 1) / float(sides)
		_add_quad(bot_o[s], bot_o[s1], top_o[s1], top_o[s], _remap(u0, 0.1, UV_IRON), _remap(u1, 0.1, UV_IRON), _remap(u1, 0.9, UV_IRON), _remap(u0, 0.9, UV_IRON))
		_add_quad(top_o[s], top_o[s1], top[s1], top[s], _remap(u0, 0.2, UV_IRON), _remap(u1, 0.2, UV_IRON), _remap(u1, 0.5, UV_IRON), _remap(u0, 0.5, UV_IRON))
		_add_quad(bot[s], bot[s1], bot_o[s1], bot_o[s], _remap(u0, 0.5, UV_IRON), _remap(u1, 0.5, UV_IRON), _remap(u1, 0.8, UV_IRON), _remap(u0, 0.8, UV_IRON))


func _build_mesh() -> void:
	_v.clear()
	_vt.clear()
	_vn.clear()
	_f.clear()

	# Large-shape doorway: thick posts at the cell edges, empty middle, heavy lintel.
	# Opening stays |x| < 0.26 so a player-sized volume is air, not a wall slab.
	var px := 0.38
	add_post(-px, 0.0, 0.125, 0.105, 0.08, 1.78, 8)
	add_post(px, 0.0, 0.125, 0.105, 0.08, 1.78, 8)
	add_block(Vector3(-px, 0.06, 0.0), Vector3(0.30, 0.12, 0.30), UV_WOOD, Vector2(0.1, 0.05), 0.014, UV_END)
	add_block(Vector3(px, 0.06, 0.0), Vector3(0.30, 0.12, 0.30), UV_WOOD, Vector2(0.4, 0.15), 0.014, UV_END)
	add_iron_band(-px, 0.0, 0.36, 0.122, 0.070)
	add_iron_band(-px, 0.0, 1.38, 0.110, 0.060)
	add_iron_band(px, 0.0, 0.36, 0.122, 0.070)
	add_iron_band(px, 0.0, 1.38, 0.110, 0.060)
	# Overhead beam — thick enough to read at iso zoom. Nothing fills |x|<0.26 below y=1.70.
	add_block(Vector3(0.0, 1.88, 0.0), Vector3(1.00, 0.28, 0.26), UV_WOOD, Vector2(0.2, 0.6), 0.016, UV_END)
	add_block(Vector3(0.0, 2.08, 0.0), Vector3(0.78, 0.12, 0.20), UV_WOOD, Vector2(0.35, 0.1), 0.010, UV_END)


func _write_obj(obj_path: String, mtl_path: String) -> void:
	var mtl := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mtl == null:
		push_error("cannot write %s" % mtl_path)
		quit(1)
		return
	mtl.store_string("newmtl gate_mat\nKd 1.00 1.00 1.00\nmap_Kd gate_albedo.png\n")
	mtl.close()
	var f := FileAccess.open(obj_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % obj_path)
		quit(1)
		return
	f.store_line("# Crystal Storm authored gate passage")
	f.store_line("mtllib gate.mtl")
	f.store_line("usemtl gate_mat")
	f.store_line("o Gate")
	f.store_line("g gate")
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
