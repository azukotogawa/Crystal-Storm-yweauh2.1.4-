class_name CrystalManager
extends Node3D

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

signal fluid_changed(world_pos: Vector2i)
signal power_changed(power: float, tier: int)
signal spawn_destroyed(spawn: CrystalSpawnPoint)
signal all_spawns_destroyed
signal crystal_touched_player
signal absorption_completed(source_id: StringName, world_pos: Vector2i)

@export var expansion_enabled: bool = true
@export var flow_substeps: int = 2
@export var ruin_spawn_count: int = 2
@export var ruin_min_distance: float = 72.0
@export var ruin_max_distance: float = 180.0
@export var player_contact_defeat_enabled: bool = false
@export var player_defeat_depth: float = 0.35
@export var player_defeat_min_tier: int = 2

var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()
var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var power: float = 0.0
var strength_tier: int = 0
var total_volume: float = 0.0
var covered_cells: int = 0

var _sim: _CrystalFluidSim
var _terrain_query: _CrystalTerrainQuery
var _absorption: Dictionary = {}
var _ruin_absorption: Dictionary = {}
var _absorbed_ruin_centers: Dictionary = {}
var evolution: _CrystalEvolution
var _spawn_points: Array[CrystalSpawnPoint] = []
var _chunk_layers: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _spawn_markers: Dictionary = {}
var _next_spawn_id: int = 0
var _rng: RandomNumberGenerator
var _crystal_material: StandardMaterial3D
var _marker_material: StandardMaterial3D
var _layer_root: Node3D
var _marker_root: Node3D
var _initialized: bool = false


