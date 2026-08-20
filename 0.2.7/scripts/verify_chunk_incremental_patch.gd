extends SceneTree
## Telemetry corroboration: interior dig examines far fewer than 256 columns.


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkRebuildTelemetry = preload("res://systems/chunk_rebuild_telemetry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_CHUNK_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_ChunkRebuildTelemetry.reset()

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Chunk incremental patch FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null

	for _attempt in 600:
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		if chunk_manager != null and terrain != null and world != null and chunk_manager.chunks.size() >= 3:
			break
		await process_frame

	if chunk_manager == null or terrain == null or world == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Chunk incremental patch FAILED")
		return

	for _w in 30:
		await process_frame

	var dig_cell := Vector2i(-1, -1)
	for lx in range(_TerrainEditor.REBUILD_EDGE_BAND, _ChunkData.SIZE - _TerrainEditor.REBUILD_EDGE_BAND):
		for lz in range(_TerrainEditor.REBUILD_EDGE_BAND, _ChunkData.SIZE - _TerrainEditor.REBUILD_EDGE_BAND):
			var wx: int = chunk_manager.get_player_chunk_coord().x * _ChunkData.SIZE + lx
			var wz: int = chunk_manager.get_player_chunk_coord().y * _ChunkData.SIZE + lz
			if world.get_surface_height(float(wx), float(wz)) > 1.0:
				dig_cell = Vector2i(wx, wz)
				break
		if dig_cell.x >= 0:
			break

	if dig_cell.x < 0:
		push_error("no interior dig cell found")
		failed = true
		_ProbeExit.finish_tree(self, 1, "Chunk incremental patch FAILED")
		return

	_ChunkRebuildTelemetry.set_scenario("incremental_interior_dig")
	_ChunkRebuildTelemetry.set_trigger_hint("terrain_edit", {"voxels_changed_hint": 1})
	var sy: float = world.get_surface_height(float(dig_cell.x), float(dig_cell.y))
	terrain.try_dig(Vector3(float(dig_cell.x) + 0.5, sy, float(dig_cell.y) + 0.5))
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 20:
		await process_frame

	var records: Array = _ChunkRebuildTelemetry.get_records()
	var edit_rows: Array = []
	for row_variant in records:
		var row: Dictionary = row_variant
		if str(row.get("trigger", "")) == "terrain_edit" and bool(row.get("incremental", false)):
			edit_rows.append(row)

	if edit_rows.is_empty():
		push_error("expected incremental terrain_edit telemetry row")
		failed = true
	else:
		var row: Dictionary = edit_rows[0]
		var examined: int = int(row.get("voxels_examined", 999))
		var rebuilt: int = int(row.get("rebuilt_columns", 999))
		var patch_size: int = int(row.get("mesh_patch_size", 999))
		var alloc_path: String = str(row.get("chunk_data_alloc_path", ""))
		if examined >= 32:
			push_error("interior dig examined %d columns (expected << 256)" % examined)
			failed = true
		elif rebuilt >= 32:
			push_error("interior dig rebuilt %d columns (expected << 256)" % rebuilt)
			failed = true
		elif patch_size >= 64:
			push_error("interior dig mesh_patch_size=%d (expected small patch)" % patch_size)
			failed = true
		elif alloc_path != "reuse":
			push_error("interior dig must reuse ChunkData (got %s)" % alloc_path)
			failed = true
		else:
			print(
				"OK incremental interior dig examined=%d rebuilt=%d patch=%d alloc=%s"
				% [examined, rebuilt, patch_size, alloc_path]
			)

	if failed:
		_ProbeExit.finish_tree(self, 1, "Chunk incremental patch FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All chunk incremental patch tests OK")