extends SceneTree
## Regression: greedy top mesh must include the world's lowest surface columns (incl. y<=0 if present).


const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

const FACE_TOP := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 77

	var found := Vector2i.ZERO
	var found_h := INF
	for wx in range(-128, 128):
		for wz in range(-128, 128):
			var tile: int = world.get_tile_type(float(wx), float(wz))
			if tile == _VoxelTypes.AIR or _CrystalTypes.is_water_tile(tile):
				continue
			var h: float = world.get_surface_height(float(wx), float(wz))
			if h < found_h:
				found_h = h
				found = Vector2i(wx, wz)

	var coord := Vector2i(
		floori(float(found.x) / float(_ChunkData.SIZE)),
		floori(float(found.y) / float(_ChunkData.SIZE))
	)
	var lx := found.x - coord.x * _ChunkData.SIZE
	var lz := found.y - coord.y * _ChunkData.SIZE

	var data := _ChunkData.new(coord, world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var sy: float = data.get_surface_y(lx, lz)
	if not is_equal_approx(sy, found_h):
		push_error("chunk local surface %.2f != world %.2f at %s" % [sy, found_h, found])
		quit(1)
		return

	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])
	var has_top := false
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_TOP:
			continue
		if int(q.get("x", -1)) == lx and int(q.get("z", -1)) == lz \
				and is_equal_approx(float(q.get("y", -1.0)), sy):
			has_top = true
			break

	if not has_top:
		push_error("no FACE_TOP quad at lowest surface_y=%.2f for column %s" % [sy, found])
		quit(1)
		return

	print("OK chunk meshes lowest surface_y=%.2f at %s (quad count=%d)" % [sy, found, quads.size()])
	quit(0)