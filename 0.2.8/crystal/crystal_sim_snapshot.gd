class_name CrystalSimSnapshot
extends RefCounted

var tick_id: int = 0
var delta: float = 0.0
var flow_substeps: int = 2
var global_flow_mult: float = 1.0
var emit_weaken_mult: float = 1.0
var spawn_emitters: Array = []
var loaded_chunks: Dictionary = {}
var sim_loaded_chunks_only: bool = true
var chunk_size: int = 16
var terrain = null
var absorption_scan_cells: int = 64
var absorption_scan_offset: int = 0
var grass_absorb_rate: float = 0.15
var bush_absorb_rate: float = 0.12
var tree_absorb_rate: float = 0.08
var farmland_absorb_rate: float = 0.10
var content_pace: float = 1.0
var min_depth: float = 0.04
var spatial_query = null
var ruin_centers: Array = []
var feature_at: Callable = Callable()
var tile_at: Callable = Callable()


func is_cell_active(pos: Vector2i) -> bool:
	const _WorldBorder = preload("res://helpers/world_border.gd")
	if not _WorldBorder.allows_crystal(float(pos.x), float(pos.y)):
		return false
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
