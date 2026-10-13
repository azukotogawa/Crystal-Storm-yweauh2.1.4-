extends SceneTree
## Deterministic 32px-density pixel art for the texture manifest.
##
##   godot --headless --path . -s res://tools/gen_texture_batch.gd
##   godot --headless --path . -s res://tools/gen_texture_batch.gd -- --contact /path/contact_sheet.png
##
## Sizes come from docs/texture_manifest.json. Batch files land in assets/art_batch1/.
## The three missing crystal icons are written to assets/art/crystal/. Nothing else under
## assets/art/ is touched.

const CRYSTAL_IDS: PackedStringArray = ["amethyst", "void_shard", "solar_crystal"]
const BATCH_CATS: PackedStringArray = ["items", "vegetation", "mobs"]

const WOOD_HI := Color8(214, 164, 96)
const WOOD_MID := Color8(150, 98, 48)
const WOOD_LO := Color8(96, 60, 30)
const WOOD_OUT := Color8(42, 24, 12)
const LEAF_HI := Color8(138, 196, 78)
const LEAF_MID := Color8(62, 132, 52)
const LEAF_LO := Color8(32, 78, 32)
const LEAF_OUT := Color8(16, 36, 16)
const BERRY := Color8(196, 48, 64)
const STONE_HI := Color8(196, 198, 206)
const STONE_MID := Color8(132, 136, 146)
const STONE_LO := Color8(78, 82, 92)
const STONE_OUT := Color8(36, 38, 46)
const METAL_HI := Color8(232, 236, 240)
const METAL_MID := Color8(168, 176, 186)
const METAL_LO := Color8(96, 104, 116)
const CRYS_HI := Color8(232, 176, 255)
const CRYS_MID := Color8(156, 72, 214)
const CRYS_LO := Color8(78, 28, 128)
const CRYS_GLOW := Color8(255, 64, 196)
const CRYS_OUT := Color8(28, 8, 48)
const COR_HI := Color8(110, 48, 132)
const COR_MID := Color8(58, 18, 78)
const COR_LO := Color8(22, 6, 30)
const COR_GLOW := Color8(255, 40, 180)
const COR_OUT := Color8(8, 4, 12)
const FUR_HI := Color8(228, 206, 170)
const FUR_MID := Color8(186, 140, 92)
const FUR_LO := Color8(110, 72, 42)
const DEER_HI := Color8(196, 140, 78)
const DEER_MID := Color8(150, 96, 48)
const DEER_LO := Color8(92, 58, 32)
const BOAR_HI := Color8(132, 78, 52)
const BOAR_MID := Color8(86, 48, 34)
const BOAR_LO := Color8(46, 26, 18)
const BIRD_HI := Color8(132, 176, 220)
const BIRD_MID := Color8(64, 108, 164)
const BIRD_LO := Color8(32, 56, 92)
const BEAK := Color8(232, 148, 48)
const SKIN_HI := Color8(236, 196, 158)
const SKIN_MID := Color8(204, 148, 110)
const SKIN_LO := Color8(148, 96, 70)
const TUNIC_HI := Color8(96, 128, 184)
const TUNIC_MID := Color8(52, 78, 140)
const TUNIC_LO := Color8(28, 40, 84)
const PUMP_HI := Color8(236, 148, 52)
const PUMP_MID := Color8(200, 96, 32)
const PUMP_LO := Color8(128, 52, 20)
const SOL_HI := Color8(255, 236, 150)
const SOL_MID := Color8(240, 164, 40)
const SOL_LO := Color8(168, 72, 16)
const SOL_CORE := Color8(255, 250, 214)
const VOID_HI := Color8(132, 56, 176)
const VOID_MID := Color8(52, 14, 78)
const VOID_LO := Color8(14, 4, 22)
const EYE := Color8(16, 12, 20)
const EYE_HI := Color8(248, 248, 236)
const PINK := Color8(224, 140, 150)
const WHITE := Color8(240, 236, 224)
const FLOWER_Y := Color8(240, 204, 48)
const FLOWER_P := Color8(224, 96, 144)
const MOSS := Color8(64, 140, 60)
const TUSK := Color8(236, 228, 206)

const GLYPH := {
	"A": "111101111101101",
	"B": "110101110101110",
	"C": "111100100100111",
	"D": "110101101101110",
	"E": "111100110100111",
	"F": "111100110100100",
	"G": "111100101101111",
	"H": "101101111101101",
	"I": "111010010010111",
	"J": "001001001101010",
	"K": "101101110101101",
	"L": "100100100100111",
	"M": "101111111101101",
	"N": "110101101101101",
	"O": "111101101101111",
	"P": "111101111100100",
	"Q": "111101101111001",
	"R": "111101110101101",
	"S": "111100111001111",
	"T": "111010010010010",
	"U": "101101101101111",
	"V": "101101101101010",
	"W": "101101111111101",
	"X": "101101010101101",
	"Y": "101101010010010",
	"Z": "111001010100111",
	"0": "111101101101111",
	"1": "010110010010111",
	"2": "111001111100111",
	"3": "111001111001111",
	"4": "101101111001001",
	"5": "111100111001111",
	"6": "111100111101111",
	"7": "111001010010010",
	"8": "111101111101111",
	"9": "111101111001111",
	"_": "000000000000111",
	"-": "000000111000000",
	" ": "000000000000000",
}

var _failed: int = 0
var _counts := {"items": 0, "vegetation": 0, "mobs": 0, "corrupted": 0, "crystals": 0}
var _sheet: Array[Dictionary] = []


