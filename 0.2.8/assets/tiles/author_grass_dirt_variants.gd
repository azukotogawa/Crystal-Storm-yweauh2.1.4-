extends SceneTree
## Repaint the grass-top and dirt-family cells of Cube.png.
## Short blades and clods inside the tile. No 4px band and no dark grid line.
##   godot --headless --path . -s res://assets/tiles/author_grass_dirt_variants.gd


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const TILE := 32

## base, dark, light, pebble. Each accent stays near the base so a full
## row of one accent is not 20% darker than its neighbor.
const GRASS := {
	Vector2i(0, 2): [Color8(42, 78, 36), Color8(39, 73, 33), Color8(45, 83, 39), Color8(70, 64, 40), 3],
	Vector2i(1, 2): [Color8(68, 124, 50), Color8(63, 115, 47), Color8(73, 133, 54), Color8(88, 110, 58), 11],
	Vector2i(2, 2): [Color8(96, 168, 64), Color8(89, 156, 60), Color8(103, 180, 68), Color8(120, 150, 70), 19],
}
const DIRT := {
	Vector2i(3, 2): [Color8(124, 88, 56), Color8(115, 82, 52), Color8(133, 94, 60), Color8(100, 92, 70), 5],
	Vector2i(0, 6): [Color8(98, 70, 44), Color8(91, 65, 41), Color8(105, 75, 47), Color8(80, 74, 56), 23],
	Vector2i(5, 6): [Color8(156, 118, 76), Color8(145, 110, 71), Color8(167, 126, 81), Color8(130, 120, 90), 37],
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


## Each row keeps one private column the neighbors in a 4-row window do not
## use, so the non-fill mask cannot repeat for four rows.
func _paint(base: Color, dark: Color, lite: Color, pebble: Color, seed: int) -> Image:
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
				mark = pebble
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


func _masks(im: Image) -> Array:
	var mode := _mode_key(im)
	var masks: Array = []
	for y in TILE:
		var mask := 0
		for x in TILE:
			if im.get_pixel(x, y).to_html(false) != mode:
				mask |= 1 << x
		masks.append(mask)
	return masks


func _has_stripe(im: Image) -> bool:
	var masks := _masks(im)
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
	for cell in GRASS.keys():
		var spec: Array = GRASS[cell]
		var tile := _paint(spec[0], spec[1], spec[2], spec[3], int(spec[4]))
		if not _accept(tile, "grass %s" % cell):
			quit(1)
			return
		atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))
		painted.append(tile)
		print("GRASS %s" % cell)
	for cell in DIRT.keys():
		var spec: Array = DIRT[cell]
		var tile := _paint(spec[0], spec[1], spec[2], spec[3], int(spec[4]))
		if not _accept(tile, "dirt %s" % cell):
			quit(1)
			return
		atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))
		painted.append(tile)
		print("DIRT %s" % cell)
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
