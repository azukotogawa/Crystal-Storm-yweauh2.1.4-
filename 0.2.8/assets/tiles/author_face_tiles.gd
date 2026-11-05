extends SceneTree


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const TILE := 32

const TARGETS := {
	Vector2i(3, 2): 0.09,
	Vector2i(0, 6): 0.10,
	Vector2i(5, 6): 0.18,
	Vector2i(6, 2): 0.255,
	Vector2i(6, 3): 0.22,
	Vector2i(6, 5): 0.16,
	Vector2i(0, 2): 0.36,
	Vector2i(1, 2): 0.40,
	Vector2i(2, 2): 0.42,
	Vector2i(3, 1): 0.52,
	Vector2i(4, 2): 0.34,
	Vector2i(0, 3): 0.24,
	Vector2i(2, 3): 0.20,
	Vector2i(4, 3): 0.30,
	Vector2i(0, 4): 0.585,
	Vector2i(1, 4): 0.55,
	Vector2i(2, 4): 0.66,
	Vector2i(0, 7): 0.75,
	Vector2i(1, 7): 0.71,
	Vector2i(2, 7): 0.83,
	Vector2i(0, 5): 0.93,
	Vector2i(1, 5): 0.86,
	Vector2i(2, 5): 0.90,
	Vector2i(6, 7): 0.11,
	Vector2i(5, 7): 0.42,
	Vector2i(4, 7): 0.62,
	Vector2i(3, 8): 0.18,
	Vector2i(4, 9): 0.38,
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


func _luma(c: Color) -> float:
	return c.get_luminance()


func _mean_luma(im: Image, cell: Vector2i) -> float:
	var sum := 0.0
	var ox := cell.x * TILE
	var oy := cell.y * TILE
	for y in TILE:
		for x in TILE:
			sum += _luma(im.get_pixel(ox + x, oy + y))
	return sum / float(TILE * TILE)


func _recolor(c: Color, lum: float) -> Color:
	var cur := _luma(c)
	if cur < 0.0008:
		return Color(lum, lum, lum, c.a)
	var f := lum / cur
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0), clampf(c.b * f, 0.0, 1.0), c.a)


func _copy_cell(im: Image, cell: Vector2i) -> Image:
	var tile := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	tile.blit_rect(im, Rect2i(cell.x * TILE, cell.y * TILE, TILE, TILE), Vector2i.ZERO)
	return tile


func _paste(im: Image, cell: Vector2i, tile: Image) -> void:
	im.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))


func _stretch_to(tile: Image, target: float, amount: float) -> void:
	var mean := 0.0
	for y in TILE:
		for x in TILE:
			mean += _luma(tile.get_pixel(x, y))
	mean /= float(TILE * TILE)
	for y in TILE:
		for x in TILE:
			var c := tile.get_pixel(x, y)
			var lum := _luma(c)
			var stretched := clampf(mean + (lum - mean) * amount, 0.025, 0.98)
			tile.set_pixel(x, y, _recolor(c, stretched))
	_nudge_mean(tile, target)


func _nudge_mean(tile: Image, target: float) -> void:
	var after := 0.0
	for y in TILE:
		for x in TILE:
			after += _luma(tile.get_pixel(x, y))
	after /= float(TILE * TILE)
	if after < 0.0008:
		return
	var scale := target / after
	for y in TILE:
		for x in TILE:
			var c := tile.get_pixel(x, y)
			tile.set_pixel(x, y, _recolor(c, clampf(_luma(c) * scale, 0.02, 0.985)))


func _row_luma(im: Image, y: int) -> float:
	var sum := 0.0
	for x in TILE:
		sum += _luma(im.get_pixel(x, y))
	return sum / float(TILE)


func _col_luma(im: Image, x: int) -> float:
	var sum := 0.0
	for y in TILE:
		sum += _luma(im.get_pixel(x, y))
	return sum / float(TILE)


func _has_grid(im: Image) -> bool:
	for y in TILE:
		var line := _row_luma(im, y)
		var neighbor := line
		if y > 0:
			neighbor = _row_luma(im, y - 1)
		if line < neighbor * 0.8:
			return true
	for x in TILE:
		var line := _col_luma(im, x)
		var neighbor := line
		if x > 0:
			neighbor = _col_luma(im, x - 1)
		if line < neighbor * 0.8:
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