func _enter_tree() -> void:
	add_to_group("crystal_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_rng = RandomNumberGenerator.new()
	if world:
		_rng.seed = world.world_seed + 9001

	_layer_root = Node3D.new()
	_layer_root.name = "CrystalLayers"
	add_child(_layer_root)

	_marker_root = Node3D.new()
	_marker_root.name = "SpawnMarkers"
	add_child(_marker_root)

	_setup_materials()
	call_deferred("_bootstrap_when_ready")


func _bootstrap_when_ready() -> void:
	while world == null:
		world = get_tree().get_first_node_in_group("world")
		await get_tree().process_frame
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		await get_tree().process_frame
	while not chunk_manager.spawn_area_ready(0, 0):
		await get_tree().process_frame

	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()

	evolution = _CrystalEvolution.new()
	_init_sim()
	_initialize_spawns()
	_initialized = true


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg == null:
		return
	sim_config = cfg
	flow_substeps = cfg.flow_substeps
	ruin_spawn_count = cfg.ruin_spawn_count
	ruin_min_distance = cfg.ruin_min_distance
	ruin_max_distance = cfg.ruin_max_distance
	player_contact_defeat_enabled = cfg.player_contact_defeat_enabled
	player_defeat_depth = cfg.player_defeat_depth
	player_defeat_min_tier = cfg.player_defeat_min_tier
	if _sim:
		_sim.config = cfg


func _init_sim() -> void:
	_terrain_query = _CrystalTerrainQuery.new()
	_terrain_query.world = world
	_terrain_query.chunk_manager = chunk_manager
	_sim = _CrystalFluidSim.new(sim_config, _terrain_query)
	if not _sim.depth_changed.is_connected(_on_sim_depth_changed):
		_sim.depth_changed.connect(_on_sim_depth_changed)


func _on_sim_depth_changed(pos: Vector2i) -> void:
	_mark_chunk_dirty(pos)
	fluid_changed.emit(pos)


func get_fluid_sim() -> _CrystalFluidSim:
	return _sim


func _setup_materials() -> void:
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_crystal_material.albedo_color = Color(0.62, 0.18, 0.98, 1.0)
	_crystal_material.emission_enabled = true
	_crystal_material.emission = Color(0.42, 0.08, 0.82)
	_crystal_material.emission_energy_multiplier = 2.2
	_crystal_material.roughness = 0.1
	_crystal_material.metallic = 0.4

	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.albedo_color = Color(1.0, 0.35, 0.9, 0.85)
	_marker_material.emission_enabled = true
	_marker_material.emission = Color(1.0, 0.2, 0.8)
	_marker_material.emission_energy_multiplier = 2.5
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _initialize_spawns() -> void:
	if _sim:
		_sim.clear()
	_spawn_points.clear()
	_next_spawn_id = 0

	var origin := CrystalSpawnPoint.new(
		_alloc_spawn_id(),
		Vector2i.ZERO,
		CrystalTypes.SpawnKind.ORIGIN,
		500.0,
		true
	)
	_spawn_points.append(origin)
	_seed_emitter(origin)

	_add_feature_ruin_spawns()
	var procedural := maxi(0, ruin_spawn_count - _count_ruin_spawns())
	for _i in procedural:
		var ruin_pos := _pick_ruin_spawn_position()
		_add_ruin_spawn_at(ruin_pos)

	_recalc_stats()
	_refresh_spawn_markers()
	_flush_dirty_chunks()


func _alloc_spawn_id() -> int:
	var id := _next_spawn_id
	_next_spawn_id += 1
	return id


func _seed_emitter(spawn: CrystalSpawnPoint) -> void:
	_set_depth(spawn.world_pos, sim_config.initial_spawn_depth, spawn.id)


func get_evolution() -> _CrystalEvolution:
	return evolution


func _add_feature_ruin_spawns() -> void:
	for center in _FeatureRegistry.get_ruin_centers():
		_add_ruin_spawn_at(center)


func _count_ruin_spawns() -> int:
	var n := 0
	for spawn in _spawn_points:
		if spawn.kind == CrystalTypes.SpawnKind.RUIN:
			n += 1
	return n


func _add_ruin_spawn_at(ruin_pos: Vector2i) -> void:
	for existing in _spawn_points:
		if existing.world_pos == ruin_pos:
			return
	var ruin := CrystalSpawnPoint.new(
		_alloc_spawn_id(),
		ruin_pos,
		CrystalTypes.SpawnKind.RUIN,
		120.0,
		false
	)
	_spawn_points.append(ruin)
	_seed_emitter(ruin)


func _pick_ruin_spawn_position() -> Vector2i:
	var best := Vector2i(64, 64)
	var best_score := -1.0
	for _attempt in 48:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(ruin_min_distance, ruin_max_distance)
		var wx := int(round(cos(angle) * dist))
		var wz := int(round(sin(angle) * dist))
		var pos := Vector2i(wx, wz)
		if absf(float(pos.x)) > float(_WorldBorder.PLAYABLE_HALF_X) \
				or absf(float(pos.y)) > float(_WorldBorder.PLAYABLE_HALF_Z):
			continue
		if CrystalTypes.is_water_tile(_tile_at(pos)):
			continue
		var surface := _terrain_at(pos)
		if surface < 34.0 or surface > 130.0:
			continue
		var separation_penalty := 0.0
		for existing in _spawn_points:
			separation_penalty += 48.0 / maxf(Vector2(pos).distance_to(Vector2(existing.world_pos)), 1.0)
		var score := Vector2(pos).length() * 0.35 + separation_penalty + _rng.randf_range(0.0, 8.0)
		if score > best_score:
			best_score = score
			best = pos
	return best


func _process(delta: float) -> void:
	if not _initialized or not expansion_enabled:
		return

	if _sim:
		_sim.tick_emitters(_spawn_points, delta)
		var sub_delta := delta / float(max(sim_config.flow_substeps, 1))
		for _i in sim_config.flow_substeps:
			_sim.tick_flow(sub_delta)
	_tick_absorption(delta)
	_tick_animal_absorption(delta)
	_tick_ruin_absorption(delta)
	_flush_dirty_chunks()
	_tick_power(delta)
	_check_player_contact()


func _set_depth(pos: Vector2i, depth: float, spawn_id: int = -1) -> void:
	if _sim:
		_sim.set_depth(pos, depth, spawn_id)


func _tick_power(delta: float) -> void:
	_recalc_stats()
	if total_volume <= 0.0:
		return
	_add_power(total_volume * sim_config.power_per_volume * delta)


func _add_power(amount: float) -> void:
	if amount <= 0.0:
		return
	power += amount
	var new_tier: int = sim_config.tier_from_power(power)
	if new_tier != strength_tier:
		strength_tier = new_tier
	power_changed.emit(power, strength_tier)


func _recalc_stats() -> void:
	if _sim == null:
		return
	var stats: Dictionary = _sim.recalc_volume()
	total_volume = float(stats.get("volume", 0.0))
	covered_cells = int(stats.get("cells", 0))


func _terrain_at(pos: Vector2i) -> float:
	if world == null:
		return 0.0
	if world.has_method("get_surface_height_smooth"):
		return world.get_surface_height_smooth(float(pos.x), float(pos.y))
	return world.get_surface_height(float(pos.x), float(pos.y))


func _tile_at(pos: Vector2i) -> int:
	if world == null:
		return VoxelTypes.AIR
	return world.get_tile_type(float(pos.x), float(pos.y))


func _chunk_coord_for(pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(pos.x) / float(ChunkData.SIZE)),
		floori(float(pos.y) / float(ChunkData.SIZE))
	)


