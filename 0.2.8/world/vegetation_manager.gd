class_name VegetationManager
extends Node

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

@export var grass_density: float = 0.68
@export var tall_grass_density: float = 0.38
@export var flower_density: float = 0.10
@export var fern_density: float = 0.08
@export var tree_density: float = 0.085
@export var bush_density: float = 0.11
@export var scatter_attempts: int = 18000

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
		_crash_crumb("VegetationManager.generate_scatter_async ABORT world=null")
		return
	_rng.seed = world.world_seed + 55002
	var half := int(_WorldBorder.PLAYABLE_HALF_X) * 0.85
	var attempts := maxi(scatter_attempts, 0)
	var batch := 0
	const BATCH_SIZE := 200
	_crash_crumb(
		"VegetationManager.generate_scatter_async ENTER attempts=%d half=%.0f seed=%d"
		% [attempts, half, int(world.world_seed)]
	)
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
			if _i == BATCH_SIZE or (_i > 0 and _i % 2000 == 0):
				_crash_crumb("VegetationManager.generate_scatter_async progress i=%d/%d" % [_i, attempts])
			await get_tree().process_frame
	_crash_crumb("VegetationManager.generate_scatter_async EXIT ok attempts=%d" % attempts)


static func _crash_crumb(msg: String) -> void:
	var line := "[CRASH_CRUMB t=%d] %s" % [Time.get_ticks_msec(), msg]
	print(line)
	var path := "user://startup_last_step.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(line + "\n")
		f.close()


## Offline bake: same placement rules, no FeatureRegistry writes.
## Returns Vector2i world column -> {tile, kind, plant_id, growth_stage, growth_progress, biome}.
## If bounds is provided {min_wx,max_wx,min_wz,max_wz}, scatter is limited to that
## rectangle with attempt count scaled so per-cell density matches full-playable scatter.
static func bake_scatter_map(
	world,
	attempts: int,
	densities: Dictionary = {},
	bounds: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {}
	if world == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.world_seed) + 55002
	var half := int(float(_WorldBorder.PLAYABLE_HALF_X) * 0.85)
	var min_wx: int = -half
	var max_wx: int = half
	var min_wz: int = -half
	var max_wz: int = half
	if not bounds.is_empty():
		min_wx = int(bounds.get("min_wx", min_wx))
		max_wx = int(bounds.get("max_wx", max_wx))
		min_wz = int(bounds.get("min_wz", min_wz))
		max_wz = int(bounds.get("max_wz", max_wz))
	var playable_cells: float = maxf(float((2 * half + 1) * (2 * half + 1)), 1.0)
	var region_w: int = maxi(max_wx - min_wx + 1, 1)
	var region_h: int = maxi(max_wz - min_wz + 1, 1)
	var region_cells: float = float(region_w * region_h)
	# Density parity: E[plants]/cell] ≈ attempts * p / playable_cells.
	var n: int = maxi(attempts, 0)
	if region_cells < playable_cells:
		n = maxi(int(round(float(attempts) * region_cells / playable_cells)), int(region_cells * 0.05))
	var grass_d: float = float(densities.get("grass_density", 0.68))
	var tall_d: float = float(densities.get("tall_grass_density", 0.38))
	var flower_d: float = float(densities.get("flower_density", 0.10))
	var fern_d: float = float(densities.get("fern_density", 0.08))
	var tree_d: float = float(densities.get("tree_density", 0.085))
	var bush_d: float = float(densities.get("bush_density", 0.11))
	var seed: int = int(world.world_seed)
	for _i in n:
		var wx := rng.randi_range(min_wx, max_wx)
		var wz := rng.randi_range(min_wz, max_wz)
		if not _WorldBorder.is_playable(float(wx), float(wz)):
			continue
		var key := Vector2i(wx, wz)
		if out.has(key):
			continue
		var placed: Dictionary = _bake_try_place(
			world, seed, wx, wz, tree_d, bush_d, flower_d, fern_d, tall_d, grass_d
		)
		if not placed.is_empty():
			out[key] = placed
	return out


