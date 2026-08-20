class_name TerrainEditor
extends Node

enum ChannelMode { DIG, RAISE, LOWER, REDIRECT }

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _StatIds = preload("res://stats/stat_ids.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const REBUILD_EDGE_BAND := 2

signal structure_placed(wx: int, wz: int, build_id: StringName, world_pos: Vector3)
signal terrain_edited(wx: int, wz: int, kind: StringName)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _channel_tick_accum: float = 0.0
var _growth_manager: Node
## Last dig/build/plant/channel failure for UI toast (empty on success).
var last_fail_reason: String = ""
## Last successful build id (for UI / feedback).
var last_build_id: StringName = &""


func _ready() -> void:
	add_to_group("terrain_editor")
	_TerrainEdits.reset()
	_ChannelRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	_PlantableRegistry.ensure_builtins()
	world = get_tree().get_first_node_in_group("world")
	call_deferred("_bind_config")
	call_deferred("_bind_growth_manager")
	call_deferred("_try_bind_chunk_manager")


func bind_chunk_manager(cm: ChunkManager) -> void:
	if cm == null:
		return
	chunk_manager = cm


func _try_bind_chunk_manager() -> void:
	if chunk_manager != null:
		return
	var cm = get_tree().get_first_node_in_group("chunk_manager")
	if cm:
		bind_chunk_manager(cm)


func _bind_config() -> void:
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.crystal_sim:
		sim_config = cfg_svc.crystal_sim


func _bind_growth_manager() -> void:
	_growth_manager = get_tree().get_first_node_in_group("vegetation_growth_manager")


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg:
		sim_config = cfg


func _process(delta: float) -> void:
	if world == null:
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("terrain_editor")
	# VoxelFluidService owns gravity water when present; equilibrium is fallback only.
	var fluid_svc := get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid_svc == null:
		_channel_tick_accum += delta
		if _channel_tick_accum >= 0.25:
			_channel_tick_accum = 0.0
			var t0 := Time.get_ticks_usec()
			_ChannelRegistry.tick_equilibrium(world, sim_config, 0.25)
			if profiler and profiler.has_method("record_func"):
				profiler.record_func("ChannelRegistry::tick_equilibrium", Time.get_ticks_usec() - t0)
	if profiler and profiler.has_method("end"):
		profiler.end("terrain_editor")


func get_dig_delay(world_pos: Vector3) -> float:
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	var dug_depth := maxf(0.0, -_TerrainEdits.get_height_delta(wx, wz))
	# Sustained rapid dig: ~12–16/s shallow, still responsive deep (terrain as strategy tool).
	var base_delay := 0.055 + dug_depth * 0.016 + dug_depth * dug_depth * 0.008
	var dig_speed := 1.0
	if is_inside_tree():
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_stat"):
			dig_speed = maxf(player.get_stat(_StatIds.DIG_SPEED), 0.1)
	return minf(base_delay / dig_speed, 0.14)


func get_channel_delay(world_pos: Vector3) -> float:
	var channel_speed := 1.0
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_stat"):
		channel_speed = maxf(player.get_stat(_StatIds.CHANNEL_SPEED), 0.1)
	return get_dig_delay(world_pos) / channel_speed


## Walls / gates / bridges place instantly — hold-repeat stays snappy, never weapon-slow.
func get_build_delay(_world_pos: Vector3 = Vector3.ZERO) -> float:
	return 0.03


func get_plant_delay() -> float:
	var plant_speed := 1.0
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_stat"):
		plant_speed = maxf(player.get_stat(_StatIds.PLANT_SPEED), 0.1)
	return 0.45 / plant_speed


func try_dig(world_pos: Vector3) -> bool:
	last_fail_reason = ""
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false
	var edited_h: float = world.get_surface_height(float(wx), float(wz))
	var min_h: float = -_WorldSettings.get_active().layer_height() * 4.0
	if edited_h <= min_h:
		last_fail_reason = "Can't dig any deeper"
		return false
	if not _TerrainEdits.dig(wx, wz, 1):
		last_fail_reason = "Can't dig here"
		return false
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("inc_frame"):
		profiler.inc_frame("terrain_edits")
	var inv = null
	var player := get_tree().get_first_node_in_group("player")
	if player and "inventory" in player:
		inv = player.inventory
	_grant_dig_loot(wx, wz, inv)
	_invalidate_and_rebuild(wx, wz)
	# Immediate water response so trenches redirect/fill without waiting a tick.
	_notify_water_reflow(wx, wz, true)
	terrain_edited.emit(wx, wz, &"dig")
	return true


func _grant_dig_loot(wx: int, wz: int, inventory) -> void:
	if inventory == null or world == null:
		return
	var tile: int = world.get_tile_type(float(wx), float(wz))
	var item_id := _loot_item_for_tile(tile)
	if item_id.is_empty():
		return
	inventory.add_item(item_id, 1)


func _loot_item_for_tile(tile: int) -> String:
	if tile in [
		VoxelTypes.HILLS, VoxelTypes.HILLS2, VoxelTypes.HILLS3, VoxelTypes.HILLS4,
		VoxelTypes.TREE_TRUNK, VoxelTypes.BUSH,
	]:
		return "wood"
	if tile in [VoxelTypes.BASIN, VoxelTypes.BASIN2, VoxelTypes.BASIN3, VoxelTypes.VALLEY, VoxelTypes.VALLEY2]:
		return "herb"
	if tile in [
		VoxelTypes.STONE, VoxelTypes.STONE2, VoxelTypes.MOUNTAIN, VoxelTypes.MOUNTAIN2,
		VoxelTypes.MOUNTAIN3, VoxelTypes.MOUNTAIN4, VoxelTypes.MOUNTAIN5, VoxelTypes.MOUNTAIN6,
		VoxelTypes.MOUNTAIN7, VoxelTypes.SNOW, VoxelTypes.SNOW2, VoxelTypes.SNOW3,
		VoxelTypes.CAVE_STONE,
	]:
		return "stone"
	return "stone"


func try_build_wall(world_pos: Vector3, inventory, prefer_stone: bool = true) -> bool:
	var build_id: StringName = &"stone_wall" if prefer_stone else &"wood_wall"
	return try_build(world_pos, inventory, build_id)


func try_build_gate(world_pos: Vector3, inventory) -> bool:
	return try_build(world_pos, inventory, &"gate")


func try_build_bridge(world_pos: Vector3, inventory) -> bool:
	return try_build(world_pos, inventory, &"bridge")


func try_build(world_pos: Vector3, inventory, buildable_id: StringName = &"stone_wall") -> bool:
	last_fail_reason = ""
	last_build_id = &""
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	if inventory == null:
		last_fail_reason = "No inventory"
		return false
	_BuildingRegistry.ensure_builtins()
	var def = _BuildingRegistry.get_def(buildable_id)
	if def == null:
		return try_build_wall(world_pos, inventory, buildable_id == &"stone_wall")

	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false

	# Gates need open ground (no stacked wall) so the player can walk through.
	if def.is_passage:
		var layers: int = int(round(_TerrainEdits.get_height_delta(wx, wz) / maxf(_WorldSettings.get_active().layer_height(), 0.001)))
		if layers > 0 and _TerrainEdits.get_build_tile(wx, wz) >= 0:
			last_fail_reason = "Clear wall before placing a gate"
			return false

	var mat_count := int(def.material_count)
	var build_cost_mult := 1.0
	var flow_block := 0.85
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("get_stat"):
		build_cost_mult = maxf(player.get_stat(_StatIds.BUILD_COST), 0.1)
		flow_block = clampf(player.get_stat(_StatIds.BUILD_FLOW_BLOCK), 0.0, 1.0)
	mat_count = maxi(1, int(ceil(float(mat_count) * build_cost_mult)))

	var paid_with: String = str(def.material_id)
	var paid_count: int = mat_count
	if not inventory.consume_item(def.material_id, mat_count):
		if def.material_id == "stone" and def.wood_fallback_count > 0 \
				and inventory.consume_item("wood", def.wood_fallback_count):
			paid_with = "wood"
			paid_count = int(def.wood_fallback_count)
		else:
			last_fail_reason = "Need %d %s" % [mat_count, def.material_id]
			return false

	if def.raises_terrain:
		if not _TerrainEdits.build_wall(wx, wz, def.tile_id):
			inventory.add_item(paid_with, paid_count)
			last_fail_reason = "Stack full" if not def.is_bridge else "Bridge stack full"
			return false
	else:
		# Passage: mark build tile for crystal/query without raising surface.
		if not _TerrainEdits.set_build_tile_only(wx, wz, def.tile_id):
			inventory.add_item(paid_with, paid_count)
			last_fail_reason = "Can't place gate here"
			return false

	var resist := clampf(def.flow_resistance * flow_block, 0.02, 0.98)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": str(buildable_id),
		"flow_resistance": resist,
		"player_built": true,
		"is_passage": bool(def.is_passage),
		"is_bridge": bool(def.is_bridge),
		"raises_terrain": bool(def.raises_terrain),
	})
	var _StructOri = load("res://helpers/structure_orientation.gd")
	if _StructOri:
		_StructOri.persist_yaw_neighborhood(wx, wz)
	if def.is_passage or def.is_bridge:
		_FeatureRegistry.set_tile_override(wx, wz, def.tile_id)
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	last_build_id = buildable_id
	var place_pos := Vector3(float(wx) + 0.5, world.get_surface_height(float(wx), float(wz)), float(wz) + 0.5)
	structure_placed.emit(wx, wz, buildable_id, place_pos)
	terrain_edited.emit(wx, wz, buildable_id)
	return true


