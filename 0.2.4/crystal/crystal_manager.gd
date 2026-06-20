class_name CrystalManager
extends Node3D

signal tile_crystalized(world_pos: Vector2i)
signal power_changed(power: float, tier: int)
signal spawn_destroyed(spawn: CrystalSpawnPoint)
signal all_spawns_destroyed
signal crystal_touched_player

@export var expansion_enabled: bool = true
@export var base_expansion_rate: float = 2.5
@export var max_new_absorptions_per_tick: int = 6
@export var ruin_spawn_count: int = 2
@export var ruin_min_distance: float = 72.0
@export var ruin_max_distance: float = 180.0
@export var player_contact_defeat_enabled: bool = false
@export var player_defeat_distance: float = 1.2
@export var player_defeat_min_tier: int = 3

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var power: float = 0.0
var strength_tier: int = 0
var total_tiles: int = 0

var _crystal_tiles: Dictionary = {}
var _absorbing: Dictionary = {}
var _frontier: Array[Vector2i] = []
var _frontier_set: Dictionary = {}
var _spawn_points: Array[CrystalSpawnPoint] = []
var _chunk_layers: Dictionary = {}
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

	_initialize_spawns()
	_initialized = true


func _setup_materials() -> void:
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_crystal_material.albedo_color = Color(0.55, 0.2, 0.95, 1.0)
	_crystal_material.emission_enabled = true
	_crystal_material.emission = Color(0.35, 0.1, 0.75)
	_crystal_material.emission_energy_multiplier = 1.8
	_crystal_material.roughness = 0.15
	_crystal_material.metallic = 0.35

	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.albedo_color = Color(1.0, 0.35, 0.9, 0.85)
	_marker_material.emission_enabled = true
	_marker_material.emission = Color(1.0, 0.2, 0.8)
	_marker_material.emission_energy_multiplier = 2.5
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _initialize_spawns() -> void:
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
	_seed_spawn_cluster(origin)

	for i in ruin_spawn_count:
		var ruin_pos := _pick_ruin_spawn_position()
		var ruin := CrystalSpawnPoint.new(
			_alloc_spawn_id(),
			ruin_pos,
			CrystalTypes.SpawnKind.RUIN,
			120.0,
			false
		)
		_spawn_points.append(ruin)
		_seed_spawn_cluster(ruin)

	_refresh_spawn_markers()
	_rebuild_dirty_chunks()


func _alloc_spawn_id() -> int:
	var id := _next_spawn_id
	_next_spawn_id += 1
	return id


func _seed_spawn_cluster(spawn: CrystalSpawnPoint) -> void:
	var core := spawn.world_pos
	_claim_tile(core, spawn.id, false)
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbor: Vector2i = core + offset
		if _can_bridge_or_absorb(neighbor):
			_claim_tile(neighbor, spawn.id, CrystalTypes.is_water_tile(_tile_at(neighbor)))


func _pick_ruin_spawn_position() -> Vector2i:
	var best := Vector2i(64, 64)
	var best_score := -1.0
	for attempt in 48:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(ruin_min_distance, ruin_max_distance)
		var wx := int(round(cos(angle) * dist))
		var wz := int(round(sin(angle) * dist))
		var pos := Vector2i(wx, wz)
		var tile := _tile_at(pos)
		if CrystalTypes.is_water_tile(tile):
			continue
		var surface := _surface_at(pos)
		if surface < 34 or surface > 130:
			continue
		var origin_dist := Vector2(pos).distance_to(Vector2.ZERO)
		var separation_penalty := 0.0
		for existing in _spawn_points:
			separation_penalty += 48.0 / maxf(Vector2(pos).distance_to(Vector2(existing.world_pos)), 1.0)
		var score := origin_dist * 0.35 + separation_penalty + _rng.randf_range(0.0, 8.0)
		if score > best_score:
			best_score = score
			best = pos
	return best


func _process(delta: float) -> void:
	if not _initialized or not expansion_enabled:
		return

	_tick_absorption(delta)
	_tick_expansion(delta)
	_check_player_contact()


