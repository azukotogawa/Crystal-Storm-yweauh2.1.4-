class_name CrystalManager
extends Node3D

const _WorldBorder = preload("res://helpers/world_border.gd")

signal fluid_changed(world_pos: Vector2i)
signal power_changed(power: float, tier: int)
signal spawn_destroyed(spawn: CrystalSpawnPoint)
signal all_spawns_destroyed
signal crystal_touched_player

@export var expansion_enabled: bool = true
@export var flow_substeps: int = 2
@export var ruin_spawn_count: int = 2
@export var ruin_min_distance: float = 72.0
@export var ruin_max_distance: float = 180.0
@export var player_contact_defeat_enabled: bool = false
@export var player_defeat_depth: float = 0.35
@export var player_defeat_min_tier: int = 2

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var power: float = 0.0
var strength_tier: int = 0
var total_volume: float = 0.0
var covered_cells: int = 0

var _depth: Dictionary = {}
var _spawn_id_by_cell: Dictionary = {}
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

	_initialize_spawns()
	_initialized = true


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
	_depth.clear()
	_spawn_id_by_cell.clear()
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

	for _i in ruin_spawn_count:
		var ruin_pos := _pick_ruin_spawn_position()
		var ruin := CrystalSpawnPoint.new(
			_alloc_spawn_id(),
			ruin_pos,
			CrystalTypes.SpawnKind.RUIN,
			120.0,
			false
		)
		_spawn_points.append(ruin)
		_seed_emitter(ruin)

	_recalc_stats()
	_refresh_spawn_markers()
	_flush_dirty_chunks()


func _alloc_spawn_id() -> int:
	var id := _next_spawn_id
	_next_spawn_id += 1
	return id


func _seed_emitter(spawn: CrystalSpawnPoint) -> void:
	_set_depth(spawn.world_pos, CrystalTypes.INITIAL_SPAWN_DEPTH, spawn.id)


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

	_tick_emitters(delta)
	var sub_delta := delta / float(max(flow_substeps, 1))
	for _i in flow_substeps:
		_tick_flow(sub_delta)
	_flush_dirty_chunks()
	_tick_power(delta)
	_check_player_contact()


func _tick_emitters(delta: float) -> void:
	for spawn in _spawn_points:
		if not spawn.active:
			continue
		var pos := spawn.world_pos
		var current: float = float(_depth.get(pos, 0.0))
		var added := spawn.emit_rate * delta
		var room := CrystalTypes.MAX_DEPTH - current
		if room <= 0.0:
			continue
		_set_depth(pos, current + minf(added, room), spawn.id)


func _tick_flow(delta: float) -> void:
	if _depth.is_empty():
		return

	var cells: Array = _depth.keys()
	var deltas: Dictionary = {}

	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		var amount: float = float(_depth.get(pos, 0.0))
		if amount < CrystalTypes.MIN_DEPTH:
			continue

		var terrain: float = _terrain_at(pos)
		var my_top: float = terrain + amount

		for dir in CrystalTypes.NEIGHBOR_DIRS:
			var neighbor: Vector2i = pos + dir
			if _flow_blocked(pos, neighbor):
				continue

			var n_tile := _tile_at(neighbor)
			var n_terrain: float = _terrain_at(neighbor)
			var n_depth: float = float(_depth.get(neighbor, 0.0))

			if CrystalTypes.is_water_tile(n_tile) and n_depth < CrystalTypes.MIN_DEPTH:
				if my_top <= n_terrain + CrystalTypes.MIN_FLOW_DIFF:
					continue

			var n_top: float = n_terrain + n_depth
			var diff: float = my_top - n_top
			if diff <= CrystalTypes.MIN_FLOW_DIFF:
				continue

			var transfer: float = min(
				amount * CrystalTypes.FLOW_RATE * delta * diff,
				diff * 0.45,
				CrystalTypes.MAX_FLOW_PER_CELL * delta,
				amount * 0.65
			)
			if transfer < CrystalTypes.MIN_DEPTH * 0.25:
				continue

			deltas[pos] = float(deltas.get(pos, 0.0)) - transfer
			deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + transfer
			_assign_spawn_on_flow(neighbor, pos)

	for pos_variant in deltas.keys():
		var pos: Vector2i = pos_variant
		var new_depth: float = float(_depth.get(pos, 0.0)) + float(deltas[pos])
		var spawn_id: int = int(_spawn_id_by_cell.get(pos, -1))
		_set_depth(pos, new_depth, spawn_id)


