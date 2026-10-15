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
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _LivingForce = preload("res://world/living_force.gd")
const _WorldState = preload("res://world/world_state.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _StructureBlueprints = preload("res://helpers/structure_blueprints.gd")
const _StructureCrafting = preload("res://helpers/structure_crafting.gd")
const _StructureIntegrity = preload("res://helpers/structure_integrity.gd")
const _SurfaceLoot = preload("res://world/surface_loot.gd")

const REBUILD_EDGE_BAND := 1

signal structure_placed(wx: int, wz: int, build_id: StringName, world_pos: Vector3)
signal terrain_edited(wx: int, wz: int, kind: StringName)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _channel_tick_accum: float = 0.0
var _growth_manager: Node
var last_fail_reason: String = ""
var last_build_id: StringName = &""
var last_stroke_stats: Dictionary = {}
var last_place_batch: Dictionary = {}
var _living_push_accum: float = 0.0
var _living_crystal: Node
var _living_crystal_tries: int = 0


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
	call_deferred("_rearm_living_push")


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
	var fluid_svc := get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid_svc == null:
		_channel_tick_accum += delta
		if _channel_tick_accum >= 0.25:
			_channel_tick_accum = 0.0
			var t0 := Time.get_ticks_usec()
			_ChannelRegistry.tick_equilibrium(world, sim_config, 0.25)
			if profiler and profiler.has_method("record_func"):
				profiler.record_func("ChannelRegistry::tick_equilibrium", Time.get_ticks_usec() - t0)
	if _LivingForce.pushback_enabled and not _LivingForce.push_watch.is_empty():
		_living_push_accum += delta
		if _living_push_accum >= _LivingForce.pushback_interval:
			_living_push_accum = 0.0
			_living_push_tick()
	if profiler and profiler.has_method("end"):
		profiler.end("terrain_editor")


func get_dig_delay(world_pos: Vector3) -> float:
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	var dug_depth := maxf(0.0, -_TerrainEdits.get_height_delta(wx, wz))
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
	last_stroke_stats = {}
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false
	if _is_water_source_column(wx, wz):
		last_fail_reason = "Can't dig water"
		return false
	var inv = null
	var player := get_tree().get_first_node_in_group("player")
	if player and "inventory" in player:
		inv = player.inventory
	if _has_adjacent_water(wx, wz):
		_grant_dig_loot(wx, wz, inv)
		if not _replace_cell_with_water_block(wx, wz):
			last_fail_reason = "Can't place water here"
			return false
		var profiler_w = get_node_or_null("/root/PerfProfiler")
		if profiler_w and profiler_w.has_method("inc_frame"):
			profiler_w.inc_frame("terrain_edits")
		_invalidate_and_rebuild(wx, wz)
		_requeue_water_neighbors(wx, wz)
		terrain_edited.emit(wx, wz, &"water")
		return true
	var edited_h: float = world.get_surface_height(float(wx), float(wz))
	var min_h: float = -_WorldSettings.get_active().layer_height() * 4.0
	if edited_h <= min_h:
		last_fail_reason = "Can't dig any deeper"
		return false
	var ws = _WorldState.get_active()
	if ws:
		ws.begin_batch()
	if not _TerrainEdits.dig(wx, wz, 1):
		if ws:
			ws.end_batch()
		last_fail_reason = "Can't dig here"
		return false
	var edited: Array = [Vector2i(wx, wz)]
	var settled: Array = _LivingForce.apply_settle(edited, world)
	if ws:
		ws.end_batch()
	for cell_v in settled:
		edited.append(cell_v)
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("inc_frame"):
		profiler.inc_frame("terrain_edits")
	_grant_dig_loot(wx, wz, inv)
	_remesh_cells(edited)
	_record_stroke(1, edited)
	_notify_water_reflow(wx, wz, true)
	_living_water_inflow(edited)
	_living_crystal_react(edited, &"dig")
	terrain_edited.emit(wx, wz, &"dig")
	return true


func try_dig_brush(world_pos: Vector3, radius: int = 1, range_player: Node = null) -> bool:
	var r := clampi(radius, 1, _LivingForce.BRUSH_RADIUS_MAX)
	if r <= 1:
		return try_dig(world_pos)
	last_fail_reason = ""
	last_stroke_stats = {}
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	var cx := floori(world_pos.x)
	var cz := floori(world_pos.z)
	if range_player != null and not _ActionTargeting._column_in_range(range_player, cx, cz, _ActionTargeting.INTERACTION_RANGE):
		last_fail_reason = "Out of range"
		return false
	var cells: Array = _LivingForce.footprint(cx, cz, r, world)
	var inv = null
	if is_inside_tree():
		var player := get_tree().get_first_node_in_group("player")
		if player and "inventory" in player:
			inv = player.inventory
	var ws = _WorldState.get_active()
	if ws:
		ws.begin_batch()
	var dug: Array = []
	var skipped_floor := 0
	var considered := 0
	for cell_v in cells:
		var cell: Vector2i = cell_v
		if range_player != null and not _ActionTargeting._column_in_range(range_player, cell.x, cell.y, _ActionTargeting.INTERACTION_RANGE):
			continue
		considered += 1
		var why := _brush_dig_cell(cell.x, cell.y, inv)
		if why == "dug":
			dug.append(cell)
		elif why == "floor":
			skipped_floor += 1
	var settled: Array = _LivingForce.apply_settle(dug, world)
	if ws:
		ws.end_batch()
	if dug.is_empty():
		if skipped_floor > 0 and skipped_floor == considered:
			last_fail_reason = "Can't dig any deeper"
		elif not _TerrainEdits.can_edit(cx, cz):
			last_fail_reason = "Outside playable area"
		elif _is_water_source_column(cx, cz):
			last_fail_reason = "Can't dig water"
		else:
			last_fail_reason = "Can't dig here"
		return false
	for cell_v in settled:
		dug.append(cell_v)
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("inc_frame"):
		profiler.inc_frame("terrain_edits")
	_remesh_cells(dug)
	_record_stroke(r, dug)
	_living_water_inflow(dug)
	_living_crystal_react(dug, &"dig")
	terrain_edited.emit(cx, cz, &"dig")
	return true


func break_cell_blocked(wx: int, wz: int) -> String:
	if _is_water_source_column(wx, wz):
		return "water"
	if _LivingForce.is_protected_column(wx, wz, world):
		return "protected"
	return ""


func grant_break_loot(wx: int, wz: int) -> bool:
	var inv = null
	if is_inside_tree():
		var player := get_tree().get_first_node_in_group("player")
		if player and "inventory" in player:
			inv = player.inventory
	return _grant_dig_loot(wx, wz, inv)


func settle_break_columns(columns: Array) -> Array:
	return _LivingForce.apply_settle(columns, world)


func remesh_break_chunk(_chunk: Vector2i, columns: Array) -> void:
	for col_v in columns:
		var col: Vector2i = col_v
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if world and world.has_method("invalidate_column_cache"):
					world.invalidate_column_cache(col.x + dx, col.y + dz)
		if chunk_manager and chunk_manager.has_method("invalidate_columns_at_world"):
			chunk_manager.invalidate_columns_at_world(col.x, col.y)


func update_break_water(_chunk: Vector2i, columns: Array) -> void:
	if columns.is_empty():
		return
	var col: Vector2i = columns[0]
	_notify_water_reflow(col.x, col.y, true)
	_living_water_inflow(columns)


func update_break_crystal(_chunk: Vector2i, columns: Array) -> void:
	_living_crystal_react(columns, &"dig")
	if columns.is_empty():
		return
	var col: Vector2i = columns[0]
	terrain_edited.emit(col.x, col.y, &"dig")


func flush_break_chunks() -> void:
	if chunk_manager and chunk_manager.has_method("flush_rebuild_pending"):
		chunk_manager.flush_rebuild_pending()


func _brush_dig_cell(wx: int, wz: int, inventory) -> String:
	if not _TerrainEdits.can_edit(wx, wz):
		return "skip"
	if _is_water_source_column(wx, wz):
		return "skip"
	if _LivingForce.is_protected_column(wx, wz, world):
		return "skip"
	var edited_h: float = world.get_surface_height(float(wx), float(wz))
	var min_h: float = -_WorldSettings.get_active().layer_height() * 4.0
	if edited_h <= min_h:
		return "floor"
	if not _TerrainEdits.dig(wx, wz, 1):
		return "floor"
	_grant_dig_loot(wx, wz, inventory)
	return "dug"


func _grant_dig_loot(wx: int, wz: int, inventory) -> bool:
	if inventory == null or world == null or not inventory.has_method("add_item"):
		return false
	var vein_item := _SurfaceLoot.take_drop(wx, wz)
	if not vein_item.is_empty():
		return int(inventory.add_item(vein_item, 1)) < 1
	var tile: int = world.get_tile_type(float(wx), float(wz))
	var item_id := _loot_item_for_tile(tile)
	if item_id.is_empty():
		return false
	return int(inventory.add_item(item_id, 1)) < 1


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


func try_place_blueprint(world_pos: Vector3, inventory, blueprint_id: StringName, quarter: int = 0, cost_scale: float = 1.0) -> bool:
	last_fail_reason = ""
	last_build_id = &""
	last_place_batch = {}
	if not _StructureBlueprints.LARGE_STRUCTURES:
		last_fail_reason = "Structures are off"
		return false
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	if inventory == null:
		last_fail_reason = "No inventory"
		return false
	var bp := _StructureBlueprints.get_blueprint(blueprint_id)
	if bp.is_empty():
		last_fail_reason = "No blueprint"
		return false
	var weapon_script = load("res://weapons/weapon_controller.gd")
	var plan: Dictionary = weapon_script.ghost_preview(blueprint_id, world_pos, quarter, world)
	if not bool(plan.get("valid", false)):
		last_fail_reason = _blueprint_reject_reason(plan)
		return false
	var tile := _blueprint_tile(bp)
	var spent := _pay_blueprint(inventory, bp, blueprint_id, cost_scale)
	if spent.is_empty():
		return false
	var wall_cells: Array[Vector3i] = []
	var passages: Array[Vector2i] = []
	var build_id := StringName(str(bp.get("build_id", "")))
	for item in plan.get("cells", []):
		var row: Dictionary = item
		var at: Vector3i = row["at"]
		if str(row.get("role", "wall")) == "passage":
			passages.append(Vector2i(at.x, at.z))
			continue
		wall_cells.append(at)
		var named := str(row.get("build", ""))
		if named != "":
			build_id = StringName(named)
	if build_id == &"":
		build_id = _build_id_for_tile(tile)
	var batch: Dictionary = _TerrainEdits.place_cells(wall_cells, tile, self, build_id)
	last_place_batch = batch
	if int(batch.get("placed_count", 0)) != wall_cells.size() or wall_cells.is_empty():
		_refund_lines(inventory, spent)
		if str(last_fail_reason).is_empty():
			last_fail_reason = "Can't place here"
		return false
	var stamped: Array[Vector2i] = []
	for col in passages:
		if not stamp_blueprint_passage(col):
			_rollback_blueprint(batch, stamped)
			_refund_lines(inventory, spent)
			if str(last_fail_reason).is_empty():
				last_fail_reason = "Can't place here"
			return false
		stamped.append(col)
	if not stamped.is_empty():
		_remesh_columns(stamped)
	var shown: Array = batch.get("columns", [])
	for col in stamped:
		shown.append(col)
	_refresh_blueprint_columns(shown)
	last_build_id = build_id
	var anchor: Vector2i = plan.get("anchor", Vector2i(floori(world_pos.x), floori(world_pos.z)))
	var tracked: Array = []
	for item in plan.get("cells", []):
		var row: Dictionary = item
		if row.get("at") is Vector3i:
			tracked.append({"at": row["at"], "role": str(row.get("role", "wall"))})
	_StructureIntegrity.bind(blueprint_id, anchor, tracked)
	var place_pos := Vector3(float(anchor.x) + 0.5, world.get_surface_height(float(anchor.x), float(anchor.y)), float(anchor.y) + 0.5)
	structure_placed.emit(anchor.x, anchor.y, build_id, place_pos)
	return true


func try_repair_structure(world_pos: Vector3, inventory) -> bool:
	if not _StructureBlueprints.LARGE_STRUCTURES:
		return false
	var col := Vector2i(floori(world_pos.x), floori(world_pos.z))
	var healed: Dictionary = _StructureIntegrity.repair_at(col, inventory)
	if not bool(healed.get("repaired", false)):
		return false
	last_fail_reason = ""
	return true


func stamp_blueprint_passage(col: Vector2i) -> bool:
	_BuildingRegistry.ensure_builtins()
	var def = _BuildingRegistry.get_def(&"gate")
	if def == null:
		return false
	if not _TerrainEdits.set_build_tile_only(col.x, col.y, int(def.tile_id)):
		return false
	var resist := clampf(float(def.flow_resistance), 0.02, 0.98)
	var visual_id := str(def.resolved_visual_id()) if def.has_method("resolved_visual_id") else "gate"
	_FeatureRegistry.register_feature(col.x, col.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": "gate",
		"visual_id": visual_id,
		"flow_resistance": resist,
		"player_built": true,
		"is_passage": true,
		"is_bridge": false,
		"raises_terrain": false,
	})
	_FeatureRegistry.set_tile_override(col.x, col.y, int(def.tile_id))
	return true