func _mark_chunk_dirty(pos: Vector2i) -> void:
	_dirty_chunks[_chunk_coord_for(pos)] = true


func _flush_dirty_chunks() -> void:
	if _dirty_chunks.is_empty():
		return
	for coord_variant in _dirty_chunks.keys():
		_rebuild_chunk_layer(coord_variant)
	_dirty_chunks.clear()


func _rebuild_chunk_layer(coord: Vector2i) -> void:
	var cells: Array = []
	var min_x := coord.x * ChunkData.SIZE
	var min_z := coord.y * ChunkData.SIZE
	var max_x := min_x + ChunkData.SIZE
	var max_z := min_z + ChunkData.SIZE

	if _sim == null:
		return
	for pos_variant in _sim.depth.keys():
		var pos: Vector2i = pos_variant
		if pos.x < min_x or pos.x >= max_x or pos.y < min_z or pos.y >= max_z:
			continue
		var depth: float = float(_sim.depth[pos])
		if depth < sim_config.min_depth:
			continue
		cells.append(CrystalCell.new(
			pos,
			_terrain_at(pos),
			depth,
			int(_sim.spawn_id_by_cell.get(pos, -1))
		))

	var layer: CrystalChunkLayer
	if _chunk_layers.has(coord):
		layer = _chunk_layers[coord]
	else:
		layer = CrystalChunkLayer.new()
		layer.name = "CrystalChunk_%d_%d" % [coord.x, coord.y]
		_layer_root.add_child(layer)
		layer.setup(coord, _crystal_material)
		_chunk_layers[coord] = layer

	layer.rebuild(cells)


func _refresh_spawn_markers() -> void:
	for child in _marker_root.get_children():
		child.queue_free()
	_spawn_markers.clear()

	for spawn in _spawn_points:
		if not spawn.active:
			continue
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.55 if spawn.is_boss else 0.35
		mesh.bottom_radius = 0.7 if spawn.is_boss else 0.45
		mesh.height = 3.5 if spawn.is_boss else 2.2
		marker.mesh = mesh
		marker.material_override = _marker_material
		var surface := _terrain_at(spawn.world_pos)
		marker.position = Vector3(
			float(spawn.world_pos.x) + 0.5,
			surface + mesh.height * 0.5 + 0.5,
			float(spawn.world_pos.y) + 0.5
		)
		_marker_root.add_child(marker)
		_spawn_markers[spawn.id] = marker


func _check_player_contact() -> void:
	if not player_contact_defeat_enabled or strength_tier < player_defeat_min_tier:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else player.global_position
	var key := Vector2i(floori(col.x), floori(col.z))
	var depth: float = get_depth_at(key.x, key.y)
	if depth >= player_defeat_depth:
		crystal_touched_player.emit()


func get_depth_at(wx: int, wz: int) -> float:
	return _sim.get_depth_at(wx, wz) if _sim else 0.0


func has_crystal_at(wx: int, wz: int) -> bool:
	return _sim.has_crystal_at(wx, wz) if _sim else false