func _tick_absorption(delta: float) -> void:
	var completed: Array[Vector2i] = []
	for pos: Vector2i in _absorbing.keys():
		var job: Dictionary = _absorbing[pos]
		job["progress"] = float(job.get("progress", 0.0)) + delta
		var duration: float = float(job.get("duration", 1.0))
		if float(job["progress"]) >= duration:
			completed.append(pos)

	for pos in completed:
		var job: Dictionary = _absorbing[pos]
		_absorbing.erase(pos)
		_finalize_absorption(
			pos,
			int(job.get("spawn_id", -1)),
			int(job.get("source_tile", VoxelTypes.AIR)),
			bool(job.get("bridge", false))
		)


func _tick_expansion(delta: float) -> void:
	if _frontier.is_empty():
		return

	var budget := int(round(base_expansion_rate * delta * (1.0 + strength_tier * 0.18)))
	budget = clampi(budget, 1, max_new_absorptions_per_tick)
	var started := 0

	while started < budget and not _frontier.is_empty():
		var pos := _pop_frontier()
		if _crystal_tiles.has(pos) or _absorbing.has(pos):
			continue
		if not _has_crystal_neighbor(pos):
			continue

		var tile := _tile_at(pos)
		if CrystalTypes.is_water_tile(tile):
			_start_bridge(pos)
			started += 1
			continue
		if not CrystalTypes.can_absorb(tile):
			continue

		_start_absorption(pos, tile)
		started += 1


func _start_absorption(pos: Vector2i, tile_id: int) -> void:
	var category := CrystalTypes.get_absorb_category(tile_id)
	var duration: float = CrystalTypes.ABSORB_SECONDS[category]
	duration /= 1.0 + strength_tier * 0.12
	_absorbing[pos] = {
		"progress": 0.0,
		"duration": duration,
		"source_tile": tile_id,
		"spawn_id": _nearest_spawn_id(pos),
		"bridge": false,
	}
	_remove_from_frontier(pos)


func _start_bridge(pos: Vector2i) -> void:
	_absorbing[pos] = {
		"progress": 0.0,
		"duration": CrystalTypes.ABSORB_SECONDS[CrystalTypes.AbsorbCategory.WATER],
		"source_tile": _tile_at(pos),
		"spawn_id": _nearest_spawn_id(pos),
		"bridge": true,
	}
	_remove_from_frontier(pos)


func _finalize_absorption(pos: Vector2i, spawn_id: int, source_tile: int, bridge: bool) -> void:
	_claim_tile(pos, spawn_id, bridge)
	if not bridge:
		var category := CrystalTypes.get_absorb_category(source_tile)
		_add_power(CrystalTypes.POWER_GAIN[category])


func _claim_tile(pos: Vector2i, spawn_id: int, bridge: bool) -> void:
	if _crystal_tiles.has(pos):
		return
	_remove_from_frontier(pos)

	var surface_y := _surface_at(pos)
	if bridge:
		surface_y += 1

	var cell: CrystalCell = CrystalCell.new(pos, surface_y, _tile_at(pos), spawn_id, bridge)
	_crystal_tiles[pos] = cell
	total_tiles = _crystal_tiles.size()
	_enqueue_frontier_neighbors(pos)
	_mark_chunk_dirty(pos)
	tile_crystalized.emit(pos)


func _enqueue_frontier_neighbors(pos: Vector2i) -> void:
	for dir in CrystalTypes.NEIGHBOR_DIRS:
		var neighbor: Vector2i = pos + dir
		if _crystal_tiles.has(neighbor) or _absorbing.has(neighbor):
			continue
		if _frontier_set.has(neighbor):
			continue
		if not _can_bridge_or_absorb(neighbor):
			continue
		_frontier.append(neighbor)
		_frontier_set[neighbor] = true


func _pop_frontier() -> Vector2i:
	if _frontier.is_empty():
		return Vector2i.ZERO
	var pos: Vector2i = _frontier.pop_front()
	_frontier_set.erase(pos)
	return pos


func _remove_from_frontier(pos: Vector2i) -> void:
	_frontier_set.erase(pos)
	var idx := _frontier.find(pos)
	if idx >= 0:
		_frontier.remove_at(idx)


func _has_crystal_neighbor(pos: Vector2i) -> bool:
	for dir in CrystalTypes.NEIGHBOR_DIRS:
		if _crystal_tiles.has(pos + dir):
			return true
	return false


func _can_bridge_or_absorb(pos: Vector2i) -> bool:
	var tile := _tile_at(pos)
	if CrystalTypes.is_water_tile(tile):
		return _has_crystal_neighbor(pos)
	return CrystalTypes.can_absorb(tile)


