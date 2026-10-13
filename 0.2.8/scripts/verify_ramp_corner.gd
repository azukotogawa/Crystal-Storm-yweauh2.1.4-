extends SceneTree
## Regression: L-shaped step corners emit triangular prism (FACE_RAMP_CORNER), not cardinal wedge.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_TOP := 0
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()

	var old_chance: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 100
	_TerrainRamps.invalidate_mesh_cache()

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_init_maps(data)

	var cx := 6
	var cz := 6
	var low_h := 10.0
	var high_h := low_h + layer
	data.surface_map[cx][cz] = low_h
	data.tile_map[cx][cz] = _VoxelTypes.GRASSLAND
	# 2×2 plateau: two perpendicular highs plus the inner diagonal.
	for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		data.surface_map[cx + d.x][cz + d.y] = high_h
		data.tile_map[cx + d.x][cz + d.y] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])

	var corner := 0
	var cardinal_at_cell := 0
	var floor_tops := 0
	for q in quads:
		var fc := int(q.get("face_code", -1))
		if int(q.get("x", -1)) != cx or int(q.get("z", -1)) != cz:
			continue
		if fc == FACE_RAMP_CORNER:
			corner += 1
			if int(q.get("ramp_dir2_x", 0)) == 0 and int(q.get("ramp_dir2_z", 0)) == 0:
				push_error("corner ramp must set ramp_dir2")
				failed = true
		elif fc == FACE_RAMP:
			cardinal_at_cell += 1
		elif fc == FACE_TOP and float(q.get("y", -1.0)) == low_h:
			floor_tops += 1

	if corner < 1:
		push_error("L-step must emit corner prism at low cell, got corner=%d cardinal=%d" % [corner, cardinal_at_cell])
		failed = true
	else:
		print("OK step-corner prisms=%d" % corner)

	if cardinal_at_cell > 0:
		push_error("L-step low cell must not get cardinal wedge, got %d" % cardinal_at_cell)
		failed = true
	else:
		print("OK no cardinal wedge on corner cell")

	if floor_tops < 1:
		push_error("corner cell must keep floor support FACE_TOP at low_h, tops=%d" % floor_tops)
		failed = true
	else:
		print("OK corner cell floor support tops=%d" % floor_tops)

	# Isolated two-pillar L (no diagonal plateau) must not emit a wedge.
	var iso := _ChunkData.new(Vector2i(0, 0), world)
	iso.capture_worker_snapshot()
	_init_maps(iso)
	iso.surface_map[4][4] = low_h
	iso.tile_map[4][4] = _VoxelTypes.GRASSLAND
	iso.surface_map[5][4] = high_h
	iso.tile_map[5][4] = _VoxelTypes.GRASSLAND
	iso.surface_map[4][5] = high_h
	iso.tile_map[4][5] = _VoxelTypes.GRASSLAND
	var iso_quads: Array = cm._build_mesh(iso).get("quads", [])
	var iso_corner := 0
	for iq in iso_quads:
		if int(iq.get("x", -1)) == 4 and int(iq.get("z", -1)) == 4 \
				and int(iq.get("face_code", -1)) == FACE_RAMP_CORNER:
			iso_corner += 1
	if iso_corner > 0:
		push_error("isolated two-pillar L must not emit corner wedge, got %d" % iso_corner)
		failed = true
	else:
		print("OK isolated corner wedge suppressed")

	# Default chance must not stamp a corner on every inner 2×2.
	var sparse := 0
	var old_pc: int = _TerrainRamps.placement_chance
	_TerrainRamps.placement_chance = 28
	for i in 40:
		var sd := _ChunkData.new(Vector2i(i, 0), world)
		sd.capture_worker_snapshot()
		_init_maps(sd)
		sd.position = Vector2i(i, 0)
		sd.surface_map[6][6] = low_h
		sd.tile_map[6][6] = _VoxelTypes.GRASSLAND
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			sd.surface_map[6 + d.x][6 + d.y] = high_h
			sd.tile_map[6 + d.x][6 + d.y] = _VoxelTypes.GRASSLAND
		var nq: Array = cm._build_mesh(sd).get("quads", [])
		for q2 in nq:
			if int(q2.get("x", -1)) == 6 and int(q2.get("z", -1)) == 6 \
					and int(q2.get("face_code", -1)) == FACE_RAMP_CORNER:
				sparse += 1
				break
	_TerrainRamps.placement_chance = old_pc
	if sparse >= 36:
		push_error("corners must be infrequent, got %d/40 inner 2×2" % sparse)
		failed = true
	elif sparse < 1:
		push_error("some corners should still appear, got %d/40" % sparse)
		failed = true
	else:
		print("OK infrequent corners %d/40" % sparse)

	if not data.is_ramp_corner(cx, cz):
		push_error("ramp_map must mark corner at (%d,%d)" % [cx, cz])
		failed = true
	else:
		print("OK ramp_map corner flag")

	# Supporting full blocks of a 2×2 must stay full blocks, not cardinal slopes.
	var support_cardinal := 0
	for q in quads:
		var qx := int(q.get("x", -1))
		var qz := int(q.get("z", -1))
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		if (qx == cx + 1 and qz == cz) or (qx == cx and qz == cz + 1):
			support_cardinal += 1
	if support_cardinal > 0:
		push_error("2×2 supporting highs must not emit cardinal ramps, got %d" % support_cardinal)
		failed = true
	else:
		print("OK supporting highs stay full blocks")

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp corner tests FAILED")
		quit(1)
		return
	print("All ramp corner tests OK")
	quit(0)


func _init_maps(data: ChunkData) -> void:
	data.surface_map.resize(_ChunkData.SIZE)
	data.tile_map.resize(_ChunkData.SIZE)
	for x in _ChunkData.SIZE:
		data.surface_map[x] = []
		data.tile_map[x] = []
		data.surface_map[x].resize(_ChunkData.SIZE)
		data.tile_map[x].resize(_ChunkData.SIZE)
		for z in _ChunkData.SIZE:
			data.surface_map[x][z] = 8.0
			data.tile_map[x][z] = _VoxelTypes.GRASSLAND