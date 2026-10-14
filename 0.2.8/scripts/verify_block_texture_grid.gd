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


func _srgb_to_linear(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)


## Same test as ChunkSurfaceMesh / ChunkRamp. source_color samples are linear.
func _shader_swaps_texel(px: Color, cutoff: float) -> bool:
	if cutoff <= 0.0:
		return false
	var lin := Color(
		_srgb_to_linear(px.r),
		_srgb_to_linear(px.g),
		_srgb_to_linear(px.b),
		px.a
	)
	return lin.r * 0.33 + lin.g * 0.33 + lin.b * 0.34 < cutoff


func _dark_cutoff() -> float:
	var cutoff := 0.0
	var pattern := RegEx.new()
	pattern.compile("vec3\\(0\\.33, 0\\.33, 0\\.34\\)\\) < ([0-9]*\\.?[0-9]+)")
	for path in _SHADERS:
		var src := FileAccess.get_file_as_string(path)
		var found := pattern.search(src)
		if found == null:
			continue
		cutoff = maxf(cutoff, float(found.get_string(1)))
	return cutoff


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
	elif "vec2 atlas_grid" in include_src or "vec2 cell_grid" not in include_src:
		_fail("atlas sample parameter must not reuse the atlas_grid uniform name")
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
				# A drawn material compiles the include. A redefinition prints
				# SHADER ERROR in the engine log; this script still checks the
				# material bound.
				var host := MeshInstance3D.new()
				var mat := ShaderMaterial.new()
				mat.shader = shader
				host.mesh = BoxMesh.new()
				host.material_override = mat
				root.add_child(host)
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
		# The row test above stays green on this atlas: dark and light texels
		# share every row, so no row is 20% darker than its neighbor. In the
		# game the surface shader still replaces the dark texels with one flat
		# color. That flat field against the texels it keeps is the grid at
		# ortho 16. Apply the shader's own cutoff to the tile.
		var cutoff := _dark_cutoff()
		var worst_cell := Vector2i(-1, -1)
		var worst_frac := 0.0
		var worst_swapped := 0
		var worst_opaque := 0
		var bad_cells := 0
		for row in rows:
			for col in cols:
				var ox := col * tw
				var oy := row * tw
				var opaque := 0
				var swapped := 0
				var luma_sum := 0.0
				for y in tw:
					for x in tw:
						var px := img.get_pixel(ox + x, oy + y)
						if px.a < 0.1:
							continue
						opaque += 1
						luma_sum += px.get_luminance()
						if _shader_swaps_texel(px, cutoff):
							swapped += 1
				if opaque < tw * tw / 2:
					continue
				if luma_sum / float(opaque) < 0.12:
					continue
				var frac := float(swapped) / float(opaque)
				if frac > worst_frac:
					worst_frac = frac
					worst_cell = Vector2i(col, row)
					worst_swapped = swapped
					worst_opaque = opaque
				if frac > 0.08:
					bad_cells += 1
		if bad_cells > 0:
			_fail(
				"%d colored tiles would draw a grid; worst cell %d,%d replaces %d/%d texels (cutoff %.4f)"
				% [bad_cells, worst_cell.x, worst_cell.y, worst_swapped, worst_opaque, cutoff]
			)
			failed = true
		else:
			print(
				"OK shader keeps tile texels (worst cell %d,%d replaces %.1f%%)"
				% [worst_cell.x, worst_cell.y, worst_frac * 100.0]
			)

	# Let the headless renderer compile the bound materials.
	await process_frame
	await process_frame
	if failed:
		quit(1)
		return
	print("All block texture grid tests OK")
	quit(0)
