extends SceneTree


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)


func _paint(tile: int, world) -> ChunkData:
	var data := _ChunkData.new(Vector2i(8, 2), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var layer: float = _WorldSettings.get_active().layer_height()
	var low := layer * 5.0
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			var y := low
			if x == 0:
				y = low + layer * 3.0
			data.patch_local_column(x, z, y, tile)
	return data


func _arrays(data: ChunkData, native: bool) -> Dictionary:
	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])
	if native:
		return _Builder.build_surface_arrays_native(data, quads)
	return _Builder.build_surface_arrays_from_terrain_quads(data, quads)


func _drawn(arrays: Dictionary) -> Dictionary:
	var normals: PackedVector3Array = arrays.get("normals", PackedVector3Array())
	var uvs: PackedVector2Array = arrays.get("uvs", PackedVector2Array())
	var colors: PackedColorArray = arrays.get("colors", PackedColorArray())
	var tops: Dictionary = {}
	var sides: Dictionary = {}
	var top_uvs: Dictionary = {}
	var side_uvs: Dictionary = {}
	var i := 0
	while i < uvs.size():
		var cell := Vector2i(int(round(colors[i].r * 255.0)), int(round(colors[i].g * 255.0)))
		var n: Vector3 = normals[i]
		var key := "%.5f,%.5f" % [uvs[i].x, uvs[i].y]
		if n.y > 0.9:
			tops[cell] = true
			top_uvs[key] = true
		elif absf(n.x) > 0.9 or absf(n.z) > 0.9:
			sides[cell] = true
			side_uvs[key] = true
		i += 4
	return {"tops": tops, "sides": sides, "top_uvs": top_uvs, "side_uvs": side_uvs}


func _separated(label: String, arrays: Dictionary, failed_box: Array) -> void:
	if arrays.is_empty():
		_fail("%s arrays empty" % label)
		failed_box[0] = true
		return
	var drawn := _drawn(arrays)
	var tops: Dictionary = drawn["tops"]
	var sides: Dictionary = drawn["sides"]
	var top_uvs: Dictionary = drawn["top_uvs"]
	var side_uvs: Dictionary = drawn["side_uvs"]
	print("UV %s tops %s sides %s" % [label, tops.keys(), sides.keys()])
	print("UV %s top_uvs=%d side_uvs=%d" % [label, top_uvs.size(), side_uvs.size()])
	if tops.is_empty() or sides.is_empty() or top_uvs.is_empty() or side_uvs.is_empty():
		_fail("%s mesh has no top or side" % label)
		failed_box[0] = true
		return
	for top in tops.keys():
		for side in sides.keys():
			if top == side:
				_fail("%s top and side share atlas cell %s" % [label, top])
				failed_box[0] = true
	var same := true
	if top_uvs.size() != side_uvs.size():
		same = false
	else:
		for key in top_uvs.keys():
			if not side_uvs.has(key):
				same = false
				break
	if same:
		_fail("%s top and side UV sets match" % label)
		failed_box[0] = true


func _same_mesh(label: String, a: Dictionary, b: Dictionary, failed_box: Array) -> void:
	if a.is_empty() or b.is_empty():
		_fail("%s missing native or gdscript arrays" % label)
		failed_box[0] = true
		return
	var au: PackedVector2Array = a.get("uvs", PackedVector2Array())
	var bu: PackedVector2Array = b.get("uvs", PackedVector2Array())
	var ac: PackedColorArray = a.get("colors", PackedColorArray())
	var bc: PackedColorArray = b.get("colors", PackedColorArray())
	if au.size() != bu.size() or ac.size() != bc.size():
		_fail("%s native/gdscript size %d/%d uv %d/%d color" % [label, au.size(), bu.size(), ac.size(), bc.size()])
		failed_box[0] = true
		return
	for i in au.size():
		if not au[i].is_equal_approx(bu[i]):
			_fail("%s uv[%d] native %s gdscript %s" % [label, i, au[i], bu[i]])
			failed_box[0] = true
			return
		if not ac[i].is_equal_approx(bc[i]):
			_fail("%s color[%d] native %s gdscript %s" % [label, i, ac[i], bc[i]])
			failed_box[0] = true
			return
	print("OK %s native matches gdscript verts=%d" % [label, au.size()])