func stamp_blueprint_column(col: Vector2i, build_id: StringName) -> void:
	_BuildingRegistry.ensure_builtins()
	var def = _BuildingRegistry.get_def(build_id)
	if def == null:
		return
	var resist := clampf(float(def.flow_resistance), 0.02, 0.98)
	var visual_id := str(def.resolved_visual_id()) if def.has_method("resolved_visual_id") else str(build_id)
	_FeatureRegistry.register_feature(col.x, col.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": str(build_id),
		"visual_id": visual_id,
		"flow_resistance": resist,
		"player_built": true,
		"is_passage": bool(def.is_passage),
		"is_bridge": bool(def.is_bridge),
		"raises_terrain": true,
	})


func update_place_crystal(_chunk: Vector2i, columns: Array) -> void:
	_living_crystal_react(columns, &"build")
	if columns.is_empty():
		return
	var col: Vector2i = columns[0]
	terrain_edited.emit(col.x, col.y, &"build")


func _blueprint_tile(bp: Dictionary) -> int:
	var listed: Array = bp.get("cells", [])
	if listed.is_empty():
		return _VoxelTypes.STONE
	return int((listed[0] as Dictionary).get("tile", _VoxelTypes.STONE))


func _build_id_for_tile(tile: int) -> StringName:
	_BuildingRegistry.ensure_builtins()
	var wood = _BuildingRegistry.get_def(&"wood_wall")
	if wood != null and int(wood.tile_id) == tile:
		return &"wood_wall"
	return &"stone_wall"


