extends SceneTree
## Block faces must not pick up a dark grid from atlas bleeding or tile outlines.
## Shaders sample mip 0 at inner texel centers. Cube.png tiles have no dark frame.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")

const _SHADERS: PackedStringArray = [
	"res://shaders/ChunkView.gdshader",
	"res://shaders/ChunkSurfaceMesh.gdshader",
	"res://shaders/ChunkRamp.gdshader",
]


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)


func _row_luma(img: Image, ox: int, oy: int, y: int, tw: int) -> float:
	var sum := 0.0
	for x in tw:
		sum += img.get_pixel(ox + x, oy + y).get_luminance()
	return sum / float(tw)


func _col_luma(img: Image, ox: int, oy: int, x: int, tw: int) -> float:
	var sum := 0.0
	for y in tw:
		sum += img.get_pixel(ox + x, oy + y).get_luminance()
	return sum / float(tw)


func _run() -> void:
	var failed := false
	var include_path := "res://shaders/atlas_sample.gdshaderinc"
	var include_src := FileAccess.get_file_as_string(include_path)
	if include_src.is_empty():
		_fail("missing %s" % include_path)
		failed = true
	elif "textureLod" not in include_src or "vec2(1.5)" not in include_src:
		_fail("atlas sample must use textureLod and the 1.5px inner inset")
		failed = true
	else:
		print("OK atlas sample locks mip 0 at inner texel centers")

	for path in _SHADERS:
		var src := FileAccess.get_file_as_string(path)
		if "atlas_sample.gdshaderinc" not in src or "cs_sample_atlas" not in src:
			_fail("%s must sample through atlas_sample.gdshaderinc" % path)
			failed = true
		elif "repeat_disable" not in src:
			_fail("%s sampler must be repeat_disable" % path)
			failed = true
		elif "texture(texture_atlas" in src or "1.0 / 32.0" in src:
			_fail("%s still uses border UV padding" % path)
			failed = true
		else:
			var shader := load(path) as Shader
			if shader == null:
				_fail("%s failed to load" % path)
				failed = true
			else:
				print("OK shader %s" % path)

	var shade_src := FileAccess.get_file_as_string("res://shaders/terrain_shade.gdshaderinc")
	if "edge_dark" in shade_src:
		_fail("terrain shade still darkens tile borders")
		failed = true
	else:
		print("OK terrain shade has no tile-border darkening")

	var import_src := FileAccess.get_file_as_string("res://assets/tiles/Cube.png.import")
	if "mipmaps/generate=false" not in import_src:
		_fail("Cube.png must import without mipmaps")
		failed = true
	else:
		print("OK Cube.png mipmaps off")

	var img := Image.load_from_file(_VoxelTypes.ATLAS_TEXTURE_PATH)
	if img == null or img.is_empty():
		_fail("Cube.png missing")
		quit(1)
		return
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var cols: int = _VoxelTypes.ATLAS_GRID_COLUMNS
	var rows: int = _VoxelTypes.ATLAS_GRID_ROWS
	if img.get_width() != cols * tw or img.get_height() != rows * tw:
		_fail("Cube.png size %dx%d" % [img.get_width(), img.get_height()])
		failed = true
	else:
		var grid_hits := 0
		for row in rows:
			for col in cols:
				var ox := col * tw
				var oy := row * tw
				for y in tw:
					var line := _row_luma(img, ox, oy, y, tw)
					var neighbor := line
					if y > 0:
						neighbor = _row_luma(img, ox, oy, y - 1, tw)
					elif y + 1 < tw:
						neighbor = _row_luma(img, ox, oy, y + 1, tw)
					if line < neighbor * 0.8:
						grid_hits += 1
				for x in tw:
					var line := _col_luma(img, ox, oy, x, tw)
					var neighbor := line
					if x > 0:
						neighbor = _col_luma(img, ox, oy, x - 1, tw)
					elif x + 1 < tw:
						neighbor = _col_luma(img, ox, oy, x + 1, tw)
					if line < neighbor * 0.8:
						grid_hits += 1
		if grid_hits > 0:
			_fail("Cube.png has %d dark grid lines" % grid_hits)
			failed = true
		else:
			print("OK Cube.png tiles have no dark grid lines")

	if failed:
		quit(1)
		return
	print("All block texture grid tests OK")
	quit(0)
