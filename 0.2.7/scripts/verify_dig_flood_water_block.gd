extends SceneTree
## Dig beside water stamps a real water/river tile in the indentation.


const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var src := (_TerrainEditor as GDScript).source_code
	if "if _flood_dig_with_water_block" not in src:
		push_error("try_dig must invoke _flood_dig_with_water_block")
		failed = true
	else:
		print("OK try_dig wires flood water stamp")
	if "_clear_flood_water_block" not in src:
		push_error("try_fill must clear flood water blocks")
		failed = true
	else:
		print("OK try_fill clears flood water blocks")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()

	var world: InfiniteNoiseWorld = _InfiniteNoiseWorld.new()
	world.world_seed = 7
	root.add_child(world)
	# Land dig target beside an authored river neighbor (avoid natural water columns).
	_FeatureRegistry.set_tile_override(3, 2, _VoxelTypes.GRASSLAND)
	_FeatureRegistry.set_tile_override(2, 2, _VoxelTypes.RIVER)

	var editor: TerrainEditor = _TerrainEditor.new()
	root.add_child(editor)
	editor.world = world
	await process_frame

	_TerrainEdits.dig(3, 2, 1)
	var stamped: bool = bool(editor.call("_flood_dig_with_water_block", 3, 2))
	var tile: int = _FeatureRegistry.get_tile_override(3, 2)
	print("stamp_result=%s tile=%d channel=%s" % [str(stamped), tile, str(_ChannelRegistry.is_channel(3, 2))])
	if not stamped:
		push_error("flood stamp beside river returned false")
		failed = true
	elif tile != _VoxelTypes.RIVER and tile != _VoxelTypes.WATER:
		push_error("dig beside river must stamp water tile, got %d" % tile)
		failed = true
	elif not _ChannelRegistry.is_channel(3, 2):
		push_error("dig beside river must register channel")
		failed = true
	elif not bool(editor.call("_is_water_source_column", 3, 2)):
		push_error("stamped dig must read as water source column")
		failed = true
	else:
		print("OK dig beside river stamped water tile=%d" % tile)

	editor.call("_clear_flood_water_block", 3, 2)
	if _FeatureRegistry.get_tile_override(3, 2) >= 0 or _ChannelRegistry.is_channel(3, 2):
		push_error("clear must remove stamped water block")
		failed = true
	else:
		print("OK flood water block cleared")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	# Far from any water source.
	_TerrainEdits.dig(80, 80, 1)
	if bool(editor.call("_flood_dig_with_water_block", 80, 80)):
		push_error("dry dig must not stamp water")
		failed = true
	else:
		print("OK dry dig stays dry")

	if failed:
		quit(1)
		return
	print("All dig-flood-water-block tests OK")
	quit(0)
