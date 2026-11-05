extends SceneTree


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkMaterial: ShaderMaterial = preload("res://shaders/ChunkView.tres")
const _ChunkViewScene: PackedScene = preload("res://scenes/ChunkView.tscn")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const LUM_MIN := 0.15
const HUE_MIN := 0.10
const LOW_SAT := 0.15
const SPAN_MIN := 0.08

const MATERIALS := {
	"grass": _VoxelTypes.GRASSLAND3,
	"dirt": _VoxelTypes.DIRT,
	"stone": _VoxelTypes.STONE,
	"sand": _VoxelTypes.DESERT,
	"snow": _VoxelTypes.SNOW,
	"crystal": _VoxelTypes.CRYSTAL,
}


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)


func _hue_dist(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)


func _sample(img: Image, cell: Vector2i) -> Dictionary:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var luma := 0.0
	var lo := 1.0
	var hi := 0.0
	var colors := {}
	var n := float(tw * tw)
	for y in tw:
		for x in tw:
			var px := img.get_pixel(cell.x * tw + x, cell.y * tw + y)
			var lum := px.get_luminance()
			r += px.r
			g += px.g
			b += px.b
			luma += lum
			lo = minf(lo, lum)
			hi = maxf(hi, lum)
			colors[px.to_html(false)] = true
	var mean := Color(r / n, g / n, b / n)
	return {
		"luma": luma / n,
		"hue": mean.h,
		"sat": mean.s,
		"colors": colors.size(),
		"span": hi - lo,
		"mean": mean,
	}


func _in_set(cell: Vector2i, cells: Array) -> bool:
	for c in cells:
		if c == cell:
			return true
	return false


func _node_count(node: Node) -> int:
	var n := 1
	for child in node.get_children():
		n += _node_count(child)
	return n