func _scaled_structure_cost(count: int) -> int:
	if count <= 0:
		return 0
	var mult := 1.0
	if is_inside_tree():
		var player := get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_stat"):
			mult = maxf(player.get_stat(_StatIds.BUILD_COST), 0.1)
	return maxi(1, int(ceil(float(count) * mult)))


func _line_count(count: int, cost_scale: float) -> int:
	var scaled := _scaled_structure_cost(count)
	if cost_scale >= 0.999 or scaled <= 0:
		return scaled
	return maxi(1, int(ceil(float(scaled) * clampf(cost_scale, 0.0, 1.0))))


func _pay_blueprint(inventory, bp: Dictionary, blueprint_id: StringName, cost_scale: float = 1.0) -> Array:
	var piece := _StructureCrafting.item_id(blueprint_id)
	if cost_scale >= 0.999 and inventory.has_method("count_item") and int(inventory.count_item(piece)) > 0:
		if not inventory.consume_item(piece, 1):
			last_fail_reason = "Need a crafted piece"
			return []
		return [{"id": piece, "count": 1}]
	var scaled: Array = []
	for line in bp.get("recipe", []):
		var need := _line_count(int((line as Dictionary).get("count", 0)), cost_scale)
		if need <= 0:
			continue
		scaled.append({"id": str((line as Dictionary).get("id", "")), "count": need})
	if not scaled.is_empty() and _inventory_covers(inventory, scaled) and _consume_lines(inventory, scaled):
		return scaled
	var paid_with := str(bp.get("cost", {}).get("id", "stone"))
	var paid_count := _line_count(int(bp.get("cost", {}).get("count", 0)), cost_scale)
	var wood_count := _line_count(int(bp.get("cost", {}).get("wood_fallback", 0)), cost_scale)
	var currency := _take_structure_payment(inventory, paid_with, paid_count, wood_count)
	if currency.is_empty():
		return []
	var n := paid_count if currency == paid_with else wood_count
	return [{"id": currency, "count": n}]