func _lip(img: Image, cell: Vector2i) -> bool:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var top_g := 0.0
	var low_g := 0.0
	var low_r := 0.0
	var n_top := 0
	var n_low := 0
	for y in tw:
		for x in tw:
			var px := img.get_pixel(cell.x * tw + x, cell.y * tw + y)
			if y < 4:
				top_g += px.g
				n_top += 1
			elif y >= 12:
				low_g += px.g
				low_r += px.r
				n_low += 1
	if n_top < 1 or n_low < 1:
		return false
	var lip_g := top_g / float(n_top)
	var body_g := low_g / float(n_low)
	var body_r := low_r / float(n_low)
	return lip_g > body_g + 0.04 and body_r > body_g


func _rings(img: Image, cell: Vector2i) -> bool:
	var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
	var ox := cell.x * tw
	var oy := cell.y * tw
	var center := img.get_pixel(ox + 16, oy + 16)
	var ring := img.get_pixel(ox + 16, oy + 10)
	var edge := img.get_pixel(ox + 2, oy + 16)
	return center.to_html(false) != ring.to_html(false) and ring.to_html(false) != edge.to_html(false)


func _run() -> void:
	var failed := false
	var img := Image.load_from_file(_VoxelTypes.ATLAS_TEXTURE_PATH)
	if img == null or img.is_empty():
		_fail("Cube.png missing")
		quit(1)
		return
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	var failed_box := [false]
	var grass := _paint(_VoxelTypes.GRASSLAND3, world)
	var log := _paint(_VoxelTypes.TREE_TRUNK, world)
	var grass_gd := _arrays(grass, false)
	var log_gd := _arrays(log, false)
	var grass_n := _arrays(grass, true)
	var log_n := _arrays(log, true)
	if grass_n.is_empty() or log_n.is_empty():
		_fail("native surface arrays missing")
		failed_box[0] = true
	_separated("grass gdscript", grass_gd, failed_box)
	_separated("log gdscript", log_gd, failed_box)
	_separated("grass native", grass_n, failed_box)
	_separated("log native", log_n, failed_box)
	_same_mesh("grass", grass_n, grass_gd, failed_box)
	_same_mesh("log", log_n, log_gd, failed_box)
	failed = bool(failed_box[0])
	var grass_side: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.GRASSLAND3, 3, 0, 0)
	var log_top: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.TREE_TRUNK, 0, 1, 2)
	var log_side: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.TREE_TRUNK, 4, 1, 2)
	print("FACE grass_side=%s log_top=%s log_side=%s" % [grass_side, log_top, log_side])
	if log_top == log_side:
		_fail("log top and side atlas cells match")
		failed = true
	if not _lip(img, grass_side):
		_fail("grass side %s has no dirt body with a grass lip" % grass_side)
		failed = true
	else:
		print("OK grass side lip %s" % grass_side)
	if not _rings(img, log_top):
		_fail("log top %s has no end rings" % log_top)
		failed = true
	else:
		print("OK log end rings %s" % log_top)
	var stone_top: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.STONE, 0, 3, 4)
	var stone_side: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.STONE, 5, 3, 4)
	var sand_top: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.DESERT, 0, 5, 6)
	var sand_side: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.DESERT, 6, 5, 6)
	var shard_top: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL_SHARD_GROUND, 0, 2, 2)
	var shard_side: Vector2i = _VoxelTypes.face_atlas(_VoxelTypes.CRYSTAL_SHARD_GROUND, 3, 2, 2)
	print(
		"FACE stone %s/%s sand %s/%s shard %s/%s"
		% [stone_top, stone_side, sand_top, sand_side, shard_top, shard_side]
	)
	if stone_top == stone_side or sand_top == sand_side or shard_top == shard_side:
		_fail("stone, sand, or crystal ground top matches its side")
		failed = true
	if failed:
		quit(1)
		return
	print("All block face UV tests OK")
	quit(0)
