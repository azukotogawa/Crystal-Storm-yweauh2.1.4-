extends SceneTree


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const TILE := 32

const STONE := {
	Vector2i(0, 4): [Color8(92, 88, 82), Color8(84, 80, 75), Color8(100, 96, 90), Color8(78, 82, 74), 7],
	Vector2i(1, 4): [Color8(108, 102, 94), Color8(99, 94, 87), Color8(118, 112, 104), Color8(90, 86, 78), 17],
	Vector2i(2, 4): [Color8(74, 78, 84), Color8(68, 72, 78), Color8(82, 86, 94), Color8(64, 70, 76), 29],
}
const ORE := {
	Vector2i(6, 1): [Color8(70, 68, 74), Color8(64, 62, 68), Color8(78, 76, 82), Color8(108, 78, 124), 43],
	Vector2i(4, 5): [Color8(82, 78, 86), Color8(76, 72, 80), Color8(90, 86, 94), Color8(124, 90, 140), 53],
	Vector2i(5, 5): [Color8(58, 60, 68), Color8(52, 54, 62), Color8(66, 68, 76), Color8(96, 70, 112), 61],
}
const CAVE := {
	Vector2i(3, 6): [Color8(66, 70, 76), Color8(60, 64, 70), Color8(74, 78, 84), Color8(88, 80, 102), 71],
	Vector2i(4, 6): [Color8(80, 84, 90), Color8(74, 78, 84), Color8(88, 92, 98), Color8(102, 96, 118), 83],
	Vector2i(6, 6): [Color8(54, 58, 64), Color8(48, 52, 58), Color8(62, 66, 72), Color8(76, 70, 90), 97],
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
	if not _blit_family(atlas, STONE, "stone", painted):
		quit(1)
		return
	if not _blit_family(atlas, ORE, "ore", painted):
		quit(1)
		return
	if not _blit_family(atlas, CAVE, "cave", painted):
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
