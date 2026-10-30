extends SceneTree


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const TILE := 32

const FAMILIES := {
	"grass": {
		Vector2i(0, 2): [Color8(40, 154, 44), Color8(30, 132, 34), Color8(58, 176, 58), Color8(78, 150, 46), 11, "grass"],
		Vector2i(1, 2): [Color8(32, 136, 36), Color8(24, 116, 28), Color8(48, 158, 48), Color8(68, 132, 40), 23, "grass"],
		Vector2i(2, 2): [Color8(44, 150, 46), Color8(32, 128, 36), Color8(58, 170, 58), Color8(74, 146, 46), 37, "grass"],
	},
	"dirt": {
		Vector2i(3, 2): [Color8(116, 44, 28), Color8(96, 32, 20), Color8(136, 56, 36), Color8(100, 48, 36), 41, "dirt"],
		Vector2i(0, 6): [Color8(100, 36, 22), Color8(80, 26, 16), Color8(120, 48, 30), Color8(88, 40, 30), 43, "dirt"],
		Vector2i(5, 6): [Color8(132, 52, 32), Color8(110, 38, 24), Color8(152, 66, 42), Color8(116, 56, 40), 47, "dirt"],
	},
	"stone": {
		Vector2i(0, 4): [Color8(148, 162, 194), Color8(126, 140, 172), Color8(170, 184, 214), Color8(138, 156, 186), 53, "stone"],
		Vector2i(1, 4): [Color8(132, 146, 178), Color8(112, 126, 158), Color8(154, 168, 198), Color8(122, 140, 170), 59, "stone"],
		Vector2i(2, 4): [Color8(160, 174, 204), Color8(138, 152, 184), Color8(182, 196, 222), Color8(150, 168, 196), 61, "stone"],
	},
	"sand": {
		Vector2i(0, 7): [Color8(236, 214, 72), Color8(214, 188, 56), Color8(248, 230, 110), Color8(200, 176, 64), 67, "sand"],
		Vector2i(1, 7): [Color8(224, 200, 56), Color8(202, 174, 44), Color8(240, 218, 92), Color8(188, 164, 52), 71, "sand"],
		Vector2i(2, 7): [Color8(244, 224, 88), Color8(222, 198, 68), Color8(252, 236, 124), Color8(208, 184, 72), 73, "sand"],
	},
	"snow": {
		Vector2i(0, 5): [Color8(236, 244, 252), Color8(206, 220, 236), Color8(248, 250, 255), Color8(220, 232, 246), 79, "snow"],
		Vector2i(1, 5): [Color8(220, 232, 244), Color8(192, 208, 228), Color8(236, 244, 252), Color8(206, 220, 238), 83, "snow"],
		Vector2i(2, 5): [Color8(246, 250, 255), Color8(218, 230, 244), Color8(255, 255, 255), Color8(230, 240, 250), 89, "snow"],
	},
	"crystal": {
		Vector2i(6, 2): [Color8(168, 48, 190), Color8(142, 36, 164), Color8(196, 78, 214), Color8(214, 140, 220), 97, "crystal"],
		Vector2i(6, 3): [Color8(142, 36, 168), Color8(118, 28, 144), Color8(170, 64, 192), Color8(188, 112, 196), 101, "crystal"],
		Vector2i(6, 5): [Color8(124, 44, 112), Color8(102, 32, 92), Color8(148, 70, 132), Color8(160, 96, 140), 103, "crystal"],
	},
	"vein": {
		Vector2i(6, 1): [Color8(86, 72, 112), Color8(68, 56, 92), Color8(108, 92, 136), Color8(176, 72, 196), 107, "crystal"],
		Vector2i(4, 5): [Color8(74, 62, 100), Color8(58, 48, 82), Color8(96, 82, 124), Color8(160, 60, 184), 109, "crystal"],
		Vector2i(5, 5): [Color8(98, 82, 126), Color8(78, 64, 104), Color8(120, 102, 150), Color8(190, 84, 210), 113, "crystal"],
	},
	"face": {
		Vector2i(6, 7): [Color8(84, 28, 16), Color8(64, 20, 12), Color8(104, 40, 22), Color8(72, 32, 24), 127, "dirt"],
		Vector2i(5, 7): [Color8(108, 120, 148), Color8(88, 100, 128), Color8(128, 142, 170), Color8(100, 116, 144), 131, "stone"],
		Vector2i(4, 7): [Color8(196, 168, 48), Color8(172, 144, 36), Color8(214, 190, 72), Color8(160, 136, 40), 137, "sand"],
		Vector2i(3, 8): [Color8(112, 28, 132), Color8(88, 20, 108), Color8(140, 52, 156), Color8(160, 90, 168), 139, "crystal"],
		Vector2i(4, 9): [Color8(150, 64, 176), Color8(124, 44, 148), Color8(176, 96, 198), Color8(196, 140, 204), 149, "crystal"],
	},
}


