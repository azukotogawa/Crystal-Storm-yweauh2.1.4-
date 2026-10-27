extends SceneTree

const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")

const RIVER := Vector2i(2, 2)
const BLOCK := Vector2i(3, 2)

var _failed := 0
var world: InfiniteNoiseWorld
var editor: TerrainEditor
var svc: VoxelFluidService
var cm: ChunkManager


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL " + msg)
	_failed += 1


func _run() -> void:
	world = _InfiniteNoiseWorld.new()
	world.world_seed = 7
	root.add_child(world)
	cm = _ChunkManager.new()
	cm.world = world
	editor = _TerrainEditor.new()
	root.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)
	svc = _VoxelFluidService.new()
	root.add_child(svc)
	svc.world = world
	svc.chunk_manager = null
	await process_frame
	print("INFO GameplayInput.world_loading=%s" % str(GameplayInput.world_loading))
	await _case("try_dig", func() -> bool: return editor.try_dig(Vector3(BLOCK.x + 0.5, 0.0, BLOCK.y + 0.5)))
	await _case("dig_cells", func() -> bool:
		var y: int = _TerrainEdits.surface_block_y(world, BLOCK.x, BLOCK.y)
		var r: Dictionary = _TerrainEdits.dig_cells([Vector3i(BLOCK.x, y, BLOCK.y)], editor)
		return int(r.get("dug_count", 0)) > 0)
	if _failed == 0:
		print("All water same-layer break tests OK")
		quit(0)
	else:
		push_error("verify_water_same_layer_break: %d failure(s)" % _failed)
		quit(1)


func _reset() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	_FeatureRegistry.set_tile_override(RIVER.x, RIVER.y, _VoxelTypes.RIVER)
	_FeatureRegistry.set_tile_override(BLOCK.x, BLOCK.y, _VoxelTypes.GRASSLAND)
	var layer: float = _WorldSettings.get_active().layer_height()
	var hr: float = world.get_surface_height(float(RIVER.x), float(RIVER.y))
	var hb: float = world.get_surface_height(float(BLOCK.x), float(BLOCK.y))
	var delta: int = int(round((hr - hb) / layer))
	if delta != 0:
		_WorldState.get_active().height_delta[BLOCK] = delta
		world.invalidate_column_cache(BLOCK.x, BLOCK.y)


func _case(label: String, brk: Callable) -> void:
	_reset()
	var layer: float = _WorldSettings.get_active().layer_height()
	var hr: float = world.get_surface_height(float(RIVER.x), float(RIVER.y))
	var hb0: float = world.get_surface_height(float(BLOCK.x), float(BLOCK.y))
	if absf(hb0 - hr) > 0.01:
		_fail("%s setup: block must share the river layer hr=%.2f hb=%.2f" % [label, hr, hb0])
		return
	var ok: bool = bool(brk.call())
	var hb1: float = world.get_surface_height(float(BLOCK.x), float(BLOCK.y))
	print("INFO %s break ok=%s river_h=%.2f block_h %.2f -> %.2f why=%s" % [label, str(ok), hr, hb0, hb1, editor.last_fail_reason])
	if hb1 > hb0 - layer + 0.01:
		_fail("%s: break did not remove the block" % label)
		return
	for _i in 6:
		svc._tick_water(0.1)
	var wet: bool = _ChannelRegistry.has_fluid(BLOCK.x, BLOCK.y, _ChannelRegistry.FLUID_WATER)
	var lvl: float = _ChannelRegistry.get_water_level(BLOCK.x, BLOCK.y) if wet else 0.0
	var sy: float = _ChannelRegistry.get_runtime_surface_y(BLOCK.x, BLOCK.y) if wet else 0.0
	print("INFO %s sim wet=%s level=%.3f surface_y=%.3f hole_floor_top=%.2f river_top=%.2f" % [label, str(wet), lvl, sy, hb1 + layer, hr + layer])
	if not wet:
		_fail("%s SIM: water did not enter the hole" % label)
	var data := _ChunkData.new(Vector2i.ZERO, world)
	data.capture_worker_snapshot()
	var water_quads := 0
	var water_top := -INF
	for q in cm._build_mesh(data).get("quads", []):
		if int(q.get("x", -1)) != BLOCK.x or int(q.get("z", -1)) != BLOCK.y:
			continue
		if int(q.get("type", -1)) != _VoxelTypes.WATER:
			continue
		water_quads += 1
		water_top = maxf(water_top, float(q.get("y", 0.0)) + float(q.get("dim_y", 1.0)) * layer)
	print("INFO %s mesh water_quads=%d water_top=%.3f" % [label, water_quads, water_top])
	if water_quads == 0:
		_fail("%s RENDER: hole mesh has no water quad" % label)
	elif water_top <= hb1 + layer + 0.01 or water_top > hr + layer + 0.01:
		_fail("%s RENDER: water top %.2f must sit above the hole floor %.2f and not above the river top %.2f" % [label, water_top, hb1 + layer, hr + layer])
	else:
		print("OK %s same-layer break fills and renders water" % label)
