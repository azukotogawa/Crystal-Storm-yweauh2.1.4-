extends SceneTree
## P1 regression: Cube.png atlas has biome-distinct river, marsh, and grass tiles.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")


func _init() -> void:
	call_deferred("_run")


func _tile_colors(img: Image, coord: Vector2i) -> Dictionary:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var colors: Dictionary = {}
	for py in tw:
		for px in tw:
			var c: Color = img.get_pixel(coord.x * tw + px, coord.y * tw + py)
			if c.a < 0.5:
				continue
			colors[c.to_html(false)] = true
	return colors


func _tile_luma(img: Image, coord: Vector2i) -> float:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var sum := 0.0
	var n := 0
	for py in tw:
		for px in tw:
			var c: Color = img.get_pixel(coord.x * tw + px, coord.y * tw + py)
			sum += c.get_luminance()
			n += 1
	return sum / float(maxi(n, 1))


func _run() -> void:
	var failed := false
	var regen_src := FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://scripts/regenerate_cube_atlas.py")
	)
	if "fill_river_tile" not in regen_src or "fill_marsh_grass" not in regen_src:
		push_error("regenerate_cube_atlas.py must define river + marsh tile fillers")
		failed = true
	elif "fill_sparse_grass" not in regen_src:
		push_error("regenerate_cube_atlas.py must define steppe/savanna sparse grass")
		failed = true
	else:
		print("OK regenerate_cube_atlas biome tile fillers")

	var img: Image = Image.load_from_file(_VoxelTypes.ATLAS_TEXTURE_PATH)
	if img == null or img.is_empty():
		push_error("Cube.png missing")
		quit(1)
		return

	var expect_w: int = _VoxelTypes.ATLAS_GRID_COLUMNS * _VoxelTypes.ATLAS_TILE_PIXELS
	var expect_h: int = _VoxelTypes.ATLAS_GRID_ROWS * _VoxelTypes.ATLAS_TILE_PIXELS
	if img.get_width() != expect_w or img.get_height() != expect_h:
		push_error(
			"Cube.png size %dx%d expected %dx%d"
			% [img.get_width(), img.get_height(), expect_w, expect_h]
		)
		failed = true
	else:
		print("OK Cube.png size=%dx%d tile=%dpx" % [expect_w, expect_h, _VoxelTypes.ATLAS_TILE_PIXELS])

	var ocean := Vector2i(0, 0)
	var river := _VoxelTypes.get_atlas_coord(_VoxelTypes.RIVER)
	var marsh := _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND)
	var plains := _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND3)
	var steppe := _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND4)
	var savanna := _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND5)
	var stone := _VoxelTypes.get_atlas_coord(_VoxelTypes.STONE)

	var river_colors := _tile_colors(img, river)
	var ocean_colors := _tile_colors(img, ocean)
	var marsh_colors := _tile_colors(img, marsh)
	var plains_colors := _tile_colors(img, plains)
	var stone_colors := _tile_colors(img, stone)

	if river_colors.size() < 4:
		push_error("river tile needs >=4 colors, got %d" % river_colors.size())
		failed = true
	else:
		print("OK river tile colors=%d" % river_colors.size())

	var river_luma := _tile_luma(img, river)
	var ocean_luma := _tile_luma(img, ocean)
	if absf(river_luma - ocean_luma) < 0.04:
		push_error("river tile must differ from ocean luma river=%.3f ocean=%.3f" % [river_luma, ocean_luma])
		failed = true
	else:
		print("OK river luma=%.3f ocean=%.3f" % [river_luma, ocean_luma])

	if marsh_colors.size() < 4:
		push_error("marsh/grassland tile needs >=4 colors, got %d" % marsh_colors.size())
		failed = true
	elif plains_colors.size() < 4:
		push_error("plains grass tile needs >=4 colors, got %d" % plains_colors.size())
		failed = true
	else:
		print("OK marsh colors=%d plains colors=%d" % [marsh_colors.size(), plains_colors.size()])

	var marsh_luma := _tile_luma(img, marsh)
	var plains_luma := _tile_luma(img, plains)
	var steppe_luma := _tile_luma(img, steppe)
	var savanna_luma := _tile_luma(img, savanna)
	if marsh_luma >= plains_luma:
		push_error("marsh must be darker than plains marsh=%.3f plains=%.3f" % [marsh_luma, plains_luma])
		failed = true
	elif absf(steppe_luma - plains_luma) < 0.05:
		push_error("steppe must differ from plains steppe=%.3f plains=%.3f" % [steppe_luma, plains_luma])
		failed = true
	elif absf(savanna_luma - steppe_luma) < 0.05:
		push_error("savanna must differ from steppe savanna=%.3f steppe=%.3f" % [savanna_luma, steppe_luma])
		failed = true
	else:
		print(
			"OK biome luma marsh=%.3f plains=%.3f steppe=%.3f savanna=%.3f"
			% [marsh_luma, plains_luma, steppe_luma, savanna_luma]
		)

	if stone_colors.size() < 4:
		push_error("stone tile needs cracked variation, got %d colors" % stone_colors.size())
		failed = true
	else:
		print("OK stone tile colors=%d" % stone_colors.size())

	if failed:
		quit(1)
		return
	print("All terrain atlas style tests OK")
	quit(0)