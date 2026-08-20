extends SceneTree
## Micro terrain contract: sparse bricks, macro parity, incremental dirty scope.


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _MacroLayerGrid = preload("res://helpers/macro_layer_grid.gd")
const _MicroLayerGrid = preload("res://helpers/micro_layer_grid.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainDirtyScope = preload("res://helpers/terrain_dirty_scope.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	if not _MicroLayerGrid.enabled():
		push_error("micro terrain must be enabled by default")
		failed = true

	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 4242

	_TerrainEdits.reset()
	var data := _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	data.prewarm_macro_storage()

	if data.micro_grid != null and data.micro_grid.brick_count() > 0:
		push_error("fresh chunk must not have micro bricks before edits")
		failed = true

	var untouched_y: float = data.get_surface_y(2, 2)
	var untouched_t: int = data.get_tile_type(2, 2)

	_TerrainEdits.dig(4, 4, 1)
	data.refresh_worker_snapshot_for_cells([Vector2i(4, 4)])
	var dirty_local: Array = [Vector2i(4, 4)]
	var examined: int = data.update_dirty_column_maps(dirty_local)
	if examined != 1:
		push_error("single-cell edit must examine exactly 1 column, got %d" % examined)
		failed = true
	else:
		print("OK incremental dirty refresh examined=%d" % examined)

	if not data.has_micro_brick(4, 4):
		push_error("dig must allocate micro brick on edited column")
		failed = true

	if data.macro_grid == null or not data.macro_grid.has_micro_flag(4, 4):
		push_error("FLAG_MICRO_PRESENT must be set when micro brick exists")
		failed = true
	elif data.macro_grid.has_micro_flag(2, 2):
		push_error("FLAG_MICRO_PRESENT must not be set without micro brick")
		failed = true
	else:
		print("OK FLAG_MICRO_PRESENT only on allocated columns")

	var edited_y: float = data.get_surface_y(4, 4)
	var edited_t: int = data.get_tile_type(4, 4)
	var brick = data.micro_grid.get_brick(4, 4)
	if brick == null or not brick.matches_macro(edited_y, edited_t):
		push_error("micro brick must mirror macro authority on edited column")
		failed = true
	else:
		print("OK micro brick mirrors macro on edited column")

	if data.has_micro_brick(2, 2):
		push_error("untouched column must not have micro brick")
		failed = true
	if not is_equal_approx(data.get_surface_y(2, 2), untouched_y):
		push_error("non-micro column surface_y must match macro-only baseline")
		failed = true
	if data.get_tile_type(2, 2) != untouched_t:
		push_error("non-micro column tile must match macro-only baseline")
		failed = true
	else:
		print("OK macro/micro query parity on columns without micro")

	var micro_before: int = data.last_micro_examined
	data._compute_column_maps(true)
	if data.last_micro_examined != micro_before:
		push_error("full map recompute must not invoke incremental micro dirty refresh")
		failed = true
	else:
		print("OK localized patch avoids whole-chunk micro refresh")

	var scope: Dictionary = _TerrainDirtyScope.compute_edit_scope(4, 4)
	if int(scope.get("dirty_columns", 0)) != 9:
		push_error("TerrainDirtyScope must remain 9 columns for single edit")
		failed = true

	_ChunkDataPool.release(data)

	if failed:
		quit(1)
		return
	print("All micro layer grid tests OK")
	quit(0)