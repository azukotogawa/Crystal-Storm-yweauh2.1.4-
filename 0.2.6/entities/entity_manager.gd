class_name EntityManager
extends Node

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

@export var animals_per_biome_chunk: int = 3
@export var max_entities: int = 128
@export var max_defenders_per_town: int = 8
@export var wildlife_seed_attempts: int = 160
@export var villagers_per_town: int = 3

signal entity_spawned(entity: Node3D)
signal entity_despawned(entity: Node3D)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var crystal_manager: CrystalManager
var _entities: Array[Node3D] = []
var _spawned_cells: Dictionary = {}
var _defenders_by_town: Dictionary = {}
var physics_skip_frames: int = 0
## Stream hitch isolation: spawn wildlife/townfolk off chunk_ready hot path.
var _pending_stream_coords: Array = []
var _pending_stream_set: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("entity_manager")
	set_process(true)


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
	var _SP = load("res://systems/startup_profiler.gd")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if crystal_manager == null:
		crystal_manager = get_tree().get_first_node_in_group("crystal_manager")
	if _SP:
		_SP.begin("fs/spawn_animal_registry")
	_seed_animal_spawns()
	if _SP:
		_SP.end("fs/spawn_animal_registry")
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager:
		if _SP:
			_SP.begin("fs/spawn_chunk_stream_bind")
		_bind_chunk_streaming()
		if _SP:
			_SP.end("fs/spawn_chunk_stream_bind")


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


## Standing militia target per town at seed / stream re-entry (defense may request more).
const STANDING_MILITIA_PER_TOWN: int = 2


func spawn_town_defenders(town: Dictionary, count: int) -> void:
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	var radius: int = int(town.get("radius", 12))
	# Always reconcile with live agents — stream unload can wipe bodies while the map stayed stale.
	_defenders_by_town[center] = _count_town_role(center, &"town_militia")
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
	var attempts: int = maxi(wildlife_seed_attempts, 96)
	var placed := 0
	for _i in attempts:
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
		placed += 1
	# Living World: standing militia + villagers at towns (agents present at run start).
	_seed_town_population()


func _seed_town_population() -> void:
	for town in _FeatureRegistry.get_towns():
		ensure_town_population(town)


## Top up standing villagers + militia for a town (safe after stream unload/reload).
func ensure_town_population(town: Dictionary) -> void:
	if town.is_empty():
		return
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	var villagers_live := _count_town_role(center, &"town_villager")
	var need_v := maxi(0, villagers_per_town - villagers_live)
	if need_v > 0:
		spawn_town_villagers(town, need_v)
	var militia_live := _count_town_role(center, &"town_militia")
	_defenders_by_town[center] = militia_live
	var need_m := maxi(0, STANDING_MILITIA_PER_TOWN - militia_live)
	if need_m > 0:
		spawn_town_defenders(town, need_m)


## Peaceful townsfolk — Living World “worth defending” agents.
func spawn_town_villagers(town: Dictionary, count: int) -> void:
	if count <= 0:
		return
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	var radius: int = int(town.get("radius", 12))
	var brain_cfg = _EntityBrainRegistry.get_def(&"town_villager")
	if brain_cfg == null:
		brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if brain_cfg == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (world.world_seed if world else 1) + 91011 + hash(center) + _count_town_role(center, &"town_villager")
	for _i in count:
		if _entities.size() >= max_entities:
			return
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(float(radius) * 0.12, float(radius) * 0.42)
		var wx := center.x + int(round(cos(angle) * dist))
		var wz := center.y + int(round(sin(angle) * dist))
		_spawn_world_entity(wx, wz, brain_cfg, center, Color(0.72, 0.62, 0.48))


func _count_town_role(town_center: Vector2i, brain_id: StringName) -> int:
	var n := 0
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		if str(entity.get("entity_kind")) != str(brain_id):
			continue
		var dc := _entity_defend_center(entity)
		if dc == town_center:
			n += 1
	return n


func _entity_defend_center(entity: Node3D) -> Vector2i:
	if entity == null or not is_instance_valid(entity):
		return Vector2i.ZERO
	if "brain" in entity and entity.brain != null and "defend_center" in entity.brain:
		return entity.brain.defend_center
	if "home_cell" in entity:
		return entity.home_cell
	return Vector2i.ZERO


func _entity_column_cell(entity: Node3D) -> Vector2i:
	if entity == null or not is_instance_valid(entity):
		return Vector2i.ZERO
	var col: Vector3 = entity.global_position
	if entity.has_method("get_combat_center"):
		col = entity.get_combat_center()
	var ws = _WorldSettings.get_active()
	return Vector2i(
		floori(ws.world_to_column(col.x)),
		floori(ws.world_to_column(col.z))
	)