func _flow_blocked(from: Vector2i, to: Vector2i) -> bool:
	var from_terrain: float = _terrain_at(from)
	var to_terrain: float = _terrain_at(to)
	if to_terrain <= from_terrain + CrystalTypes.CLIFF_HEIGHT:
		return false
	var my_top: float = from_terrain + float(_depth.get(from, 0.0))
	return my_top <= to_terrain + CrystalTypes.MIN_FLOW_DIFF


func _assign_spawn_on_flow(to: Vector2i, from: Vector2i) -> void:
	if _spawn_id_by_cell.has(to):
		return
	if _spawn_id_by_cell.has(from):
		_spawn_id_by_cell[to] = _spawn_id_by_cell[from]


func _set_depth(pos: Vector2i, depth: float, spawn_id: int = -1) -> void:
	depth = clampf(depth, 0.0, CrystalTypes.MAX_DEPTH)
	if depth < CrystalTypes.MIN_DEPTH:
		if _depth.has(pos):
			_depth.erase(pos)
			_spawn_id_by_cell.erase(pos)
			_mark_chunk_dirty(pos)
			fluid_changed.emit(pos)
		return

	var changed: bool = not _depth.has(pos) or absf(float(_depth[pos]) - depth) > 0.02
	_depth[pos] = depth
	if spawn_id >= 0:
		_spawn_id_by_cell[pos] = spawn_id
	if changed:
		_mark_chunk_dirty(pos)
		fluid_changed.emit(pos)


func _tick_power(delta: float) -> void:
	_recalc_stats()
	if total_volume <= 0.0:
		return
	_add_power(total_volume * 0.0025 * delta)


func _add_power(amount: float) -> void:
	if amount <= 0.0:
		return
	power += amount
	var new_tier: int = CrystalTypes.tier_from_power(power)
	if new_tier != strength_tier:
		strength_tier = new_tier
	power_changed.emit(power, strength_tier)


func _recalc_stats() -> void:
	total_volume = 0.0
	covered_cells = _depth.size()
	for pos_variant in _depth.keys():
		total_volume += float(_depth[pos_variant])


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

	for pos_variant in _depth.keys():
		var pos: Vector2i = pos_variant
		if pos.x < min_x or pos.x >= max_x or pos.y < min_z or pos.y >= max_z:
			continue
		var depth: float = float(_depth[pos])
		if depth < CrystalTypes.MIN_DEPTH:
			continue
		cells.append(CrystalCell.new(
			pos,
			_terrain_at(pos),
			depth,
			int(_spawn_id_by_cell.get(pos, -1))
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
	var key := Vector2i(floori(player.global_position.x), floori(player.global_position.z))
	var depth: float = float(_depth.get(key, 0.0))
	if depth >= player_defeat_depth:
		crystal_touched_player.emit()


func get_depth_at(wx: int, wz: int) -> float:
	return float(_depth.get(Vector2i(wx, wz), 0.0))


func has_crystal_at(wx: int, wz: int) -> bool:
	return get_depth_at(wx, wz) >= CrystalTypes.MIN_DEPTH


func get_crystal_top(wx: float, wz: float) -> float:
	var key := Vector2i(floori(wx), floori(wz))
	var depth: float = float(_depth.get(key, 0.0))
	if depth < CrystalTypes.MIN_DEPTH:
		return -INF
	return _terrain_at(key) + depth


func get_walkable_height(wx: float, wz: float) -> float:
	var ramp_entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		ramp_entry = chunk_manager.get_ramp_entry_at_world(wx, wz)
	var base := TerrainRamps.walkable_height_from_entry(world, wx, wz, ramp_entry) if world else 1.0
	var depth := get_depth_at(floori(wx), floori(wz))
	if depth >= CrystalTypes.MIN_DEPTH:
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
	if _depth.is_empty():
		return INF
	var best := INF
	var px := int(floor(from_pos.x))
	var pz := int(floor(from_pos.z))
	for dx in range(-32, 33):
		for dz in range(-32, 33):
			var key := Vector2i(px + dx, pz + dz)
			if float(_depth.get(key, 0.0)) < CrystalTypes.MIN_DEPTH:
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


func get_debug_stats() -> Dictionary:
	var max_depth := 0.0
	for pos_variant in _depth.keys():
		max_depth = maxf(max_depth, float(_depth[pos_variant]))
	return {
		"tiles": covered_cells,
		"volume": total_volume,
		"max_depth": max_depth,
		"power": power,
		"tier": strength_tier,
		"spawns_active": get_active_spawns().size(),
		"spawns_total": _spawn_points.size(),
	}
