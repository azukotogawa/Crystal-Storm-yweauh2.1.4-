extends SceneTree
## Author Batch 02 32×32 hue-shift tops into existing Cube.png cells only.
## Usage: godot --headless --path . -s assets/tiles/batch02/author_batch02.gd


const ATLAS_PATH := "res://assets/tiles/Cube.png"
const SRC_DIR := "res://assets/tiles/batch02"
const TILE := 32
const COLS := 7
const ROWS := 10

const SLOTS := {
	"grassland": Vector2i(0, 2),
	"grassland2": Vector2i(1, 2),
	"grassland5": Vector2i(4, 2),
	"hills2": Vector2i(1, 3),
}

# Hue-shifts of Batch 01 GRASSLAND3 / HILLS. Sides stay DIRT / TREE_TRUNK.
const G1 := Color(0.36, 0.56, 0.20)
const G1_D := Color(0.24, 0.42, 0.12)
const G1_L := Color(0.48, 0.64, 0.26)
const G2 := Color(0.42, 0.54, 0.18)
const G2_D := Color(0.30, 0.40, 0.10)
const G2_L := Color(0.54, 0.62, 0.26)
const G5 := Color(0.46, 0.50, 0.22)
const G5_D := Color(0.34, 0.38, 0.14)
const G5_L := Color(0.58, 0.56, 0.30)
const H2 := Color(0.08, 0.22, 0.12)
const H2_D := Color(0.05, 0.14, 0.08)
const H2_L := Color(0.14, 0.30, 0.14)


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
		push_error("bad atlas size %dx%d" % [atlas.get_width(), atlas.get_height()])
		quit(1)
		return
	if atlas.get_format() != Image.FORMAT_RGBA8:
		atlas.convert(Image.FORMAT_RGBA8)

	var tiles := {
		"grassland": _tile_grass(G1, G1_D, G1_L),
		"grassland2": _tile_grass(G2, G2_D, G2_L),
		"grassland5": _tile_grass(G5, G5_D, G5_L),
		"hills2": _tile_canopy(),
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


func _tile_grass(base: Color, dark: Color, lite: Color) -> Image:
	var im := _blank(base)
	var spots: Array[Vector2i] = [
		Vector2i(6, 8), Vector2i(15, 5), Vector2i(23, 12), Vector2i(9, 21),
		Vector2i(19, 25), Vector2i(26, 17),
	]
	for p in spots:
		_blob(im, p.x, p.y, 2, dark)
	_blob(im, 12, 14, 2, lite)
	_blob(im, 24, 7, 2, lite)
	return im


func _tile_canopy() -> Image:
	var im := _blank(H2)
	_blob(im, 6, 7, 4, H2_D)
	_blob(im, 18, 5, 4, H2_D)
	_blob(im, 11, 18, 4, H2_D)
	_blob(im, 24, 20, 3, H2_D)
	_blob(im, 27, 10, 3, H2_L)
	_blob(im, 4, 24, 2, H2_L)
	_blob(im, 16, 12, 3, H2_L)
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
