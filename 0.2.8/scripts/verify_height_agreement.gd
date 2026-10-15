extends SceneTree


const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 7
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var base_h := 8.0
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			data.patch_local_column(x, z, base_h, _VoxelTypes.GRASSLAND3)
	for x in range(8, 12):
		for z in range(6, 10):
			data.patch_local_column(x, z, base_h + layer, _VoxelTypes.GRASSLAND3)
	if data._has_halo_surface:
		data._halo_surface[4 + _ChunkData.HALO][4 + _ChunkData.HALO] = 40.0

	TerrainRamps.placement_chance = 100
	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var sampled: float = cm._sample_height(data, 4, 4)
	if not is_equal_approx(sampled, base_h):
		push_error("interior height used halo %.2f, surface is %.2f" % [sampled, base_h])
		failed = true
	else:
		print("OK interior sample follows surface_map %.2f" % sampled)

	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])
	if not _ramp_maps_match_quads(data, quads):
		push_error("ramp_map and ramp quads disagree after mesh build")
		failed = true
	else:
		print("OK ramp_map matches emitted ramp quads")

	var sloped := false
	for q_v in quads:
		var q: Dictionary = q_v
		if int(q.get("face_code", 0)) != _ChunkManager.FACE_RAMP:
			continue
		var qy: float = float(q.get("y", 0.0))
		var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
		if dir == Vector2i.ZERO:
			continue
		var wx := float(q.get("x", 0.0)) + 0.5
		var wz := float(q.get("z", 0.0)) + 0.5
		var walk: float = TerrainRamps.surface_height_on_ramp(wx, wz, qy, dir)
		var flat: float = TerrainRamps.voxel_top_y(qy)
		if absf(walk - flat) > layer * 0.2:
			sloped = true
			print("OK walk slope %.2f vs flat top %.2f on mesh y %.2f" % [walk, flat, qy])
			break
	if not sloped:
		push_error("no cardinal ramp quad produced a sloped walk height")
		failed = true
	else:
		for q_v in quads:
			var q: Dictionary = q_v
			if int(q.get("face_code", 0)) != _ChunkManager.FACE_RAMP:
				continue
			var qy: float = float(q.get("y", 0.0))
			var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
			if dir == Vector2i.ZERO:
				continue
			var low_edge: float = qy
			var high_edge: float = qy + layer
			if dir.x < 0:
				low_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.02, float(q.get("z", 0.0)) + 0.5, qy, dir)
				high_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.98, float(q.get("z", 0.0)) + 0.5, qy, dir)
			elif dir.x > 0:
				low_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.98, float(q.get("z", 0.0)) + 0.5, qy, dir)
				high_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.02, float(q.get("z", 0.0)) + 0.5, qy, dir)
			elif dir.y < 0:
				low_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.5, float(q.get("z", 0.0)) + 0.02, qy, dir)
				high_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.5, float(q.get("z", 0.0)) + 0.98, qy, dir)
			else:
				low_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.5, float(q.get("z", 0.0)) + 0.98, qy, dir)
				high_edge = TerrainRamps.surface_height_on_ramp(float(q.get("x", 0.0)) + 0.5, float(q.get("z", 0.0)) + 0.02, qy, dir)
			if absf(low_edge - qy) > layer * 0.15 or absf(high_edge - (qy + layer)) > layer * 0.15:
				push_error("wedge walk low=%.2f high=%.2f, surface %.2f layer %.2f" % [low_edge, high_edge, qy, layer])
				failed = true
			else:
				print("OK landing wedge meets the low shelf and the high top")
			break

	data.ramp_map[Vector2i(1, 1)] = {"dir": Vector2i(1, 0), "corner": false, "side": false}
	cm.sync_ramp_map_to_mesh(data, quads)
	if data.has_ramp(1, 1):
		push_error("ramp_map entry with no quad survived sync")
		failed = true
	elif not _ramp_maps_match_quads(data, quads):
		push_error("sync dropped a quad-backed ramp")
		failed = true
	else:
		print("OK orphan ramp_map entry removed")

	TerrainRamps.placement_chance = 28
	if failed:
		quit(1)
		return
	print("All height agreement tests OK")
	quit(0)


func _ramp_maps_match_quads(data: ChunkData, quads: Array) -> bool:
	var visual: Dictionary = {}
	for q_v in quads:
		var q: Dictionary = q_v
		if int(q.get("face_code", 0)) < _ChunkManager.FACE_RAMP:
			continue
		var cell := Vector2i(int(floor(float(q.get("x", 0.0)))), int(floor(float(q.get("z", 0.0)))))
		visual[cell] = true
	for key_v in data.ramp_map.keys():
		if not visual.has(key_v):
			return false
	for key_v in visual.keys():
		var cell: Vector2i = key_v
		if cell.x < 0 or cell.y < 0 or cell.x >= _ChunkData.SIZE or cell.y >= _ChunkData.SIZE:
			continue
		if not data.has_ramp(cell.x, cell.y):
			return false
	return true
