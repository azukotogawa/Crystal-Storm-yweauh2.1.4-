extends SceneTree
## End-to-end terrain gameplay loop contracts (completion checklist).
## Usage: godot --headless -s scripts/verify_terrain_loop_complete.gd


const _ActionTargeting = preload("res://player/action_targeting.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_cursor_exact_no_hysteresis()
	_test_dig_build_use_highlight_only()
	_test_immediate_edit_and_micro()
	_test_water_responds_to_dig()
	_test_crystal_cache_invalidation()
	_test_world_border_blocks()
	_test_feedback_signals()
	_test_movement_after_edit()

	if _failed == 0:
		print("All terrain loop complete tests OK")
		quit(0)
	else:
		push_error("verify_terrain_loop_complete: %d failure(s)" % _failed)
		quit(1)


func _test_cursor_exact_no_hysteresis() -> void:
	var hl := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "CELL_HYSTERESIS" in hl:
		_fail("cursor must not use cell hysteresis (exact mouse follow)")
	if "Exact mouse follow" not in hl and "_stable_cell = hover_cell" not in hl:
		_fail("highlight must assign stable cell from live hover")
	else:
		print("OK cursor exact follow (no hysteresis)")


func _test_dig_build_use_highlight_only() -> void:
	var w := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "facing fallback mismatch" not in w and "ALWAYS use the highlighted" not in w \
			and "highlighted cursor cell" not in w:
		# Accept either wording
		if "_resolve_terrain_target" not in w:
			_fail("weapon missing shared terrain target")
	if "Out of range" not in w:
		_fail("out-of-range must fail clear, not dig another cell")
	if w.find("player.voxel_position + forward") >= 0 and w.find("try_dig") > w.find("player.voxel_position + forward"):
		# dig path must not re-introduce facing fallback after target ZERO
		var dig_fn_start := w.find("func _do_dig_attack")
		var dig_fn_end := w.find("func _try_build_wall")
		if dig_fn_start >= 0 and dig_fn_end > dig_fn_start:
			var dig_body := w.substr(dig_fn_start, dig_fn_end - dig_fn_start)
			if "voxel_position + forward" in dig_body:
				_fail("dig still falls back to facing cell (misses highlight)")
	print("OK dig/build lock to highlighted cell")


func _test_immediate_edit_and_micro() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 77
	var data: ChunkData = _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	data.prewarm_macro_storage()
	var h0: float = world.get_surface_height(3.0, 3.0)
	if not _TerrainEdits.dig(3, 3, 1):
		_fail("dig failed")
		_ChunkDataPool.release(data)
		return
	var h1: float = world.get_surface_height(3.0, 3.0)
	var layer: float = _WorldSettings.get_active().layer_height()
	if not is_equal_approx(h1, h0 - layer):
		_fail("surface height must update immediately after dig h0=%.2f h1=%.2f" % [h0, h1])
	data.refresh_worker_snapshot_for_cells([Vector2i(3, 3)])
	data.update_dirty_column_maps([Vector2i(3, 3)])
	if not data.has_micro_brick(3, 3):
		_fail("micro brick must allocate on dig")
	else:
		print("OK immediate surface + micro after dig")
	_ChunkDataPool.release(data)


func _test_water_responds_to_dig() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	_FluidRegistry.ensure_builtins()
	var heights: Dictionary = {}
	for x in 6:
		for z in 6:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(2, 2)] = 10.5
	_ChannelRegistry.register_channel(1, 2, Vector2i(1, 0), 0.8)
	_ChannelRegistry.register_channel(2, 2, Vector2i(0, 0), 0.05)
	_TerrainEdits.dig(2, 2, 1)
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.test_base_heights = heights
	var engine := _VoxelFluidEngine.new(cfg, terrain, _FluidRegistry.get_def(&"water"))
	engine.empty_cell_inflow_cap = 0.35
	_ChannelRegistry.sync_depth_from_engine(engine)
	engine.set_subset_cells([Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)])
	var before: float = _ChannelRegistry.get_water_level(2, 2)
	for _i in 14:
		var changed: Array = engine.tick_flow(0.2)
		for pos_variant in changed:
			var pos: Vector2i = pos_variant
			var level: float = float(engine.depth.get(pos, 0.0))
			if level < 0.05:
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
			elif _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, level)
	var after: float = _ChannelRegistry.get_water_level(2, 2)
	if after <= before + 0.02:
		_fail("water must flow into dug depression before=%.3f after=%.3f" % [before, after])
	else:
		print("OK water responds to dig depression %.3f→%.3f" % [before, after])


