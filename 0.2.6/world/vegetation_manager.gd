class_name VegetationManager
extends Node

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

@export var grass_density: float = 0.18
@export var tree_density: float = 0.045
@export var bush_density: float = 0.06
@export var scatter_attempts: int = 12000

signal vegetation_registered(world_pos: Vector2i, kind: int)

var world: InfiniteNoiseWorld
var _rng: RandomNumberGenerator


func _enter_tree() -> void:
	add_to_group("vegetation_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	_rng = RandomNumberGenerator.new()


func generate() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	_rng.seed = world.world_seed + 55002
	_scatter_playable_vegetation()


func generate_scatter_async() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	_rng.seed = world.world_seed + 55002
	var half := int(_WorldBorder.PLAYABLE_HALF_X) * 0.85
	var attempts := maxi(scatter_attempts, 0)
	var batch := 0
	const BATCH_SIZE := 200
	for _i in attempts:
		var wx := _rng.randi_range(int(-half), int(half))
		var wz := _rng.randi_range(int(-half), int(half))
		if not _WorldBorder.is_playable(float(wx), float(wz)):
			continue
		var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
		if feat.has("kind") and int(feat.get("kind", 0)) == _WorldFeatureTypes.FeatureKind.TOWN:
			continue
		_try_place_vegetation(wx, wz)
		batch += 1
		if batch >= BATCH_SIZE:
			batch = 0
			await get_tree().process_frame


func _scatter_playable_vegetation() -> void:
	var half := int(_WorldBorder.PLAYABLE_HALF_X) * 0.85
	for _i in scatter_attempts:
		var wx := _rng.randi_range(int(-half), int(half))
		var wz := _rng.randi_range(int(-half), int(half))
		if not _WorldBorder.is_playable(float(wx), float(wz)):
			continue
		var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
		if feat.has("kind") and int(feat.get("kind", 0)) == _WorldFeatureTypes.FeatureKind.TOWN:
			continue
		_try_place_vegetation(wx, wz)


func _try_place_vegetation(wx: int, wz: int) -> void:
	if world == null:
		return
	var tile := world.get_tile_type(float(wx), float(wz))
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER or tile == VoxelTypes.STONE:
		return

	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	var biome_name: String = biome.get("name", "plains")
	var moist: float = biome.get("moist", 0.5)

	var bucket := _hash(wx, wz) % 1000
	var forest_bias := 1.0
	if biome_name == "forest":
		forest_bias = 1.8
	elif biome_name == "marsh":
		forest_bias = 0.35
	elif biome_name == "steppe":
		forest_bias = 0.55

	if float(bucket) / 1000.0 < tree_density * forest_bias:
		_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.TREE_TRUNK)
		_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.TREE, {
			"biome": biome_name,
			"plant_id": "tree",
			"growth_stage": 2,
			"growth_progress": 1.0,
		})
		vegetation_registered.emit(Vector2i(wx, wz), _WorldFeatureTypes.FeatureKind.TREE)
		return

	if float(bucket % 997) / 997.0 < bush_density * moist:
		_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.BUSH)
		_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.BUSH, {
			"plant_id": "bush",
			"growth_stage": 2,
			"growth_progress": 1.0,
		})
		vegetation_registered.emit(Vector2i(wx, wz), _WorldFeatureTypes.FeatureKind.BUSH)
		return

	if float(bucket % 983) / 983.0 < grass_density:
		_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.GRASS_TUFT)
		_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.GRASS_PATCH, {
			"plant_id": "grass_tuft",
			"growth_stage": 1,
			"growth_progress": 1.0,
		})
		vegetation_registered.emit(Vector2i(wx, wz), _WorldFeatureTypes.FeatureKind.GRASS_PATCH)


func _hash(wx: int, wz: int) -> int:
	return absi(wx * 92837111 ^ wz * 689287499 ^ world.world_seed)