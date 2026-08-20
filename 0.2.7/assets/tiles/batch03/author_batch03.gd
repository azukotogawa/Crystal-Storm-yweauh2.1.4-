extends SceneTree
## Author Batch 03 into unused Cube.png holes. Usage:
##   godot --headless --path . -s assets/tiles/batch03/author_batch03.gd


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const SRC_DIR := "res://assets/tiles/batch03"
const TILE := 32
const COLS := 7
const ROWS := 10

const SLOTS := {
	"grassland4": Vector2i(3, 1),
	"farmland": Vector2i(4, 1),
	"town_path": Vector2i(5, 1),
}

# Dry steppe — tan-olive, darker than savanna, not dirt-brown.
const STEPPE := Color(0.40, 0.36, 0.16)
const STEPPE_D := Color(0.28, 0.24, 0.10)
const STEPPE_L := Color(0.50, 0.44, 0.22)
# Furrowed farm — cooler brown-green rows.
const FARM := Color(0.36, 0.30, 0.14)
const FARM_D := Color(0.24, 0.18, 0.08)
const FARM_L := Color(0.44, 0.38, 0.18)
# Packed town path — pale earth, not grass.
const PATH := Color(0.66, 0.58, 0.42)
const PATH_D := Color(0.50, 0.42, 0.28)
const PATH_L := Color(0.76, 0.68, 0.52)


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
		"grassland4": _tile_steppe(),
		"farmland": _tile_furrows(),
		"town_path": _tile_path(),
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


func _tile_steppe() -> Image:
	var im := _blank(STEPPE)
	var spots: Array[Vector2i] = [
		Vector2i(7, 9), Vector2i(18, 6), Vector2i(25, 14), Vector2i(10, 22),
	]
	for p in spots:
		_blob(im, p.x, p.y, 2, STEPPE_D)
	_blob(im, 14, 16, 2, STEPPE_L)
	_blob(im, 4, 4, 2, STEPPE_L)
	return im


func _tile_furrows() -> Image:
	var im := _blank(FARM)
	# Horizontal 3px furrows that wrap in X — reads as plowed rows, not dirt clods.
	for y in [5, 6, 7, 15, 16, 17, 25, 26, 27]:
		for x in TILE:
			_plot(im, x, y, FARM_D if y % 10 != 6 else FARM_L)
	_blob(im, 8, 11, 2, FARM_L)
	_blob(im, 22, 20, 2, FARM_D)
	return im


func _tile_path() -> Image:
	var im := _blank(PATH)
	var spots: Array[Vector2i] = [
		Vector2i(8, 8), Vector2i(20, 6), Vector2i(12, 20), Vector2i(24, 22),
	]
	for p in spots:
		_blob(im, p.x, p.y, 3, PATH_D)
	_blob(im, 16, 14, 2, PATH_L)
	_blob(im, 5, 26, 2, PATH_L)
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