func _note_entity_removed(entity: Node3D) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	if str(entity.get("entity_kind")) == "town_militia":
		var center := _entity_defend_center(entity)
		var cur := int(_defenders_by_town.get(center, 0))
		_defenders_by_town[center] = maxi(0, cur - 1)


func _pick_animal_kind(wx: int, wz: int, rng: RandomNumberGenerator) -> int:
	if world == null:
		return _WorldFeatureTypes.AnimalKind.RABBIT
	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	var name: String = biome.get("name", "plains")
	# Temperate forest family + steppe family (Living World Phase 1).
	if name == "forest" or name == "dense forest" or name == "pine forest" or name == "jungle":
		return _WorldFeatureTypes.AnimalKind.DEER if rng.randf() < 0.55 else _WorldFeatureTypes.AnimalKind.BOAR
	if name == "steppe":
		return _WorldFeatureTypes.AnimalKind.RABBIT if rng.randf() < 0.7 else _WorldFeatureTypes.AnimalKind.BIRD
	if name == "plains":
		return _WorldFeatureTypes.AnimalKind.RABBIT if rng.randf() < 0.5 else _WorldFeatureTypes.AnimalKind.BIRD
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
	if _pending_stream_set.has(coord):
		_pending_stream_set.erase(coord)
	_despawn_entities_in_chunk(coord)


func _despawn_entities_in_chunk(coord: Vector2i) -> void:
	if chunk_manager == null:
		return
	var to_remove: Array[Node3D] = []
	for entity in _entities:
		if not is_instance_valid(entity):
			continue
		var cell := _entity_column_cell(entity)
		var entity_coord := chunk_manager.world_to_chunk_coord(cell.x, cell.y)
		if entity_coord != coord:
			continue
		to_remove.append(entity)
	for entity in to_remove:
		_entities.erase(entity)
		var cell := _entity_column_cell(entity)
		_spawned_cells.erase(cell)
		_note_entity_removed(entity)
		entity_despawned.emit(entity)
		entity.queue_free()


func _on_chunk_ready(coord: Vector2i, _data: ChunkData) -> void:
	# Queue for budgeted drain — spawning agents inside ChunkManager apply
	# stacked multi-ms entity instantiate/tree work onto chunk_upload.
	if _pending_stream_set.has(coord):
		return
	_pending_stream_set[coord] = true
	_pending_stream_coords.append(coord)


func _process(_delta: float) -> void:
	if _pending_stream_coords.is_empty():
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("entity_stream_spawn")
	var fbs = get_node_or_null("/root/FrameBudgetScheduler")
	var drain := func(token = null) -> void:
		while not _pending_stream_coords.is_empty():
			if token != null and not token.can_continue():
				break
			var coord: Vector2i = _pending_stream_coords.pop_front()
			if not _pending_stream_set.has(coord):
				continue
			_pending_stream_set.erase(coord)
			if chunk_manager != null and chunk_manager.chunks.has(coord):
				_activate_chunk_entities(coord)
			if token != null:
				token.spend_unit()
			else:
				break
	if fbs and fbs.has_method("run_budgeted"):
		fbs.run_budgeted(&"entity_spawn", drain)
		if fbs.has_method("report_queue_depth"):
			fbs.report_queue_depth(&"entity_spawn", _pending_stream_coords.size(), 0)
	else:
		drain.call(null)
	if profiler and profiler.has_method("end"):
		profiler.end("entity_stream_spawn")


func _activate_chunk_entities(coord: Vector2i) -> void:
	# Re-populate standing townfolk when a settlement chunk streams back in.
	_ensure_town_population_for_chunk(coord)
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


func _ensure_town_population_for_chunk(coord: Vector2i) -> void:
	if chunk_manager == null:
		return
	for town in _FeatureRegistry.get_towns():
		if not _town_overlaps_chunk(town, coord):
			continue
		ensure_town_population(town)


func _town_overlaps_chunk(town: Dictionary, coord: Vector2i) -> bool:
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	var radius: float = float(town.get("radius", 12))
	var size := float(ChunkData.SIZE)
	var chunk_cx := float(coord.x) * size + size * 0.5
	var chunk_cz := float(coord.y) * size + size * 0.5
	var dist := Vector2(float(center.x) - chunk_cx, float(center.y) - chunk_cz).length()
	# Town disk vs chunk AABB (approx half-diagonal of chunk).
	return dist <= radius + size * 0.75


## Test/harness: count standing agents for a town after stream cycles.
func count_town_agents(town_center: Vector2i) -> Dictionary:
	return {
		"villagers": _count_town_role(town_center, &"town_villager"),
		"militia": _count_town_role(town_center, &"town_militia"),
		"defenders_accounted": int(_defenders_by_town.get(town_center, 0)),
	}


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
	_note_entity_removed(entity)
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