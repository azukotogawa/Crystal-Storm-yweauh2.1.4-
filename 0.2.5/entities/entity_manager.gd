class_name EntityManager
extends Node

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")

@export var animals_per_biome_chunk: int = 2
@export var max_entities: int = 128

signal entity_spawned(entity: Node3D)
signal entity_despawned(entity: Node3D)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var _entities: Array[Node3D] = []
var _spawned_cells: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("entity_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")


func seed_spawns() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager and chunk_manager.has_signal("chunk_ready"):
		if not chunk_manager.chunk_ready.is_connected(_on_chunk_ready):
			chunk_manager.chunk_ready.connect(_on_chunk_ready)
	_seed_animal_spawns()
	for coord in chunk_manager.chunks.keys():
		_on_chunk_ready(coord, chunk_manager.chunks[coord].chunk_data)


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


func _on_chunk_ready(coord: Vector2i, _data: ChunkData) -> void:
	if _entities.size() >= max_entities:
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
		_spawn_placeholder_animal(pos, int(spawn.get("animal_kind", 0)))
		_spawned_cells[key] = true


func _spawn_placeholder_animal(world_pos: Vector2i, animal_kind: int) -> void:
	var entity := Node3D.new()
	entity.name = _WorldFeatureTypes.ANIMAL_DISPLAY.get(animal_kind, "Animal")

	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.55
	mesh_instance.mesh = mesh
	mesh_instance.position.y = 0.35

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _animal_color(animal_kind)
	mesh_instance.material_override = mat
	entity.add_child(mesh_instance)

	var surface := 1.0
	if world:
		surface = TerrainRamps.walkable_height(world, float(world_pos.x) + 0.5, float(world_pos.y) + 0.5)
	entity.position = Vector3(float(world_pos.x) + 0.5, surface, float(world_pos.y) + 0.5)
	add_child(entity)
	_entities.append(entity)
	entity_spawned.emit(entity)


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