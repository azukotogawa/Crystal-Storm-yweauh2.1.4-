extends SceneTree
## Author Batch 05 unshared cells. Usage:
##   godot --headless --path . -s assets/tiles/batch05/author_batch05.gd


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const SRC_DIR := "res://assets/tiles/batch05"
const TILE := 32
const COLS := 7
const ROWS := 10

const SLOTS := {
	"hills3": Vector2i(3, 3),
	"hills4": Vector2i(4, 3),
	"bush": Vector2i(5, 3),
	"grass_tuft": Vector2i(5, 2),
	"mountain3": Vector2i(3, 5),
}

# Pine — cooler/darker than HILLS, not bark-brown TREE_TRUNK.
const PINE := Color(0.10, 0.24, 0.16)
const PINE_D := Color(0.06, 0.16, 0.10)
const PINE_L := Color(0.16, 0.32, 0.18)
# Jungle — wetter/deeper than HILLS, not a bush pad.
const JUNG := Color(0.08, 0.26, 0.12)
const JUNG_D := Color(0.04, 0.16, 0.08)
const JUNG_L := Color(0.14, 0.36, 0.16)
# Bush pad — round clumps, distinct from jungle field.
const BUSH := Color(0.16, 0.28, 0.10)
const BUSH_D := Color(0.10, 0.18, 0.06)
const BUSH_L := Color(0.24, 0.38, 0.14)
# Tuft — brighter marks than meadow GRASSLAND2.
const TUFT := Color(0.34, 0.52, 0.16)
const TUFT_D := Color(0.22, 0.38, 0.10)
const TUFT_L := Color(0.48, 0.64, 0.22)
# Peak — cooler than MOUNTAIN2, not ochre STONE2.
const PEAK := Color(0.38, 0.44, 0.52)
const PEAK_D := Color(0.24, 0.30, 0.38)
const PEAK_L := Color(0.52, 0.58, 0.66)


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
		"hills3": _tile_needles(),
		"hills4": _tile_jungle(),
		"bush": _tile_clumps(),
		"grass_tuft": _tile_tufts(),
		"mountain3": _tile_peak(),
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


func _tile_needles() -> Image:
	var im := _blank(PINE)
	for x in [6, 7, 8, 16, 17, 18, 25, 26, 27]:
		for y in TILE:
			_plot(im, x, y, PINE_D if x % 10 != 7 else PINE_L)
	_blob(im, 12, 10, 2, PINE_L)
	_blob(im, 22, 22, 2, PINE_D)
	return im


func _tile_jungle() -> Image:
	var im := _blank(JUNG)
	_blob(im, 7, 8, 4, JUNG_D)
	_blob(im, 20, 6, 4, JUNG_D)
	_blob(im, 12, 20, 4, JUNG_L)
	_blob(im, 26, 22, 3, JUNG_D)
	_blob(im, 4, 24, 3, JUNG_L)
	return im


func _tile_clumps() -> Image:
	var im := _blank(BUSH)
	_blob(im, 8, 10, 5, BUSH_D)
	_blob(im, 22, 8, 4, BUSH_L)
	_blob(im, 16, 22, 5, BUSH_D)
	_blob(im, 6, 24, 3, BUSH_L)
	return im


func _tile_tufts() -> Image:
	var im := _blank(TUFT)
	var spots: Array[Vector2i] = [
		Vector2i(6, 8), Vector2i(14, 6), Vector2i(24, 10),
		Vector2i(8, 20), Vector2i(18, 24), Vector2i(26, 18),
	]
	for p in spots:
		_blob(im, p.x, p.y, 2, TUFT_L)
	_blob(im, 12, 14, 2, TUFT_D)
	return im


func _tile_peak() -> Image:
	var im := _blank(PEAK)
	_blob(im, 8, 8, 5, PEAK_L)
	_blob(im, 22, 10, 4, PEAK_D)
	_blob(im, 12, 22, 5, PEAK_D)
	_blob(im, 26, 24, 3, PEAK_L)
	for x in TILE:
		_plot(im, x, 15, PEAK_D)
		_plot(im, x, 16, PEAK_D)
	return im


func _wrap_blend(im: Image) -> void:
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