func _inventory_covers(inventory, lines: Array) -> bool:
	if not inventory.has_method("count_item"):
		return false
	for line in lines:
		if int(inventory.count_item(str((line as Dictionary).get("id", "")))) < int((line as Dictionary).get("count", 0)):
			return false
	return true


func _consume_lines(inventory, lines: Array) -> bool:
	var spent: Array = []
	for line in lines:
		var id := str((line as Dictionary).get("id", ""))
		var need := int((line as Dictionary).get("count", 0))
		if not inventory.consume_item(id, need):
			_refund_lines(inventory, spent)
			return false
		spent.append({"id": id, "count": need})
	return true


func _refund_lines(inventory, lines: Array) -> void:
	if not inventory.has_method("add_item"):
		return
	for line in lines:
		inventory.add_item(str((line as Dictionary).get("id", "")), int((line as Dictionary).get("count", 0)))


func _rollback_blueprint(batch: Dictionary, passages: Array) -> void:
	for cell in batch.get("placed", []):
		if cell is Vector3i:
			var at: Vector3i = cell
			_TerrainEdits.unstack_build(at.x, at.z)
	for col_v in batch.get("columns", []):
		if col_v is Vector2i:
			var col: Vector2i = col_v
			_FeatureRegistry.clear_feature(col.x, col.y)
	for col_v in passages:
		if col_v is Vector2i:
			var col: Vector2i = col_v
			_FeatureRegistry.clear_feature(col.x, col.y)
			_TerrainEdits.clear_build_tile(col.x, col.y)


func _remesh_columns(columns: Array) -> void:
	var by_chunk := {}
	for col_v in columns:
		if not (col_v is Vector2i):
			continue
		var col: Vector2i = col_v
		var key := _TerrainEdits.chunk_for_column(col.x, col.y)
		if not by_chunk.has(key):
			by_chunk[key] = []
		(by_chunk[key] as Array).append(col)
	for key_v in by_chunk.keys():
		var key: Vector2i = key_v
		var cols: Array = by_chunk[key]
		remesh_break_chunk(key, cols)
		update_break_water(key, cols)
		update_place_crystal(key, cols)
	if not by_chunk.is_empty():
		flush_break_chunks()


func _take_structure_payment(inventory, paid_with: String, paid_count: int, wood_count: int) -> String:
	if paid_count <= 0:
		return paid_with
	if inventory.has_method("consume_item") and inventory.consume_item(paid_with, paid_count):
		return paid_with
	if paid_with == "stone" and wood_count > 0 and inventory.consume_item("wood", wood_count):
		return "wood"
	last_fail_reason = "Need %d %s" % [paid_count, paid_with]
	return ""


func _blueprint_reject_reason(plan: Dictionary) -> String:
	for item in plan.get("cells", []):
		if bool((item as Dictionary).get("valid", false)):
			continue
		if str((item as Dictionary).get("reason", "")) == "unsupported":
			return "Needs support"
		return "Can't place here"
	return "Can't place here"