class Pix:
	var img: Image
	var w: int
	var h: int

	func _init(image: Image) -> void:
		img = image
		w = image.get_width()
		h = image.get_height()

	func clear() -> void:
		img.fill(Color(0, 0, 0, 0))

	func put(x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= w or y >= h or c.a < 0.5:
			return
		img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))

	func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
		if rw <= 0 or rh <= 0:
			return
		for yy in rh:
			for xx in rw:
				put(x + xx, y + yy, c)

	func shade_rect(x: int, y: int, rw: int, rh: int, hi: Color, mid: Color, lo: Color) -> void:
		if rw <= 0 or rh <= 0:
			return
		for yy in rh:
			for xx in rw:
				var c := mid
				var edge_lo := yy >= rh - 1 or xx >= rw - 1
				var edge_hi := (yy == 0 or xx == 0) and not edge_lo
				if edge_hi:
					c = hi
				elif edge_lo:
					c = lo
				put(x + xx, y + yy, c)

	func disc(cx: int, cy: int, rx: int, ry: int, hi: Color, mid: Color, lo: Color) -> void:
		rx = maxi(rx, 1)
		ry = maxi(ry, 1)
		var band := maxi(maxi(rx, ry) / 3, 1)
		var rad := rx * rx * ry * ry
		for y in range(cy - ry, cy + ry + 1):
			for x in range(cx - rx, cx + rx + 1):
				var dx := x - cx
				var dy := y - cy
				if dx * dx * ry * ry + dy * dy * rx * rx > rad:
					continue
				var c := mid
				var light := -dx - dy
				if light > band:
					c = hi
				elif -light > band:
					c = lo
				put(x, y, c)

	func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var err := dx + dy
		var guard := 0
		while guard < 512:
			put(x0, y0, c)
			if x0 == x1 and y0 == y1:
				return
			var e2 := err * 2
			if e2 >= dy:
				err += dy
				x0 += sx
			if e2 <= dx:
				err += dx
				y0 += sy
			guard += 1

	func erase_rect(x: int, y: int, rw: int, rh: int) -> void:
		var clear := Color(0, 0, 0, 0)
		for yy in rh:
			for xx in rw:
				var px := x + xx
				var py := y + yy
				if px >= 0 and py >= 0 and px < w and py < h:
					img.set_pixel(px, py, clear)

	func tri(x0: int, y0: int, x1: int, y1: int, x2: int, y2: int, c: Color) -> void:
		var min_x := mini(x0, mini(x1, x2))
		var max_x := maxi(x0, maxi(x1, x2))
		var min_y := mini(y0, mini(y1, y2))
		var max_y := maxi(y0, maxi(y1, y2))
		for y in range(min_y, max_y + 1):
			for x in range(min_x, max_x + 1):
				var w0 := _edge(x1, y1, x2, y2, x, y)
				var w1 := _edge(x2, y2, x0, y0, x, y)
				var w2 := _edge(x0, y0, x1, y1, x, y)
				var pos := w0 >= 0 and w1 >= 0 and w2 >= 0
				var neg := w0 <= 0 and w1 <= 0 and w2 <= 0
				if pos or neg:
					put(x, y, c)

	func _edge(ax: int, ay: int, bx: int, by: int, cx: int, cy: int) -> int:
		return (cx - ax) * (by - ay) - (cy - ay) * (bx - ax)

	func eye(x: int, y: int) -> void:
		put(x, y, Color8(16, 12, 20))
		put(x - 1, y - 1, Color8(248, 248, 236))

	func glow_pixels(c: Color, count: int, salt: int) -> void:
		if c.a < 0.5 or count <= 0:
			return
		var spots: Array[Vector2i] = []
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				if img.get_pixel(x, y).a < 0.5:
					continue
				var interior := true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if img.get_pixel(x + d.x, y + d.y).a < 0.5:
						interior = false
						break
				if interior:
					spots.append(Vector2i(x, y))
		if spots.is_empty():
			return
		var used := {}
		var n := mini(count, spots.size())
		var i := 0
		while i < n:
			var idx := _mix(salt, i) % spots.size()
			if used.has(idx):
				i += 1
				if i > n * 4:
					break
				continue
			used[idx] = true
			var spot: Vector2i = spots[idx]
			img.set_pixel(spot.x, spot.y, c)
			i += 1

	func _mix(a: int, b: int) -> int:
		var x := (a * 16777619 + b * 2166136261) & 0x7fffffff
		x = (x ^ (x >> 13)) & 0x7fffffff
		return x

	func outline(c: Color) -> void:
		var marks: Array[Vector2i] = []
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > 0.5:
					continue
				var hit := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + int(d.x)
					var ny: int = y + int(d.y)
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if img.get_pixel(nx, ny).a > 0.5:
						hit = true
						break
				if hit:
					marks.append(Vector2i(x, y))
		for mark in marks:
			img.set_pixel(mark.x, mark.y, c)

	func seal() -> void:
		var clear := Color(0, 0, 0, 0)
		img.set_pixel(0, 0, clear)
		img.set_pixel(w - 1, 0, clear)
		img.set_pixel(0, h - 1, clear)
		img.set_pixel(w - 1, h - 1, clear)

	func finish(out_c: Color, glow: Color, glow_n: int, salt: int) -> void:
		glow_pixels(glow, glow_n, salt)
		if glow.a > 0.5 and glow_n > 0 and not _has_rgb(glow):
			_stamp_glow(glow, salt)
		outline(out_c)
		seal()

	func _has_rgb(c: Color) -> bool:
		var key := _rgb_key(c)
		for y in h:
			for x in w:
				var p := img.get_pixel(x, y)
				if p.a > 0.5 and _rgb_key(p) == key:
					return true
		return false

	func _stamp_glow(c: Color, salt: int) -> void:
		var spots: Array[Vector2i] = []
		for y in range(2, h - 2):
			for x in range(2, w - 2):
				if img.get_pixel(x, y).a > 0.5:
					spots.append(Vector2i(x, y))
		if spots.is_empty():
			put(w / 2, h / 2, c)
			return
		var spot: Vector2i = spots[_mix(salt, 91) % spots.size()]
		img.set_pixel(spot.x, spot.y, Color(c.r, c.g, c.b, 1.0))

	func _rgb_key(c: Color) -> String:
		return "%d,%d,%d" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var slots: Array = _manifest_slots()
	if slots.is_empty():
		push_error("texture manifest has no slots")
		quit(1)
		return
	for slot in slots:
		if not (slot is Dictionary):
			continue
		_emit_slot(slot)
	if _failed == 0:
		var contact := _contact_arg()
		if not contact.is_empty():
			_write_contact(contact)
	print("items=%d vegetation=%d mobs=%d corrupted=%d crystals=%d failed=%d" % [
		int(_counts.items), int(_counts.vegetation), int(_counts.mobs),
		int(_counts.corrupted), int(_counts.crystals), _failed,
	])
	if _failed > 0:
		print("Texture batch generate failed")
		quit(1)
		return
	print("All texture batch generate OK")
	quit(0)


func _emit_slot(slot: Dictionary) -> void:
	var path := str(slot.get("path", ""))
	var category := str(slot.get("category", ""))
	var size: Array = slot.get("expected_size", [0, 0])
	var tw := int(size[0]) if size.size() > 0 else 0
	var th := int(size[1]) if size.size() > 1 else 0
	var crystal := path.get_file().get_basename()
	if path.begins_with("res://assets/art/crystal/") and crystal in CRYSTAL_IDS:
		if tw <= 0 or th <= 0:
			tw = 64
			th = 64
		var crystal_img := _draw(path, false)
		_store(crystal_img, path, true)
		_counts.crystals = int(_counts.crystals) + 1
		_sheet.append({"name": crystal, "original": "", "batch": path, "w": tw, "h": th})
		return
	if category not in BATCH_CATS or not path.begins_with("res://assets/art/"):
		return
	if tw <= 0 or th <= 0:
		_fail("slot %s has no expected size" % path)
		return
	var batch_path := "res://assets/art_batch1/" + path.substr("res://assets/art/".length())
	var image := _draw(path, false)
	_store(image, batch_path, false)
	_bump(category)
	_sheet.append({"name": path.get_file().get_basename(), "original": path, "batch": batch_path, "w": tw, "h": th})
	if "/vegetation/" in path:
		var corrupt_path := batch_path.get_base_dir().path_join("corrupted_" + batch_path.get_file())
		var corrupt_img := _draw(path, true)
		_store(corrupt_img, corrupt_path, false)
		_counts.corrupted = int(_counts.corrupted) + 1
		_sheet.append({
			"name": corrupt_path.get_file().get_basename(),
			"original": "",
			"batch": corrupt_path,
			"w": tw,
			"h": th,
		})


func _bump(category: String) -> void:
	if category == "items":
		_counts.items = int(_counts.items) + 1
	elif category == "vegetation":
		_counts.vegetation = int(_counts.vegetation) + 1
	elif category == "mobs":
		_counts.mobs = int(_counts.mobs) + 1