func try_plant(world_pos: Vector3, inventory, plant_id: StringName = &"grass_tuft") -> bool:
	if world == null or chunk_manager == null or inventory == null:
		return false
	var def = _PlantableRegistry.get_def(plant_id)
	if def == null:
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		return false
	if not _can_plant_at(wx, wz):
		return false
	if not inventory.consume_item(def.material_id, def.material_cost):
		return false
	_FeatureRegistry.set_tile_override(wx, wz, def.tile_id)
	_FeatureRegistry.register_feature(wx, wz, def.feature_kind, {
		"player_placed": true,
		"plant_id": str(plant_id),
		"growth_stage": 0,
		"growth_progress": 0.0,
	})
	if _growth_manager and _growth_manager.has_method("register_plant"):
		_growth_manager.register_plant(wx, wz, plant_id)
	_invalidate_and_rebuild(wx, wz)
	return true


func try_channel_water(
	world_pos: Vector3,
	inventory = null,
	mode: int = ChannelMode.DIG,
	face_dir: Vector3 = Vector3.ZERO
) -> bool:
	if world == null or chunk_manager == null:
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		return false

	match mode:
		ChannelMode.RAISE:
			return _channel_raise(wx, wz, inventory)
		ChannelMode.LOWER:
			return _channel_lower(wx, wz, inventory)
		ChannelMode.REDIRECT:
			return _channel_redirect(wx, wz, face_dir)
		_:
			return _channel_dig(wx, wz, inventory)


