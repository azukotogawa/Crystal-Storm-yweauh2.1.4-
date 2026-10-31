class_name FlatBlockAtlas
extends RefCounted

const COLORS_PATH := "res://assets/tiles/cube_flat_colors.json"
const EDGE_SHADE := 0.86

static var _texture: Texture2D


static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var data = JSON.parse_string(FileAccess.get_file_as_string(COLORS_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var tile := int(data.get("tile", 32))
	var grid: Array = data.get("grid", [7, 10])
	if tile <= 0 or grid.size() < 2:
		return null
	var image := Image.create(int(grid[0]) * tile, int(grid[1]) * tile, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	for entry in data.get("tiles", []):
		var rgb: Array = entry.get("rgb", [])
		if rgb.size() < 3:
			continue
		var base := Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
		var edge := Color(base.r * EDGE_SHADE, base.g * EDGE_SHADE, base.b * EDGE_SHADE, 1.0)
		var x0 := int(entry.get("col", 0)) * tile
		var y0 := int(entry.get("row", 0)) * tile
		image.fill_rect(Rect2i(x0, y0, tile, tile), edge)
		image.fill_rect(Rect2i(x0 + 1, y0 + 1, tile - 2, tile - 2), base)
	_texture = ImageTexture.create_from_image(image)
	_texture.resource_name = "FlatBlockAtlas"
	return _texture


static func tile_color(col: int, row: int) -> Color:
	var tex := texture()
	if tex == null:
		return Color(0, 0, 0, 0)
	var image := tex.get_image()
	var tile := image.get_width() / 7
	return image.get_pixel(col * tile + tile / 2, row * tile + tile / 2)
