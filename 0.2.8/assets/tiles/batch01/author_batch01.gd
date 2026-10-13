extends SceneTree
## Author Batch 01 32×32 tiles: fill + 2–4px marks, one palette.
## Blit ONLY the ten Cube.png cells. Usage:
##   godot --headless --path . -s assets/tiles/batch01/author_batch01.gd


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const SRC_DIR := "res://assets/tiles/batch01"
const TILE := 32
const COLS := 7
const ROWS := 10

const SLOTS := {
	"ocean": Vector2i(0, 0),
	"river": Vector2i(1, 0),
	"beach": Vector2i(0, 1),
	"grassland3": Vector2i(2, 2),
	"dirt": Vector2i(3, 2),
	"hills": Vector2i(0, 3),
	"tree_trunk": Vector2i(2, 3),
	"stone": Vector2i(0, 4),
	"stone2": Vector2i(2, 4),
	"dirt2": Vector2i(0, 6),
}

# One world: sit under honey gate / slate bridge / ochre ruin / terracotta hall.
# Sides painted a step light (shader ×0.68).
const GRASS := Color(0.30, 0.50, 0.24)
const GRASS_D := Color(0.20, 0.36, 0.16)
const GRASS_L := Color(0.40, 0.58, 0.28)
const DIRT := Color(0.58, 0.42, 0.26)
const DIRT_D := Color(0.46, 0.32, 0.18)
const DIRT2 := Color(0.28, 0.20, 0.14)
const DIRT2_D := Color(0.18, 0.13, 0.10)
const RIVER := Color(0.16, 0.36, 0.50)
const RIVER_D := Color(0.10, 0.26, 0.40)
const OCEAN := Color(0.08, 0.16, 0.32)
const OCEAN_D := Color(0.05, 0.10, 0.22)
const BEACH := Color(0.82, 0.72, 0.48)
const BEACH_D := Color(0.70, 0.58, 0.34)
const STONE := Color(0.50, 0.52, 0.56)
const STONE_D := Color(0.34, 0.36, 0.40)
const STONE_L := Color(0.62, 0.64, 0.68)
const STONE2 := Color(0.58, 0.46, 0.34)
const STONE2_D := Color(0.40, 0.30, 0.22)
const HILLS := Color(0.12, 0.28, 0.14)
const HILLS_D := Color(0.08, 0.18, 0.10)
const HILLS_L := Color(0.18, 0.36, 0.16)
const BARK := Color(0.34, 0.20, 0.12)
const BARK_D := Color(0.22, 0.12, 0.08)
const BARK_L := Color(0.46, 0.30, 0.16)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var abs_atlas := ProjectSettings.globalize_path(ATLAS_PATH)
	var abs_src := ProjectSettings.globalize_path(SRC_DIR)
	DirAccess.make_dir_recursive_absolute(abs_src)
	var atlas := Image.load_from_file(abs_atlas)
	if atlas == null:
		push_error("cannot load atlas")
		quit(1)
		return
	if atlas.get_width() != COLS * TILE or atlas.get_height() != ROWS * TILE:
		push_error("bad atlas size")
		quit(1)
		return
	if atlas.get_format() != Image.FORMAT_RGBA8:
		atlas.convert(Image.FORMAT_RGBA8)

	var tiles := {
		"grassland3": _tile_grass(),
		"dirt": _tile_clods(DIRT, DIRT_D),
		"dirt2": _tile_clods(DIRT2, DIRT2_D),
		"river": _tile_water(RIVER, RIVER_D, false),
		"ocean": _tile_water(OCEAN, OCEAN_D, true),
		"beach": _tile_clods(BEACH, BEACH_D),
		"hills": _tile_canopy(),
		"tree_trunk": _tile_bark(),
		"stone": _tile_stone(STONE, STONE_D, STONE_L),
		"stone2": _tile_stone(STONE2, STONE2_D, STONE2.lerp(Color(0.70, 0.56, 0.40), 0.4)),
	}

	for name in SLOTS.keys():
		var cell: Vector2i = SLOTS[name]
		var tile: Image = tiles[name]
		_wrap_blend(tile)
		tile.save_png(abs_src.path_join("%s.png" % name))
		_save_repeat(tile, abs_src.path_join("%s_2x2.png" % name))
		atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))
		print("BLIT %s -> (%d,%d)" % [name, cell.x, cell.y])

	atlas.save_png(abs_atlas)
	print("WROTE %s %dx%d" % [abs_atlas, atlas.get_width(), atlas.get_height()])
	quit(0)