func _refresh_blueprint_columns(columns: Array) -> void:
	var feat_layer = get_tree().get_first_node_in_group("feature_visual_layer") if is_inside_tree() else null
	for col_v in columns:
		if not (col_v is Vector2i):
			continue
		var col: Vector2i = col_v
		if feat_layer and feat_layer.has_method("refresh_cell"):
			feat_layer.refresh_cell(col.x, col.y)


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

	if def.is_passage:
		var blocking: Dictionary = _FeatureRegistry.get_feature(wx, wz)
		var blocking_id := str(blocking.get("build_id", "")).strip_edges()
		if blocking_id in ["wood_wall", "stone_wall", "bridge"]:
			last_fail_reason = "Clear wall before placing a gate"
			return false
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

	var existing: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	var existing_id := str(existing.get("build_id", "")).strip_edges()
	if existing_id != "" and not def.raises_terrain:
		last_fail_reason = "Already built"
		return false

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
		if not _TerrainEdits.set_build_tile_only(wx, wz, def.tile_id):
			inventory.add_item(paid_with, paid_count)
			last_fail_reason = "Can't place gate here"
			return false

	var resist := clampf(def.flow_resistance * flow_block, 0.02, 0.98)
	var visual_id := str(def.resolved_visual_id()) if def.has_method("resolved_visual_id") else str(buildable_id)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": str(buildable_id),
		"visual_id": visual_id,
		"flow_resistance": resist,
		"player_built": true,
		"is_passage": bool(def.is_passage),
		"is_bridge": bool(def.is_bridge),
		"raises_terrain": bool(def.raises_terrain),
	})
	var _StructOri = load("res://helpers/structure_orientation.gd")
	if _StructOri:
		_StructOri.persist_yaw_neighborhood(wx, wz)
	if def.is_passage and not def.is_bridge:
		_FeatureRegistry.set_tile_override(wx, wz, def.tile_id)
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	last_build_id = buildable_id
	var place_pos := Vector3(float(wx) + 0.5, world.get_surface_height(float(wx), float(wz)), float(wz) + 0.5)
	structure_placed.emit(wx, wz, buildable_id, place_pos)
	_living_crystal_react([Vector2i(wx, wz)], &"build")
	terrain_edited.emit(wx, wz, buildable_id)
	return true


func try_fill(world_pos: Vector3, inventory, tile_id: int = -1) -> bool:
	last_fail_reason = ""
	last_build_id = &"fill"
	if world == null or chunk_manager == null or inventory == null:
		last_fail_reason = "Terrain not ready"
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false
	var use_tile: int = tile_id
	var paid := "stone"
	if use_tile < 0:
		if inventory.count_item("stone") > 0:
			use_tile = _VoxelTypes.STONE
			paid = "stone"
		elif inventory.count_item("wood") > 0:
			use_tile = _VoxelTypes.DIRT
			paid = "wood"
		else:
			last_fail_reason = "Need stone or wood"
			return false
	if not inventory.consume_item(paid, 1):
		last_fail_reason = "Need 1 %s" % paid
		return false
	_clear_flood_water_block(wx, wz)
	if not _TerrainEdits.build_wall(wx, wz, use_tile):
		inventory.add_item(paid, 1)
		last_fail_reason = "Stack full"
		return false
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	terrain_edited.emit(wx, wz, &"fill")
	return true


func try_place_cardinal_ramp(world_pos: Vector3, inventory = null) -> bool:
	last_fail_reason = ""
	last_build_id = &"cardinal_ramp"
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false
	var self_h: float = world.get_surface_height(float(wx), float(wz))
	var layer: float = _WorldSettings.get_active().layer_height()
	var dir := Vector2i.ZERO
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nh: float = world.get_surface_height(float(wx + d.x), float(wz + d.y))
		if nh >= self_h - layer * 1.15 and nh <= self_h - layer * 0.85:
			dir = d
			break
	if dir == Vector2i.ZERO:
		last_fail_reason = "Ramp needs a one-layer step-down neighbor"
		return false
	var far_h: float = world.get_surface_height(float(wx + dir.x * 2), float(wz + dir.y * 2))
	if absf(far_h - self_h) <= layer * 0.15:
		last_fail_reason = "Opposing ramps would form a V"
		return false
	if inventory != null and not inventory.consume_item("stone", 1):
		if inventory == null or not inventory.consume_item("wood", 1):
			last_fail_reason = "Need 1 stone or wood"
			return false
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": "cardinal_ramp",
		"player_built": true,
		"dir": dir,
		"raises_terrain": false,
	})
	_invalidate_and_rebuild(wx, wz)
	terrain_edited.emit(wx, wz, &"cardinal_ramp")
	return true


