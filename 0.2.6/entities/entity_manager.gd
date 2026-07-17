class_name EntityManager
extends Node

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

@export var animals_per_biome_chunk: int = 2
@export var max_entities: int = 128
@export var max_defenders_per_town: int = 8

signal entity_spawned(entity: Node3D)
signal entity_despawned(entity: Node3D)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
var _entities: Array[Node3D] = []
var _spawned_cells: Dictionary = {}
var _defenders_by_town: Dictionary = {}
var physics_skip_frames: int = 0


func _enter_tree() -> void:
	add_to_group("entity_manager")


func _entity_parent() -> Node:
	var visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if visuals and visuals.has_method("get_entities_root"):
		return visuals.get_entities_root()
	return self


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	max_entities = int(cfg.max_entities)
	animals_per_biome_chunk = int(cfg.animals_per_biome_chunk)
	physics_skip_frames = int(cfg.entity_physics_skip_frames)
	if not bool(cfg.entity_spawning_enabled):
		_clear_runtime_entities()


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	_EntityBrainRegistry.ensure_builtins()
	call_deferred("_await_chunk_manager_bind")


func seed_spawns() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if crystal_manager == null:
		crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	_seed_animal_spawns()
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager:
		_bind_chunk_streaming()


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	if cm == null:
		return
	chunk_manager = cm
	_bind_chunk_streaming()
	_refresh_entity_visuals()


func _await_chunk_manager_bind() -> void:
	while chunk_manager == null and is_inside_tree():
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		if chunk_manager != null:
			break
		await get_tree().process_frame
	if chunk_manager != null:
		_bind_chunk_streaming()


func _refresh_entity_visuals() -> void:
	if chunk_manager == null:
		return
	var registry = get_tree().get_first_node_in_group("game_visual_registry")
	if registry and registry.has_method("ensure_textures_ready"):
		await registry.ensure_textures_ready()
	elif registry and registry.has_method("ensure_ready"):
		await registry.ensure_ready()
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		if entity.has_method("refresh_visual"):
			entity.refresh_visual()


func _bind_chunk_streaming() -> void:
	if chunk_manager == null:
		return
	if chunk_manager.has_signal("chunk_ready") and not chunk_manager.chunk_ready.is_connected(_on_chunk_ready):
		chunk_manager.chunk_ready.connect(_on_chunk_ready)
	if chunk_manager.has_signal("chunk_unloaded") and not chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
		chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	for coord in chunk_manager.chunks.keys():
		var entry = chunk_manager.chunks[coord]
		var data: ChunkData = entry.chunk_data if entry else null
		_on_chunk_ready(coord, data)


func spawn_town_defenders(town: Dictionary, count: int) -> void:
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	var radius: int = int(town.get("radius", 12))
	var current: int = int(_defenders_by_town.get(center, 0))
	if current >= max_defenders_per_town:
		return

	var brain_cfg = _EntityBrainRegistry.get_def(&"town_militia")
	if brain_cfg == null:
		return

	var to_spawn := mini(count, max_defenders_per_town - current)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(center) + str(Time.get_ticks_msec()))
	for _i in to_spawn:
		if _entities.size() >= max_entities:
			return
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(float(radius) * 0.55, float(radius) * 0.85)
		var wx := center.x + int(round(cos(angle) * dist))
		var wz := center.y + int(round(sin(angle) * dist))
		_spawn_world_entity(wx, wz, brain_cfg, center, Color(0.55, 0.58, 0.72))
		_defenders_by_town[center] = int(_defenders_by_town.get(center, 0)) + 1


func _seed_animal_spawns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.world_seed + 66003
	var half := 512
	for _i in 96:
		var wx := rng.randi_range(-half, half)
		var wz := rng.randi_range(-half, half)
		if not _is_valid_animal_cell(wx, wz):
			continue
		var animal_kind := _pick_animal_kind(wx, wz, rng)
		_FeatureRegistry.register_entity_spawn(
			wx, wz,
			_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN,
			animal_kind
		)


func _pick_animal_kind(wx: int, wz: int, rng: RandomNumberGenerator) -> int:
	if world == null:
		return _WorldFeatureTypes.AnimalKind.RABBIT
	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	var name: String = biome.get("name", "plains")
	if name == "forest":
		return _WorldFeatureTypes.AnimalKind.DEER if rng.randf() < 0.55 else _WorldFeatureTypes.AnimalKind.BOAR
	if name == "steppe":
		return _WorldFeatureTypes.AnimalKind.RABBIT
	return _WorldFeatureTypes.AnimalKind.BIRD if rng.randf() < 0.4 else _WorldFeatureTypes.AnimalKind.RABBIT


func _is_valid_animal_cell(wx: int, wz: int) -> bool:
	if world == null:
		return false
	var tile := world.get_tile_type(float(wx), float(wz))
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER:
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.TOWN:
		return false
	return true


func _on_chunk_unloaded(coord: Vector2i) -> void:
	_despawn_entities_in_chunk(coord)


func _despawn_entities_in_chunk(coord: Vector2i) -> void:
	if chunk_manager == null:
		return
	var to_remove: Array[Node3D] = []
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		var col: Vector3 = entity.global_position
		if entity.has_method("get_combat_center"):
			col = entity.get_combat_center()
		var ws = _WorldSettings.get_active()
		var wx := int(floori(ws.world_to_column(col.x)))
		var wz := int(floori(ws.world_to_column(col.z)))
		var entity_coord := chunk_manager.world_to_chunk_coord(wx, wz)
		if entity_coord != coord:
			continue
		to_remove.append(entity)
	for entity in to_remove:
		_entities.erase(entity)
		var ws = _WorldSettings.get_active()
		var cell := Vector2i(
			floori(ws.world_to_column(entity.global_position.x)),
			floori(ws.world_to_column(entity.global_position.z))
		)
		_spawned_cells.erase(cell)
		entity_despawned.emit(entity)
		entity.queue_free()