func _init() -> void:
	call_deferred("_run")


func _h(seed: int, a: int, b: int) -> int:
	var n: int = a * 1103515245 + b * 12345 + seed * 1013904223
	n = (n ^ (n >> 16)) * 2246822519
	n = n ^ (n >> 13)
	if n < 0:
		n = -n
	return n


func _paint(base: Color, dark: Color, lite: Color, accent: Color, seed: int, kind: String) -> Image:
	var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	im.fill(base)
	for y in TILE:
		var spots: Array[int] = [
			(y * 3 + seed) % TILE,
			(y * 3 + seed + 8) % TILE,
			(y * 5 + seed + 3) % TILE,
			(y * 5 + seed + 14) % TILE,
			(y * 7 + seed + 19) % TILE,
			(y * 7 + seed + 25) % TILE,
			(y * 11 + seed + 6) % TILE,
			(y * 11 + seed + 21) % TILE,
			(y * 13 + seed + 10) % TILE,
			(y * 13 + seed + 27) % TILE,
			(y * 17 + seed + 4) % TILE,
			(y * 17 + seed + 16) % TILE,
		]
		var inks: Array[Color] = [dark, lite, accent, dark, lite, accent, dark, lite, accent, dark, lite, accent]
		for i in spots.size():
			im.set_pixel(spots[i], y, inks[i])
		_motif(im, y, seed, kind, dark, lite, accent)
	return im


func _motif(im: Image, y: int, seed: int, kind: String, dark: Color, lite: Color, accent: Color) -> void:
	if kind == "grass":
		var bx := (seed + (y / 3) * 5) % TILE
		im.set_pixel(bx, y, lite)
		im.set_pixel((bx + 1) % TILE, y, accent if y % 3 == 0 else lite)
	elif kind == "dirt":
		var cx := (seed + (y / 4) * 7) % TILE
		if y % 4 < 2:
			im.set_pixel(cx, y, dark)
			im.set_pixel((cx + 1) % TILE, y, dark)
			im.set_pixel((cx + 2) % TILE, y, lite)
	elif kind == "stone":
		var crack := (y + seed) % TILE
		im.set_pixel(crack, y, dark)
		im.set_pixel((crack + 1) % TILE, y, accent)
		if y % 7 == seed % 7:
			for k in 4:
				im.set_pixel((crack + 4 + k) % TILE, y, dark)
	elif kind == "sand":
		var phase := (y * 2 + seed) % TILE
		for k in range(0, TILE, 8):
			im.set_pixel((phase + k) % TILE, y, accent)
			im.set_pixel((phase + k + 1) % TILE, y, lite)
	elif kind == "snow":
		if (y + seed) % 4 == 0:
			var p := (y * 4 + seed) % TILE
			im.set_pixel(p, y, dark)
			im.set_pixel((p + 1) % TILE, y, dark)
	elif kind == "crystal":
		var a := (y + seed) % TILE
		var b := (TILE - 1 - ((y * 2 + seed) % TILE)) % TILE
		im.set_pixel(a, y, lite)
		im.set_pixel((a + 1) % TILE, y, accent)
		im.set_pixel(b, y, dark)


func _has_stripe(im: Image) -> bool:
	var mode := _mode_key(im)
	var masks: Array[int] = []
	for y in TILE:
		var mask := 0
		for x in TILE:
			if im.get_pixel(x, y).to_html(false) != mode:
				mask |= 1 << x
		masks.append(mask)
	for y in range(TILE - 3):
		var mask: int = masks[y]
		if mask == 0:
			continue
		if mask == masks[y + 1] and mask == masks[y + 2] and mask == masks[y + 3]:
			return true
	return false