func try_place_corner_ramp(world_pos: Vector3, inventory = null) -> bool:
	last_fail_reason = ""
	last_build_id = &"corner_ramp"
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false
	var self_h: float = world.get_surface_height(float(wx), float(wz))
	var layer: float = _WorldSettings.get_active().layer_height()
	var highs: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nh: float = world.get_surface_height(float(wx + d.x), float(wz + d.y))
		if nh >= self_h + layer * 0.85 and nh <= self_h + layer * 1.15:
			highs.append(d)
	var picked: Array = []
	for i in highs.size():
		for j in range(i + 1, highs.size()):
			var a: Vector2i = highs[i]
			var b: Vector2i = highs[j]
			if a.x * b.x + a.y * b.y == 0:
				picked = [a, b]
				break
		if not picked.is_empty():
			break
	if picked.size() != 2:
		last_fail_reason = "Corner ramp needs two perpendicular higher neighbors"
		return false
	var diag: Vector2i = picked[0] + picked[1]
	var diag_h: float = world.get_surface_height(float(wx + diag.x), float(wz + diag.y))
	if diag_h < self_h + layer * 0.85 or diag_h > self_h + layer * 1.15:
		last_fail_reason = "Corner ramp needs a supporting high plateau"
		return false
	if inventory != null and not inventory.consume_item("stone", 1):
		if inventory == null or not inventory.consume_item("wood", 1):
			last_fail_reason = "Need 1 stone or wood"
			return false
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": "corner_ramp",
		"player_built": true,
		"corner": true,
		"dir": picked[0],
		"dir2": picked[1],
		"raises_terrain": false,
	})
	_invalidate_and_rebuild(wx, wz)
	terrain_edited.emit(wx, wz, &"corner_ramp")
	return true


func can_remove(world_pos: Vector3) -> bool:
	if world == null or chunk_manager == null:
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		return false
	if _is_water_source_column(wx, wz):
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	var build_id := str(feat.get("build_id", "")).strip_edges()
	var player_built: bool = bool(feat.get("player_built", false)) or bool(feat.get("player_placed", false))
	if build_id in ["wood_wall", "stone_wall", "gate", "bridge", "cardinal_ramp", "corner_ramp"]:
		player_built = true
	var kind: int = int(feat.get("kind", 0))
	if not player_built and kind in [
		_WorldFeatureTypes.FeatureKind.TOWN,
		_WorldFeatureTypes.FeatureKind.TOWN_BUILDING,
		_WorldFeatureTypes.FeatureKind.RUIN,
		_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN,
	]:
		return false
	var is_channel: bool = bool(feat.get("channel", false)) or _ChannelRegistry.is_channel(wx, wz)
	var is_plant: bool = str(feat.get("plant_id", "")) != "" and bool(feat.get("player_placed", false))
	return player_built or is_channel or is_plant


func try_remove(world_pos: Vector3, inventory = null) -> bool:
	last_fail_reason = ""
	last_build_id = &""
	if world == null or chunk_manager == null:
		last_fail_reason = "Terrain not ready"
		return false
	var wx := floori(world_pos.x)
	var wz := floori(world_pos.z)
	if not _TerrainEdits.can_edit(wx, wz):
		last_fail_reason = "Outside playable area"
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	var protected_kind: int = int(feat.get("kind", 0))
	var protected_built: bool = bool(feat.get("player_built", false)) or bool(feat.get("player_placed", false))
	if not protected_built and protected_kind in [
		_WorldFeatureTypes.FeatureKind.TOWN,
		_WorldFeatureTypes.FeatureKind.TOWN_BUILDING,
		_WorldFeatureTypes.FeatureKind.RUIN,
		_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN,
	]:
		last_fail_reason = "Nothing to remove"
		return false
	if _is_water_source_column(wx, wz) and not bool(feat.get("player_built", false)):
		last_fail_reason = "Can't remove water"
		return false
	var build_id := str(feat.get("build_id", "")).strip_edges()
	var player_built: bool = bool(feat.get("player_built", false)) or bool(feat.get("player_placed", false))
	if build_id in ["wood_wall", "stone_wall", "gate", "bridge", "cardinal_ramp", "corner_ramp"]:
		player_built = true
	var kind: int = int(feat.get("kind", 0))
	if not player_built and kind in [
		_WorldFeatureTypes.FeatureKind.TOWN,
		_WorldFeatureTypes.FeatureKind.TOWN_BUILDING,
		_WorldFeatureTypes.FeatureKind.RUIN,
		_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN,
	]:
		last_fail_reason = "Nothing to remove"
		return false
	var is_channel: bool = bool(feat.get("channel", false)) or _ChannelRegistry.is_channel(wx, wz)
	var is_plant: bool = str(feat.get("plant_id", "")) != "" and bool(feat.get("player_placed", false))
	if not player_built and not is_channel and not is_plant and _TerrainEdits.get_build_tile(wx, wz) < 0:
		last_fail_reason = "Nothing to remove"
		return false

	var refund_id := ""
	var refund_n := 0
	if is_plant:
		var pdef = _PlantableRegistry.get_def(StringName(str(feat.get("plant_id", ""))))
		if pdef:
			refund_id = str(pdef.material_id)
			refund_n = 1
		_FeatureRegistry.clear_feature(wx, wz)
		_FeatureRegistry.clear_tile_override(wx, wz)
	elif is_channel:
		_ChannelRegistry.unregister_channel(wx, wz)
		_FeatureRegistry.clear_feature(wx, wz)
		_FeatureRegistry.clear_tile_override(wx, wz)
	else:
		var def = _BuildingRegistry.get_def(StringName(build_id)) if build_id != "" else null
		var raises: bool = bool(feat.get("raises_terrain", def != null and bool(def.raises_terrain)))
		# Only unstack height that this structure actually added. Do not dig
		# the supporting terrain under a WorldObject-only wall/gate/bridge.
		if raises and _TerrainEdits.get_height_delta(wx, wz) > 0.01:
			if not _TerrainEdits.unstack_build(wx, wz):
				last_fail_reason = "Can't unstack"
				return false
		else:
			_TerrainEdits.clear_build_tile(wx, wz)
		var remaining := _TerrainEdits.get_height_delta(wx, wz) > 0.01 \
			and _TerrainEdits.get_build_tile(wx, wz) >= 0
		if not remaining:
			_FeatureRegistry.clear_feature(wx, wz)
			_FeatureRegistry.clear_tile_override(wx, wz)
		if def:
			refund_id = str(def.material_id)
			refund_n = 1
		var _StructOri = load("res://helpers/structure_orientation.gd")
		if _StructOri:
			_StructOri.persist_yaw_neighborhood(wx, wz)

	if inventory != null and refund_id != "" and refund_n > 0 and inventory.has_method("add_item"):
		inventory.add_item(refund_id, refund_n)
	_invalidate_and_rebuild(wx, wz)
	_notify_water_reflow(wx, wz, true)
	var feat_layer = get_tree().get_first_node_in_group("feature_visual_layer") if is_inside_tree() else null
	if feat_layer and feat_layer.has_method("refresh_cell"):
		feat_layer.refresh_cell(wx, wz)
	terrain_edited.emit(wx, wz, &"remove")
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
		"visual_id": str(def.resolved_visual_id()) if def.has_method("resolved_visual_id") else str(plant_id),
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
			if _ChannelRegistry.has_fluid(wx + dx, wz + dz, _ChannelRegistry.FLUID_WATER):
				return true
	return false