func _on_chunk_ready(coord: Vector2i, _data: ChunkData) -> void:
	if animals_per_biome_chunk <= 0 or _entities.size() >= max_entities:
		return
	var spawns: Array = _FeatureRegistry.get_spawns_in_chunk(coord)
	for spawn in spawns:
		if _entities.size() >= max_entities:
			return
		var pos: Vector2i = spawn.world_pos
		var key := Vector2i(pos)
		if _spawned_cells.has(key):
			continue
		if int(spawn.get("kind", 0)) != _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
			continue
		var brain_cfg = _brain_for_animal(int(spawn.get("animal_kind", 0)))
		_spawn_world_entity(pos.x, pos.y, brain_cfg, pos, _animal_color(int(spawn.get("animal_kind", 0))))
		_spawned_cells[key] = true


func _brain_for_animal(animal_kind: int):
	match animal_kind:
		_WorldFeatureTypes.AnimalKind.DEER:
			return _EntityBrainRegistry.get_def(&"deer")
		_WorldFeatureTypes.AnimalKind.BOAR:
			return _EntityBrainRegistry.get_def(&"boar")
		_WorldFeatureTypes.AnimalKind.BIRD:
			return _EntityBrainRegistry.get_def(&"bird")
		_:
			return _EntityBrainRegistry.get_def(&"rabbit")


func _spawn_world_entity(
	wx: int,
	wz: int,
	brain_cfg,
	defend_center: Vector2i,
	tint: Color
) -> void:
	if brain_cfg == null:
		return
	var entity: _WorldEntity = _WorldEntity.new()
	entity.died.connect(_on_entity_died)
	var parent := _entity_parent()
	parent.add_child(entity)
	if not entity.is_inside_tree():
		push_error("EntityManager: entity not in tree before setup")
		return
	entity.setup(brain_cfg, Vector2i(wx, wz), world, chunk_manager, crystal_manager, defend_center, tint)
	_entities.append(entity)
	if entity.has_method("refresh_visual"):
		entity.refresh_visual()
	entity_spawned.emit(entity)


func _on_entity_died(entity: Node3D, _world_pos: Vector2i = Vector2i.ZERO) -> void:
	if not is_instance_valid(entity):
		return
	_entities.erase(entity)
	_spawned_cells.erase(_world_pos)
	entity_despawned.emit(entity)


func export_entities() -> Array:
	_prune()
	var out: Array = []
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		if not entity.has_method("export_save_state"):
			continue
		out.append(entity.export_save_state())
	return out


func import_entities(rows: Array) -> void:
	if rows.is_empty():
		return
	_clear_runtime_entities()
	for row in rows:
		if not row is Dictionary:
			continue
		_spawn_from_save(row)


func _clear_runtime_entities() -> void:
	for entity in _entities.duplicate():
		if is_instance_valid(entity):
			entity.queue_free()
	_entities.clear()
	_spawned_cells.clear()
	_defenders_by_town.clear()


func _spawn_from_save(data: Dictionary) -> void:
	var brain_id: StringName = StringName(str(data.get("brain_id", "rabbit")))
	var brain_cfg = _EntityBrainRegistry.get_def(brain_id)
	if brain_cfg == null:
		return
	var pos_arr: Array = data.get("world_pos", [0, 0])
	var cell := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
	var defend_arr: Array = data.get("defend_center", [cell.x, cell.y])
	var defend := Vector2i(int(defend_arr[0]), int(defend_arr[1]))
	var tint_arr: Array = data.get("tint", [0.72, 0.72, 0.68, 1.0])
	var tint := Color(float(tint_arr[0]), float(tint_arr[1]), float(tint_arr[2]), float(tint_arr[3]))
	var entity: _WorldEntity = _WorldEntity.new()
	entity.died.connect(_on_entity_died)
	_entity_parent().add_child(entity)
	entity.setup(brain_cfg, cell, world, chunk_manager, crystal_manager, defend, tint)
	if data.has("health"):
		entity.health = float(data.health)
	# Final save position after setup defaults; emit spawn so Spatial Query indexes correctly.
	entity.global_position = Vector3(
		float(data.get("x", float(cell.x) + 0.5)),
		float(data.get("y", 1.0)),
		float(data.get("z", float(cell.y) + 0.5))
	)
	_entities.append(entity)
	_spawned_cells[cell] = true
	entity_spawned.emit(entity)


func get_active_entity_count() -> int:
	_prune()
	return _entities.size()


func _prune() -> void:
	var kept: Array[Node3D] = []
	for e in _entities:
		if is_instance_valid(e):
			kept.append(e)
	_entities = kept


func _animal_color(kind: int) -> Color:
	match kind:
		_WorldFeatureTypes.AnimalKind.DEER:
			return Color(0.62, 0.45, 0.28)
		_WorldFeatureTypes.AnimalKind.BOAR:
			return Color(0.35, 0.28, 0.22)
		_WorldFeatureTypes.AnimalKind.BIRD:
			return Color(0.55, 0.62, 0.78)
		_:
			return Color(0.72, 0.72, 0.68)