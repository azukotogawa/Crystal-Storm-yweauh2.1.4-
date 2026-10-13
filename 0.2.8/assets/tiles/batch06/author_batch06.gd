extends SceneTree
## Author corrupted-ground cells onto Cube.png.
##   godot --headless --path . -s assets/tiles/batch06/author_batch06.gd
## Placeholder nearest art. A later pass can replace the same atlas cells.

const ATLAS_PATH := "res://assets/tiles/Cube.png"
const SRC_DIR := "res://assets/tiles/batch06"
const TILE := 32
const COLS := 7
const ROWS := 10

const SLOTS := {
	"crystal": Vector2i(6, 2),
	"crystal_vein": Vector2i(6, 1),
	"crystal_shard_ground": Vector2i(6, 3),
	"crystal_scar": Vector2i(6, 5),
}

const CRYSTAL := Color(0.36, 0.16, 0.52)
const CRYSTAL_D := Color(0.20, 0.08, 0.32)
const CRYSTAL_L := Color(0.58, 0.34, 0.78)
const VEIN := Color(0.26, 0.12, 0.40)
const VEIN_L := Color(0.66, 0.40, 0.88)
const SHARD := Color(0.42, 0.20, 0.58)
const SHARD_L := Color(0.78, 0.55, 0.95)
const SCAR := Color(0.30, 0.26, 0.32)
const SCAR_D := Color(0.18, 0.15, 0.20)


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
		"crystal": _tile_crystal(),
		"crystal_vein": _tile_vein(),
		"crystal_shard_ground": _tile_shards(),
		"crystal_scar": _tile_scar(),
	}
	for name in SLOTS.keys():
		var cell: Vector2i = SLOTS[name]
		var tile: Image = tiles[name]
		_wrap_blend(tile)
		tile.save_png(abs_src.path_join("%s.png" % name))
		atlas.blit_rect(tile, Rect2i(0, 0, TILE, TILE), Vector2i(cell.x * TILE, cell.y * TILE))
		print("BLIT %s -> (%d,%d)" % [name, cell.x, cell.y])
	atlas.save_png(abs_atlas)
	print("WROTE %s" % abs_atlas)
	quit(0)


func _blank(c: Color) -> Image:
	var im := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	im.fill(c)
	return im


func _plot(im: Image, x: int, y: int, c: Color) -> void:
	if x < 1 or y < 1 or x >= TILE - 1 or y >= TILE - 1:
		return
	im.set_pixel(x, y, c)


func _blob(im: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				_plot(im, cx + dx, cy + dy, c)


func _tile_crystal() -> Image:
	var im := _blank(CRYSTAL)
	_blob(im, 10, 10, 3, CRYSTAL_L)
	_blob(im, 22, 8, 2, CRYSTAL_D)
	_blob(im, 16, 20, 3, CRYSTAL_L)
	_blob(im, 24, 22, 2, CRYSTAL_D)
	return im


func _tile_vein() -> Image:
	var im := _blank(VEIN)
	for i in 18:
		_plot(im, 8 + i, 6 + int(i / 2), VEIN_L)
		_plot(im, 9 + i, 7 + int(i / 2), VEIN_L)
	_blob(im, 12, 22, 2, CRYSTAL_D)
	_blob(im, 22, 14, 2, VEIN_L)
	return im


func _tile_shards() -> Image:
	var im := _blank(SHARD)
	_blob(im, 8, 8, 2, SHARD_L)
	_blob(im, 18, 12, 2, CRYSTAL_L)
	_blob(im, 12, 22, 2, SHARD_L)
	_blob(im, 24, 22, 2, CRYSTAL_D)
	return im


func _tile_scar() -> Image:
	var im := _blank(SCAR)
	for x in range(4, 28):
		_plot(im, x, 16, SCAR_D)
	_blob(im, 10, 10, 3, SCAR_D)
	_blob(im, 22, 22, 3, SCAR_D)
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