func _replace_cell_with_water_block(wx: int, wz: int) -> bool:
	if world == null:
		return false
	if _is_water_source_column(wx, wz):
		return false
	var tile: int = VoxelTypes.WATER
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nt: int = world.get_tile_type(float(wx + dx), float(wz + dz))
			if nt in [VoxelTypes.RIVER, VoxelTypes.OCEAN, VoxelTypes.OCEAN2, VoxelTypes.OCEAN3]:
				tile = VoxelTypes.RIVER
				break
		if tile == VoxelTypes.RIVER:
			break
	_FeatureRegistry.set_tile_override(wx, wz, tile)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"flood_from_dig": true,
		"water_tile": tile,
	})
	return true


func _clear_flood_water_block(wx: int, wz: int) -> void:
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if not bool(feat.get("flood_from_dig", false)):
		return
	_FeatureRegistry.clear_tile_override(wx, wz)
	_FeatureRegistry.clear_feature(wx, wz)


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


func _rearm_living_push() -> void:
	_LivingForce.rearm_push_watch()


func _record_stroke(radius: int, cells: Array) -> void:
	var chunks := {}
	for cell_v in cells:
		var cell: Vector2i = cell_v
		chunks[_LivingForce.chunk_coord(cell.x, cell.y)] = true
	var flush_chunks := chunks.size()
	if chunk_manager and "edit_flush_chunk_count" in chunk_manager:
		flush_chunks = int(chunk_manager.edit_flush_chunk_count)
	last_stroke_stats = {
		"radius": radius,
		"cells": cells.duplicate(),
		"cell_count": cells.size(),
		"home_chunks": chunks.size(),
		"flush_count": int(chunk_manager.edit_flush_count) if chunk_manager and "edit_flush_count" in chunk_manager else 1,
		"flush_chunks": flush_chunks,
	}


func _remesh_cells(cells: Array) -> void:
	var seen := {}
	for cell_v in cells:
		var cell: Vector2i = cell_v
		if seen.has(cell):
			continue
		seen[cell] = true
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if world and world.has_method("invalidate_column_cache"):
					world.invalidate_column_cache(cell.x + dx, cell.y + dz)
		if chunk_manager and chunk_manager.has_method("invalidate_columns_at_world"):
			chunk_manager.invalidate_columns_at_world(cell.x, cell.y)
	if chunk_manager and chunk_manager.has_method("flush_rebuild_pending"):
		chunk_manager.flush_rebuild_pending()