func _draw(path: String, corrupt: bool) -> Image:
	var size := _size_of(path)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var pix := Pix.new(image)
	pix.clear()
	var info := _parse(path)
	var folder := str(info.folder)
	var kind := str(info.kind)
	var stage := int(info.stage)
	match folder:
		"items":
			_item(pix, kind)
		"building":
			_building(pix, kind)
		"entity":
			_entity(pix, kind)
		"vegetation":
			_plant(pix, kind, stage, corrupt)
		"crystal":
			_crystal(pix, kind)
		_:
			_fail("no drawer for %s" % path)
	return image


func _size_of(path: String) -> Vector2i:
	for row in _sheet:
		pass
	var slots := _manifest_slots()
	for slot in slots:
		if str(slot.get("path", "")) != path:
			continue
		var size: Array = slot.get("expected_size", [0, 0])
		return Vector2i(int(size[0]), int(size[1]))
	return Vector2i(32, 32)


func _parse(path: String) -> Dictionary:
	var file := path.get_file().get_basename()
	var folder := path.get_base_dir().get_file()
	# Vegetation variants are named corrupted_<plant>. The mob corrupted_beast keeps its name.
	if folder == "vegetation" and file.begins_with("corrupted_"):
		file = file.substr("corrupted_".length())
	var stage := 0
	var kind := file
	var idx := file.rfind("_s")
	if idx > 0 and file.substr(idx + 2).is_valid_int():
		stage = int(file.substr(idx + 2))
		kind = file.substr(0, idx)
	return {"folder": folder, "kind": kind, "stage": stage}


func _store(image: Image, res_path: String, crystal_root: bool) -> void:
	var err := _audit(image, res_path)
	if not err.is_empty():
		_fail("%s: %s" % [res_path, err])
	if not _allowed_write(res_path, crystal_root):
		_fail("refusing to write %s" % res_path)
		return
	var abs_path := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	if image.save_png(abs_path) != OK:
		_fail("save failed %s" % res_path)


func _allowed_write(res_path: String, crystal_root: bool) -> bool:
	if res_path.begins_with("res://assets/art_batch1/"):
		return true
	if not crystal_root:
		return false
	if not res_path.begins_with("res://assets/art/crystal/"):
		return false
	return res_path.get_file().get_basename() in CRYSTAL_IDS


func _audit(image: Image, _label: String) -> String:
	var w := image.get_width()
	var h := image.get_height()
	if w < 8 or h < 8:
		return "too small"
	var colors := {}
	var opaque := 0
	var edge_dark := 0
	var partial := 0
	var magenta := 0
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			if c.a > 0.04 and c.a < 0.96:
				partial += 1
			if c.a < 0.5:
				continue
			opaque += 1
			var r8 := int(round(c.r * 255.0))
			var g8 := int(round(c.g * 255.0))
			var b8 := int(round(c.b * 255.0))
			var key := "%d,%d,%d" % [r8, g8, b8]
			colors[key] = true
			if r8 >= 240 and g8 <= 80 and b8 >= 160:
				magenta += 1
			var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			if lum > 0.25:
				continue
			var clear_n := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + int(d.x)
				var ny: int = y + int(d.y)
				if nx < 0 or ny < 0 or nx >= w or ny >= h or image.get_pixel(nx, ny).a < 0.5:
					clear_n = true
					break
			if clear_n:
				edge_dark += 1
	if opaque < 40:
		return "not enough opaque pixels (%d)" % opaque
	if colors.size() > 24:
		return "palette %d" % colors.size()
	if partial > 0:
		return "partial alpha"
	if edge_dark < 8:
		return "outline %d" % edge_dark
	if image.get_pixel(0, 0).a > 0.1 or image.get_pixel(w - 1, 0).a > 0.1:
		return "corner"
	if image.get_pixel(0, h - 1).a > 0.1 or image.get_pixel(w - 1, h - 1).a > 0.1:
		return "corner"
	if "/corrupted_" in _label and magenta < 1:
		return "no magenta glow"
	return ""


func _box(p: Pix) -> Rect2i:
	return Rect2i(2, 2, p.w - 4, p.h - 4)


func _grow(stage: int, max_stage: int, lo: int, hi: int) -> int:
	if hi < lo:
		var swap := lo
		lo = hi
		hi = swap
	if max_stage <= 0:
		return hi
	return lo + (hi - lo) * clampi(stage, 0, max_stage) / max_stage


