extends SceneTree
## Macro terrain grid — parity with legacy surface_map/tile_map via real ChunkData path.


const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _MacroLayerGrid = preload("res://helpers/macro_layer_grid.gd")
const MAIN_SCENE := "res://scenes/main.tscn"


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_MACRO_TERRAIN", "1")
	call_deferred("_run")


func _run() -> void:
	if not _MacroLayerGrid.enabled():
		_ProbeExit.finish_tree(self, 1, "macro layer grid verify FAILED: macro disabled")
		return

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "macro layer grid verify FAILED: main scene")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	for _i in 600:
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		if chunk_manager != null and world != null and chunk_manager.chunks.size() >= 1:
			break
		await process_frame

	if chunk_manager == null or world == null or chunk_manager.chunks.is_empty():
		_ProbeExit.finish_tree(self, 1, "macro layer grid verify FAILED: no chunks")
		return

	var coord: Vector2i = chunk_manager.chunks.keys()[0]
	var view = chunk_manager.chunks[coord]
	var data: ChunkData = view.chunk_data
	if data == null:
		_ProbeExit.finish_tree(self, 1, "macro layer grid verify FAILED: no chunk data")
		return

	data._bind_macro_surface_if_needed()
	if data.macro_grid == null or not data.macro_grid.is_ready():
		_ProbeExit.finish_tree(self, 1, "macro layer grid verify FAILED: macro not ready after load")
		return

	data.ensure_legacy_maps_synced()

	var mismatches := 0
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			var macro_y: float = data.macro_grid.get_surface_y(x, z)
			var legacy_y: float = float(data.surface_map[x][z]) if data.surface_map.size() > x else -1.0
			var macro_t: int = data.macro_grid.get_surface_tile(x, z)
			var legacy_t: int = int(data.tile_map[x][z]) if data.tile_map.size() > x else -1
			if not is_equal_approx(macro_y, legacy_y):
				mismatches += 1
				push_error("macro/legacy surface_y mismatch at %d,%d: %.3f vs %.3f" % [x, z, macro_y, legacy_y])
			if macro_t != legacy_t:
				mismatches += 1
				push_error("macro/legacy tile mismatch at %d,%d: %d vs %d" % [x, z, macro_t, legacy_t])
			if data.get_surface_y(x, z) != macro_y or data.get_tile_type(x, z) != macro_t:
				mismatches += 1
				push_error("façade mismatch at %d,%d" % [x, z])

	# Incremental dirty refresh on one interior cell
	var local := [Vector2i(4, 4)]
	var before_y: float = data.macro_grid.get_surface_y(4, 4)
	data.refresh_worker_snapshot_for_cells(local)
	var examined: int = data.update_dirty_column_maps(local)
	data._bind_macro_surface_if_needed()
	if examined != 1:
		push_error("update_dirty_column_maps examined %d expected 1" % examined)
		mismatches += 1
	var after_y: float = data.macro_grid.get_surface_y(4, 4)
	if not is_equal_approx(before_y, after_y):
		push_error("dirty refresh changed unchanged cell %.3f -> %.3f" % [before_y, after_y])
		mismatches += 1
	data.sync_legacy_cells(local)
	if not is_equal_approx(data.get_surface_y(4, 4), float(data.surface_map[4][4])):
		mismatches += 1

	if data.macro_grid.schema_version < 1:
		mismatches += 1

	# Ramp flags batch at finalize only — set_ramp_* must not touch macro flags inline.
	data.ramp_map.clear()
	data.set_ramp_cardinal(5, 5, Vector2i(1, 0))
	var inline_ramp: int = data.macro_grid.get_flags(5, 5) & _MacroLayerGrid.FLAG_RAMP
	if inline_ramp != 0:
		push_error("set_ramp_cardinal wrote macro FLAG_RAMP before finalize")
		mismatches += 1
	data.finalize_macro_metadata(true)
	if (data.macro_grid.get_flags(5, 5) & _MacroLayerGrid.FLAG_RAMP) == 0:
		push_error("finalize_macro_metadata did not sync ramp flag")
		mismatches += 1

	var cm := _ChunkManager.new()
	data.ramp_map.clear()
	cm._build_mesh(data)
	data.finalize_macro_metadata(true)
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			var expect_ramp: bool = data.has_ramp(x, z)
			var has_flag: bool = (data.macro_grid.get_flags(x, z) & _MacroLayerGrid.FLAG_RAMP) != 0
			if expect_ramp != has_flag:
				push_error("mesh ramp flag mismatch at %d,%d map=%s flag=%s" % [
					x, z, expect_ramp, has_flag
				])
				mismatches += 1

	if mismatches > 0:
		_ProbeExit.finish_tree(self, 1, "macro layer grid verify FAILED mismatches=%d" % mismatches)
		return

	print("OK macro grid ready schema=%d façade parity=%d cells" % [
		data.macro_grid.schema_version,
		_ChunkData.SIZE * _ChunkData.SIZE,
	])
	_ProbeExit.finish_tree(self, 0, "All macro layer grid tests OK")