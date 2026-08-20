extends SceneTree
## Author the Crystal Storm town_hall landmark mesh + albedo atlas.
##
## Mesh is in voxel-column units (Y up from unraised ground).
## Runtime bind multiplies XZ by voxel_scale; Y stays 1.0 — a WIDE hall
## with a pitched roof, not a wall, gate, pillar, or deck.
##
## Usage: godot --headless --path . -s assets/structures/town_hall/author_town_hall.gd

const HERE := "res://assets/structures/town_hall"
const SRC := HERE + "/src"

# Godot OBJ UVs treat v=0 as image top for this importer.
const UV_WALL := Vector4(0.02, 0.02, 0.48, 0.98)
const UV_ROOF := Vector4(0.52, 0.02, 0.98, 0.48)
const UV_WOOD := Vector4(0.52, 0.50, 0.98, 0.74)
const UV_END := Vector4(0.52, 0.76, 0.98, 0.98)

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
	_build_albedo(abs_here.path_join("town_hall_albedo.png"), 256)
	_build_mesh()
	_write_obj(abs_here.path_join("town_hall.obj"), abs_here.path_join("town_hall.mtl"))
	quit(0)


func _build_albedo(path: String, size: int) -> void:
	var wall := _load_src("plaster.jpg")
	var roof := _load_src("roof.jpg")
	var wood := _load_src("timber.jpg")
	var endg := _load_src("endgrain.jpg")
	if wall == null or roof == null or wood == null or endg == null:
		push_error("town_hall author: missing src")
		quit(1)
		return
	_make_seamless(wall, 18)
	_make_seamless(roof, 14)
	_make_seamless(wood, 16)
	_make_seamless(endg, 16)
	wall.resize(size, size, Image.INTERPOLATE_LANCZOS)
	roof.resize(size, size, Image.INTERPOLATE_LANCZOS)
	wood.resize(size, size, Image.INTERPOLATE_LANCZOS)
	endg.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var atlas := Image.create(size, size, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.55, 0.42, 0.28, 1.0))
	var half := size / 2
	var q := size / 4
	var face := wall.duplicate()
	face.resize(half, size, Image.INTERPOLATE_LANCZOS)
	var roof_q := roof.duplicate()
	roof_q.resize(half, half, Image.INTERPOLATE_LANCZOS)
	var wood_q := wood.duplicate()
	wood_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	var end_q := endg.duplicate()
	end_q.resize(half, q, Image.INTERPOLATE_LANCZOS)
	atlas.blit_rect(face, Rect2i(0, 0, half, size), Vector2i(0, 0))
	atlas.blit_rect(roof_q, Rect2i(0, 0, half, half), Vector2i(half, 0))
	atlas.blit_rect(wood_q, Rect2i(0, 0, half, q), Vector2i(half, half))
	atlas.blit_rect(end_q, Rect2i(0, 0, half, q), Vector2i(half, half + q))
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


func add_block(center: Vector3, size: Vector3, region: Vector4, uv_shift: Vector2, bevel: float = 0.012, top_region: Vector4 = Vector4.ZERO) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var b := minf(bevel, minf(hx, minf(hy, hz)) * 0.35)
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
	var su := clampf(size.x * 0.7, 0.25, 0.95)
	var sv := clampf(size.y * 0.7, 0.2, 0.95)
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
	_add_quad(t00, t10, t11, t01, _remap(0.08, 0.08, top_r), _remap(0.92, 0.08, top_r), _remap(0.92, 0.92, top_r), _remap(0.08, 0.92, top_r))