func _nearest_spawn_id(pos: Vector2i) -> int:
	var best_id := 0
	var best_dist := INF
	for spawn in _spawn_points:
		if not spawn.active:
			continue
		var dist := Vector2(pos).distance_squared_to(Vector2(spawn.world_pos))
		if dist < best_dist:
			best_dist = dist
			best_id = spawn.id
	return best_id


func _add_power(amount: float) -> void:
	if amount <= 0.0:
		return
	power += amount
	var new_tier: int = CrystalTypes.tier_from_power(power)
	if new_tier != strength_tier:
		strength_tier = new_tier
	power_changed.emit(power, strength_tier)


func _tile_at(pos: Vector2i) -> int:
	if world == null:
		return VoxelTypes.AIR
	return world.get_tile_type(float(pos.x), float(pos.y))


func _surface_at(pos: Vector2i) -> int:
	if world == null:
		return 0
	return int(world.get_surface_height(float(pos.x), float(pos.y)))


func _chunk_coord_for(pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(pos.x) / float(ChunkData.SIZE)),
		floori(float(pos.y) / float(ChunkData.SIZE))
	)


func _mark_chunk_dirty(pos: Vector2i) -> void:
	var coord := _chunk_coord_for(pos)
	_rebuild_chunk_layer(coord)


func _rebuild_dirty_chunks() -> void:
	var coords: Dictionary = {}
	for pos: Vector2i in _crystal_tiles.keys():
		coords[_chunk_coord_for(pos)] = true
	for coord: Vector2i in coords.keys():
		_rebuild_chunk_layer(coord)


func _rebuild_chunk_layer(coord: Vector2i) -> void:
	var cells: Array = []
	var min_x := coord.x * ChunkData.SIZE
	var min_z := coord.y * ChunkData.SIZE
	var max_x := min_x + ChunkData.SIZE
	var max_z := min_z + ChunkData.SIZE

	for pos: Vector2i in _crystal_tiles.keys():
		if pos.x >= min_x and pos.x < max_x and pos.y >= min_z and pos.y < max_z:
			cells.append(_crystal_tiles[pos])

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
		var surface := _surface_at(spawn.world_pos)
		marker.position = Vector3(
			float(spawn.world_pos.x) + 0.5,
			float(surface) + mesh.height * 0.5 + 0.5,
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
	var px := int(floor(player.global_position.x))
	var pz := int(floor(player.global_position.z))
	var key := Vector2i(px, pz)
	if not _crystal_tiles.has(key):
		return
	var cell: CrystalCell = _crystal_tiles[key]
	var dy := absf(player.global_position.y - (float(cell.surface_y) + 1.0))
	if dy <= player_defeat_distance:
		crystal_touched_player.emit()


func has_crystal_at(wx: int, wz: int) -> bool:
	return _crystal_tiles.has(Vector2i(wx, wz))


func get_crystal_cell(wx: int, wz: int) -> CrystalCell:
	return _crystal_tiles.get(Vector2i(wx, wz))


func get_walkable_height(wx: float, wz: float) -> float:
	var base := 0.0
	if world:
		base = world.get_surface_height(wx, wz) + 1.0
	var key := Vector2i(floori(wx), floori(wz))
	if _crystal_tiles.has(key):
		var cell: CrystalCell = _crystal_tiles[key]
		return maxf(base, float(cell.surface_y) + 1.0)
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
	if _crystal_tiles.is_empty():
		return INF
	var best := INF
	var px := int(floor(from_pos.x))
	var pz := int(floor(from_pos.z))
	for dx in range(-24, 25):
		for dz in range(-24, 25):
			var key := Vector2i(px + dx, pz + dz)
			if not _crystal_tiles.has(key):
				continue
			var dist := Vector2(from_pos.x, from_pos.z).distance_to(
				Vector2(float(key.x) + 0.5, float(key.y) + 0.5)
			)
			best = minf(best, dist)
	if best == INF:
		for spawn in _spawn_points:
			if spawn.active:
				best = minf(
					best,
					Vector2(from_pos.x, from_pos.z).distance_to(Vector2(spawn.world_pos))
				)
	return best


func get_debug_stats() -> Dictionary:
	return {
		"tiles": total_tiles,
		"power": power,
		"tier": strength_tier,
		"frontier": _frontier.size(),
		"absorbing": _absorbing.size(),
		"spawns_active": get_active_spawns().size(),
		"spawns_total": _spawn_points.size(),
	}