func _mesh_cells(tile: int, world) -> Dictionary:
	var data := _ChunkData.new(Vector2i(4, 5), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var layer: float = _WorldSettings.get_active().layer_height()
	var low := layer * 4.0
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			var y := low
			if x == 0:
				y = low + layer * 3.0
			data.patch_local_column(x, z, y, tile)
	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var block_quads: Array = mesh.get("quads", []).filter(func(q): return not q.has("wave_riser"))
	var arrays: Dictionary = _Builder.build_surface_arrays_from_terrain_quads(data, block_quads)
	var normals: PackedVector3Array = arrays.get("normals", PackedVector3Array())
	var colors: PackedColorArray = arrays.get("colors", PackedColorArray())
	var tops: Dictionary = {}
	var sides: Dictionary = {}
	var i := 0
	while i < colors.size():
		var cell := Vector2i(int(round(colors[i].r * 255.0)), int(round(colors[i].g * 255.0)))
		var normal: Vector3 = normals[i]
		if normal.y > 0.9:
			tops[cell] = true
		elif absf(normal.x) > 0.9 or absf(normal.z) > 0.9:
			sides[cell] = true
		i += 4
	return {"tops": tops, "sides": sides, "quads": mesh.get("quads", []).size()}


func _run() -> void:
	var failed := false
	var tex := load(_VoxelTypes.ATLAS_TEXTURE_PATH) as Texture2D
	if tex == null:
		_fail("Cube.png import failed")
		quit(1)
		return
	print("IMPORT Cube.png %dx%d" % [tex.get_width(), tex.get_height()])
	if tex.get_width() != _VoxelTypes.ATLAS_GRID_COLUMNS * _VoxelTypes.ATLAS_TILE_PIXELS:
		_fail("atlas width %d" % tex.get_width())
		failed = true
	if tex.get_height() != _VoxelTypes.ATLAS_GRID_ROWS * _VoxelTypes.ATLAS_TILE_PIXELS:
		_fail("atlas height %d" % tex.get_height())
		failed = true
	var img := tex.get_image()
	if img == null or img.is_empty():
		_fail("imported atlas has no image")
		quit(1)
		return

	var bound: Texture2D = _ChunkMaterial.get_shader_parameter("texture_atlas") as Texture2D
	if bound == null or "Cube.png" not in bound.resource_path:
		_fail("ChunkView material lost Cube.png")
		failed = true
	else:
		print("MATERIAL %s" % bound.resource_path)

	var packed_view := _ChunkViewScene.instantiate()
	var view_nodes := _node_count(packed_view)
	print("SCENE ChunkView nodes=%d" % view_nodes)
	if view_nodes < 2:
		_fail("ChunkView scene is empty")
		failed = true
	packed_view.free()

	var samples := {}
	for name in MATERIALS.keys():
		var tile: int = int(MATERIALS[name])
		var top := _VoxelTypes.get_atlas_coord_for_face(tile, 0)
		var side := _VoxelTypes.get_atlas_coord_for_face(tile, 3)
		var bottom := _VoxelTypes.get_atlas_coord_for_face(tile, 2)
		print("FACE %s top=%s side=%s bottom=%s" % [name, top, side, bottom])
		if top == side or top == bottom or side == bottom:
			_fail("%s canonical faces are not distinct %s %s %s" % [name, top, side, bottom])
			failed = true
		for face_name in ["top", "side", "bottom"]:
			var cell: Vector2i = top if face_name == "top" else (side if face_name == "side" else bottom)
			var sample: Dictionary = _sample(img, cell)
			samples["%s_%s" % [name, face_name]] = sample
			print(
				"TILE %s %s cell=%s L=%.3f H=%.3f S=%.3f colors=%d span=%.3f"
				% [name, face_name, cell, sample["luma"], sample["hue"], sample["sat"], sample["colors"], sample["span"]]
			)
			if int(sample["colors"]) < 6:
				_fail("%s %s is flat (%d colors)" % [name, face_name, sample["colors"]])
				failed = true
			if float(sample["span"]) < SPAN_MIN:
				_fail("%s %s value span %.3f < %.2f" % [name, face_name, sample["span"], SPAN_MIN])
				failed = true
		for x in 16:
			for z in 16:
				var ft := _VoxelTypes.face_atlas(tile, 0, x, z)
				var fs := _VoxelTypes.face_atlas(tile, 4, x, z)
				var fb := _VoxelTypes.face_atlas(tile, 2, x, z)
				if ft == fs or ft == fb or fs == fb:
					_fail("%s column %d,%d faces collide %s %s %s" % [name, x, z, ft, fs, fb])
					failed = true
					break
			if failed:
				break

	var grass_top_ok := true
	var dirt_side_ok := true
	for x in 8:
		for z in 8:
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.GRASSLAND3, 0, x, z), _VoxelTypes.GRASS_TOP_VARIANTS):
				grass_top_ok = false
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.GRASSLAND3, 3, x, z), _VoxelTypes.GRASS_SIDE_VARIANTS):
				dirt_side_ok = false
			if _VoxelTypes.face_atlas(_VoxelTypes.GRASSLAND3, 2, x, z) != _VoxelTypes.SOIL_BOTTOM:
				_fail("grass bottom left the soil underside")
				failed = true
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.STONE, 0, x, z), _VoxelTypes.STONE_VARIANTS):
				_fail("stone top left the stone set")
				failed = true
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.STONE, 5, x, z), _VoxelTypes.STONE_VARIANTS):
				_fail("stone side left the stone set")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.STONE, 2, x, z) != _VoxelTypes.ROCK_BOTTOM:
				_fail("stone bottom left the rock underside")
				failed = true
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.DESERT, 0, x, z), _VoxelTypes.SAND_VARIANTS):
				_fail("sand top left the sand set")
				failed = true
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.DESERT, 6, x, z), _VoxelTypes.SAND_VARIANTS):
				_fail("sand side left the sand set")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.DESERT, 2, x, z) != _VoxelTypes.SAND_BOTTOM:
				_fail("sand bottom left the sand underside")
				failed = true
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.SNOW, 0, x, z), _VoxelTypes.SNOW_VARIANTS):
				_fail("snow top left the snow set")
				failed = true
			if not _in_set(_VoxelTypes.face_atlas(_VoxelTypes.SNOW, 3, x, z), _VoxelTypes.STONE_VARIANTS):
				_fail("snow side left the rock set")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL, 0, x, z) != _VoxelTypes.get_atlas_coord(_VoxelTypes.CRYSTAL):
				_fail("crystal top left its cell")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL, 3, x, z) != _VoxelTypes.CRYSTAL_SIDE:
				_fail("crystal side left its cell")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL, 2, x, z) != _VoxelTypes.CRYSTAL_BOTTOM:
				_fail("crystal bottom left its cell")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL_SHARD_GROUND, 0, x, z) != _VoxelTypes.get_atlas_coord(_VoxelTypes.CRYSTAL_SHARD_GROUND):
				_fail("shard top moved")
				failed = true
			if _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL_SCAR, 0, x, z) != _VoxelTypes.get_atlas_coord(_VoxelTypes.CRYSTAL_SCAR):
				_fail("scar top moved")
				failed = true
	if not grass_top_ok or not dirt_side_ok:
		_fail("grass block is not grass-topped and grass-sided")
		failed = true
	else:
		print("MAP grass top in grass set, side in grass-side set, bottom %s" % _VoxelTypes.SOIL_BOTTOM)

	var names: Array = MATERIALS.keys()
	var worst_l := 1.0
	var worst_pair := ""
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Dictionary = samples["%s_top" % names[i]]
			var b: Dictionary = samples["%s_top" % names[j]]
			var dl := absf(float(a["luma"]) - float(b["luma"]))
			var dh := _hue_dist(float(a["hue"]), float(b["hue"]))
			var low_sat := minf(float(a["sat"]), float(b["sat"])) < LOW_SAT
			print(
				"PAIR %s-%s dL=%.3f dH=%.3f low_sat=%s"
				% [names[i], names[j], dl, dh, low_sat]
			)
			if dl < worst_l:
				worst_l = dl
				worst_pair = "%s-%s" % [names[i], names[j]]
			if dl < LUM_MIN or (dh < HUE_MIN and not low_sat):
				_fail(
					"%s vs %s contrast dL=%.3f dH=%.3f (need dL>=%.2f and dH>=%.2f unless sat<%.2f)"
					% [names[i], names[j], dl, dh, LUM_MIN, HUE_MIN, LOW_SAT]
				)
				failed = true
	print("THRESHOLD luma>=%.2f hue>=%.2f low_sat<%.2f worst=%s dL=%.3f" % [LUM_MIN, HUE_MIN, LOW_SAT, worst_pair, worst_l])

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	var drawn: Dictionary = _mesh_cells(_VoxelTypes.GRASSLAND3, world)
	print("MESH grass quads=%d tops=%d sides=%d" % [drawn["quads"], drawn["tops"].size(), drawn["sides"].size()])
	if drawn["quads"] < 1 or drawn["tops"].size() < 1 or drawn["sides"].size() < 1:
		_fail("grass mesh did not emit a top and a side")
		failed = true
	for cell in drawn["tops"].keys():
		if not _in_set(cell, _VoxelTypes.GRASS_TOP_VARIANTS):
			_fail("meshed grass top %s is outside the grass set" % cell)
			failed = true
	for cell in drawn["sides"].keys():
		if not _in_set(cell, _VoxelTypes.GRASS_SIDE_VARIANTS):
			_fail("meshed grass side %s is outside the grass-side set" % cell)
			failed = true

	if failed:
		quit(1)
		return
	print("All texture contrast tests OK")
	quit(0)