func _mode_key(im: Image) -> String:
	var counts: Dictionary = {}
	for y in TILE:
		for x in TILE:
			var key := im.get_pixel(x, y).to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
	var best := ""
	var mode := -1
	for key in counts.keys():
		if int(counts[key]) > mode:
			mode = int(counts[key])
			best = str(key)
	return best


func _luma_row(im: Image, y: int) -> float:
	var sum := 0.0
	for x in TILE:
		sum += im.get_pixel(x, y).get_luminance()
	return sum / float(TILE)


func _luma_col(im: Image, x: int) -> float:
	var sum := 0.0
	for y in TILE:
		sum += im.get_pixel(x, y).get_luminance()
	return sum / float(TILE)


func _has_grid(im: Image) -> bool:
	for y in TILE:
		var line := _luma_row(im, y)
		var neighbor := line
		if y > 0:
			neighbor = _luma_row(im, y - 1)
		if line < neighbor * 0.8:
			return true
	for x in TILE:
		var line := _luma_col(im, x)
		var neighbor := line
		if x > 0:
			neighbor = _luma_col(im, x - 1)
		if line < neighbor * 0.8:
			return true
	return false


func _stats(im: Image) -> Dictionary:
	var counts: Dictionary = {}
	for y in TILE:
		for x in TILE:
			var key := im.get_pixel(x, y).to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
	var mode := 0
	for key in counts.keys():
		mode = maxi(mode, int(counts[key]))
	return {"colors": counts.size(), "marks": TILE * TILE - mode}


func _accept(im: Image, label: String) -> bool:
	var stats := _stats(im)
	if _has_stripe(im) or _has_grid(im) or int(stats["colors"]) < 4 or int(stats["colors"]) > 24 or int(stats["marks"]) < 280:
		push_error(
			"%s rejected stripe=%s grid=%s colors=%d marks=%d"
			% [label, _has_stripe(im), _has_grid(im), stats["colors"], stats["marks"]]
		)
		return false
	print("OK %s colors=%d marks=%d" % [label, stats["colors"], stats["marks"]])
	return true


func _mean(im: Image) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := float(TILE * TILE)
	for y in TILE:
		for x in TILE:
			var px := im.get_pixel(x, y)
			r += px.r
			g += px.g
			b += px.b
	return Color(r / n, g / n, b / n)


func _run() -> void:
	var path := ProjectSettings.globalize_path(ATLAS_PATH)
	var atlas := Image.load_from_file(path)
	if atlas == null:
		push_error("cannot load Cube.png")
		quit(1)
		return
	if atlas.get_format() != Image.FORMAT_RGBA8:
		atlas.convert(Image.FORMAT_RGBA8)
	var painted: Array[Image] = []
	var means: Dictionary = {}
	for label in FAMILIES.keys():
		var family: Dictionary = FAMILIES[label]
		for cell in family.keys():
			var spec: Array = family[cell]
			var tile := _paint(spec[0], spec[1], spec[2], spec[3], int(spec[4]), str(spec[5]))
			if not _accept(tile, "%s %s" % [label, cell]):
				quit(1)
				return
			atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))
			painted.append(tile)
			if not means.has(label):
				var mean := _mean(tile)
				means[label] = mean
				print(
					"MEAN %s L=%.3f H=%.3f S=%.3f"
					% [label, mean.get_luminance(), mean.h, mean.s]
				)
	for i in painted.size():
		for j in range(i + 1, painted.size()):
			var diff := 0
			for y in TILE:
				for x in TILE:
					if painted[i].get_pixel(x, y).to_html(false) != painted[j].get_pixel(x, y).to_html(false):
						diff += 1
			if diff < 40:
				push_error("painted tiles %d and %d differ by %d" % [i, j, diff])
				quit(1)
				return
	var err := atlas.save_png(path)
	if err != OK:
		push_error("save failed %s" % err)
		quit(1)
		return
	print("WROTE %s" % path)
	quit(0)
