extends SceneTree
## Author the Crystal Storm bridge deck mesh + albedo atlas.
##
## Mesh is in voxel-column units (width ≈ 1 column, Y up from the raised fill).
## Runtime bind multiplies XZ by voxel_scale and Y by ~1.15 — a LOW crossing
## cap on raised-over-dig terrain, not a wall, gate, or floor tile.
##
## Usage: godot --headless --path . -s assets/structures/bridge/author_bridge.gd

const HERE := "res://assets/structures/bridge"
const SRC := HERE + "/src"

const UV_DECK := Vector4(0.02, 0.02, 0.48, 0.98)
const UV_END := Vector4(0.52, 0.52, 0.98, 0.98)
const UV_RAIL := Vector4(0.52, 0.27, 0.98, 0.48)
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
	_build_albedo(abs_here.path_join("bridge_albedo.png"), 256)
	_build_mesh()
	_write_obj(abs_here.path_join("bridge.obj"), abs_here.path_join("bridge.mtl"))
	quit(0)


func _build_albedo(path: String, size: int) -> void:
	var deck := _load_src("deck.jpg")
	var endg := _load_src("endgrain.jpg")
	var rail := _load_src("rail.jpg")
	var rope := _load_src("rope.jpg")
	if deck == null or endg == null or rail == null or rope == null:
		push_error("bridge author: missing src texture")
		quit(1)
		return
	_make_seamless(deck, 16)
	_make_seamless(endg, 16)
	_make_seamless(rail, 16)
	_make_seamless(rope, 16)
	deck.resize(size, size, Image.INTERPOLATE_LANCZOS)
	endg.resize(size, size, Image.INTERPOLATE_LANCZOS)
	rail.resize(size, size, Image.INTERPOLATE_LANCZOS)
	rope.resize(size, size, Image.INTERPOLATE_LANCZOS)

	var atlas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.32, 0.36, 0.40, 1.0))
	var half := size / 2
	var q := size / 4
	var face := deck.duplicate()
	face.resize(half, size, Image.INTERPOLATE_LANCZOS)
	var end_q := endg.duplicate()
	end_q.resize(half, half, Image.INTERPOLATE_LANCZOS)
	var rail_q := rail.duplicate()
	rail_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	var rope_q := rope.duplicate()
	rope_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	atlas.blit_rect(face, Rect2i(0, 0, half, size), Vector2i(0, 0))
	atlas.blit_rect(end_q, Rect2i(0, 0, half, half), Vector2i(half, 0))
	atlas.blit_rect(rail_q, Rect2i(0, 0, half, q), Vector2i(half, half))
	atlas.blit_rect(rope_q, Rect2i(0, 0, half, q), Vector2i(half, half + q))
	# Cool the deck so it stays slate, not honey-gate or bark-palisade.
	_tint_rect(atlas, Rect2i(0, 0, half, size), Color(0.72, 0.82, 0.95), 0.14)
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