func _stats(im: Image) -> Dictionary:
	var counts: Dictionary = {}
	var lo := 1.0
	var hi := 0.0
	for y in TILE:
		for x in TILE:
			var px := im.get_pixel(x, y)
			var key := px.to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
			var lum := _luma(px)
			lo = minf(lo, lum)
			hi = maxf(hi, lum)
	var mode := 0
	for key in counts.keys():
		mode = maxi(mode, int(counts[key]))
	return {"colors": counts.size(), "marks": TILE * TILE - mode, "span": hi - lo}


func _paint_speckle(base: Color, dark: Color, lite: Color, accent: Color, seed: int) -> Image:
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
		]
		var inks: Array[Color] = [dark, lite, accent, dark, lite, accent, dark, lite, accent, dark]
		for i in spots.size():
			im.set_pixel(spots[i], y, inks[i])
		var extra := 1 + (_h(seed, y, 4) % 28)
		im.set_pixel(extra, y, lite if y % 2 == 0 else accent)
	return im


func _add_ink(im: Image, ink: Color, seed: int) -> void:
	for y in TILE:
		var x := 1 + (_h(seed, y, 9) % 30)
		if im.get_pixel(x, y).is_equal_approx(ink):
			x = (x + 7) % TILE
		im.set_pixel(x, y, ink)
		if y % 2 == 0:
			im.set_pixel((x + 3) % TILE, y, ink)


func _with_span(im: Image) -> Image:
	var stats := _stats(im)
	if float(stats["span"]) >= 0.1 and int(stats["colors"]) >= 6:
		return im
	var base := im.get_pixel(0, 0)
	var dark := _recolor(base, clampf(_luma(base) * 0.62, 0.04, 0.9))
	var lite := _recolor(base, clampf(_luma(base) * 1.28, 0.08, 0.98))
	_add_ink(im, dark, 3)
	_add_ink(im, lite, 8)
	_add_ink(im, base.lerp(Color(0.15, 0.45, 0.2), 0.35), 13)
	return im


func _paint_lip(seed: int, dirt: Color, soil: Color, grass: Color, blade: Color) -> Image:
	var im := _paint_speckle(dirt, soil, dirt.lightened(0.12), soil.darkened(0.08), seed)
	for y in 4:
		for x in TILE:
			var band := y < 2 or (x + y + seed) % 3 != 0
			if y == 3 and (x + seed) % 2 == 0:
				band = false
			if band:
				im.set_pixel(x, y, grass if (x + y) % 4 != 0 else blade)
			else:
				im.set_pixel(x, y, dirt if (x + seed) % 2 == 0 else soil)
	return _with_span(im)


func _paint_bark(seed: int, base: Color, dark: Color, lite: Color, knot: Color) -> Image:
	var im := _paint_speckle(base, dark, lite, knot, seed)
	for y in TILE:
		var groove := (_h(seed, y / 3, 2) % 26) + 2
		im.set_pixel(groove, y, dark)
		im.set_pixel((groove + 1) % TILE, y, knot)
		if y % 5 == seed % 5:
			im.set_pixel((groove + 6) % TILE, y, lite)
	return _with_span(im)


func _paint_rings(seed: int, base: Color, dark: Color, lite: Color, heart: Color) -> Image:
	var im := _paint_speckle(base, dark, lite, heart, seed)
	var cx := 15.5 + float(seed % 3) - 1.0
	var cy := 15.5 + float((seed / 3) % 3) - 1.0
	for y in TILE:
		for x in TILE:
			var d := Vector2(float(x) - cx, float(y) - cy).length()
			var band := int(d + float(seed % 2)) % 4
			if band == 0 and d > 2.5:
				im.set_pixel(x, y, dark)
			elif band == 2 and d > 2.5:
				im.set_pixel(x, y, lite)
			elif d < 2.2:
				im.set_pixel(x, y, heart)
	return _with_span(im)


func _paint_crystal_side(seed: int) -> Image:
	return _with_span(_paint_speckle(
		Color8(150, 64, 176),
		Color8(110, 40, 140),
		Color8(186, 110, 204),
		Color8(210, 160, 214),
		seed
	))


