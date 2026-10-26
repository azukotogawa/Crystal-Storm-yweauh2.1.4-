extends SceneTree


const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var src := (_TerrainEditor as GDScript).source_code
	if "_replace_cell_with_water_block" in src:
		push_error("dig beside water must not swap the cell for a water tile")
		failed = true
	else:
		print("OK no instant water swap beside water")
	if "request_flow(" not in src:
		push_error("terrain edits must request flow from the fluid service")
		failed = true
	else:
		print("OK terrain edits reach water only through request_flow")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	var world: InfiniteNoiseWorld = _InfiniteNoiseWorld.new()
	world.world_seed = 7
	root.add_child(world)
	_FeatureRegistry.set_tile_override(3, 2, _VoxelTypes.GRASSLAND)
	_FeatureRegistry.set_tile_override(2, 2, _VoxelTypes.RIVER)
	var editor: TerrainEditor = _TerrainEditor.new()
	root.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(_ChunkManager.new())
	await process_frame

	var h0: float = world.get_surface_height(3.0, 2.0)
	var dug: bool = editor.try_dig(Vector3(3.5, 0.0, 2.5))
	var h1: float = world.get_surface_height(3.0, 2.0)
	if not dug or h1 >= h0 - 0.01:
		push_error("dig beside river must open a cavity h %.2f to %.2f why=%s" % [h0, h1, editor.last_fail_reason])
		failed = true
	elif _FeatureRegistry.get_tile_override(3, 2) != _VoxelTypes.GRASSLAND:
		push_error("dig beside river must not stamp a water tile")
		failed = true
	else:
		print("OK dig beside river leaves a cavity %.2f to %.2f" % [h0, h1])

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	if failed:
		quit(1)
		return
	print("All dig-flood-water-block tests OK")
	quit(0)
