extends SceneTree
## Headless: chunk pipeline stages, job-local scratch, frozen WorldState inputs.
## Usage: godot --headless -s scripts/verify_chunk_pipeline.gd

const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")


var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("OK chunk pipeline stages + stateless worker")
		quit(0)
	else:
		push_error("verify_chunk_pipeline: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	# Stage contract surface
	if _ChunkPipeline.STAGES.size() < 6:
		_fail("pipeline must expose explicit stage list")
	for s in [
		_ChunkPipeline.STAGE_STREAM_REQUEST,
		_ChunkPipeline.STAGE_SNAPSHOT,
		_ChunkPipeline.STAGE_COLUMN,
		_ChunkPipeline.STAGE_MESH,
		_ChunkPipeline.STAGE_BUFFER,
		_ChunkPipeline.STAGE_APPLY,
	]:
		if s not in _ChunkPipeline.STAGES:
			_fail("missing stage constant %s" % s)

	# Job-local visit grids are independent
	var v1: Array = _ChunkPipeline.alloc_greedy_visited(4)
	var v2: Array = _ChunkPipeline.alloc_greedy_visited(4)
	v1[0][0] = true
	if bool(v2[0][0]):
		_fail("alloc_greedy_visited must not share storage across jobs")
	v2[1][1] = true
	if bool(v1[1][1]):
		_fail("mutating one visit grid must not affect another")

	_WorldState.replace_active()
	var world = _InfiniteNoiseWorld.new()
	if "world_seed" in world:
		world.world_seed = 7

	var mgr = _ChunkManager.new()
	# Two isolated jobs with frozen snapshots
	_TerrainEdits.dig(2, 2, 1)
	var data_a = _ChunkData.new(Vector2i(0, 0), world)
	data_a.capture_worker_snapshot()  # STAGE_SNAPSHOT
	if not data_a.has_worker_overlay_snapshot():
		_fail("snapshot stage did not freeze overlays")
		return
	var frozen_a: float = data_a.get_worker_height_delta(2, 2)

	_TerrainEdits.build_wall(5, 5, _VoxelTypes.STONE)
	var data_b = _ChunkData.new(Vector2i(1, 0), world)
	data_b.capture_worker_snapshot()
	var frozen_b_build: int = data_b.get_worker_build_tile(5 - 16, 5)  # world 5,5 is in chunk (0,0) actually
	# chunk (1,0) covers wx 16..31 — use local dig for B
	_WorldState.replace_active()
	_TerrainEdits.dig(18, 2, 1)
	data_b = _ChunkData.new(Vector2i(1, 0), world)
	data_b.capture_worker_snapshot()
	var frozen_b: float = data_b.get_worker_height_delta(2, 2)  # local 2,2 → world 18,2

	# Live mutate after freeze — frozen arrays must stay put
	_TerrainEdits.dig(2, 2, 1)
	_TerrainEdits.dig(18, 2, 1)
	if not is_equal_approx(data_a.get_worker_height_delta(2, 2), frozen_a):
		_fail("job A frozen delta changed after live dig")
	if not is_equal_approx(data_b.get_worker_height_delta(2, 2), frozen_b):
		_fail("job B frozen delta changed after live dig")

	# Pure stage entry: mesh stage must not require manager shared scratch fields
	var cm_src := FileAccess.get_file_as_string("res://chunks/chunk_manager.gd")
	if cm_src.find("_greedy_visited_scratch") >= 0:
		_fail("manager still declares shared _greedy_visited_scratch")
	if cm_src.find("var _micro_skip_set") >= 0 or cm_src.find("var _micro_skip_active") >= 0:
		_fail("manager still declares shared micro skip fields")

	# Run full worker job path via shipped pipeline (column+mesh+buffer)
	_WorldState.replace_active()
	_TerrainEdits.dig(3, 3, 1)
	var data = _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	var stamp_before: Dictionary = data.overlay_mesh_stamp.duplicate()
	var job: Dictionary = _ChunkPipeline.run_worker_job(
		mgr,
		data,
		true,
		[],
		Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE),
		[],
		{},
		false,
		true
	)
	if not bool(job.get("ok", false)):
		_fail("run_worker_job failed")
	if not job.has("stages"):
		_fail("worker job must report stages")
	var stages: Array = job.get("stages", [])
	if _ChunkPipeline.STAGE_COLUMN not in stages or _ChunkPipeline.STAGE_MESH not in stages:
		_fail("worker job stages incomplete: %s" % str(stages))
	var quads: Array = job.get("merged_quads", [])
	if quads.is_empty():
		_fail("mesh stage produced no quads for non-empty terrain")
	# Job finished with job-local micro skip cleared
	if not data._mesh_job_micro_skip.is_empty():
		_fail("mesh job micro skip should be cleared after mesh stage")

	# Two sequential jobs: independent visit via alloc (already tested) + independent outputs
	_WorldState.replace_active()
	var d1 = _ChunkData.new(Vector2i(0, 0), world)
	d1.capture_worker_snapshot()
	var j1: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d1, true, [], Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), [], {}, false, true
	)
	var d2 = _ChunkData.new(Vector2i(0, 0), world)
	_TerrainEdits.dig(4, 4, 2)
	d2.capture_worker_snapshot()
	var j2: Dictionary = _ChunkPipeline.run_worker_job(
		mgr, d2, true, [], Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), [], {}, false, true
	)
	if not bool(j1.get("ok", false)) or not bool(j2.get("ok", false)):
		_fail("sequential isolated jobs must succeed")
	# Dig job should see different examined/count characteristics vs pristine (not hard-coded counts)
	var c1: int = int(j1.get("merged_quads", []).size())
	var c2: int = int(j2.get("merged_quads", []).size())
	if c1 <= 0 or c2 <= 0:
		_fail("both jobs should emit quads")
	# Frozen stamp still current for d2 until live mutation
	if not d2.is_overlay_mesh_stamp_current():
		_fail("d2 stamp should be current after its own capture+job without further dig")
	_TerrainEdits.dig(4, 4, 1)
	if d2.is_overlay_mesh_stamp_current():
		_fail("live dig after job must stale mesh stamp (WorldState preserved)")

	# Mid-job live WorldState must not feed column maps: re-run column only from frozen
	_WorldState.replace_active()
	_TerrainEdits.dig(1, 1, 1)
	var d3 = _ChunkData.new(Vector2i(0, 0), world)
	d3.capture_worker_snapshot()
	var fr: float = d3.get_worker_height_delta(1, 1)
	_TerrainEdits.dig(1, 1, 1)  # live deeper
	var col: Dictionary = _ChunkPipeline.run_column_stage(mgr, d3, true, [])
	if not bool(col.get("ok", false)):
		_fail("column stage failed")
	if not is_equal_approx(d3.get_worker_height_delta(1, 1), fr):
		_fail("column stage must not refresh frozen worker deltas from live WorldState")

	# Structural: pipeline module exists and manager routes worker through it
	if cm_src.find("run_worker_job") < 0 and cm_src.find("_ChunkPipeline") < 0:
		_fail("chunk_manager worker entry must call ChunkPipeline")
	var pipe_src := FileAccess.get_file_as_string("res://chunks/chunk_pipeline.gd")
	if pipe_src.find("run_column_stage") < 0 or pipe_src.find("run_mesh_stage") < 0:
		_fail("chunk_pipeline missing stage APIs")

	mgr.free()
