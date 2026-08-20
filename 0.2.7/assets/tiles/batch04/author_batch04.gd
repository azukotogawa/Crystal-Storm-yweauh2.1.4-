extends SceneTree
## Author Batch 04 unique-cell placeholders. Usage:
##   godot --headless --path . -s assets/tiles/batch04/author_batch04.gd


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const SRC_DIR := "res://assets/tiles/batch04"
const TILE := 32
const COLS := 7
const ROWS := 10

const SLOTS := {
	"mountain2": Vector2i(1, 4),
	"basin": Vector2i(0, 9),
	"snow": Vector2i(0, 5),
	"snow2": Vector2i(1, 5),
}

# Cooler/bluer than Batch 01 STONE (0.50, 0.52, 0.56) — mountain, not cobble.
const MTN := Color(0.42, 0.48, 0.54)
const MTN_D := Color(0.28, 0.34, 0.40)
const MTN_L := Color(0.54, 0.60, 0.66)
# Khaki cracked mud — yellower than DIRT (0.58, 0.42, 0.26).
const BASIN := Color(0.52, 0.44, 0.24)
const BASIN_D := Color(0.38, 0.30, 0.14)
const BASIN_L := Color(0.62, 0.52, 0.32)
# High-value snow with blue shadow; not pure white.
const SNOW := Color(0.84, 0.88, 0.92)
const SNOW_D := Color(0.68, 0.76, 0.86)
const SNOW_L := Color(0.94, 0.96, 0.98)
const ICE := Color(0.74, 0.82, 0.90)
const ICE_D := Color(0.58, 0.70, 0.82)
const ICE_L := Color(0.86, 0.92, 0.96)


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
		"mountain2": _tile_plates(MTN, MTN_D, MTN_L),
		"basin": _tile_cracks(BASIN, BASIN_D, BASIN_L),
		"snow": _tile_snow(SNOW, SNOW_D, SNOW_L),
		"snow2": _tile_snow(ICE, ICE_D, ICE_L),
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


func _tile_plates(base: Color, dark: Color, lite: Color) -> Image:
	var im := _blank(base)
	_blob(im, 8, 10, 5, lite)
	_blob(im, 22, 8, 4, dark)
	_blob(im, 12, 22, 5, dark)
	_blob(im, 26, 24, 4, lite)
	for x in TILE:
		if (x + 5) % 13 != 0:
			_plot(im, x, 16, dark)
			_plot(im, x, 17, dark)
	for y in range(6, 22):
		_plot(im, 18, y, dark)
		_plot(im, 19, y, dark)
	return im


func _tile_cracks(base: Color, dark: Color, lite: Color) -> Image:
	var im := _blank(base)
	_blob(im, 7, 8, 3, lite)
	_blob(im, 20, 10, 3, dark)
	_blob(im, 12, 22, 4, dark)
	_blob(im, 25, 24, 3, lite)
	for x in TILE:
		_plot(im, x, 14, dark)
		_plot(im, x, 15, dark)
	for y in range(8, 24):
		_plot(im, 10, y, dark)
	return im


func _tile_snow(base: Color, dark: Color, lite: Color) -> Image:
	var im := _blank(base)
	_blob(im, 8, 9, 4, dark)
	_blob(im, 22, 7, 3, dark)
	_blob(im, 14, 22, 4, lite)
	_blob(im, 26, 24, 3, lite)
	_blob(im, 5, 24, 2, dark)
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
