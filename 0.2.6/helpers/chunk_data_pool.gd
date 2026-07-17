class_name ChunkDataPool
extends RefCounted
## Reuse ChunkData shells for stream loads (terrain-edit reuse path unchanged).


const MAX_POOL_SIZE := 24

static var _pool: Array = []
static var _alloc_new_count: int = 0
static var _alloc_reuse_count: int = 0
static var _release_count: int = 0


static func reset_stats() -> void:
	_alloc_new_count = 0
	_alloc_reuse_count = 0
	_release_count = 0


static func acquire(coord: Vector2i, world: InfiniteNoiseWorld) -> ChunkData:
	if _pool.is_empty():
		_alloc_new_count += 1
		var fresh: ChunkData = ChunkData.new(coord, world)
		if fresh.is_macro_terrain_enabled():
			fresh.prewarm_macro_storage()
		return fresh
	_alloc_reuse_count += 1
	var data: ChunkData = _pool.pop_back()
	data.prepare_for_reuse(coord, world)
	if data.is_macro_terrain_enabled():
		data.prewarm_macro_storage()
	return data


static func release(data: ChunkData) -> void:
	if data == null:
		return
	data.world = null
	_release_count += 1
	if _pool.size() < MAX_POOL_SIZE:
		_pool.append(data)


static func clear() -> void:
	_pool.clear()


static func get_stats() -> Dictionary:
	return {
		"alloc_new": _alloc_new_count,
		"alloc_reuse": _alloc_reuse_count,
		"release_count": _release_count,
		"pool_size": _pool.size(),
	}