func _item(p: Pix, kind: String) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	match kind:
		"wooden_sword":
			p.shade_rect(x + w * 18 / 100, y + h * 62 / 100, maxi(w * 16 / 100, 2), h * 28 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.shade_rect(x + w * 8 / 100, y + h * 50 / 100, w * 36 / 100, maxi(h * 12 / 100, 2), WOOD_HI, WOOD_LO, WOOD_LO)
			_blade(p, x + w * 34 / 100, y + h * 50 / 100, x + w * 86 / 100, y + h * 8 / 100)
			p.disc(x + w * 22 / 100, y + h * 78 / 100, maxi(w / 14, 1), maxi(h / 14, 1), WOOD_HI, WOOD_MID, WOOD_LO)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 1)
		"stone_pick":
			p.shade_rect(x + w * 42 / 100, y + h * 28 / 100, maxi(w * 14 / 100, 2), h * 62 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.shade_rect(x + w * 8 / 100, y + h * 16 / 100, w * 78 / 100, maxi(h * 16 / 100, 3), STONE_HI, STONE_MID, STONE_LO)
			p.tri(x + w * 8 / 100, y + h * 22 / 100, x + w / 10, y + h * 8 / 100, x + w * 28 / 100, y + h * 18 / 100, STONE_HI)
			p.tri(x + w * 78 / 100, y + h * 22 / 100, x + w * 92 / 100, y + h * 8 / 100, x + w * 62 / 100, y + h * 18 / 100, STONE_LO)
			p.finish(STONE_OUT, Color(0, 0, 0, 0), 0, 2)
		"shortbow":
			_bow(p, x + w * 38 / 100, y + h / 2, w * 28 / 100, h * 38 / 100)
			p.line(x + w * 62 / 100, y + h * 14 / 100, x + w * 62 / 100, y + h * 86 / 100, WOOD_LO)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 3)
		"wood":
			p.shade_rect(x + w * 12 / 100, y + h * 28 / 100, w * 76 / 100, h * 42 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.disc(x + w * 18 / 100, y + h / 2, maxi(w / 8, 2), h * 22 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.disc(x + w * 18 / 100, y + h / 2, maxi(w / 16, 1), maxi(h / 12, 1), WOOD_LO, WOOD_MID, WOOD_HI)
			p.line(x + w * 40 / 100, y + h * 34 / 100, x + w * 82 / 100, y + h * 34 / 100, WOOD_LO)
			p.line(x + w * 40 / 100, y + h * 66 / 100, x + w * 82 / 100, y + h * 66 / 100, WOOD_HI)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 4)
		"stone":
			p.disc(x + w / 2, y + h * 54 / 100, w * 34 / 100, h * 28 / 100, STONE_HI, STONE_MID, STONE_LO)
			p.disc(x + w * 38 / 100, y + h * 42 / 100, w * 16 / 100, h * 14 / 100, STONE_HI, STONE_MID, STONE_LO)
			p.line(x + w * 40 / 100, y + h * 40 / 100, x + w * 70 / 100, y + h * 62 / 100, STONE_LO)
			p.finish(STONE_OUT, Color(0, 0, 0, 0), 0, 5)
		"herb":
			p.line(x + w / 2, y + h * 88 / 100, x + w / 2, y + h * 28 / 100, LEAF_LO)
			p.disc(x + w * 32 / 100, y + h * 40 / 100, w * 16 / 100, h * 10 / 100, LEAF_HI, LEAF_MID, LEAF_LO)
			p.disc(x + w * 68 / 100, y + h * 48 / 100, w * 16 / 100, h * 10 / 100, LEAF_HI, LEAF_MID, LEAF_LO)
			p.disc(x + w / 2, y + h * 22 / 100, w * 12 / 100, h * 12 / 100, LEAF_HI, LEAF_MID, LEAF_LO)
			p.disc(x + w / 2, y + h * 20 / 100, maxi(w / 14, 1), maxi(h / 14, 1), FLOWER_Y, FLOWER_P, LEAF_MID)
			p.finish(LEAF_OUT, Color(0, 0, 0, 0), 0, 6)
		"crystal_shard":
			_gem(p, x + w / 2, y + h * 48 / 100, w * 28 / 100, h * 36 / 100, CRYS_HI, CRYS_MID, CRYS_LO, CRYS_GLOW)
			p.finish(CRYS_OUT, CRYS_GLOW, 3, 7)
		_:
			p.disc(x + w / 2, y + h / 2, w / 4, h / 4, STONE_HI, STONE_MID, STONE_LO)
			p.finish(STONE_OUT, Color(0, 0, 0, 0), 0, 8)
			_fail("unknown item %s" % kind)


func _blade(p: Pix, x0: int, y0: int, x1: int, y1: int) -> void:
	p.line(x0 - 1, y0 - 1, x1 - 1, y1 - 1, METAL_HI)
	p.line(x0, y0, x1, y1, METAL_MID)
	p.line(x0 + 1, y0 + 1, x1 + 1, y1 + 1, METAL_LO)


func _bow(p: Pix, cx: int, cy: int, rx: int, ry: int) -> void:
	rx = maxi(rx, 3)
	ry = maxi(ry, 4)
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx := x - cx
			var dy := y - cy
			var outer := dx * dx * ry * ry + dy * dy * rx * rx
			var rad := rx * rx * ry * ry
			var inner_rx := maxi(rx - 1, 1)
			var inner := dx * dx * ry * ry + dy * dy * inner_rx * inner_rx
			var inner_rad := inner_rx * inner_rx * ry * ry
			if outer <= rad and inner >= inner_rad and dx <= 1:
				var c := WOOD_HI if dy < -ry / 3 else (WOOD_LO if dy > ry / 3 else WOOD_MID)
				p.put(x, y, c)


func _building(p: Pix, kind: String) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	match kind:
		"wood_wall":
			var logs := 4
			var lw := w / logs
			for i in logs:
				var lx := x + i * lw
				p.shade_rect(lx + 1, y + h / 8, maxi(lw - 2, 2), h * 7 / 8, WOOD_HI, WOOD_MID, WOOD_LO)
				p.rect(lx + 1, y + h / 3, maxi(lw - 2, 2), maxi(h / 16, 1), WOOD_LO)
				p.rect(lx + 1, y + h * 2 / 3, maxi(lw - 2, 2), maxi(h / 16, 1), WOOD_HI)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 11)
		"stone_wall":
			_bricks(p, x, y + h / 10, w, h * 9 / 10)
			p.finish(STONE_OUT, Color(0, 0, 0, 0), 0, 12)
		"gate":
			p.shade_rect(x + w / 10, y + h / 5, w / 5, h * 4 / 5, WOOD_HI, WOOD_MID, WOOD_LO)
			p.shade_rect(x + w * 70 / 100, y + h / 5, w / 5, h * 4 / 5, WOOD_HI, WOOD_MID, WOOD_LO)
			p.shade_rect(x + w / 10, y + h / 8, w * 80 / 100, maxi(h / 8, 3), WOOD_HI, WOOD_MID, WOOD_LO)
			p.disc(x + w / 2, y + h * 42 / 100, w * 22 / 100, h * 18 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.erase_rect(x + w * 32 / 100, y + h * 42 / 100, w * 36 / 100, h * 48 / 100)
			p.line(x + w / 2, y + h * 28 / 100, x + w / 2, y + h * 40 / 100, METAL_MID)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 13)
		"bridge":
			p.shade_rect(x + 1, y + h * 42 / 100, w - 2, maxi(h / 7, 3), WOOD_HI, WOOD_MID, WOOD_LO)
			p.shade_rect(x + 1, y + h * 28 / 100, maxi(w / 10, 2), h * 22 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.shade_rect(x + w - w / 10, y + h * 28 / 100, maxi(w / 10, 2), h * 22 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.line(x + w / 8, y + h * 30 / 100, x + w * 7 / 8, y + h * 30 / 100, WOOD_LO)
			for i in 4:
				var px := x + w * (18 + i * 16) / 100
				p.line(px, y + h * 44 / 100, px, y + h * 54 / 100, WOOD_LO)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 14)
		"ruin_pillar":
			p.shade_rect(x + w * 30 / 100, y + h * 28 / 100, w * 40 / 100, h * 62 / 100, STONE_HI, STONE_MID, STONE_LO)
			p.shade_rect(x + w * 22 / 100, y + h * 78 / 100, w * 56 / 100, h * 12 / 100, STONE_HI, STONE_MID, STONE_LO)
			p.shade_rect(x + w * 26 / 100, y + h * 18 / 100, w * 34 / 100, h * 12 / 100, STONE_HI, STONE_MID, STONE_LO)
			p.erase_rect(x + w * 58 / 100, y + h * 16 / 100, w / 5, h / 8)
			p.rect(x + w * 34 / 100, y + h * 62 / 100, w / 8, maxi(h / 14, 2), MOSS)
			p.rect(x + w * 48 / 100, y + h * 70 / 100, w / 10, maxi(h / 16, 1), MOSS)
			p.finish(STONE_OUT, Color(0, 0, 0, 0), 0, 15)
		"town_hall":
			p.shade_rect(x + w * 16 / 100, y + h * 40 / 100, w * 68 / 100, h * 50 / 100, WOOD_HI, Color8(186, 154, 110), WOOD_LO)
			p.tri(x + w * 8 / 100, y + h * 42 / 100, x + w / 2, y + h * 8 / 100, x + w * 92 / 100, y + h * 42 / 100, Color8(168, 64, 48))
			p.tri(x + w * 16 / 100, y + h * 40 / 100, x + w / 2, y + h * 16 / 100, x + w * 84 / 100, y + h * 40 / 100, Color8(210, 96, 64))
			p.shade_rect(x + w * 42 / 100, y + h * 62 / 100, w * 16 / 100, h * 28 / 100, WOOD_HI, WOOD_MID, WOOD_LO)
			p.rect(x + w * 24 / 100, y + h * 52 / 100, w / 8, h / 8, Color8(186, 214, 220))
			p.rect(x + w * 64 / 100, y + h * 52 / 100, w / 8, h / 8, Color8(150, 186, 196))
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 16)
		_:
			p.shade_rect(x + w / 4, y + h / 4, w / 2, h / 2, STONE_HI, STONE_MID, STONE_LO)
			p.finish(STONE_OUT, Color(0, 0, 0, 0), 0, 17)
			_fail("unknown building %s" % kind)


