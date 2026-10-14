extends SceneTree
## Grass and dirt must vary per column on the mesh the game draws.
## verify_block_texture_grid only averages whole rows of Cube.png and applies
## the near-black shader cutoff. A flat grass fill has no dark row, so that
## check stays green while every plains column still samples one cell. The
## windowed grid probe paints six copies of that same cell. This check builds
## a chunk through ChunkManager and reads the surface-mesh vertex colors.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const _MIN_VARIANTS := 3
const _MIN_MARKS := 280


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)


func _cell_of(color: Color) -> Vector2i:
	return Vector2i(int(round(color.r * 255.0)), int(round(color.g * 255.0)))


func _paint_chunk(tile: int, cliff: bool) -> ChunkData:
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	var data := _ChunkData.new(Vector2i(2, 3), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var layer: float = _WorldSettings.get_active().layer_height()
	var low := layer * 4.0
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			var y := low
			if cliff and x == 0:
				y = low + layer * 3.0
			data.patch_local_column(x, z, y, tile)
	return data


func _drawn_cells(data: ChunkData) -> Dictionary:
	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var arrays: Dictionary = _Builder.build_surface_arrays_from_terrain_quads(data, mesh.get("quads", []))
	var normals: PackedVector3Array = arrays.get("normals", PackedVector3Array())
	var colors: PackedColorArray = arrays.get("colors", PackedColorArray())
	var tops: Dictionary = {}
	var sides: Dictionary = {}
	var i := 0
	while i < colors.size():
		var cell := _cell_of(colors[i])
		var n: Vector3 = normals[i]
		if n.y > 0.9:
			tops[cell] = true
		elif absf(n.x) > 0.9 or absf(n.z) > 0.9:
			sides[cell] = true
		i += 4
	return {"tops": tops, "sides": sides, "quads": mesh.get("quads", []).size()}


func _mode_marks(img: Image, cell: Vector2i) -> Dictionary:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var counts: Dictionary = {}
	var ox := cell.x * tw
	var oy := cell.y * tw
	for y in tw:
		for x in tw:
			var px := img.get_pixel(ox + x, oy + y)
			var key := px.to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
	var mode := 0
	for key in counts.keys():
		mode = maxi(mode, int(counts[key]))
	return {"colors": counts.size(), "marks": tw * tw - mode}


## The shipped grass tile is one fill plus the same 4px bands on every row
## group. Those bands are lighter than the fill, so a "darker than the
## neighbor row" test never sees them, and every row in a band has the same
## average so the rows match each other.
func _has_stripe(img: Image, cell: Vector2i) -> bool:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var ox := cell.x * tw
	var oy := cell.y * tw
	var mode := _mode_key(img, cell)
	var masks: Array[int] = []
	for y in tw:
		var mask := 0
		for x in tw:
			var px := img.get_pixel(ox + x, oy + y)
			if px.to_html(false) != mode:
				mask |= 1 << x
		masks.append(mask)
	for y in range(tw - 3):
		var mask: int = masks[y]
		if mask == 0:
			continue
		if mask == masks[y + 1] and mask == masks[y + 2] and mask == masks[y + 3]:
			return true
	return false


func _mode_key(img: Image, cell: Vector2i) -> String:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var counts: Dictionary = {}
	var ox := cell.x * tw
	var oy := cell.y * tw
	for y in tw:
		for x in tw:
			var key := img.get_pixel(ox + x, oy + y).to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
	var best := ""
	var mode := -1
	for key in counts.keys():
		if int(counts[key]) > mode:
			mode = int(counts[key])
			best = str(key)
	return best


func _row_is_grid(img: Image, cell: Vector2i) -> bool:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var ox := cell.x * tw
	var oy := cell.y * tw
	for y in tw:
		var sum := 0.0
		for x in tw:
			sum += img.get_pixel(ox + x, oy + y).get_luminance()
		var line := sum / float(tw)
		var neighbor := line
		if y > 0:
			var nsum := 0.0
			for x in tw:
				nsum += img.get_pixel(ox + x, oy + y - 1).get_luminance()
			neighbor = nsum / float(tw)
		if line < neighbor * 0.8:
			return true
	for x in tw:
		var sum := 0.0
		for y in tw:
			sum += img.get_pixel(ox + x, oy + y).get_luminance()
		var line := sum / float(tw)
		var neighbor := line
		if x > 0:
			var nsum := 0.0
			for y in tw:
				nsum += img.get_pixel(ox + x - 1, oy + y).get_luminance()
			neighbor = nsum / float(tw)
		if line < neighbor * 0.8:
			return true
	return false


func _cells_differ(img: Image, a: Vector2i, b: Vector2i) -> int:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var diff := 0
	for y in tw:
		for x in tw:
			var pa := img.get_pixel(a.x * tw + x, a.y * tw + y)
			var pb := img.get_pixel(b.x * tw + x, b.y * tw + y)
			if pa.to_html(false) != pb.to_html(false):
				diff += 1
	return diff


func _run() -> void:
	var failed := false
	var img := Image.load_from_file(_VoxelTypes.ATLAS_TEXTURE_PATH)
	if img == null or img.is_empty():
		_fail("Cube.png missing")
		quit(1)
		return

	var grass := _drawn_cells(_paint_chunk(_VoxelTypes.GRASSLAND3, true))
	var dirt := _drawn_cells(_paint_chunk(_VoxelTypes.DIRT, false))
	var grass_tops: Dictionary = grass["tops"]
	var grass_sides: Dictionary = grass["sides"]
	var dirt_tops: Dictionary = dirt["tops"]
	print(
		"drawn grass tops %d sides %d (quads %d); dirt tops %d"
		% [grass_tops.size(), grass_sides.size(), grass["quads"], dirt_tops.size()]
	)
	if grass_tops.size() < _MIN_VARIANTS:
		_fail("plains grass tops use %d atlas cells, want %d" % [grass_tops.size(), _MIN_VARIANTS])
		failed = true
	if grass_sides.size() < _MIN_VARIANTS:
		_fail("grass cliff sides use %d atlas cells, want %d" % [grass_sides.size(), _MIN_VARIANTS])
		failed = true
	if dirt_tops.size() < _MIN_VARIANTS:
		_fail("dirt tops use %d atlas cells, want %d" % [dirt_tops.size(), _MIN_VARIANTS])
		failed = true

	var seen: Dictionary = {}
	for cell in grass_tops.keys():
		seen[cell] = true
	for cell in grass_sides.keys():
		seen[cell] = true
	for cell in dirt_tops.keys():
		seen[cell] = true
	var cells: Array = seen.keys()
	for i in cells.size():
		var cell: Vector2i = cells[i]
		if _row_is_grid(img, cell) or _has_stripe(img, cell):
			_fail("drawn cell %s has a grid or stripe" % cell)
			failed = true
		var marks: Dictionary = _mode_marks(img, cell)
		if int(marks["colors"]) < 4 or int(marks["marks"]) < _MIN_MARKS:
			_fail(
				"drawn cell %s is a flat fill (colors %d marks %d)"
				% [cell, marks["colors"], marks["marks"]]
			)
			failed = true
		for j in range(i + 1, cells.size()):
			var other: Vector2i = cells[j]
			var diff := _cells_differ(img, cell, other)
			if diff < 40:
				_fail("cells %s and %s are not distinct (%d px)" % [cell, other, diff])
				failed = true

	var again := _drawn_cells(_paint_chunk(_VoxelTypes.GRASSLAND3, true))
	if again["tops"] != grass_tops or again["sides"] != grass_sides:
		_fail("grass variants changed on a second mesh of the same columns")
		failed = true
	else:
		print("OK remesh kept the same grass cells")

	if failed:
		quit(1)
		return
	print("All block texture variant tests OK")
	quit(0)