func add_pitched_roof() -> void:
	# Ridge along Z, eaves at ±X. Reads as a house from the iso camera.
	var y_ridge := 2.42
	var y_eave := 1.42
	var x_eave := 0.72
	var z0 := -0.62
	var z1 := 0.62
	var ridge0 := Vector3(0.0, y_ridge, z0)
	var ridge1 := Vector3(0.0, y_ridge, z1)
	var el0 := Vector3(-x_eave, y_eave, z0)
	var el1 := Vector3(-x_eave, y_eave, z1)
	var er0 := Vector3(x_eave, y_eave, z0)
	var er1 := Vector3(x_eave, y_eave, z1)
	# Left slope
	_add_quad(el0, ridge0, ridge1, el1, _remap(0.05, 0.05, UV_ROOF), _remap(0.95, 0.05, UV_ROOF), _remap(0.95, 0.95, UV_ROOF), _remap(0.05, 0.95, UV_ROOF))
	# Right slope
	_add_quad(ridge0, er0, er1, ridge1, _remap(0.05, 0.05, UV_ROOF), _remap(0.95, 0.05, UV_ROOF), _remap(0.95, 0.95, UV_ROOF), _remap(0.05, 0.95, UV_ROOF))
	# Gable walls (plaster triangles) so the ends are not open.
	var gable_l := Vector3(-0.58, 1.38, z0)
	var gable_r := Vector3(0.58, 1.38, z0)
	_add_tri(ridge0, gable_l, gable_r, _remap(0.5, 0.95, UV_WALL), _remap(0.08, 0.15, UV_WALL), _remap(0.92, 0.15, UV_WALL))
	var gable_l2 := Vector3(-0.58, 1.38, z1)
	var gable_r2 := Vector3(0.58, 1.38, z1)
	_add_tri(ridge1, gable_r2, gable_l2, _remap(0.5, 0.95, UV_WALL), _remap(0.92, 0.15, UV_WALL), _remap(0.08, 0.15, UV_WALL))
	# Overhang lips
	add_block(Vector3(0.0, y_eave + 0.03, 0.0), Vector3(x_eave * 2.08, 0.05, 1.30), UV_WOOD, Vector2(0.1, 0.2), 0.006, UV_WOOD)


func _build_mesh() -> void:
	_v.clear()
	_vt.clear()
	_vn.clear()
	_f.clear()
	# Wide plaster body — footprint larger than a wall cell.
	add_block(Vector3(0.0, 0.70, 0.0), Vector3(1.22, 1.40, 1.08), UV_WALL, Vector2(0.05, 0.1), 0.016, UV_WALL)
	# Timber sills
	add_block(Vector3(0.0, 0.04, 0.0), Vector3(1.26, 0.08, 1.12), UV_WOOD, Vector2(0.2, 0.3), 0.006, UV_END)
	# Door (iso +Z)
	add_block(Vector3(0.0, 0.38, 0.56), Vector3(0.26, 0.62, 0.08), UV_WOOD, Vector2(0.0, 0.1), 0.008, UV_END)
	add_block(Vector3(0.0, 0.08, 0.62), Vector3(0.38, 0.08, 0.16), UV_WOOD, Vector2(0.3, 0.2), 0.006, UV_END)
	# Windows
	add_block(Vector3(-0.36, 0.88, 0.55), Vector3(0.18, 0.22, 0.05), UV_WOOD, Vector2(0.4, 0.5), 0.004, UV_END)
	add_block(Vector3(0.36, 0.88, 0.55), Vector3(0.18, 0.22, 0.05), UV_WOOD, Vector2(0.1, 0.6), 0.004, UV_END)
	add_pitched_roof()
	# Chimney on the back slope
	add_block(Vector3(-0.22, 2.05, -0.22), Vector3(0.16, 0.42, 0.16), UV_WALL, Vector2(0.2, 0.7), 0.01, UV_WALL)
	add_block(Vector3(-0.22, 2.28, -0.22), Vector3(0.20, 0.07, 0.20), UV_WOOD, Vector2(0.0, 0.0), 0.006, UV_END)


func _write_obj(obj_path: String, mtl_path: String) -> void:
	var mtl := FileAccess.open(mtl_path, FileAccess.WRITE)
	if mtl == null:
		push_error("cannot write %s" % mtl_path)
		quit(1)
		return
	mtl.store_string("newmtl town_hall_mat\nKd 1.00 1.00 1.00\nmap_Kd town_hall_albedo.png\n")
	mtl.close()
	var f := FileAccess.open(obj_path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % obj_path)
		quit(1)
		return
	f.store_line("# Crystal Storm authored town_hall landmark")
	f.store_line("mtllib town_hall.mtl")
	f.store_line("usemtl town_hall_mat")
	f.store_line("o TownHall")
	f.store_line("g town_hall")
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