func _bricks(p: Pix, x: int, y: int, w: int, h: int) -> void:
	var bh := maxi(h / 6, 3)
	var bw := maxi(w / 3, 4)
	var row := 0
	var yy := y
	while yy + 2 < y + h:
		var offset := 0 if row % 2 == 0 else bw / 2
		var xx := x - offset
		while xx < x + w:
			var rx := maxi(xx, x)
			var right := mini(xx + bw - 1, x + w)
			var rw := right - rx
			var rh := mini(bh - 1, y + h - yy)
			if rw > 1 and rh > 1:
				p.shade_rect(rx, yy, rw, rh, STONE_HI, STONE_MID, STONE_LO)
			xx += bw
		yy += bh
		row += 1


func _entity(p: Pix, kind: String) -> void:
	match kind:
		"rabbit":
			_rabbit(p)
		"deer":
			_deer(p, false)
		"boar":
			_boar(p, false)
		"bird":
			_bird(p)
		"town_militia":
			_militia(p)
		"crystal_mite":
			_mite(p)
		"farm_bomber":
			_bomber(p)
		"crystal_stag":
			_deer(p, true)
		"thornling":
			_thornling(p)
		"corrupted_beast":
			_boar(p, true)
		"shard_guard":
			_guard(p)
		"crystal_wisp":
			_wisp(p)
		_:
			var r := _box(p)
			p.disc(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2, r.size.x / 5, r.size.y / 5, FUR_HI, FUR_MID, FUR_LO)
			p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 19)
			_fail("unknown entity %s" % kind)


