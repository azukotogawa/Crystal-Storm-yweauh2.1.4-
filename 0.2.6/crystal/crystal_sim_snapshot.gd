class_name CrystalSimSnapshot
extends RefCounted
## Immutable-ish per-tick inputs for CrystalSimulation.
## Built by the gameplay façade from WorldState/SpatialQuery/world bindings — never by the sim via the scene tree.

var tick_id: int = 0
var delta: float = 0.0
var flow_substeps: int = 2
var global_flow_mult: float = 1.0
var emit_weaken_mult: float = 1.0
## Array of Dictionaries: { id, world_pos: Vector2i, emit_rate, active }
var spawn_emitters: Array = []
## Optional: set of loaded chunk coords (Vector2i -> true). Empty = all cells active.
var loaded_chunks: Dictionary = {}
var sim_loaded_chunks_only: bool = true
var chunk_size: int = 16
## World-gen / overlay terrain accessor already prepared by façade (no tree).
var terrain = null  # CrystalTerrainQuery
## Feature/animal/ruin absorption inputs (read-only maps for this tick).
var absorption_scan_cells: int = 64
var absorption_scan_offset: int = 0
## Plant absorption rates by tile (from config) — pure data.
var grass_absorb_rate: float = 0.15
var bush_absorb_rate: float = 0.12
var tree_absorb_rate: float = 0.08
var farmland_absorb_rate: float = 0.10
var min_depth: float = 0.04
## Optional SpatialQuery layer handle for discovery (read-only); may be null.
var spatial_query = null
## Ruin centers as Array[Vector2i] snapshot for this tick.
var ruin_centers: Array = []
## Feature lookup provided as Callable(wx, wz) -> Dictionary (no tree).
var feature_at: Callable = Callable()
## Tile lookup override: Callable(pos) -> int when terrain.world unavailable in tests.
var tile_at: Callable = Callable()


func is_cell_active(pos: Vector2i) -> bool:
	if not sim_loaded_chunks_only or loaded_chunks.is_empty():
		return true
	var coord := Vector2i(
		floori(float(pos.x) / float(chunk_size)),
		floori(float(pos.y) / float(chunk_size))
	)
	return loaded_chunks.has(coord)


func get_feature(wx: int, wz: int) -> Dictionary:
	if feature_at.is_valid():
		var f = feature_at.call(wx, wz)
		if f is Dictionary:
			return f
	return {}


func get_tile(pos: Vector2i) -> int:
	if tile_at.is_valid():
		return int(tile_at.call(pos))
	if terrain and terrain.has_method("get_tile"):
		return int(terrain.get_tile(pos))
	return 0
