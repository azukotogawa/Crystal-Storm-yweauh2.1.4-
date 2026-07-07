class_name TerrainEdits
extends RefCounted

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

static var _height_delta: Dictionary = {}  # Vector2i -> int
static var _build_tile: Dictionary = {}  # Vector2i -> int (VoxelTypes id)


static func reset() -> void:
	_height_delta.clear()
	_build_tile.clear()


static func get_height_delta(wx: int, wz: int) -> float:
	var layers: int = int(_height_delta.get(Vector2i(wx, wz), 0))
	return float(layers) * _WorldSettings.get_active().layer_height()


static func get_build_tile(wx: int, wz: int) -> int:
	return int(_build_tile.get(Vector2i(wx, wz), -1))


static func can_edit(wx: int, wz: int) -> bool:
	return _WorldBorder.is_playable(float(wx), float(wz))


static func dig(wx: int, wz: int, amount: int = 1) -> bool:
	if not can_edit(wx, wz):
		return false
	var key := Vector2i(wx, wz)
	var next: int = int(_height_delta.get(key, 0)) - amount
	if next < -6:
		return false
	_height_delta[key] = next
	if next == 0 and not _build_tile.has(key):
		_height_delta.erase(key)
	return true


static func build_wall(wx: int, wz: int, tile_id: int) -> bool:
	if not can_edit(wx, wz):
		return false
	var key := Vector2i(wx, wz)
	var next: int = int(_height_delta.get(key, 0)) + 1
	if next > 8:
		return false
	_height_delta[key] = next
	_build_tile[key] = tile_id
	return true


static func edit_count() -> int:
	return _height_delta.size()


static func to_dict() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	return {
		"height_delta": _Codec.encode_vec2i_dict(_height_delta),
		"build_tile": _Codec.encode_vec2i_dict(_build_tile),
	}


static func load_from_dict(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	reset()
	_height_delta = _Codec.decode_vec2i_dict(data.get("height_delta", {}))
	_build_tile = _Codec.decode_vec2i_dict(data.get("build_tile", {}))