func _rabbit(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var bx := x + w * 48 / 100
	var by := y + h * 62 / 100
	p.disc(bx, by, w * 22 / 100, h * 16 / 100, FUR_HI, FUR_MID, FUR_LO)
	var hx := bx + w * 16 / 100
	var hy := by - h * 16 / 100
	p.disc(hx, hy, maxi(w / 10, 2), maxi(h / 12, 2), FUR_HI, FUR_MID, FUR_LO)
	p.shade_rect(hx - w / 12, y + h / 12, maxi(w / 14, 2), hy - y - h / 14, FUR_HI, FUR_MID, FUR_LO)
	p.shade_rect(hx + w / 18, y + h / 10, maxi(w / 14, 2), hy - y - h / 12, FUR_HI, FUR_MID, FUR_LO)
	p.rect(hx - w / 16, y + h / 8, 1, maxi(h / 8, 2), PINK)
	p.eye(hx + 1, hy)
	p.disc(bx - w * 18 / 100, by, maxi(w / 14, 2), maxi(h / 16, 2), WHITE, FUR_HI, FUR_LO)
	_legs(p, bx, by + h * 10 / 100, w, h, y + h - 1, FUR_MID, FUR_LO)
	p.finish(WOOD_OUT, Color(0, 0, 0, 0), 0, 21)


func _deer(p: Pix, crystal: bool) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var bx := x + w * 42 / 100
	var by := y + h * 58 / 100
	p.disc(bx, by, w * 24 / 100, h * 14 / 100, DEER_HI, DEER_MID, DEER_LO)
	var hx := bx + w * 22 / 100
	var hy := by - h * 20 / 100
	p.shade_rect(bx + w * 12 / 100, hy + h / 12, maxi(w / 10, 2), h * 16 / 100, DEER_HI, DEER_MID, DEER_LO)
	p.disc(hx, hy, maxi(w / 11, 2), maxi(h / 13, 2), DEER_HI, DEER_MID, DEER_LO)
	p.rect(hx, hy, maxi(w / 12, 2), maxi(h / 16, 2), DEER_LO)
	p.eye(hx, hy - 1)
	var ant := CRYS_HI if crystal else DEER_LO
	p.line(hx - 1, hy - h / 14, hx - w / 8, y + h / 8, ant)
	p.line(hx + 1, hy - h / 14, hx + w / 10, y + h / 10, ant)
	p.line(hx - w / 8, y + h / 8, hx - w / 5, y + h / 6, ant)
	p.line(hx + w / 10, y + h / 10, hx + w / 6, y + h / 7, ant)
	if crystal:
		p.put(hx - w / 8, y + h / 8, CRYS_GLOW)
		p.put(hx + w / 10, y + h / 7, CRYS_GLOW)
		p.rect(bx - w / 12, by - h / 16, maxi(w / 10, 2), maxi(h / 12, 2), CRYS_MID)
	p.disc(bx - w * 22 / 100, by - h / 20, maxi(w / 16, 1), maxi(h / 14, 1), WHITE, DEER_HI, DEER_LO)
	_legs(p, bx, by + h / 10, w, h, y + h - 1, DEER_MID, DEER_LO)
	p.finish(WOOD_OUT, CRYS_GLOW if crystal else Color(0, 0, 0, 0), 3 if crystal else 0, 22)


func _boar(p: Pix, corrupt: bool) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var hi := COR_HI if corrupt else BOAR_HI
	var mid := COR_MID if corrupt else BOAR_MID
	var lo := COR_LO if corrupt else BOAR_LO
	var bx := x + w * 42 / 100
	var by := y + h * 58 / 100
	p.disc(bx, by, w * 28 / 100, h * 16 / 100, hi, mid, lo)
	p.disc(bx + w * 24 / 100, by - h / 20, w * 12 / 100, h * 10 / 100, hi, mid, lo)
	p.rect(bx + w * 30 / 100, by, maxi(w / 10, 2), maxi(h / 14, 2), lo)
	p.line(bx + w * 32 / 100, by + h / 16, bx + w * 40 / 100, by + h / 8, TUSK)
	p.line(bx + w * 30 / 100, by + h / 12, bx + w * 36 / 100, by + h / 7, TUSK)
	if corrupt:
		p.put(bx + w * 28 / 100, by - h / 12, COR_GLOW)
		p.line(bx, by - h * 14 / 100, bx + w / 14, y + h / 5, CRYS_MID)
		p.put(bx + w / 14, y + h / 5, COR_GLOW)
	else:
		p.eye(bx + w * 26 / 100, by - h / 12)
	for i in 3:
		var sx := bx - w / 8 + i * w / 10
		p.line(sx, by - h * 12 / 100, sx - 1, by - h * 20 / 100, lo)
	_legs(p, bx, by + h * 12 / 100, w, h, y + h - 1, mid, lo)
	p.finish(COR_OUT if corrupt else WOOD_OUT, COR_GLOW if corrupt else Color(0, 0, 0, 0), 4 if corrupt else 0, 23)


func _bird(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var bx := x + w * 46 / 100
	var by := y + h * 48 / 100
	p.disc(bx, by, w * 18 / 100, h * 12 / 100, BIRD_HI, BIRD_MID, BIRD_LO)
	p.disc(bx - w / 10, by - h / 8, w * 16 / 100, h * 8 / 100, BIRD_HI, WHITE, BIRD_MID)
	p.disc(bx + w * 16 / 100, by - h / 14, maxi(w / 12, 2), maxi(h / 14, 2), BIRD_HI, BIRD_MID, BIRD_LO)
	p.tri(bx + w * 22 / 100, by - h / 20, bx + w * 36 / 100, by, bx + w * 22 / 100, by + h / 16, BEAK)
	p.eye(bx + w * 18 / 100, by - h / 10)
	p.line(bx - w * 16 / 100, by, bx - w * 34 / 100, by - h / 8, BIRD_MID)
	p.line(bx - w * 16 / 100, by + 1, bx - w * 30 / 100, by + h / 10, BIRD_LO)
	p.line(bx + w / 10, by + h * 10 / 100, bx + w / 10, y + h - 2, BIRD_LO)
	p.line(bx + w / 5, by + h * 10 / 100, bx + w / 5, y + h - 2, BIRD_LO)
	p.finish(Color8(16, 24, 40), Color(0, 0, 0, 0), 0, 24)


func _militia(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var cx := x + w * 46 / 100
	var foot := y + h - 2
	var head_y := y + h * 22 / 100
	p.disc(cx, head_y, maxi(w / 10, 2), maxi(h / 11, 2), SKIN_HI, SKIN_MID, SKIN_LO)
	p.shade_rect(cx - w / 10, head_y - h / 10, w / 5, maxi(h / 12, 2), METAL_HI, METAL_MID, METAL_LO)
	p.eye(cx + w / 18, head_y)
	p.shade_rect(cx - w * 14 / 100, y + h * 34 / 100, w * 28 / 100, h * 28 / 100, TUNIC_HI, TUNIC_MID, TUNIC_LO)
	p.shade_rect(cx - w / 8, foot - h * 28 / 100, maxi(w / 12, 2), h * 28 / 100, TUNIC_HI, TUNIC_MID, TUNIC_LO)
	p.shade_rect(cx + w / 18, foot - h * 28 / 100, maxi(w / 12, 2), h * 28 / 100, TUNIC_HI, TUNIC_MID, TUNIC_LO)
	p.shade_rect(x + w / 8, y + h * 40 / 100, w / 7, h / 4, WOOD_HI, WOOD_MID, WOOD_LO)
	p.line(cx + w * 16 / 100, foot - h / 8, cx + w * 28 / 100, y + h / 8, WOOD_MID)
	p.tri(cx + w * 24 / 100, y + h / 10, cx + w * 34 / 100, y + h / 7, cx + w * 26 / 100, y + h / 5, METAL_HI)
	p.finish(Color8(20, 16, 28), Color(0, 0, 0, 0), 0, 25)


func _mite(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var cx := x + w / 2
	var cy := y + h * 58 / 100
	p.disc(cx, cy, w * 28 / 100, h * 16 / 100, CRYS_HI, CRYS_MID, CRYS_LO)
	p.disc(cx + w / 6, cy - h / 20, w / 8, h / 10, CRYS_HI, CRYS_MID, CRYS_LO)
	_gem(p, cx - w / 12, cy - h * 16 / 100, w / 8, h / 6, CRYS_HI, CRYS_MID, CRYS_LO, CRYS_GLOW)
	for i in 3:
		var lx := cx - w / 4 + i * w / 5
		p.line(lx, cy + h / 10, lx - w / 16, y + h - 2, CRYS_LO)
		p.line(lx + w / 10, cy + h / 12, lx + w / 8, y + h - 2, CRYS_LO)
	p.put(cx + w / 5, cy - h / 16, CRYS_GLOW)
	p.finish(CRYS_OUT, CRYS_GLOW, 3, 26)


func _bomber(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var cx := x + w / 2
	var cy := y + h * 58 / 100
	p.disc(cx, cy, w * 26 / 100, h * 22 / 100, PUMP_HI, PUMP_MID, PUMP_LO)
	p.line(cx, cy - h * 18 / 100, cx - w / 16, y + h / 8, LEAF_MID)
	p.disc(cx - w / 10, y + h / 7, maxi(w / 12, 2), maxi(h / 16, 2), LEAF_HI, LEAF_MID, LEAF_LO)
	p.eye(cx - w / 12, cy - h / 20)
	p.eye(cx + w / 10, cy - h / 20)
	p.line(cx - w / 12, cy + h / 12, cx + w / 10, cy + h / 10, PUMP_LO)
	p.rect(cx - w / 16, y + h - h / 6, maxi(w / 14, 2), h / 8, LEAF_LO)
	p.rect(cx + w / 10, y + h - h / 6, maxi(w / 14, 2), h / 8, LEAF_LO)
	p.finish(Color8(64, 24, 12), Color(0, 0, 0, 0), 0, 27)


func _thornling(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var cx := x + w / 2
	var cy := y + h * 55 / 100
	p.disc(cx, cy, w * 22 / 100, h * 20 / 100, LEAF_HI, LEAF_MID, LEAF_LO)
	for i in 7:
		var ang := i * 360 / 7
		var dx := int(round(cos(deg_to_rad(float(ang))) * float(w) * 0.32))
		var dy := int(round(sin(deg_to_rad(float(ang))) * float(h) * 0.32))
		p.line(cx + dx / 3, cy + dy / 3, cx + dx, cy + dy, LEAF_LO)
		p.put(cx + dx, cy + dy, WOOD_LO)
	p.eye(cx - w / 14, cy - h / 20)
	p.eye(cx + w / 12, cy - h / 20)
	p.line(cx - w / 10, y + h - 2, cx - w / 16, cy + h / 6, WOOD_MID)
	p.line(cx + w / 10, y + h - 2, cx + w / 16, cy + h / 6, WOOD_MID)
	p.finish(LEAF_OUT, Color(0, 0, 0, 0), 0, 28)


func _guard(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var cx := x + w * 44 / 100
	var foot := y + h - 2
	p.disc(cx, y + h * 20 / 100, maxi(w / 11, 2), maxi(h / 12, 2), CRYS_HI, CRYS_MID, CRYS_LO)
	p.rect(cx - w / 10, y + h * 22 / 100, w / 5, maxi(h / 18, 1), CRYS_GLOW)
	p.shade_rect(cx - w * 20 / 100, y + h * 32 / 100, w * 40 / 100, h * 28 / 100, CRYS_HI, CRYS_MID, CRYS_LO)
	p.shade_rect(cx - w / 6, foot - h * 26 / 100, maxi(w / 10, 2), h * 26 / 100, CRYS_HI, CRYS_MID, CRYS_LO)
	p.shade_rect(cx + w / 14, foot - h * 26 / 100, maxi(w / 10, 2), h * 26 / 100, CRYS_HI, CRYS_MID, CRYS_LO)
	_blade(p, cx + w / 5, y + h * 55 / 100, x + w - 3, y + h / 6)
	p.finish(CRYS_OUT, CRYS_GLOW, 3, 29)


func _wisp(p: Pix) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var cx := x + w / 2
	var cy := y + h * 58 / 100
	p.tri(cx, y + h / 8, cx - w / 5, cy, cx + w / 5, cy, CRYS_HI)
	p.disc(cx, cy, w * 22 / 100, h * 18 / 100, CRYS_HI, CRYS_MID, CRYS_LO)
	p.disc(cx, cy + h / 20, maxi(w / 10, 2), maxi(h / 12, 2), SOL_CORE, CRYS_HI, CRYS_MID)
	p.put(cx - w / 3, cy - h / 8, CRYS_GLOW)
	p.put(cx + w / 3, cy + h / 10, CRYS_GLOW)
	p.finish(CRYS_OUT, CRYS_GLOW, 2, 30)


func _legs(p: Pix, bx: int, top: int, w: int, h: int, foot: int, mid: Color, lo: Color) -> void:
	var lw := maxi(w / 16, 1)
	var span := maxi(w / 5, 4)
	var xs: Array[int] = [bx - span, bx - span / 3, bx + span / 5, bx + span]
	for lx in xs:
		p.shade_rect(lx, top, lw, maxi(foot - top, 2), mid, lo, lo)


func _plant(p: Pix, kind: String, stage: int, corrupt: bool) -> void:
	var crystal := kind in ["crystal_bush", "crystal_grass", "shard_tree"]
	var pal := _plant_pal(corrupt, crystal)
	match kind:
		"grass_tuft", "crystal_grass":
			_grass(p, stage, 1, pal, kind == "crystal_grass")
		"tall_grass":
			_grass(p, stage, 1, pal, false)
			_grass_extra(p, stage, pal)
		"fern":
			_fern(p, stage, pal)
		"bush", "crystal_bush":
			_bush(p, stage, pal, kind == "crystal_bush")
		"tree":
			_tree(p, stage, pal, false)
		"shard_tree":
			_tree(p, stage, pal, true)
		"wildflower":
			_flower(p, stage, pal, corrupt)
		_:
			_bush(p, stage, pal, false)
			_fail("unknown plant %s" % kind)
	var glow: Color = pal.glow
	var glow_n := 5 if corrupt or crystal else 0
	p.finish(pal.out, glow, glow_n, 40 + stage + (7 if corrupt else 0))


func _plant_pal(corrupt: bool, crystal: bool) -> Dictionary:
	if corrupt:
		return {"hi": COR_HI, "mid": COR_MID, "lo": COR_LO, "out": COR_OUT, "glow": COR_GLOW, "accent": COR_GLOW}
	if crystal:
		return {"hi": CRYS_HI, "mid": CRYS_MID, "lo": CRYS_LO, "out": CRYS_OUT, "glow": CRYS_GLOW, "accent": CRYS_GLOW}
	return {"hi": LEAF_HI, "mid": LEAF_MID, "lo": LEAF_LO, "out": LEAF_OUT, "glow": Color(0, 0, 0, 0), "accent": BERRY}


func _grass(p: Pix, stage: int, max_stage: int, pal: Dictionary, crystal: bool) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var base := y + h - 2
	var height := _grow(stage, max_stage, h * 35 / 100, h * 78 / 100)
	var count := 3 + stage
	for i in count:
		var bx := x + w * (18 + i * 16) / 100
		var lean := (i - count / 2) * maxi(w / 14, 1)
		var col: Color = pal.hi if i % 2 == 0 else pal.mid
		p.line(bx, base, bx + lean, base - height + i * 2, col)
		p.line(bx + 1, base, bx + lean + 1, base - height + h / 10, pal.lo)
	if crystal:
		_gem(p, x + w / 2, base - height / 2, maxi(w / 10, 2), maxi(h / 8, 3), pal.hi, pal.mid, pal.lo, pal.glow)


func _grass_extra(p: Pix, stage: int, pal: Dictionary) -> void:
	var r := _box(p)
	var x := r.position.x
	var base := r.position.y + r.size.y - 2
	var h := r.size.y
	var reach := _grow(stage, 1, h * 55 / 100, h * 88 / 100)
	p.line(x + r.size.x * 70 / 100, base, x + r.size.x * 88 / 100, base - reach, pal.hi)
	p.line(x + r.size.x * 20 / 100, base, x + r.size.x * 8 / 100, base - reach * 3 / 4, pal.mid)


func _fern(p: Pix, stage: int, pal: Dictionary) -> void:
	var r := _box(p)
	var x := r.position.x
	var w := r.size.x
	var h := r.size.y
	var base := r.position.y + h - 2
	var height := _grow(stage, 1, h * 50 / 100, h * 82 / 100)
	var top := base - height
	var bx := x + w / 2
	p.line(bx, base, bx - w / 12, top, pal.lo)
	var n := 3 + stage * 2
	for i in n:
		var t := (i + 1) * 100 / (n + 1)
		var yy := base - height * t / 100
		var length := w * (16 + i * 6) / 100
		var dir := -1 if i % 2 == 0 else 1
		p.line(bx - w / 24, yy, bx + dir * length / 2, yy - length / 6, pal.hi if i % 2 == 0 else pal.mid)
		p.line(bx - w / 24, yy + 1, bx + dir * length / 3, yy + 1, pal.lo)


func _bush(p: Pix, stage: int, pal: Dictionary, crystal: bool) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var rad := _grow(stage, 2, w * 16 / 100, w * 34 / 100)
	var cx := x + w / 2
	var cy := y + h * 58 / 100
	p.disc(cx, cy, rad, rad * 3 / 4, pal.hi, pal.mid, pal.lo)
	p.disc(cx - rad / 2, cy + rad / 5, rad * 3 / 5, rad / 2, pal.hi, pal.mid, pal.lo)
	p.disc(cx + rad / 3, cy - rad / 6, rad / 2, rad * 2 / 5, pal.hi, pal.mid, pal.lo)
	if crystal:
		_gem(p, cx, cy - rad / 2, maxi(rad / 3, 2), maxi(rad / 2, 3), pal.hi, pal.mid, pal.lo, pal.glow)
	elif stage > 0 and pal.accent.a > 0.5 and pal.accent != pal.glow:
		p.put(cx - rad / 3, cy, pal.accent)
		p.put(cx + rad / 4, cy + rad / 5, pal.accent)
		if stage > 1:
			p.put(cx, cy - rad / 4, pal.accent)


func _tree(p: Pix, stage: int, pal: Dictionary, shard: bool) -> void:
	var r := _box(p)
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var canopy := _grow(stage, 2, w * 16 / 100, w * 36 / 100)
	var trunk_h := _grow(stage, 2, h * 28 / 100, h * 46 / 100)
	var cx := x + w / 2
	var foot := y + h - 2
	var tw := maxi(w / 8, 2)
	var trunk_hi := WOOD_HI if pal.out != COR_OUT else COR_HI
	var trunk_mid := WOOD_MID if pal.out != COR_OUT else COR_MID
	var trunk_lo := WOOD_LO if pal.out != COR_OUT else COR_LO
	p.shade_rect(cx - tw / 2, foot - trunk_h, tw, trunk_h, trunk_hi, trunk_mid, trunk_lo)
	var cy := foot - trunk_h - canopy / 4
	if shard:
		_gem(p, cx, cy - canopy / 3, canopy * 2 / 3, canopy, pal.hi, pal.mid, pal.lo, pal.glow)
		_gem(p, cx - canopy / 2, cy, canopy / 2, canopy * 2 / 3, pal.hi, pal.mid, pal.lo, pal.glow)
		_gem(p, cx + canopy / 2, cy + canopy / 6, canopy / 2, canopy / 2, pal.mid, pal.lo, pal.hi, pal.glow)
	else:
		p.disc(cx, cy, canopy, canopy * 3 / 4, pal.hi, pal.mid, pal.lo)
		if stage > 0:
			p.disc(cx - canopy / 2, cy + canopy / 4, canopy * 3 / 5, canopy / 2, pal.hi, pal.mid, pal.lo)
		if stage > 1:
			p.disc(cx + canopy / 3, cy - canopy / 5, canopy / 2, canopy * 2 / 5, pal.hi, pal.mid, pal.lo)


func _flower(p: Pix, stage: int, pal: Dictionary, corrupt: bool) -> void:
	var r := _box(p)
	var x := r.position.x
	var w := r.size.x
	var h := r.size.y
	var base := r.position.y + h - 2
	var cx := x + w / 2
	var stem := _grow(stage, 1, h * 40 / 100, h * 62 / 100)
	var top := base - stem
	p.line(cx, base, cx, top, pal.lo)
	p.disc(cx - w / 6, top + stem / 3, maxi(w / 10, 2), maxi(h / 16, 2), pal.hi, pal.mid, pal.lo)
	p.disc(cx + w / 7, top + stem / 2, maxi(w / 12, 2), maxi(h / 18, 2), pal.hi, pal.mid, pal.lo)
	var petal: Color = COR_GLOW if corrupt else (FLOWER_P if stage > 0 else FLOWER_Y)
	p.disc(cx, top - h / 20, maxi(w / 8, 2), maxi(h / 9, 2), petal, petal, pal.lo)
	p.disc(cx, top - h / 20, maxi(w / 18, 1), maxi(h / 18, 1), SOL_HI if not corrupt else WHITE, petal, pal.mid)


func _gem(p: Pix, cx: int, cy: int, rx: int, ry: int, hi: Color, mid: Color, lo: Color, core: Color) -> void:
	rx = maxi(rx, 2)
	ry = maxi(ry, 3)
	p.tri(cx, cy - ry, cx - rx, cy, cx + rx, cy, hi)
	p.tri(cx - rx, cy, cx, cy + ry, cx + rx, cy, lo)
	p.tri(cx, cy - ry / 2, cx - rx / 3, cy, cx + rx / 4, cy + ry / 5, mid)
	if core.a > 0.5:
		p.put(cx, cy, core)


func _crystal(p: Pix, kind: String) -> void:
	var r := _box(p)
	var cx := r.position.x + r.size.x / 2
	var cy := r.position.y + r.size.y / 2
	var rx := r.size.x * 28 / 100
	var ry := r.size.y * 40 / 100
	match kind:
		"amethyst":
			_gem(p, cx, cy, rx, ry, CRYS_HI, CRYS_MID, CRYS_LO, CRYS_GLOW)
			_gem(p, cx - rx / 2, cy + ry / 5, rx / 3, ry / 2, CRYS_HI, CRYS_MID, CRYS_LO, CRYS_GLOW)
			_gem(p, cx + rx / 2, cy + ry / 6, rx / 3, ry / 2, CRYS_MID, CRYS_LO, CRYS_HI, WHITE)
			p.finish(CRYS_OUT, CRYS_GLOW, 5, 51)
		"void_shard":
			_gem(p, cx + r.size.x / 10, cy, rx * 3 / 4, ry, VOID_HI, VOID_MID, VOID_LO, VOID_HI)
			p.line(cx - rx / 4, cy - ry / 3, cx + rx / 5, cy + ry / 3, CRYS_GLOW)
			p.line(cx, cy - ry / 2, cx - rx / 5, cy + ry / 4, VOID_HI)
			p.finish(Color8(4, 2, 10), CRYS_GLOW, 4, 52)
		"solar_crystal":
			_gem(p, cx, cy, rx, ry, SOL_HI, SOL_MID, SOL_LO, SOL_CORE)
			p.line(cx - rx - 2, cy, cx - rx / 2, cy, SOL_HI)
			p.line(cx + rx / 2, cy, cx + rx + 2, cy, SOL_HI)
			p.line(cx, cy - ry - 2, cx, cy - ry / 2, SOL_CORE)
			p.finish(Color8(96, 40, 8), SOL_CORE, 4, 53)
		_:
			_gem(p, cx, cy, rx / 2, ry / 2, CRYS_HI, CRYS_MID, CRYS_LO, CRYS_GLOW)
			p.finish(CRYS_OUT, Color(0, 0, 0, 0), 0, 54)
			_fail("unknown crystal %s" % kind)


func _manifest_slots() -> Array:
	var text := FileAccess.get_file_as_string("res://docs/texture_manifest.json")
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return []
	var slots = parsed.get("slots", [])
	if slots is Array:
		return slots
	return []


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _contact_arg() -> String:
	var env := OS.get_environment("CRYSTALSTORM_CONTACT_OUT").strip_edges()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if str(args[i]) == "--contact" and i + 1 < args.size():
			return str(args[i + 1])
	return env


func _write_contact(out_path: String) -> void:
	if _sheet.is_empty():
		_fail("contact sheet has no sprites")
		return
	var scale := 4
	var cols := 4
	var max_side := 32
	for row in _sheet:
		max_side = maxi(max_side, maxi(int(row.w), int(row.h)))
	var label_h := 14
	var pad := 8
	var pair_w := max_side * scale * 2 + 6
	var pair_h := max_side * scale
	var cell_w := pair_w + pad
	var cell_h := label_h + pair_h + pad
	var rows := int(ceil(float(_sheet.size()) / float(cols)))
	var sheet := Image.create(cols * cell_w + pad, rows * cell_h + pad, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(54, 58, 66))
	for i in _sheet.size():
		var row: Dictionary = _sheet[i]
		var col := i % cols
		var line := i / cols
		var ox := pad + col * cell_w
		var oy := pad + line * cell_h
		_paint_text(sheet, str(row.name), ox, oy, Color8(236, 232, 220), 2)
		var left := _load_png(str(row.original))
		var right := _load_png(str(row.batch))
		var top := oy + label_h
		var half := max_side * scale
		if left != null:
			var dx := (half - left.get_width() * scale) / 2
			var dy := (half - left.get_height() * scale) / 2
			_blit(sheet, left, Vector2i(ox + dx, top + dy), scale)
		if right != null:
			var dx := (half - right.get_width() * scale) / 2
			var dy := (half - right.get_height() * scale) / 2
			_blit(sheet, right, Vector2i(ox + half + 4 + dx, top + dy), scale)
	var folder := out_path.get_base_dir()
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
	if sheet.save_png(out_path) != OK:
		_fail("contact sheet save failed")
		return
	print("contact sheet %s" % out_path)


func _load_png(res_or_abs: String) -> Image:
	if res_or_abs.is_empty():
		return null
	var abs_path := res_or_abs
	if res_or_abs.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(res_or_abs)
	if not FileAccess.file_exists(abs_path):
		return null
	var image := Image.load_from_file(abs_path)
	if image == null or image.is_empty():
		return null
	return image


func _blit(dst: Image, src: Image, at: Vector2i, scale: int) -> void:
	var big := src.duplicate()
	big.resize(maxi(src.get_width() * scale, 1), maxi(src.get_height() * scale, 1), Image.INTERPOLATE_NEAREST)
	var rect := Rect2i(0, 0, big.get_width(), big.get_height())
	if at.x + rect.size.x > dst.get_width() or at.y + rect.size.y > dst.get_height():
		return
	dst.blit_rect(big, rect, at)


func _paint_text(img: Image, text: String, x: int, y: int, color: Color, scale: int) -> void:
	var cursor := x
	var upper := text.to_upper()
	for i in upper.length():
		var ch := upper.substr(i, 1)
		var glyph := str(GLYPH.get(ch, "000000000000000"))
		if glyph.length() < 15:
			cursor += 4 * scale
			continue
		for gy in 5:
			for gx in 3:
				if glyph.substr(gy * 3 + gx, 1) != "1":
					continue
				for sy in scale:
					for sx in scale:
						var px := cursor + gx * scale + sx
						var py := y + gy * scale + sy
						if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
							img.set_pixel(px, py, color)
		cursor += 4 * scale