func _blank(c: Color) -> Image:
	var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	im.fill(c)
	return im


func _blob(im: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_plot(im, cx + dx, cy + dy, c)


func _tile_grass() -> Image:
	var im := _blank(GRASS)
	var spots: Array[Vector2i] = [
		Vector2i(5, 7), Vector2i(14, 4), Vector2i(22, 11), Vector2i(8, 20),
		Vector2i(18, 24), Vector2i(27, 16),
	]
	for p in spots:
		_blob(im, p.x, p.y, 2, GRASS_D)
	_blob(im, 11, 13, 2, GRASS_L)
	_blob(im, 25, 6, 2, GRASS_L)
	return im


func _tile_clods(base: Color, dark: Color) -> Image:
	var im := _blank(base)
	var spots: Array[Vector2i] = [
		Vector2i(6, 8), Vector2i(16, 5), Vector2i(24, 14), Vector2i(9, 22), Vector2i(20, 26),
	]
	for p in spots:
		_blob(im, p.x, p.y, 3, dark)
	return im


func _tile_water(base: Color, dark: Color, deep: bool) -> Image:
	var im := _blank(base)
	# Irregular 3–4px pools only — no full-width bars (those grid the ocean rim).
	if deep:
		_blob(im, 8, 10, 4, dark)
		_blob(im, 22, 8, 3, dark)
		_blob(im, 14, 22, 4, dark)
		_blob(im, 26, 24, 3, dark)
	else:
		_blob(im, 10, 9, 3, dark)
		_blob(im, 22, 18, 4, dark)
		_blob(im, 6, 24, 3, dark)
	return im


func _tile_canopy() -> Image:
	var im := _blank(HILLS)
	_blob(im, 7, 8, 4, HILLS_D)
	_blob(im, 20, 6, 3, HILLS_D)
	_blob(im, 12, 20, 4, HILLS_D)
	_blob(im, 25, 22, 3, HILLS_L)
	_blob(im, 4, 24, 2, HILLS_L)
	return im


func _tile_bark() -> Image:
	var im := _blank(BARK)
	# Three 3px vertical ribs that wrap in Y — reads as bark on sides, pad on tops.
	for x in [5, 6, 7, 16, 17, 18, 26, 27, 28]:
		for y in TILE:
			_plot(im, x, y, BARK_D if x % 11 != 6 else BARK_L)
	_blob(im, 11, 10, 2, BARK_L)
	_blob(im, 22, 21, 2, BARK_D)
	return im


func _tile_stone(base: Color, dark: Color, lite: Color) -> Image:
	var im := _blank(base)
	_blob(im, 8, 9, 4, lite)
	_blob(im, 22, 8, 3, dark)
	_blob(im, 14, 22, 4, dark)
	_blob(im, 26, 24, 3, lite)
	# Two 2px wrap cracks, not a brick lattice.
	for x in TILE:
		if (x + 3) % 11 != 0:
			_plot(im, x, 15, dark)
			_plot(im, x, 16, dark)
	for y in range(4, 20):
		_plot(im, 19, y, dark)
		_plot(im, 20, y, dark)
	return im


func _wrap_blend(im: Image) -> void:
	# 1px wrap soften only — keep 2–4px marks sharp.
	for y in TILE:
		var a: Color = im.get_pixel(0, y)
		var b: Color = im.get_pixel(TILE - 1, y)
		im.set_pixel(0, y, a.lerp(b, 0.25))
		im.set_pixel(TILE - 1, y, b.lerp(a, 0.25))
	for x in TILE:
		var a: Color = im.get_pixel(x, 0)
		var b: Color = im.get_pixel(x, TILE - 1)
		im.set_pixel(x, 0, a.lerp(b, 0.25))
		im.set_pixel(x, TILE - 1, b.lerp(a, 0.25))


func _save_repeat(tile: Image, path: String) -> void:
	var big := Image.create(TILE * 2, TILE * 2, false, Image.FORMAT_RGBA8)
	big.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(0, 0))
	big.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(TILE, 0))
	big.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(0, TILE))
	big.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(TILE, TILE))
	big.save_png(path)


func _plot(im: Image, x: int, y: int, c: Color) -> void:
	im.set_pixel(posmod(x, TILE), posmod(y, TILE), c)