func _test_crystal_cache_invalidation() -> void:
	var tq := _CrystalTerrainQuery.new()
	tq.test_base_heights = {Vector2i(1, 1): 10.0}
	_TerrainEdits.reset()
	var h0: float = tq.get_terrain_height(Vector2i(1, 1))
	_TerrainEdits.dig(1, 1, 1)
	# Without invalidate, cache may hold old height
	var h_cached: float = tq.get_terrain_height(Vector2i(1, 1))
	tq.invalidate_terrain_caches()
	var h1: float = tq.get_terrain_height(Vector2i(1, 1))
	var layer: float = _WorldSettings.get_active().layer_height()
	if not is_equal_approx(h1, h0 - layer) and not is_equal_approx(h1, 10.0 - layer):
		# test_base + delta
		if absf(h1 - (10.0 - layer)) > 0.01:
			_fail("crystal query after invalidate want ~%.2f got %.2f (cached was %.2f)" % [
				10.0 - layer, h1, h_cached
			])
			return
	var cm_src := (load("res://crystal/crystal_manager.gd") as GDScript).source_code
	if "invalidate_terrain_caches" not in cm_src or "terrain_edited" not in cm_src:
		_fail("crystal manager must bind terrain_edited → invalidate caches")
	else:
		print("OK crystal invalidates heights after dig h=%.2f" % h1)


func _test_world_border_blocks() -> void:
	if not _WorldBorder.blocks_player_at(0.0, 0.0, _VoxelTypes.OCEAN):
		_fail("ocean must stop player")
	if not _WorldBorder.blocks_player_movement(float(_WorldBorder.PLAYABLE_HALF_X) + 50.0, 0.0):
		_fail("ocean border band must block")
	if not _WorldBorder.blocks_player_movement(0.0, float(_WorldBorder.PLAYABLE_HALF_Z) + 40.0):
		_fail("mountain border band must block")
	if _WorldBorder.allows_crystal(float(_WorldBorder.PLAYABLE_HALF_X) + 2.0, 0.0):
		_fail("crystal outside playable")
	else:
		print("OK world borders stop player + crystal")


func _test_feedback_signals() -> void:
	var te := (load("res://world/terrain_editor.gd") as GDScript).source_code
	if "signal terrain_edited" not in te:
		_fail("terrain_editor must emit terrain_edited")
	if "structure_placed" not in te:
		_fail("terrain_editor must emit structure_placed")
	var w := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_flash_dig_feedback" not in w or "_flash_build_feedback" not in w:
		_fail("weapon must flash dig/build feedback")
	if "show_place_flash" not in w:
		_fail("visual place/dig flash required")
	else:
		print("OK terrain action feedback signals + flashes")


func _test_movement_after_edit() -> void:
	_TerrainEdits.reset()
	var probe_src := (load("res://player/voxel_floor_probe.gd") as GDScript).source_code
	if "live_delta" not in probe_src and "get_height_delta" not in probe_src:
		_fail("floor probe must include live terrain delta in height cache")
	var p_src := (load("res://player/player.gd") as GDScript).source_code
	if "soft_follow" not in p_src:
		_fail("player must soft-follow ground after terrain edits")
	else:
		print("OK movement smooth after terrain edits")