func _accept(im: Image, label: String) -> bool:
	var stats := _stats(im)
	if _has_stripe(im) or _has_grid(im) or int(stats["colors"]) < 6 or int(stats["colors"]) > 24 or int(stats["marks"]) < 300 or float(stats["span"]) < 0.08:
		push_error(
			"%s rejected stripe=%s grid=%s colors=%d marks=%d span=%.3f"
			% [label, _has_stripe(im), _has_grid(im), stats["colors"], stats["marks"], stats["span"]]
		)
		return false
	print("OK %s colors=%d marks=%d span=%.3f" % [label, stats["colors"], stats["marks"], stats["span"]])
	return true


func _retarget(atlas: Image, cell: Vector2i, target: float) -> bool:
	var src := _copy_cell(atlas, cell)
	var tile := src.duplicate()
	_stretch_to(tile, target, 1.45)
	tile = _with_span(tile)
	_nudge_mean(tile, target)
	if _has_grid(tile) or _has_stripe(tile) or int(_stats(tile)["colors"]) > 24:
		tile = src.duplicate()
		_stretch_to(tile, target, 1.0)
		tile = _with_span(tile)
		_nudge_mean(tile, target)
	if not _accept(tile, "retarget %s L=%.3f" % [cell, _mean_luma(tile, Vector2i.ZERO)]):
		return false
	_paste(atlas, cell, tile)
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
	for cell in TARGETS.keys():
		if not _retarget(atlas, cell, float(TARGETS[cell])):
			quit(1)
			return
	var lips := {
		Vector2i(3, 4): 21,
		Vector2i(5, 4): 44,
		Vector2i(6, 4): 67,
	}
	var lip_colors := [
		[Color8(118, 74, 42), Color8(92, 56, 32), Color8(86, 122, 48), Color8(64, 96, 36)],
		[Color8(132, 84, 48), Color8(104, 64, 36), Color8(98, 138, 54), Color8(74, 108, 40)],
		[Color8(104, 64, 36), Color8(80, 48, 28), Color8(74, 110, 42), Color8(56, 88, 32)],
	]
	var i := 0
	for cell in lips.keys():
		var cols: Array = lip_colors[i]
		var tile := _paint_lip(int(lips[cell]), cols[0], cols[1], cols[2], cols[3])
		if not _accept(tile, "lip %s" % cell):
			quit(1)
			return
		_paste(atlas, cell, tile)
		i += 1
	var barks := {
		Vector2i(1, 3): [Color8(132, 86, 48), Color8(78, 46, 26), Color8(176, 128, 76), Color8(96, 60, 34), 19],
		Vector2i(5, 3): [Color8(118, 74, 40), Color8(68, 40, 22), Color8(164, 116, 68), Color8(88, 54, 30), 37],
		Vector2i(4, 4): [Color8(146, 96, 54), Color8(88, 52, 30), Color8(188, 140, 86), Color8(108, 68, 38), 53],
	}
	for cell in barks.keys():
		var spec: Array = barks[cell]
		var tile := _paint_bark(int(spec[4]), spec[0], spec[1], spec[2], spec[3])
		if not _accept(tile, "bark %s" % cell):
			quit(1)
			return
		_paste(atlas, cell, tile)
	var ends := {
		Vector2i(3, 3): [Color8(168, 124, 74), Color8(102, 68, 38), Color8(196, 156, 102), Color8(214, 176, 122), 11],
		Vector2i(3, 7): [Color8(150, 108, 64), Color8(90, 58, 32), Color8(184, 142, 90), Color8(200, 160, 108), 29],
		Vector2i(5, 9): [Color8(184, 138, 84), Color8(114, 76, 44), Color8(210, 170, 116), Color8(224, 188, 136), 47],
	}
	for cell in ends.keys():
		var spec: Array = ends[cell]
		var tile := _paint_rings(int(spec[4]), spec[0], spec[1], spec[2], spec[3])
		if not _accept(tile, "end %s" % cell):
			quit(1)
			return
		_paste(atlas, cell, tile)
	var shard := _paint_crystal_side(71)
	if not _accept(shard, "shard side"):
		quit(1)
		return
	_paste(atlas, Vector2i(3, 5), shard)
	var err := atlas.save_png(path)
	if err != OK:
		push_error("save failed %s" % err)
		quit(1)
		return
	print("WROTE %s" % path)
	quit(0)
