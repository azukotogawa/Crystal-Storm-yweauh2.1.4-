class_name CrystalPresentation
extends RefCounted
## Crystal mesh/visual rebuild scheduling. Subscribes to simulation events only.
## Does not own gameplay rules or fluid state.

const _CrystalSimEvents = preload("res://crystal/crystal_sim_events.gd")
const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")

## Injected by façade
var fluid = null  # CrystalFluidSim (read-only for mesh)
var sim_config = null
var layer_root: Node3D = null
var crystal_material: StandardMaterial3D = null
var chunk_size: int = 16

var _chunk_layers: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _patch_dirty_by_chunk: Dictionary = {}
var _chunk_needs_full_rebuild: Dictionary = {}
var _cells_by_chunk: Dictionary = {}

var max_rebuilds_per_frame: int = 5
var mesh_budget_us: int = 2500
var spread_damping_start: int = 600
var spread_damping_full: int = 3000
var mesh_rebuilds_when_large: int = 1

var rebuild_count: int = 0
var patch_count: int = 0
var events_applied: int = 0
var last_flush_rebuilds: int = 0

## Callables injected by façade (avoid presentation→tree coupling for world height).
var crystal_floor_at: Callable = Callable()  # (Vector2i) -> float
var is_chunk_render_active: Callable = Callable()  # (Vector2i) -> bool
var player_chunk_coord: Callable = Callable()  # () -> Vector2i
var make_layer: Callable = Callable()  # (coord) -> CrystalChunkLayer


func clear_visual_state() -> void:
	for coord in _chunk_layers.keys():
		var layer = _chunk_layers[coord]
		if layer and is_instance_valid(layer):
			layer.queue_free()
	_chunk_layers.clear()
	_dirty_chunks.clear()
	_patch_dirty_by_chunk.clear()
	_chunk_needs_full_rebuild.clear()
	_cells_by_chunk.clear()


func rebuild_cell_index() -> void:
	_cells_by_chunk.clear()
	if fluid == null:
		return
	for pos_variant in fluid.depth.keys():
		_index_crystal_cell(pos_variant)


## After save import: full reindex and schedule full rebuild for every occupied chunk.
func mark_all_indexed_dirty() -> void:
	rebuild_cell_index()
	for coord_v in _cells_by_chunk.keys():
		var coord: Vector2i = coord_v
		_chunk_needs_full_rebuild[coord] = true
		_dirty_chunks[coord] = true


func apply_events(events: Array) -> void:
	for ev_v in events:
		if not ev_v is Dictionary:
			continue
		events_applied += 1
		var ev: Dictionary = ev_v
		var kind: int = int(ev.get("kind", 0))
		match kind:
			_CrystalSimEvents.Kind.DEPTH_CHANGED:
				var pos: Vector2i = ev.pos
				_index_crystal_cell(pos)
				_mark_chunk_dirty(pos)
			_CrystalSimEvents.Kind.DEPTH_CLEARED:
				var pos2: Vector2i = ev.pos
				_unindex_crystal_cell(pos2)
				_mark_chunk_dirty(pos2)
			_CrystalSimEvents.Kind.FLOW_BATCH:
				_apply_flow_batch(ev.get("changed", []), ev.get("mesh_dirty", []))
			_CrystalSimEvents.Kind.MESH_DIRTY:
				for p in ev.get("positions", []):
					_mark_chunk_dirty(p)
			_:
				pass


func _apply_flow_batch(changed: Array, mesh_dirty: Array) -> void:
	if mesh_dirty.is_empty():
		for pos_variant in changed:
			var pos: Vector2i = pos_variant
			if fluid and fluid.depth.has(pos):
				_index_crystal_cell(pos)
			else:
				_unindex_crystal_cell(pos)
		return
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		if fluid and fluid.depth.has(pos):
			_index_crystal_cell(pos)
		else:
			_unindex_crystal_cell(pos)
	for pos_variant in mesh_dirty:
		var pos: Vector2i = pos_variant
		var coord := _chunk_coord_for(pos)
		if not _chunk_active(coord):
			continue
		if not fluid or not fluid.depth.has(pos):
			_chunk_needs_full_rebuild[coord] = true
			_dirty_chunks[coord] = true
			continue
		var layer = _chunk_layers.get(coord)
		if layer == null or not layer.has_cell(pos):
			_chunk_needs_full_rebuild[coord] = true
			_dirty_chunks[coord] = true
			continue
		if _chunk_needs_full_rebuild.has(coord):
			_dirty_chunks[coord] = true
			continue
		if not _patch_dirty_by_chunk.has(coord):
			_patch_dirty_by_chunk[coord] = []
		var bucket: Array = _patch_dirty_by_chunk[coord]
		if pos not in bucket:
			bucket.append(pos)
		_dirty_chunks[coord] = true