func _channel_dig(wx: int, wz: int, inventory) -> bool:
	var surf: float = world.get_surface_height(float(wx), float(wz))
	if surf > 52.0 and not _has_adjacent_water(wx, wz) and not _ChannelRegistry.is_channel(wx, wz):
		return false
	if inventory and not inventory.consume_item("stone", 1):
		return false
	if not _TerrainEdits.dig(wx, wz, 1):
		if inventory:
			inventory.add_item("stone", 1)
		return false

	var flow_dir := _ChannelRegistry.compute_downhill_dir(world, wx, wz)
	var water_level := 0.55
	if _ChannelRegistry.is_channel(wx, wz):
		water_level = _ChannelRegistry.get_water_level(wx, wz)
	_ChannelRegistry.register_channel(wx, wz, flow_dir, water_level)

	var tile := VoxelTypes.RIVER if _has_adjacent_water(wx, wz) or flow_dir != Vector2i.ZERO else VoxelTypes.WATER
	_FeatureRegistry.set_tile_override(wx, wz, tile)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"channel": true,
		"flow_dir": [flow_dir.x, flow_dir.y],
		"water_level": water_level,
	})
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	return true


func _channel_raise(wx: int, wz: int, inventory) -> bool:
	if not _ChannelRegistry.is_channel(wx, wz) and not _has_adjacent_water(wx, wz):
		return _channel_dig(wx, wz, inventory)
	if inventory and not inventory.consume_item("stone", 1):
		return false
	var step: float = sim_config.channel_raise_step
	var new_level := _ChannelRegistry.adjust_water_level(wx, wz, step)
	if new_level <= 0.0:
		_ChannelRegistry.register_channel(wx, wz, _ChannelRegistry.compute_downhill_dir(world, wx, wz), 0.55)
		new_level = _ChannelRegistry.get_water_level(wx, wz)
	_update_channel_metadata(wx, wz, new_level)
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	return true


func _channel_lower(wx: int, wz: int, inventory) -> bool:
	if not _ChannelRegistry.is_channel(wx, wz):
		return false
	if inventory and not inventory.consume_item("stone", 1):
		return false
	var step: float = sim_config.channel_lower_step
	var new_level := _ChannelRegistry.adjust_water_level(wx, wz, -step)
	if new_level <= 0.06:
		_ChannelRegistry.unregister_channel(wx, wz)
		_FeatureRegistry.clear_tile_override(wx, wz)
		_FeatureRegistry.clear_feature(wx, wz)
	else:
		_update_channel_metadata(wx, wz, new_level)
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	return true