func get_crystal_top(wx: float, wz: float) -> float:
	var key := Vector2i(floori(wx), floori(wz))
	var depth: float = get_depth_at(key.x, key.y)
	if depth < sim_config.min_depth:
		return -INF
	return _terrain_at(key) + depth


func get_walkable_height(wx: float, wz: float) -> float:
	var ramp_entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		ramp_entry = chunk_manager.get_ramp_entry_at_world(wx, wz)
	var base := TerrainRamps.walkable_height_from_entry(world, wx, wz, ramp_entry) if world else 1.0
	var depth := get_depth_at(floori(wx), floori(wz))
	if depth >= sim_config.min_depth:
		return maxf(base, _terrain_at(Vector2i(floori(wx), floori(wz))) + depth + 0.05)
	return base


func get_active_spawns() -> Array[CrystalSpawnPoint]:
	var active: Array[CrystalSpawnPoint] = []
	for spawn in _spawn_points:
		if spawn.active:
			active.append(spawn)
	return active


func damage_spawn(spawn_id: int, amount: float) -> bool:
	for spawn in _spawn_points:
		if spawn.id != spawn_id:
			continue
		if spawn.apply_damage(amount):
			spawn_destroyed.emit(spawn)
			_on_spawn_destroyed(spawn)
			return true
		return false
	return false


func damage_spawn_at_world(pos: Vector2i, amount: float, radius: float = 2.5) -> bool:
	var destroyed := false
	for spawn in _spawn_points:
		if not spawn.active:
			continue
		if Vector2(pos).distance_to(Vector2(spawn.world_pos)) <= radius:
			if spawn.apply_damage(amount):
				spawn_destroyed.emit(spawn)
				_on_spawn_destroyed(spawn)
				destroyed = true
	return destroyed


func _on_spawn_destroyed(spawn: CrystalSpawnPoint) -> void:
	var marker = _spawn_markers.get(spawn.id)
	if marker:
		marker.queue_free()
		_spawn_markers.erase(spawn.id)
	if get_active_spawns().is_empty():
		all_spawns_destroyed.emit()


func get_nearest_crystal_distance(from_pos: Vector3) -> float:
	if _sim == null or _sim.depth.is_empty():
		return INF
	var best := INF
	var px := int(floor(from_pos.x))
	var pz := int(floor(from_pos.z))
	for dx in range(-32, 33):
		for dz in range(-32, 33):
			var key := Vector2i(px + dx, pz + dz)
			if get_depth_at(key.x, key.y) < sim_config.min_depth:
				continue
			var dist := Vector2(from_pos.x, from_pos.z).distance_to(
				Vector2(float(key.x) + 0.5, float(key.y) + 0.5)
			)
			best = minf(best, dist)
	if best == INF:
		for spawn in _spawn_points:
			if spawn.active:
				best = minf(best, Vector2(from_pos.x, from_pos.z).distance_to(Vector2(spawn.world_pos)))
	return best


func _tick_absorption(delta: float) -> void:
	if _sim == null or _sim.depth.is_empty():
		return
	var completed: Array[Vector2i] = []
	for pos_variant in _sim.depth.keys():
		var pos: Vector2i = pos_variant
		var depth: float = float(_sim.depth.get(pos, 0.0))
		if depth < sim_config.min_depth:
			continue
		var tile_id := _tile_at(pos)
		if not _is_absorbable_tile(tile_id):
			continue
		var rate: float = _absorption_rate(tile_id)
		var progress: float = float(_absorption.get(pos, 0.0)) + delta * rate * depth
		if progress >= 1.0:
			completed.append(pos)
		else:
			_absorption[pos] = progress
	for pos in completed:
		_complete_absorption(pos)


func _is_absorbable_tile(tile_id: int) -> bool:
	return tile_id in [
		VoxelTypes.GRASS_TUFT,
		VoxelTypes.BUSH,
		VoxelTypes.TREE_TRUNK,
		VoxelTypes.FARMLAND,
	]