func on_chunk_loaded(coord: Vector2i) -> void:
	if _cells_by_chunk.has(coord):
		_dirty_chunks[coord] = true


func on_chunk_unloaded(coord: Vector2i) -> void:
	if _chunk_layers.has(coord):
		var layer = _chunk_layers[coord]
		if is_instance_valid(layer):
			layer.queue_free()
		_chunk_layers.erase(coord)
	_dirty_chunks.erase(coord)
	_patch_dirty_by_chunk.erase(coord)
	_chunk_needs_full_rebuild.erase(coord)


func dirty_chunk_count() -> int:
	return _dirty_chunks.size()


func flush(profiler = null) -> int:
	if _dirty_chunks.is_empty():
		last_flush_rebuilds = 0
		return 0
	if profiler and profiler.has_method("begin"):
		profiler.begin("crystal_mesh")
	var t0 := Time.get_ticks_usec()
	var rebuilt := 0
	var keys: Array = _dirty_chunks.keys()
	var player_chunk: Vector2i = Vector2i.ZERO
	if player_chunk_coord.is_valid():
		player_chunk = player_chunk_coord.call()
	if player_chunk != Vector2i(-99999, -99999):
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _manhattan(a, player_chunk) < _manhattan(b, player_chunk)
		)
	var budget: int = _effective_mesh_rebuild_budget()
	for coord_variant in keys:
		var coord: Vector2i = coord_variant
		if not _chunk_active(coord):
			_dirty_chunks.erase(coord)
			continue
		if _chunk_needs_full_rebuild.has(coord):
			_rebuild_chunk_layer(coord)
			_chunk_needs_full_rebuild.erase(coord)
			_patch_dirty_by_chunk.erase(coord)
			rebuild_count += 1
		else:
			_patch_chunk_layer(coord)
			_patch_dirty_by_chunk.erase(coord)
			patch_count += 1
		_dirty_chunks.erase(coord)
		rebuilt += 1
		if rebuilt >= budget:
			break
		if Time.get_ticks_usec() - t0 >= mesh_budget_us:
			break
	if profiler and profiler.has_method("end"):
		profiler.end("crystal_mesh")
	last_flush_rebuilds = rebuilt
	return rebuilt


func diagnostics() -> Dictionary:
	return {
		"dirty_chunks": _dirty_chunks.size(),
		"layers": _chunk_layers.size(),
		"rebuild_count": rebuild_count,
		"patch_count": patch_count,
		"events_applied": events_applied,
		"last_flush_rebuilds": last_flush_rebuilds,
	}


func _index_crystal_cell(pos: Vector2i) -> void:
	if fluid == null or not fluid.depth.has(pos):
		_unindex_crystal_cell(pos)
		return
	var coord := _chunk_coord_for(pos)
	if not _cells_by_chunk.has(coord):
		_cells_by_chunk[coord] = []
	var bucket: Array = _cells_by_chunk[coord]
	if pos not in bucket:
		bucket.append(pos)


func _unindex_crystal_cell(pos: Vector2i) -> void:
	var coord := _chunk_coord_for(pos)
	if not _cells_by_chunk.has(coord):
		return
	var bucket: Array = _cells_by_chunk[coord]
	bucket.erase(pos)
	if bucket.is_empty():
		_cells_by_chunk.erase(coord)


func _mark_chunk_dirty(pos: Vector2i) -> void:
	var coord := _chunk_coord_for(pos)
	if not _chunk_active(coord):
		return
	_dirty_chunks[coord] = true


func _chunk_coord_for(pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(pos.x) / float(chunk_size)),
		floori(float(pos.y) / float(chunk_size))
	)


