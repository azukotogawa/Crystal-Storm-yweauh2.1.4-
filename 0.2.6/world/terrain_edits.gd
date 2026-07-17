class_name TerrainEdits
extends RefCounted
## Compatibility façade over WorldState terrain overlay storage.

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")


static func _ws():
	return _WorldState.get_active()


static func reset() -> void:
	_ws().reset_terrain()


static func get_height_delta(wx: int, wz: int) -> float:
	var layers: int = int(_ws().height_delta.get(Vector2i(wx, wz), 0))
	return float(layers) * _WorldSettings.get_active().layer_height()


static func get_build_tile(wx: int, wz: int) -> int:
	return int(_ws().build_tile.get(Vector2i(wx, wz), -1))


static func can_edit(wx: int, wz: int) -> bool:
	return _WorldBorder.is_playable(float(wx), float(wz))


static func dig(wx: int, wz: int, amount: int = 1) -> bool:
	if not can_edit(wx, wz):
		return false
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var next: int = int(ws.height_delta.get(key, 0)) - amount
	if next < -6:
		return false
	ws.height_delta[key] = next
	if next == 0 and not ws.build_tile.has(key):
		ws.height_delta.erase(key)
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	return true


static func build_wall(wx: int, wz: int, tile_id: int) -> bool:
	if not can_edit(wx, wz):
		return false
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var next: int = int(ws.height_delta.get(key, 0)) + 1
	if next > 8:
		return false
	ws.height_delta[key] = next
	ws.build_tile[key] = tile_id
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	return true


static func edit_count() -> int:
	return _ws().height_delta.size()


static func to_dict() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	return {
		"height_delta": _Codec.encode_vec2i_dict(ws.height_delta),
		"build_tile": _Codec.encode_vec2i_dict(ws.build_tile),
	}


static func load_from_dict(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	ws.begin_batch()
	ws.height_delta = _Codec.decode_vec2i_dict(data.get("height_delta", {}))
	ws.build_tile = _Codec.decode_vec2i_dict(data.get("build_tile", {}))
	ws.bump(_WorldState.DOMAIN_TERRAIN)
	ws.end_batch()