func _absorption_rate(tile_id: int) -> float:
	match tile_id:
		VoxelTypes.GRASS_TUFT:
			return sim_config.grass_absorb_rate
		VoxelTypes.BUSH:
			return sim_config.bush_absorb_rate
		VoxelTypes.TREE_TRUNK:
			return sim_config.tree_absorb_rate
		VoxelTypes.FARMLAND:
			return sim_config.farmland_absorb_rate
		_:
			return 0.08


func _absorption_power_boost(tile_id: int) -> float:
	match tile_id:
		VoxelTypes.TREE_TRUNK:
			return sim_config.tree_absorb_power
		VoxelTypes.FARMLAND:
			return sim_config.farmland_absorb_power
		VoxelTypes.BUSH:
			return sim_config.bush_absorb_power
		_:
			return sim_config.grass_absorb_power


func _complete_absorption(pos: Vector2i) -> void:
	var tile_id := _tile_at(pos)
	var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
	_absorption.erase(pos)
	_FeatureRegistry.clear_tile_override(pos.x, pos.y)
	_FeatureRegistry.clear_feature(pos.x, pos.y)
	_add_power(_absorption_power_boost(tile_id))
	var source_id := _absorption_source_for(tile_id, feat)
	if evolution:
		evolution.record_absorption(source_id)
	absorption_completed.emit(source_id, pos)
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(pos.x, pos.y)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(pos.x), float(pos.y))


func _absorption_source_for(tile_id: int, feat: Dictionary) -> StringName:
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.RUIN:
		return &"ruin"
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
		return &"animal"
	match tile_id:
		VoxelTypes.FARMLAND:
			return &"farmland"
		VoxelTypes.TREE_TRUNK:
			return &"tree"
		VoxelTypes.BUSH:
			return &"bush"
		_:
			return &"grass"


func _tick_animal_absorption(delta: float) -> void:
	if _sim == null:
		return
	for pos_variant in _sim.depth.keys():
		var pos: Vector2i = pos_variant
		if float(_sim.depth.get(pos, 0.0)) < sim_config.min_depth:
			continue
		var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
		if not feat.has("kind") or int(feat.kind) != _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
			continue
		var progress: float = float(_absorption.get(pos, 0.0)) + delta * 0.25
		if progress >= 1.0:
			_complete_absorption(pos)
		else:
			_absorption[pos] = progress


func _tick_ruin_absorption(delta: float) -> void:
	if _sim == null:
		return
	for center in _FeatureRegistry.get_ruin_centers():
		if _absorbed_ruin_centers.has(center):
			continue
		if float(_sim.depth.get(center, 0.0)) < sim_config.min_depth:
			continue
		var progress: float = float(_ruin_absorption.get(center, 0.0)) + delta * 0.12
		if progress >= 1.0:
			_absorbed_ruin_centers[center] = true
			_ruin_absorption.erase(center)
			_add_power(18.0)
			if evolution:
				evolution.record_absorption(&"ruin")
			absorption_completed.emit(&"ruin", center)
			_clear_ruin_at(center)
		else:
			_ruin_absorption[center] = progress


func _clear_ruin_at(center: Vector2i) -> void:
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			if Vector2(dx, dz).length() > 5.0:
				continue
			var wx := center.x + dx
			var wz := center.y + dz
			_FeatureRegistry.clear_tile_override(wx, wz)
			_FeatureRegistry.clear_feature(wx, wz)
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(center.x, center.y)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(center.x), float(center.y))


func get_coverage_ratio() -> float:
	var playable_cells: float = float(_WorldBorder.PLAYABLE_HALF_X * 2 * _WorldBorder.PLAYABLE_HALF_Z * 2)
	if playable_cells <= 1.0:
		return 0.0
	return float(covered_cells) / playable_cells


func get_debug_stats() -> Dictionary:
	var max_depth := 0.0
	if _sim:
		for pos_variant in _sim.depth.keys():
			max_depth = maxf(max_depth, float(_sim.depth[pos_variant]))
	return {
		"tiles": covered_cells,
		"volume": total_volume,
		"max_depth": max_depth,
		"power": power,
		"tier": strength_tier,
		"spawns_active": get_active_spawns().size(),
		"spawns_total": _spawn_points.size(),
	}
