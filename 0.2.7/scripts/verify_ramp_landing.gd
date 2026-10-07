extends SceneTree
## Regression: cardinal step ramps emit on landing (high) column, not the lower approach cell.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const FACE_RAMP := 7


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

	var low_x := 5
	var low_z := 5
	var high_x := 6
	var high_z := 5
	var low_h := 10.0
	var high_h := low_h + layer
	for x0 in _ChunkData.SIZE:
		for z0 in _ChunkData.SIZE:
			data.surface_map[x0][z0] = low_h
			data.tile_map[x0][z0] = _VoxelTypes.GRASSLAND
	for hx in range(high_x, high_x + 3):
		for hz in range(high_z - 1, high_z + 2):
			data.surface_map[hx][hz] = high_h
			data.tile_map[hx][hz] = _VoxelTypes.GRASSLAND

	var cm := _ChunkManager.new()
	cm.ramp_placement_chance = 100
	var quads: Array = cm._build_mesh(data).get("quads", [])

	var ramp_on_low := 0
	var ramp_on_high := 0
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(q.get("x", -1)) == low_x and int(q.get("z", -1)) == low_z:
			ramp_on_low += 1
		if int(q.get("x", -1)) == high_x and int(q.get("z", -1)) == high_z:
			ramp_on_high += 1
			var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
			if dir != Vector2i(-1, 0):
				push_error("landing ramp must point toward low neighbor, got %s" % dir)
				failed = true

	if ramp_on_low > 0:
		push_error("cardinal ramp must not emit on approach cell (%d,%d), got %d" % [low_x, low_z, ramp_on_low])
		failed = true
	else:
		print("OK no cardinal ramp on approach cell")

	if ramp_on_high < 1:
		push_error("cardinal ramp must emit on landing cell (%d,%d), got %d" % [high_x, high_z, ramp_on_high])
		failed = true
	else:
		print("OK landing ramp on high cell=%d" % ramp_on_high)

	if not data.has_ramp(high_x, high_z):
		push_error("ramp_map must mark landing cell")
		failed = true
	else:
		print("OK ramp_map landing cell")

	for step in [
		{"land": Vector2i(8, 8), "low": Vector2i(9, 8), "dir": Vector2i(1, 0)},
		{"land": Vector2i(8, 10), "low": Vector2i(7, 10), "dir": Vector2i(-1, 0)},
		{"land": Vector2i(10, 8), "low": Vector2i(10, 9), "dir": Vector2i(0, 1)},
		{"land": Vector2i(12, 8), "low": Vector2i(12, 7), "dir": Vector2i(0, -1)},
	]:
		var land: Vector2i = step.land
		var low: Vector2i = step.low
		var want: Vector2i = step.dir
		var fresh := _ChunkData.new(Vector2i(0, 0), world)
		fresh.capture_worker_snapshot()
		_init_maps(fresh)
		for x2 in _ChunkData.SIZE:
			for z2 in _ChunkData.SIZE:
				fresh.surface_map[x2][z2] = 10.0
		# Half-chunk terrace so the approach has only one high neighbor (cardinal,
		# not an inner corner of leftover plateau, and not a 10-8-10 V).
		for x2 in _ChunkData.SIZE:
			for z2 in _ChunkData.SIZE:
				var along: int = (x2 - land.x) * want.x + (z2 - land.y) * want.y
				if along > 0:
					fresh.surface_map[x2][z2] = 10.0 - layer
		var q4: Array = cm._build_mesh(fresh).get("quads", [])
		var found := false
		for q2 in q4:
			if int(q2.get("face_code", -1)) != FACE_RAMP:
				continue
			if int(q2.get("x", -1)) != land.x or int(q2.get("z", -1)) != land.y:
				continue
			var got := Vector2i(int(q2.get("ramp_dir_x", 0)), int(q2.get("ramp_dir_z", 0)))
			if got != want:
				push_error("dir %s ramp dir want %s got %s" % [str(land), str(want), str(got)])
				failed = true
			found = true
		if not found:
			push_error("missing FACE_RAMP on landing %s dir %s" % [str(land), str(want)])
			failed = true
		else:
			print("OK FACE_RAMP landing %s dir %s" % [str(land), str(want)])

	# Stale in-chunk halo must not hide a stamped step (live remesh leftover).
	var stale := _ChunkData.new(Vector2i(0, 0), world)
	stale.capture_worker_snapshot()
	_init_maps(stale)
	stale._maps_resident = true
	for xs in _ChunkData.SIZE:
		for zs in _ChunkData.SIZE:
			stale.surface_map[xs][zs] = 10.0
	for xs2 in range(6, _ChunkData.SIZE):
		for zs2 in _ChunkData.SIZE:
			stale.surface_map[xs2][zs2] = 10.0 - layer
	var dim := _ChunkData.SIZE + 2
	stale._halo_surface.resize(dim)
	for ix in dim:
		stale._halo_surface[ix] = []
		stale._halo_surface[ix].resize(dim)
		for iz in dim:
			stale._halo_surface[ix][iz] = 10.0
	stale._has_halo_surface = true
	var sq: Array = cm._build_mesh(stale).get("quads", [])
	var stale_found := false
	for sq_v in sq:
		var sqd: Dictionary = sq_v
		if int(sqd.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(sqd.get("x", -1)) == 5 and int(sqd.get("z", -1)) == 5:
			stale_found = true
			break
	if not stale_found:
		push_error("stale halo hid FACE_RAMP on landing (5,5)")
		failed = true
	else:
		print("OK FACE_RAMP despite stale in-chunk halo")

	# Live south failure: landing is also one layer below a perpendicular ridge.
	# Side-entry corner pick + approach-block used to consume the landing
	# (ramp_map.approach=true, faces=[]). Cardinal FACE_RAMP must still emit.
	var terrace := _ChunkData.new(Vector2i(0, 0), world)
	terrace.capture_worker_snapshot()
	_init_maps(terrace)
	for x3 in _ChunkData.SIZE:
		for z3 in _ChunkData.SIZE:
			terrace.surface_map[x3][z3] = 10.0
	var t_land := Vector2i(10, 8)
	var t_low := Vector2i(10, 9)
	var t_ridge := Vector2i(11, 8)
	for xt in _ChunkData.SIZE:
		for zt in range(t_low.y, _ChunkData.SIZE):
			terrace.surface_map[xt][zt] = 10.0 - layer
	terrace.surface_map[t_land.x][t_land.y] = 10.0
	terrace.surface_map[t_ridge.x][t_ridge.y] = 10.0 + layer
	var tq: Array = cm._build_mesh(terrace).get("quads", [])
	var t_found := false
	var t_entry: Dictionary = terrace.get_ramp_entry(t_land.x, t_land.y)
	for tq_v in tq:
		var tqd: Dictionary = tq_v
		if int(tqd.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(tqd.get("x", -1)) != t_land.x or int(tqd.get("z", -1)) != t_land.y:
			continue
		var tdir := Vector2i(int(tqd.get("ramp_dir_x", 0)), int(tqd.get("ramp_dir_z", 0)))
		if tdir != Vector2i(0, 1):
			push_error("terrace landing dir want (0, 1) got %s" % str(tdir))
			failed = true
		t_found = true
	if not t_found:
		push_error("terrace landing missing FACE_RAMP (entry=%s)" % str(t_entry))
		failed = true
	elif bool(t_entry.get("approach", false)):
		push_error("terrace landing consumed as approach %s" % str(t_entry))
		failed = true
	else:
		print("OK terrace landing FACE_RAMP not stolen as approach")

	# Approach column is in the +X neighbor. A capture halo still holding the
	# pre-stamp border height hides the step; resident remesh must copy it.
	var border := _ChunkData.new(Vector2i(0, 0), world)
	border.capture_worker_snapshot()
	_init_maps(border)
	var neighbor := _ChunkData.new(Vector2i(1, 0), world)
	neighbor.capture_worker_snapshot()
	_init_maps(neighbor)
	var border_h := 10.0
	for bx in _ChunkData.SIZE:
		for bz in _ChunkData.SIZE:
			border.surface_map[bx][bz] = border_h
			border.tile_map[bx][bz] = _VoxelTypes.GRASSLAND
			neighbor.surface_map[bx][bz] = border_h
			neighbor.tile_map[bx][bz] = _VoxelTypes.GRASSLAND
	var edge_lx := _ChunkData.SIZE - 1
	var edge_lz := 8
	neighbor.surface_map[0][edge_lz] = border_h - layer
	var halo_ix := edge_lx + 1 + _ChunkData.HALO
	var halo_iz := edge_lz + _ChunkData.HALO
	border._halo_surface[halo_ix][halo_iz] = border_h
	var hidden: Array = cm._build_mesh(border).get("quads", [])
	if _ramp_quads_at(hidden, edge_lx, edge_lz) != 0:
		push_error("pre-stamp halo border should hide the neighbor step")
		failed = true
	else:
		print("OK cross-chunk step hidden while halo border is pre-stamp")
	var border_view := ChunkView.new()
	border_view.chunk_data = border
	var neighbor_view := ChunkView.new()
	neighbor_view.chunk_data = neighbor
	cm.chunks[border.position] = border_view
	cm.chunks[neighbor.position] = neighbor_view
	border.preserve_column_maps = true
	cm._refresh_preserve_halo(border)
	var revealed: Array = cm._build_mesh(border).get("quads", [])
	var edge_dir := Vector2i.ZERO
	for rq in revealed:
		if int(rq.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(rq.get("x", -1)) != edge_lx or int(rq.get("z", -1)) != edge_lz:
			continue
		edge_dir = Vector2i(int(rq.get("ramp_dir_x", 0)), int(rq.get("ramp_dir_z", 0)))
	if edge_dir != Vector2i(1, 0):
		push_error("cross-chunk landing ramp want dir (1, 0), got %s (halo=%s)" % [
			str(edge_dir), str(border.get_halo_surface_y(edge_lx + 1, edge_lz))
		])
		failed = true
	else:
		print("OK cross-chunk FACE_RAMP after preserve halo refresh")
	border_view.free()
	neighbor_view.free()

	# East yard failure: approach already a two-layer cliff, sides still high.
	# Subtracting another layer never becomes one cardinal step. The stamp
	# must write landing_h - layer and drop the approach sides.
	var cliff := _ChunkData.new(Vector2i(0, 0), world)
	cliff.capture_worker_snapshot()
	_init_maps(cliff)
	var land_c := Vector2i(8, 8)
	var approach_c := Vector2i(9, 8)
	for x3 in _ChunkData.SIZE:
		for z3 in _ChunkData.SIZE:
			cliff.surface_map[x3][z3] = 10.0
	cliff.surface_map[approach_c.x][approach_c.y] = 10.0 - layer * 2.0
	var before_cliff: Array = cm._build_mesh(cliff).get("quads", [])
	if _ramp_quads_at(before_cliff, land_c.x, land_c.y) != 0:
		push_error("two-layer cliff should not emit a cardinal ramp")
		failed = true
	else:
		print("OK two-layer cliff emits no cardinal ramp")
	var cliff_view := ChunkView.new()
	cliff_view.chunk_data = cliff
	cm.chunks[cliff.position] = cliff_view
	cm.defer_world_bake_bootstrap = true
	root.add_child(cm)
	var yard_script = load("res://world/validation_yard.gd")
	var remesh := {}
	yard_script._stamp_generated_step_maps(self, land_c, Vector2i(1, 0), remesh)
	var stamped_approach := float(cliff.surface_map[approach_c.x][approach_c.y])
	var stamped_side := float(cliff.surface_map[approach_c.x][approach_c.y + 1])
	if not is_equal_approx(stamped_approach, 10.0 - layer) or not is_equal_approx(stamped_side, 10.0 - layer):
		push_error("isolated stamp want approach/side %.2f, got approach %.2f side %.2f" % [
			10.0 - layer, stamped_approach, stamped_side
		])
		failed = true
	else:
		print("OK yard stamp writes an isolated one-layer step")
	var after_cliff: Array = cm._build_mesh(cliff).get("quads", [])
	var cliff_dir := Vector2i.ZERO
	for cq in after_cliff:
		if int(cq.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(cq.get("x", -1)) != land_c.x or int(cq.get("z", -1)) != land_c.y:
			continue
		cliff_dir = Vector2i(int(cq.get("ramp_dir_x", 0)), int(cq.get("ramp_dir_z", 0)))
	if cliff_dir != Vector2i(1, 0):
		push_error("isolated yard step want FACE_RAMP dir (1, 0), got %s" % str(cliff_dir))
		failed = true
	else:
		print("OK isolated yard step emits FACE_RAMP")
	cliff_view.free()

	# 10-8-10 valley: two landings must not point into the same pit (no V).
	var valley := _ChunkData.new(Vector2i(0, 0), world)
	valley.capture_worker_snapshot()
	_init_maps(valley)
	for xv in _ChunkData.SIZE:
		for zv in _ChunkData.SIZE:
			valley.surface_map[xv][zv] = 10.0
	valley.surface_map[8][8] = 10.0 - layer
	var vq: Array = cm._build_mesh(valley).get("quads", [])
	var v_left := 0
	var v_right := 0
	for vq_v in vq:
		var vqd: Dictionary = vq_v
		if int(vqd.get("face_code", -1)) != FACE_RAMP:
			continue
		var vx := int(vqd.get("x", -1))
		var vz := int(vqd.get("z", -1))
		var vd := Vector2i(int(vqd.get("ramp_dir_x", 0)), int(vqd.get("ramp_dir_z", 0)))
		if vx == 7 and vz == 8 and vd == Vector2i(1, 0):
			v_left += 1
		if vx == 9 and vz == 8 and vd == Vector2i(-1, 0):
			v_right += 1
	if v_left > 0 and v_right > 0:
		push_error("opposing V-ramps into valley (7,8) and (9,8)")
		failed = true
	else:
		print("OK no opposing V-ramps into 10-8-10 valley (left=%d right=%d)" % [v_left, v_right])

	# Two-cell-wide valley 10-8-8-10: ramps facing across the pit must not both exist.
	var wide := _ChunkData.new(Vector2i(0, 0), world)
	wide.capture_worker_snapshot()
	_init_maps(wide)
	for xw in _ChunkData.SIZE:
		for zw in _ChunkData.SIZE:
			wide.surface_map[xw][zw] = 10.0
	wide.surface_map[8][8] = 10.0 - layer
	wide.surface_map[9][8] = 10.0 - layer
	var wq: Array = cm._build_mesh(wide).get("quads", [])
	var w_left := 0
	var w_right := 0
	for wq_v in wq:
		var wqd: Dictionary = wq_v
		if int(wqd.get("face_code", -1)) != FACE_RAMP:
			continue
		var wx := int(wqd.get("x", -1))
		var wz := int(wqd.get("z", -1))
		var wd := Vector2i(int(wqd.get("ramp_dir_x", 0)), int(wqd.get("ramp_dir_z", 0)))
		if wx == 7 and wz == 8 and wd == Vector2i(1, 0):
			w_left += 1
		if wx == 10 and wz == 8 and wd == Vector2i(-1, 0):
			w_right += 1
	if w_left > 0 and w_right > 0:
		push_error("opposing V-ramps across 2-wide valley")
		failed = true
	else:
		print("OK no V-ramps across 2-wide valley (left=%d right=%d)" % [w_left, w_right])

	_TerrainRamps.placement_chance = old_chance
	_TerrainRamps.invalidate_mesh_cache()

	if failed:
		print("Ramp landing tests FAILED")
		quit(1)
		return
	print("All ramp landing tests OK")
	quit(0)


func _ramp_quads_at(quads: Array, lx: int, lz: int) -> int:
	var n := 0
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_RAMP:
			continue
		if int(q.get("x", -1)) == lx and int(q.get("z", -1)) == lz:
			n += 1
	return n


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