## Bucket world-map vegetation into per-chunk local entries for package storage.
static func bucket_by_chunk(world_map: Dictionary, cells: int = 16) -> Dictionary:
	var by_chunk: Dictionary = {}  # Vector2i chunk -> Array
	for key_v in world_map.keys():
		var key: Vector2i = key_v
		var entry: Dictionary = world_map[key]
		var cx: int = int(floor(float(key.x) / float(cells)))
		var cz: int = int(floor(float(key.y) / float(cells)))
		var ckey := Vector2i(cx, cz)
		if not by_chunk.has(ckey):
			by_chunk[ckey] = []
		var local: Dictionary = entry.duplicate()
		local["lx"] = key.x - cx * cells
		local["lz"] = key.y - cz * cells
		by_chunk[ckey].append(local)
	return by_chunk


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
	var placed: Dictionary = _bake_try_place(
		world,
		world.world_seed,
		wx,
		wz,
		tree_density,
		bush_density,
		flower_density,
		fern_density,
		tall_grass_density,
		grass_density
	)
	if placed.is_empty():
		return
	var tile_id: int = int(placed.get("tile", -1))
	var kind: int = int(placed.get("kind", 0))
	if tile_id >= 0:
		_FeatureRegistry.set_tile_override(wx, wz, tile_id)
	_FeatureRegistry.register_feature(wx, wz, kind, {
		"biome": str(placed.get("biome", "")),
		"plant_id": str(placed.get("plant_id", "")),
		"growth_stage": int(placed.get("growth_stage", 1)),
		"growth_progress": float(placed.get("growth_progress", 1.0)),
	})
	vegetation_registered.emit(Vector2i(wx, wz), kind)


static func _bake_try_place(
	world,
	seed: int,
	wx: int,
	wz: int,
	tree_d: float,
	bush_d: float,
	flower_d: float,
	fern_d: float,
	tall_d: float,
	grass_d: float
) -> Dictionary:
	var tile: int = int(world.get_tile_type(float(wx), float(wz)))
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER or tile == VoxelTypes.STONE:
		return {}

	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	var biome_name: String = str(biome.get("name", "plains"))
	var moist: float = float(biome.get("moist", 0.5))

	var bucket: int = int(_hash_seed(wx, wz, seed) % 1000)
	var forest_bias: float = 1.0
	if biome_name == "forest":
		forest_bias = 1.8
	elif biome_name == "marsh":
		forest_bias = 0.35
	elif biome_name == "steppe":
		forest_bias = 0.55

	if float(bucket) / 1000.0 < tree_d * forest_bias:
		return {
			"tile": VoxelTypes.TREE_TRUNK,
			"kind": _WorldFeatureTypes.FeatureKind.TREE,
			"biome": biome_name,
			"plant_id": "tree",
			"growth_stage": 2,
			"growth_progress": 1.0,
		}

	if float(bucket % 997) / 997.0 < bush_d * moist:
		return {
			"tile": VoxelTypes.BUSH,
			"kind": _WorldFeatureTypes.FeatureKind.BUSH,
			"plant_id": "bush",
			"growth_stage": 2,
			"growth_progress": 1.0,
			"biome": biome_name,
		}

	var grass_roll: float = float(bucket % 983) / 983.0
	if grass_roll < flower_d and moist > 0.42 and biome_name in ["plains", "forest", "marsh"]:
		return {
			"tile": VoxelTypes.GRASSLAND2,
			"kind": _WorldFeatureTypes.FeatureKind.GRASS_PATCH,
			"plant_id": "wildflower",
			"growth_stage": 1,
			"growth_progress": 1.0,
			"biome": biome_name,
		}

	if grass_roll < flower_d + fern_d and biome_name == "forest":
		return {
			"tile": VoxelTypes.HILLS2,
			"kind": _WorldFeatureTypes.FeatureKind.BUSH,
			"plant_id": "fern",
			"growth_stage": 1,
			"growth_progress": 1.0,
			"biome": biome_name,
		}

	if grass_roll < flower_d + fern_d + tall_d:
		return {
			"tile": VoxelTypes.GRASSLAND3,
			"kind": _WorldFeatureTypes.FeatureKind.GRASS_PATCH,
			"plant_id": "tall_grass",
			"growth_stage": 1,
			"growth_progress": 1.0,
			"biome": biome_name,
		}

	if grass_roll < flower_d + fern_d + tall_d + grass_d:
		return {
			"tile": VoxelTypes.GRASS_TUFT,
			"kind": _WorldFeatureTypes.FeatureKind.GRASS_PATCH,
			"plant_id": "grass_tuft",
			"growth_stage": 1,
			"growth_progress": 1.0,
			"biome": biome_name,
		}
	return {}


func _hash(wx: int, wz: int) -> int:
	return _hash_seed(wx, wz, world.world_seed if world else 0)


static func _hash_seed(wx: int, wz: int, seed: int) -> int:
	return absi(wx * 92837111 ^ wz * 689287499 ^ seed)