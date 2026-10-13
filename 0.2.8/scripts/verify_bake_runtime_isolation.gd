extends SceneTree
## Verify a complete baked world never procedurally regenerates static terrain.
## Expects:
##   generate_chunk_calls = 0
##   halo_noise_calls = 0
##   runtime_noise_height_calls = 0  (for in-package cells during stream/dirty)

const _WorldBake = preload("res://world/world_bake_service.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")

var _failed: int = 0
var _ok_n: int = 0


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	_ok_n += 1
	print("OK: %s" % msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_SMOKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")

	var world = _InfiniteNoiseWorld.new(12349)
	var bake = _WorldBake.ensure_active()
	bake.delete_bake(12349, 2)
	var baked: Dictionary = bake.bake_world(world, 2, null)
	if not bool(baked.get("ok", false)):
		_fail("bake_world failed: %s" % str(baked))
		_quit_with_code()
		return
	var saved: Dictionary = bake.save_bake()
	if not bool(saved.get("ok", false)):
		_fail("save_bake failed: %s" % str(saved))
		_quit_with_code()
		return
	if not bake.load_bake(12349, 2):
		_fail("load_bake failed: %s" % bake.last_error)
		_quit_with_code()
		return
	_ok("bake loaded bounds=%s veg=%s" % [str(bake.bounds_dict()), str(bake.vegetation_baked)])

	var mgr = _ChunkManager.new()
	mgr.world = world
	bake.reset_runtime_gen_stats()

	# Stream all package coords via full column stage + halo capture.
	var coords: Array = bake.covered_coords()
	for c_variant in coords:
		var coord: Vector2i = c_variant
		_WorldState.replace_active()
		var data = _ChunkData.new(coord, world)
		data.capture_worker_snapshot()
		var col: Dictionary = _ChunkPipeline.run_column_stage(mgr, data, true, [])
		if str(col.get("column_source", "")) != "bake":
			_fail("column_source want bake got=%s at %s" % [str(col.get("column_source")), str(coord)])
		if not data.has_baked_base():
			_fail("missing stored baked base at %s" % str(coord))
		# Dirty rebuild a few interior + edge cells without noise.
		var dirty: Array = [Vector2i(1, 1), Vector2i(0, 0), Vector2i(15, 15), Vector2i(8, 0)]
		data.update_dirty_column_maps(dirty)
		# Dig overlay recompose
		_TerrainEdits.dig(coord.x * 16 + 3, coord.y * 16 + 3, 1)
		data.capture_worker_snapshot()
		data.update_dirty_column_maps([Vector2i(3, 3)])
		var job: Dictionary = _ChunkPipeline.run_worker_job(
			mgr, data, false, [Vector2i(3, 3)],
			Rect2i(2, 2, 3, 3), [], {}, false, false
		)
		if not bool(job.get("ok", false)):
			_fail("dirty worker job failed at %s" % str(coord))
		# Natural height for dig strata must come from bake.
		var natural: float = data.get_natural_surface_y(3, 3)
		var base: float = data.get_baked_base_height(3, 3)
		if not is_equal_approx(natural, base):
			_fail("natural_surface != baked base at %s n=%s b=%s" % [str(coord), str(natural), str(base)])

	var st: Dictionary = bake.runtime_gen_stats()
	print("STATS: %s" % JSON.stringify(st))
	if int(st.get("generate_chunk_calls", -1)) != 0:
		_fail("generate_chunk_calls want 0 got %s" % str(st.get("generate_chunk_calls")))
	else:
		_ok("generate_chunk_calls=0")
	if int(st.get("halo_noise_calls", -1)) != 0:
		_fail("halo_noise_calls want 0 got %s" % str(st.get("halo_noise_calls")))
	else:
		_ok("halo_noise_calls=0")
	if int(st.get("runtime_noise_height_calls", -1)) != 0:
		_fail("runtime_noise_height_calls want 0 got %s" % str(st.get("runtime_noise_height_calls")))
	else:
		_ok("runtime_noise_height_calls=0")
	if int(st.get("halo_bake_hits", 0)) <= 0:
		_fail("expected halo_bake_hits > 0")
	else:
		_ok("halo_bake_hits=%d" % int(st.get("halo_bake_hits", 0)))
	if int(st.get("dirty_bake_hits", 0)) <= 0:
		_fail("expected dirty_bake_hits > 0")
	else:
		_ok("dirty_bake_hits=%d" % int(st.get("dirty_bake_hits", 0)))

	# Outside package: generate path still allowed (smoke: just past max bounds).
	var outside := Vector2i(bake.max_cx + 2, bake.max_cz + 2)
	if bake.should_block_procedural_generate(outside):
		_fail("outside package should not block generate")
	else:
		_ok("outside package not blocked")
	bake.reset_runtime_gen_stats()
	_WorldState.replace_active()
	var d_out = _ChunkData.new(outside, world)
	d_out.capture_worker_snapshot()
	var col_out: Dictionary = _ChunkPipeline.run_column_stage(mgr, d_out, true, [])
	if str(col_out.get("column_source", "")) != "generate":
		_fail("outside want generate got=%s" % str(col_out.get("column_source")))
	else:
		_ok("outside package uses generate")
	var st_out: Dictionary = bake.runtime_gen_stats()
	if int(st_out.get("generate_chunk_calls", 0)) < 1:
		_fail("outside generate_chunk_calls should increment")
	else:
		_ok("outside generate_chunk_calls=%d" % int(st_out.get("generate_chunk_calls", 0)))

	print("RESULT ok=%d fail=%d" % [_ok_n, _failed])
	_quit_with_code()


func _quit_with_code() -> void:
	quit(1 if _failed > 0 else 0)