func _channel_redirect(wx: int, wz: int, face_dir: Vector3) -> bool:
	if not _ChannelRegistry.is_channel(wx, wz):
		if not _channel_dig(wx, wz, null):
			return false
	var flow_dir := _ChannelRegistry.cardinal_from_vector(face_dir)
	if flow_dir == Vector2i.ZERO:
		flow_dir = _ChannelRegistry.compute_downhill_dir(world, wx, wz)
	_ChannelRegistry.set_flow_dir(wx, wz, flow_dir)
	_update_channel_metadata(wx, wz, _ChannelRegistry.get_water_level(wx, wz))
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	return true


func _update_channel_metadata(wx: int, wz: int, water_level: float) -> void:
	var flow_dir := _ChannelRegistry.get_flow_dir(wx, wz)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"channel": true,
		"flow_dir": [flow_dir.x, flow_dir.y],
		"water_level": water_level,
	})


func _can_plant_at(wx: int, wz: int) -> bool:
	if _TerrainEdits.get_build_tile(wx, wz) >= 0:
		return false
	var tile := world.get_tile_type(float(wx), float(wz))
	if tile in [
		VoxelTypes.RIVER, VoxelTypes.WATER, VoxelTypes.OCEAN, VoxelTypes.OCEAN2,
		VoxelTypes.STONE, VoxelTypes.STONE2,
		VoxelTypes.GRASS_TUFT, VoxelTypes.BUSH, VoxelTypes.TREE_TRUNK,
	]:
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if not feat.is_empty():
		var kind: int = int(feat.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
		if kind in [
			_WorldFeatureTypes.FeatureKind.TOWN,
			_WorldFeatureTypes.FeatureKind.TOWN_BUILDING,
			_WorldFeatureTypes.FeatureKind.RUIN,
		]:
			return false
	return true


func _has_adjacent_water(wx: int, wz: int) -> bool:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var t := world.get_tile_type(float(wx + dx), float(wz + dz))
			if t in [VoxelTypes.RIVER, VoxelTypes.WATER, VoxelTypes.OCEAN, VoxelTypes.OCEAN2]:
				return true
			if _ChannelRegistry.is_channel(wx + dx, wz + dz):
				return true
	return false


static func rebuild_ring_for_cell(wx: int, wz: int) -> int:
	var chunk_x := floori(float(wx) / float(_ChunkData.SIZE))
	var chunk_z := floori(float(wz) / float(_ChunkData.SIZE))
	var lx := wx - chunk_x * _ChunkData.SIZE
	var lz := wz - chunk_z * _ChunkData.SIZE
	if lx < REBUILD_EDGE_BAND or lx >= _ChunkData.SIZE - REBUILD_EDGE_BAND:
		return 1
	if lz < REBUILD_EDGE_BAND or lz >= _ChunkData.SIZE - REBUILD_EDGE_BAND:
		return 1
	return 0


func _invalidate_and_rebuild(wx: int, wz: int) -> void:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if world and world.has_method("invalidate_column_cache"):
				world.invalidate_column_cache(wx + dx, wz + dz)
	if chunk_manager and chunk_manager.has_method("invalidate_columns_at_world"):
		chunk_manager.invalidate_columns_at_world(wx, wz)
		if chunk_manager.has_method("flush_rebuild_pending"):
			chunk_manager.flush_rebuild_pending()
	elif chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(wx), float(wz))


## Dig/channel/build reshape water — mark fluid dirty; channels force immediate steps.
func _notify_water_reflow(wx: int, wz: int, immediate: bool = false) -> void:
	var fluid_svc := get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid_svc == null:
		return
	# Immediate multi-step fluid only when water/channels are actually nearby.
	# Dry-land dig/build was paying full recompute_region_now cost every edit (major hitch).
	var near_water := _region_needs_immediate_water(wx, wz)
	if immediate and near_water and fluid_svc.has_method("recompute_region_now"):
		# One interactive step is enough for trench fill feedback; rest on process budget.
		fluid_svc.recompute_region_now(wx, wz, 2, 1)
	elif fluid_svc.has_method("mark_region_dirty"):
		fluid_svc.mark_region_dirty(wx, wz, 2)


func _region_needs_immediate_water(wx: int, wz: int) -> bool:
	# Only player channels / registered fluid — natural river tiles alone should not
	# force interactive multi-step recompute on every nearby dig (major hitch).
	if _ChannelRegistry.is_channel(wx, wz):
		return true
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		return true
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx == 0 and dz == 0:
				continue
			if _ChannelRegistry.is_channel(wx + dx, wz + dz):
				return true
			if _ChannelRegistry.has_fluid(wx + dx, wz + dz, _ChannelRegistry.FLUID_WATER):
				return true
	return false