func add_block(center: Vector3, size: Vector3, region: Vector4, uv_shift: Vector2, bevel: float = 0.008, top_region: Vector4 = Vector4.ZERO) -> void:
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
	var su := clampf(size.x * 0.85, 0.2, 0.95)
	var sv := clampf(maxf(size.y, size.z) * 0.85, 0.15, 0.95)
	var u0 := fposmod(uv_shift.x, 0.25)
	var v0 := fposmod(uv_shift.y, 0.25)
	var u1 := u0 + su
	var v1 := v0 + sv
	_add_quad(b00, b10, m10, m00, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b11, b01, m01, m11, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b01, b00, m00, m01, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b10, b11, m11, m10, _remap(u0, v0, region), _remap(u1, v0, region), _remap(u1, v1, region), _remap(u0, v1, region))
	_add_quad(b01, b11, b10, b00, _remap(0.15, 0.15, UV_END), _remap(0.85, 0.15, UV_END), _remap(0.85, 0.85, UV_END), _remap(0.15, 0.85, UV_END))
	_add_quad(m00, m10, t10, t00, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m10, m11, t11, t10, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m11, m01, t01, t11, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	_add_quad(m01, m00, t00, t01, _remap(u0, v1, region), _remap(u1, v1, region), _remap(u1, 1.0, region), _remap(u0, 1.0, region))
	var top_r := top_region if top_region != Vector4.ZERO else region
	_add_quad(t00, t10, t11, t01, _remap(0.05 + uv_shift.x * 0.2, 0.05, top_r), _remap(0.95, 0.05, top_r), _remap(0.95, 0.95, top_r), _remap(0.05, 0.95, top_r))


func _build_mesh() -> void:
	_v.clear()
	_vt.clear()
	_vn.clear()
	_f.clear()

	# Walk-span is +X. Rails sit on ±Z. Yaw 90° when the trench runs north-south.
	# Solid deck slab so iso does not read as an empty pallet, plus plank lips.
	add_block(Vector3(0.0, 0.040, 0.0), Vector3(0.90, 0.06, 0.78), UV_DECK, Vector2(0.1, 0.05), 0.006, UV_DECK)
	var plank_n := 5
	var z0 := -0.38
	var z1 := 0.38
	var gap := 0.012
	var usable := (z1 - z0) - gap * float(plank_n - 1)
	var pw := usable / float(plank_n)
	var z := z0
	for i in plank_n:
		var jit := (float(i % 2) - 0.5) * 0.012
		add_block(
			Vector3(jit, 0.078, z + pw * 0.5),
			Vector3(0.86, 0.034, pw * 0.94),
			UV_DECK,
			Vector2(0.08 * float(i), 0.12 * float(i)),
			0.004,
			UV_DECK
		)
		z += pw + gap

	# End headers — the span beams that say "this crosses a gap".
	add_block(Vector3(-0.48, 0.070, 0.0), Vector3(0.16, 0.14, 1.02), UV_RAIL, Vector2(0.05, 0.2), 0.008, UV_END)
	add_block(Vector3(0.48, 0.070, 0.0), Vector3(0.16, 0.14, 1.02), UV_RAIL, Vector2(0.35, 0.1), 0.008, UV_END)

	# Side rails — tall/thick enough to read at iso, still a low cap (Y < 0.7).
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var rz := side * 0.48
		var post_xs: Array[float] = [-0.42, 0.0, 0.42]
		for px in post_xs:
			add_block(Vector3(px, 0.28, rz), Vector3(0.10, 0.38, 0.10), UV_RAIL, Vector2(absf(px), 0.2), 0.008, UV_END)
		add_block(Vector3(0.0, 0.49, rz), Vector3(1.02, 0.08, 0.08), UV_RAIL, Vector2(0.3, 0.4), 0.006, UV_RAIL)
		add_block(Vector3(0.0, 0.32, rz), Vector3(0.90, 0.045, 0.05), UV_ROPE, Vector2(0.1, 0.2), 0.004, UV_ROPE)
		# Knee braces from end posts down onto the headers.
		add_block(Vector3(-0.34, 0.20, rz), Vector3(0.16, 0.10, 0.07), UV_RAIL, Vector2(0.4, 0.3), 0.005, UV_RAIL)
		add_block(Vector3(0.34, 0.20, rz), Vector3(0.16, 0.10, 0.07), UV_RAIL, Vector2(0.15, 0.35), 0.005, UV_RAIL)


func _write_obj(obj_path: String, mtl_path: String) -> void:
	var mtl := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mtl == null:
		push_error("cannot write %s" % mtl_path)
		quit(1)
		return
	mtl.store_string("newmtl bridge_mat\nKd 1.00 1.00 1.00\nmap_Kd bridge_albedo.png\n")
	mtl.close()
	var f := FileAccess.open(obj_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % obj_path)
		quit(1)
		return
	f.store_line("# Crystal Storm authored bridge deck")
	f.store_line("mtllib bridge.mtl")
	f.store_line("usemtl bridge_mat")
	f.store_line("o Bridge")
	f.store_line("g bridge")
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