func _chunk_active(coord: Vector2i) -> bool:
	if is_chunk_render_active.is_valid():
		return bool(is_chunk_render_active.call(coord))
	return true


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _effective_mesh_rebuild_budget() -> int:
	var budget: int = max_rebuilds_per_frame
	var cells: int = fluid.cell_count() if fluid else 0
	if cells >= spread_damping_full:
		return mini(budget, mesh_rebuilds_when_large)
	if cells >= maxi(spread_damping_start - 120, 200):
		return maxi(1, mini(budget, mesh_rebuilds_when_large))
	if cells >= spread_damping_start:
		return maxi(1, mini(budget, int(ceil(float(budget) * 0.5))))
	return budget


func _lod_tier_for_chunk(coord: Vector2i) -> int:
	if _CrystalClusterMesh.use_legacy_renderer():
		return _CrystalClusterMesh.LOD_FULL
	var player_chunk: Vector2i = Vector2i(-99999, -99999)
	if player_chunk_coord.is_valid():
		player_chunk = player_chunk_coord.call()
	if player_chunk == Vector2i(-99999, -99999):
		return _CrystalClusterMesh.LOD_MID
	var dist := _manhattan(coord, player_chunk)
	return _CrystalClusterMesh.lod_tier_for_chunk_distance(dist)


func _make_render_cell(pos: Vector2i, depth: float, spawn_id: int):
	var floor_h: float = 0.0
	if crystal_floor_at.is_valid():
		floor_h = float(crystal_floor_at.call(pos))
	var cell = _CrystalCell.new(pos, floor_h, depth, spawn_id)
	if not _CrystalClusterMesh.use_legacy_renderer() and fluid:
		var min_d: float = sim_config.min_depth if sim_config else 0.04
		cell.neighbor_mask = _CrystalClusterMesh.neighbor_mask_from_depths(
			pos, fluid.depth, min_d
		)
	return cell


func _rebuild_chunk_layer(coord: Vector2i) -> void:
	if not _chunk_active(coord) or layer_root == null:
		return
	var cells: Array = []
	var positions: Array = _cells_by_chunk.get(coord, [])
	var min_d: float = sim_config.min_depth if sim_config else 0.04
	for pos_variant in positions:
		var pos: Vector2i = pos_variant
		if not fluid or not fluid.depth.has(pos):
			continue
		var depth: float = float(fluid.depth[pos])
		if depth < min_d:
			continue
		cells.append(_make_render_cell(
			pos,
			depth,
			int(fluid.spawn_id_by_cell.get(pos, -1))
		))
	var layer
	if _chunk_layers.has(coord):
		layer = _chunk_layers[coord]
	else:
		if make_layer.is_valid():
			layer = make_layer.call(coord)
		else:
			layer = load("res://crystal/crystal_chunk_layer.gd").new()
			layer.name = "CrystalChunk_%d_%d" % [coord.x, coord.y]
			layer_root.add_child(layer)
			layer.setup(coord, crystal_material)
		_chunk_layers[coord] = layer
	layer.rebuild(cells, _lod_tier_for_chunk(coord))


func _patch_chunk_layer(coord: Vector2i) -> void:
	var positions: Array = _patch_dirty_by_chunk.get(coord, [])
	if positions.is_empty():
		_rebuild_chunk_layer(coord)
		return
	if not _chunk_layers.has(coord):
		_rebuild_chunk_layer(coord)
		return
	var cells: Array = []
	var needs_full := false
	for pos_variant in positions:
		var pos: Vector2i = pos_variant
		if not fluid or not fluid.depth.has(pos):
			needs_full = true
			break
		cells.append(_make_render_cell(
			pos,
			float(fluid.depth[pos]),
			int(fluid.spawn_id_by_cell.get(pos, -1))
		))
	var layer = _chunk_layers[coord]
	if needs_full or not layer.patch_cells(cells):
		_rebuild_chunk_layer(coord)


func refresh_lod_if_player_moved(last_player_chunk: Vector2i) -> Vector2i:
	if _CrystalClusterMesh.use_legacy_renderer():
		return last_player_chunk
	if not player_chunk_coord.is_valid():
		return last_player_chunk
	var player_chunk: Vector2i = player_chunk_coord.call()
	if player_chunk == Vector2i(-99999, -99999) or player_chunk == last_player_chunk:
		return last_player_chunk
	for coord_variant in _chunk_layers.keys():
		var coord: Vector2i = coord_variant
		var layer = _chunk_layers[coord]
		var new_tier := _lod_tier_for_chunk(coord)
		if layer.lod_tier != new_tier:
			_chunk_needs_full_rebuild[coord] = true
			_dirty_chunks[coord] = true
	return player_chunk
