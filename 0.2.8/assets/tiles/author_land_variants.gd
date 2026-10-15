extends SceneTree


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const TILE := 32

const FAMILIES := {
	"sand": {
		Vector2i(0, 7): [Color8(196, 168, 112), Color8(184, 156, 104), Color8(208, 180, 124), Color8(170, 150, 96), 101],
		Vector2i(1, 7): [Color8(176, 148, 96), Color8(164, 138, 88), Color8(188, 160, 108), Color8(154, 132, 84), 103],
		Vector2i(2, 7): [Color8(214, 186, 128), Color8(202, 174, 118), Color8(224, 198, 140), Color8(186, 164, 108), 107],
	},
	"beach": {
		Vector2i(0, 1): [Color8(220, 204, 164), Color8(208, 192, 152), Color8(230, 216, 176), Color8(196, 180, 140), 111],
		Vector2i(1, 1): [Color8(204, 188, 148), Color8(192, 176, 136), Color8(216, 200, 160), Color8(180, 164, 128), 113],
		Vector2i(2, 1): [Color8(232, 216, 176), Color8(220, 204, 164), Color8(240, 226, 188), Color8(208, 192, 156), 127],
	},
	"leaves": {
		Vector2i(0, 3): [Color8(42, 86, 36), Color8(36, 76, 32), Color8(50, 96, 42), Color8(64, 78, 34), 131],
		Vector2i(2, 3): [Color8(28, 64, 30), Color8(24, 56, 26), Color8(36, 74, 36), Color8(48, 70, 28), 137],
		Vector2i(4, 3): [Color8(58, 108, 46), Color8(50, 96, 40), Color8(68, 120, 52), Color8(78, 96, 40), 139],
	},
	"wood": {
		Vector2i(1, 3): [Color8(118, 78, 44), Color8(106, 70, 40), Color8(130, 88, 50), Color8(92, 64, 40), 149],
		Vector2i(3, 3): [Color8(96, 62, 36), Color8(86, 54, 32), Color8(108, 72, 42), Color8(78, 52, 34), 151],
		Vector2i(5, 3): [Color8(140, 94, 54), Color8(128, 84, 48), Color8(152, 106, 62), Color8(112, 78, 46), 157],
	},
	"snow": {
		Vector2i(0, 5): [Color8(228, 232, 236), Color8(214, 220, 226), Color8(238, 240, 244), Color8(200, 210, 220), 163],
		Vector2i(1, 5): [Color8(210, 218, 226), Color8(198, 206, 216), Color8(222, 228, 234), Color8(186, 198, 210), 167],
		Vector2i(2, 5): [Color8(236, 240, 244), Color8(224, 230, 236), Color8(244, 246, 248), Color8(208, 218, 228), 173],
	},
	"tundra": {
		Vector2i(0, 8): [Color8(156, 164, 158), Color8(144, 152, 146), Color8(168, 176, 170), Color8(132, 140, 134), 179],
		Vector2i(1, 8): [Color8(140, 148, 142), Color8(128, 136, 130), Color8(152, 160, 154), Color8(118, 126, 120), 181],
		Vector2i(2, 8): [Color8(172, 178, 168), Color8(160, 166, 156), Color8(184, 190, 180), Color8(148, 154, 144), 191],
	},
	"basin": {
		Vector2i(0, 9): [Color8(168, 150, 118), Color8(156, 138, 108), Color8(180, 162, 130), Color8(146, 132, 104), 193],
		Vector2i(1, 9): [Color8(186, 168, 136), Color8(174, 156, 124), Color8(198, 180, 148), Color8(160, 148, 116), 197],
		Vector2i(2, 9): [Color8(150, 134, 106), Color8(138, 122, 96), Color8(162, 146, 118), Color8(128, 116, 92), 199],
	},
	"valley": {
		Vector2i(1, 6): [Color8(124, 92, 68), Color8(112, 82, 60), Color8(136, 102, 76), Color8(100, 78, 58), 211],
		Vector2i(2, 6): [Color8(104, 76, 56), Color8(94, 68, 50), Color8(116, 86, 64), Color8(84, 64, 48), 223],
		Vector2i(3, 9): [Color8(144, 106, 76), Color8(132, 96, 68), Color8(156, 118, 86), Color8(118, 90, 64), 227],
	},
	"dry": {
		Vector2i(3, 1): [Color8(118, 108, 52), Color8(108, 98, 46), Color8(130, 120, 60), Color8(96, 90, 44), 229],
		Vector2i(4, 2): [Color8(186, 170, 78), Color8(172, 156, 70), Color8(198, 184, 90), Color8(156, 144, 64), 233],
		Vector2i(5, 2): [Color8(150, 138, 64), Color8(138, 126, 56), Color8(162, 150, 74), Color8(124, 114, 52), 239],
	},
	"farm": {
		Vector2i(4, 1): [Color8(112, 78, 46), Color8(102, 70, 40), Color8(124, 88, 52), Color8(90, 66, 40), 241],
		Vector2i(4, 8): [Color8(128, 90, 52), Color8(116, 80, 46), Color8(140, 102, 60), Color8(104, 76, 44), 251],
		Vector2i(5, 8): [Color8(96, 66, 40), Color8(86, 58, 36), Color8(108, 76, 46), Color8(78, 56, 36), 257],
	},
	"path": {
		Vector2i(5, 1): [Color8(132, 120, 102), Color8(120, 110, 94), Color8(144, 132, 114), Color8(108, 100, 88), 263],
		Vector2i(6, 8): [Color8(114, 104, 90), Color8(104, 94, 82), Color8(126, 116, 102), Color8(94, 86, 76), 269],
		Vector2i(6, 9): [Color8(150, 138, 118), Color8(138, 126, 108), Color8(162, 150, 130), Color8(124, 114, 98), 271],
	},
	"ocean": {
		Vector2i(0, 0): [Color8(24, 64, 112), Color8(20, 56, 100), Color8(32, 76, 124), Color8(36, 88, 130), 277],
		Vector2i(2, 0): [Color8(16, 48, 92), Color8(14, 42, 82), Color8(24, 60, 104), Color8(28, 72, 112), 281],
		Vector2i(4, 0): [Color8(32, 80, 132), Color8(26, 70, 118), Color8(42, 92, 144), Color8(48, 100, 148), 283],
	},
	"river": {
		Vector2i(1, 0): [Color8(48, 128, 150), Color8(40, 116, 138), Color8(58, 140, 162), Color8(64, 150, 160), 293],
		Vector2i(3, 0): [Color8(36, 108, 132), Color8(30, 96, 120), Color8(46, 120, 144), Color8(52, 132, 148), 307],
		Vector2i(5, 0): [Color8(60, 146, 164), Color8(50, 132, 152), Color8(72, 158, 176), Color8(78, 164, 170), 311],
	},
	"crystal": {
		Vector2i(6, 2): [Color8(148, 72, 186), Color8(132, 64, 170), Color8(164, 86, 200), Color8(176, 120, 210), 313],
		Vector2i(6, 3): [Color8(110, 64, 160), Color8(98, 56, 146), Color8(124, 76, 174), Color8(140, 100, 180), 317],
		Vector2i(6, 5): [Color8(92, 52, 112), Color8(80, 46, 100), Color8(106, 64, 126), Color8(120, 80, 130), 331],
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


func _paint(base: Color, dark: Color, lite: Color, grain: Color, seed: int) -> Image:
	var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	im.fill(base)
	for y in TILE:
		var sig := 1 + (y % 30)
		var blocked := {}
		for dy in range(-3, 4):
			var yy := y + dy
			if yy >= 0 and yy < TILE:
				blocked[1 + (yy % 30)] = true
		im.set_pixel(sig, y, dark if y % 2 == 0 else lite)
		var placed := 0
		var k := 0
		while placed < 9 and k < 48:
			var x := 1 + (_h(seed, y, k) % 30)
			k += 1
			if blocked.has(x):
				continue
			if im.get_pixel(x, y).is_equal_approx(base) == false:
				continue
			var mark := lite
			if placed % 3 == 1:
				mark = dark
			elif placed % 3 == 2:
				mark = grain
			im.set_pixel(x, y, mark)
			if placed % 4 == 0 and y + 1 < TILE:
				var below := y + 1
				var sig_below := 1 + (below % 30)
				if x != sig_below and not _near_sig(below, x):
					im.set_pixel(x, below, dark)
			placed += 1
	return im


func _near_sig(y: int, x: int) -> bool:
	for dy in range(-3, 4):
		var yy := y + dy
		if yy >= 0 and yy < TILE and x == 1 + (yy % 30):
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


func _blit_family(atlas: Image, family: Dictionary, label: String, painted: Array[Image]) -> bool:
	for cell in family.keys():
		var spec: Array = family[cell]
		var tile := _paint(spec[0], spec[1], spec[2], spec[3], int(spec[4]))
		if not _accept(tile, "%s %s" % [label, cell]):
			return false
		atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))
		painted.append(tile)
		print("%s %s" % [label, cell])
	return true


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
	for label in FAMILIES.keys():
		if not _blit_family(atlas, FAMILIES[label], label, painted):
			quit(1)
			return
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
