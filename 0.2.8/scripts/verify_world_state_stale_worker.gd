extends SceneTree
## Headless: worker mesh-input stamp + stale job rejection + frozen overlay reads.
## Usage: godot --headless -s scripts/verify_world_state_stale_worker.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _MicroLayerGrid = preload("res://helpers/micro_layer_grid.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")


var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("OK world state stale worker")
		quit(0)
	else:
		push_error("verify_world_state_stale_worker: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_WorldState.replace_active()
	var ws = _WorldState.get_active()

	var world = _InfiniteNoiseWorld.new()
	if "world_seed" in world:
		world.world_seed = 42
	var data = _ChunkData.new(Vector2i(0, 0), world)

	# Seed an overlay cell then freeze snapshot
	_TerrainEdits.dig(2, 3, 1)
	data.capture_worker_snapshot()
	if not data.has_worker_overlay_snapshot():
		_fail("capture_worker_snapshot did not set worker overlay snapshot")
		return
	if data.overlay_mesh_stamp.is_empty():
		_fail("overlay_mesh_stamp empty after capture")
		return
	if not data.is_overlay_mesh_stamp_current():
		_fail("stamp should be current immediately after capture")
	if not ws.is_mesh_stamp_current(data.overlay_mesh_stamp):
		_fail("WorldState stamp check disagrees with ChunkData")

	var frozen_h: float = float(data.get_worker_height_delta(2, 3))
	if is_equal_approx(frozen_h, 0.0):
		_fail("frozen worker height delta should reflect dig")

	# Live mutation after capture: stamp stale, frozen arrays unchanged
	_TerrainEdits.dig(2, 3, 1)
	if data.is_overlay_mesh_stamp_current():
		_fail("stamp must be stale after mesh-input dig")
	if not is_equal_approx(float(data.get_worker_height_delta(2, 3)), frozen_h):
		_fail("worker frozen arrays mutated after live dig (not immutable)")

	# Micro grid overlay helpers must prefer frozen arrays (worker path)
	var micro_h: float = _MicroLayerGrid._overlay_height_delta(data, 2, 3, 2, 3)
	if not is_equal_approx(micro_h, frozen_h):
		_fail("MicroLayerGrid must read frozen height delta when snapshot present (got %s want %s)" % [
			micro_h, frozen_h
		])
	var live_h: float = _TerrainEdits.get_height_delta(2, 3)
	if is_equal_approx(live_h, frozen_h):
		_fail("live TerrainEdits should differ from frozen after post-capture dig")

	# Region snapshot API also freezes copies
	var region: Dictionary = ws.capture_mesh_overlay_snapshot(0, 0, 16, 16)
	var hmap: Dictionary = region.get("height_delta", {})
	var layers_at: int = int(hmap.get(Vector2i(2, 3), 0))
	_TerrainEdits.dig(2, 3, 1)
	if int(hmap.get(Vector2i(2, 3), 0)) != layers_at:
		_fail("capture_mesh_overlay_snapshot contents mutated")

	# ChunkManager.is_mesh_job_stale — shipped gate used by apply path
	var mgr = _ChunkManager.new()
	var coord := Vector2i(0, 0)
	mgr._chunk_gen_tokens[coord] = 7
	data.capture_worker_snapshot()
	if mgr.is_mesh_job_stale(coord, data, 7):
		_fail("job should not be stale when token and stamp match")
	if not mgr.is_mesh_job_stale(coord, data, 6):
		_fail("token mismatch should be stale")
	_TerrainEdits.dig(4, 4, 1)
	if not mgr.is_mesh_job_stale(coord, data, 7):
		_fail("mesh-input stamp supersede should make job stale")

	# Feature-meta only must NOT stale mesh stamp
	data.capture_worker_snapshot()
	ws.bump(_WorldState.DOMAIN_FEATURE)
	if not data.is_overlay_mesh_stamp_current():
		_fail("feature-meta bump must not invalidate mesh stamp")

	# Feature tile DOES stale mesh stamp
	data.capture_worker_snapshot()
	_FeatureRegistry.set_tile_override(1, 1, _VoxelTypes.STONE)
	if data.is_overlay_mesh_stamp_current():
		_fail("feature tile override must invalidate mesh stamp")

	# Micro derive on worker snapshot must ignore post-capture live digs elsewhere
	_WorldState.replace_active()
	data = _ChunkData.new(Vector2i(0, 0), world)
	_TerrainEdits.dig(2, 3, 1)
	data.capture_worker_snapshot()
	_TerrainEdits.dig(7, 7, 1)  # live only — not in frozen snapshot
	# Force maps so derive can run
	if data.has_method("_compute_column_maps"):
		data._compute_column_maps(true)
	data.derive_micro_from_terrain_edits()
	var micro = data.micro_grid if "micro_grid" in data else null
	if micro == null and data.has_method("_micro_grid"):
		micro = data._micro_grid()
	if micro != null:
		if micro.has_method("has_brick"):
			if not micro.has_brick(2, 3):
				_fail("micro should allocate brick for frozen dig at (2,3)")
			if micro.has_brick(7, 7):
				_fail("micro must not see post-capture live dig at (7,7) via frozen path")
	else:
		# Fallback: helpers still return frozen vs live
		if not is_equal_approx(
			_MicroLayerGrid._overlay_height_delta(data, 7, 7, 7, 7), 0.0
		):
			_fail("frozen overlay height at (7,7) should be 0 after post-capture-only dig")

	# Halo border refresh after capture must use frozen halo deltas, not live WorldState
	_WorldState.replace_active()
	data = _ChunkData.new(Vector2i(0, 0), world)
	# Exterior neighbor of local (0,0) is world (-1, 0)
	_TerrainEdits.dig(-1, 0, 1)
	data.capture_worker_snapshot()
	var dim: int = _ChunkData.SIZE + _ChunkData.HALO * 2
	if data._worker_halo_height_delta.is_empty():
		_fail("worker halo height delta not captured")
	else:
		var frozen_halo: float = float(data._worker_halo_height_delta[0][1])  # lx=-1,lz=0 → ix=0,iz=1
		_TerrainEdits.dig(-1, 0, 1)  # live deeper
		# Refresh exterior via worker path (has snapshot → frozen deltas)
		data._refresh_halo_border_for_local_cell(0, 0)
		if not is_equal_approx(float(data._worker_halo_height_delta[0][1]), frozen_halo):
			_fail("halo frozen height delta mutated by live dig")
		# Live WorldState differs
		var live_ext: float = _TerrainEdits.get_height_delta(-1, 0)
		if is_equal_approx(live_ext, frozen_halo):
			_fail("live exterior dig should differ from frozen halo delta")

	# Source-level guard: micro worker helpers must not call live TerrainEdits when snapshot set
	# (behavioral proof above). Structural string audit of critical call sites:
	var micro_src := FileAccess.get_file_as_string("res://helpers/micro_layer_grid.gd")
	if micro_src.find("_overlay_build_tile") < 0 or micro_src.find("has_worker_overlay_snapshot") < 0:
		_fail("micro_layer_grid missing worker-snapshot overlay helpers")
	var chunk_src := FileAccess.get_file_as_string("res://chunks/chunk_data.gd")
	if chunk_src.find("_worker_halo_height_delta") < 0:
		_fail("chunk_data missing frozen halo height delta storage")
	if chunk_src.find("never re-read live WorldState") < 0 \
			and chunk_src.find("_worker_halo_height_delta[ix][iz]") < 0:
		_fail("halo border path not wired to frozen halo deltas")

	mgr.free()
	data = null