func _living_water_inflow(dug: Array) -> void:
	if not _LivingForce.water_inflow_enabled or dug.is_empty() or world == null:
		return
	if not is_inside_tree():
		return
	var anchor := Vector2i(-999999, -999999)
	for cell_v in dug:
		var cell: Vector2i = cell_v
		if _dug_below_adjacent_water(cell.x, cell.y):
			anchor = cell
			break
	if anchor.x < -900000:
		return
	var fluid_svc := get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid_svc and fluid_svc.has_method("recompute_region_now"):
		fluid_svc.recompute_region_now(anchor.x, anchor.y, 2, 1)


func _dug_below_adjacent_water(wx: int, wz: int) -> bool:
	var layer: float = _WorldSettings.get_active().layer_height()
	var top: float = world.get_surface_height(float(wx), float(wz)) + layer
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var step: Vector2i = dir
		var nx: int = wx + step.x
		var nz: int = wz + step.y
		if not _is_water_source_column(nx, nz):
			continue
		var waterline: float = world.get_surface_height(float(nx), float(nz)) + layer
		if top < waterline - 0.001:
			return true
	return false


func _living_crystal_node():
	if _living_crystal != null and is_instance_valid(_living_crystal):
		return _living_crystal
	if not is_inside_tree() or _living_crystal_tries > 8:
		return null
	_living_crystal_tries += 1
	_living_crystal = get_tree().get_first_node_in_group("crystal_manager")
	return _living_crystal


func _living_crystal_react(cells: Array, kind: StringName) -> void:
	if not _LivingForce.crystal_react_enabled or cells.is_empty():
		return
	var crystal = _living_crystal_node()
	if crystal == null or not crystal.has_method("nudge_depth") or not crystal.has_method("get_depth_at"):
		return
	var min_d := 0.04
	if "sim_config" in crystal and crystal.sim_config:
		min_d = float(crystal.sim_config.min_depth)
	var amount := _LivingForce.crystal_build_pressure if kind == &"build" else _LivingForce.crystal_dig_pressure
	var nudged := {}
	var count := 0
	var depth_at := func(x: int, z: int) -> float:
		return float(crystal.get_depth_at(x, z))
	for cell_v in cells:
		if count >= _LivingForce.crystal_pressure_cells_per_stroke:
			break
		var cell: Vector2i = cell_v
		var targets: Array = _LivingForce.pressure_targets(
			cell, depth_at, min_d, _LivingForce.crystal_react_radius, _LivingForce.crystal_pressure_cells_per_stroke
		)
		for t_v in targets:
			if count >= _LivingForce.crystal_pressure_cells_per_stroke:
				break
			var t: Vector2i = t_v
			if nudged.has(t):
				continue
			crystal.nudge_depth(t.x, t.y, amount)
			nudged[t] = true
			count += 1
		if count > 0:
			_LivingForce.arm_player_builds(cell, _LivingForce.crystal_react_radius)


func _living_push_tick() -> void:
	var crystal = _living_crystal_node()
	if crystal == null or not crystal.has_method("get_depth_at"):
		return
	var depth_at := func(x: int, z: int) -> float:
		return float(crystal.get_depth_at(x, z))
	var broke: Array = _LivingForce.tick_pushback(depth_at)
	if broke.is_empty():
		return
	_remesh_cells(broke)
	var feat_layer = get_tree().get_first_node_in_group("feature_visual_layer")
	for cell_v in broke:
		var cell: Vector2i = cell_v
		if feat_layer and feat_layer.has_method("refresh_cell"):
			feat_layer.refresh_cell(cell.x, cell.y)
		terrain_edited.emit(cell.x, cell.y, &"remove")


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


func _requeue_water_neighbors(wx: int, wz: int) -> void:
	if not is_inside_tree():
		return
	var fluid_svc := get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid_svc and fluid_svc.has_method("requeue_neighbors_on_edit"):
		fluid_svc.requeue_neighbors_on_edit(wx, wz)


func _notify_water_reflow(wx: int, wz: int, immediate: bool = false) -> void:
	if not is_inside_tree():
		return
	var fluid_svc := get_tree().get_first_node_in_group("voxel_fluid_service")
	if fluid_svc == null:
		return
	var near_water := _region_needs_immediate_water(wx, wz)
	if immediate and near_water and fluid_svc.has_method("recompute_region_now"):
		fluid_svc.recompute_region_now(wx, wz, 2, 1)
	elif fluid_svc.has_method("mark_region_dirty"):
		fluid_svc.mark_region_dirty(wx, wz, 2)


func _region_needs_immediate_water(wx: int, wz: int) -> bool:
	if _is_water_source_column(wx, wz):
		return true
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		return true
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx == 0 and dz == 0:
				continue
			if _is_water_source_column(wx + dx, wz + dz):
				return true
			if _ChannelRegistry.has_fluid(wx + dx, wz + dz, _ChannelRegistry.FLUID_WATER):
				return true
	return false


func _is_water_source_column(wx: int, wz: int) -> bool:
	if world == null:
		return false
	var t: int = world.get_tile_type(float(wx), float(wz))
	return t in [
		VoxelTypes.RIVER, VoxelTypes.WATER,
		VoxelTypes.OCEAN, VoxelTypes.OCEAN2, VoxelTypes.OCEAN3,
	]