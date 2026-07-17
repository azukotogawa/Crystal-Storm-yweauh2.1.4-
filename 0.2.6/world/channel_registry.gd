class_name ChannelRegistry
extends RefCounted
## Compatibility façade over WorldState channel overlay storage.

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldState = preload("res://world/world_state.gd")

## Player-dug water channels: per-cell water level and preferred flow direction.


static func _ws():
	return _WorldState.get_active()


static func reset() -> void:
	_ws().reset_channels()


static func is_channel(wx: int, wz: int) -> bool:
	return _ws().channels.has(Vector2i(wx, wz))


static func get_channel(wx: int, wz: int) -> Dictionary:
	return _ws().channels.get(Vector2i(wx, wz), {})


static func get_water_level(wx: int, wz: int) -> float:
	var entry: Dictionary = get_channel(wx, wz)
	return float(entry.get("water_level", 0.0))


static func get_flow_dir(wx: int, wz: int) -> Vector2i:
	var entry: Dictionary = get_channel(wx, wz)
	return entry.get("flow_dir", Vector2i.ZERO)


static func register_channel(
	wx: int,
	wz: int,
	flow_dir: Vector2i,
	water_level: float = 0.5
) -> void:
	var ws = _ws()
	ws.channels[Vector2i(wx, wz)] = {
		"water_level": clampf(water_level, 0.05, 1.0),
		"flow_dir": _normalize_cardinal(flow_dir),
	}
	ws.bump(_WorldState.DOMAIN_CHANNEL)


static func set_water_level(wx: int, wz: int, level: float) -> float:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	if not ws.channels.has(key):
		return 0.0
	var entry: Dictionary = ws.channels[key]
	var clamped := clampf(level, 0.05, 1.0)
	entry["water_level"] = clamped
	ws.channels[key] = entry
	ws.bump(_WorldState.DOMAIN_CHANNEL)
	return clamped


static func adjust_water_level(wx: int, wz: int, delta: float) -> float:
	var current := get_water_level(wx, wz)
	if current <= 0.0 and not is_channel(wx, wz):
		return 0.0
	return set_water_level(wx, wz, current + delta)


static func set_flow_dir(wx: int, wz: int, flow_dir: Vector2i) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	if not ws.channels.has(key):
		return
	var entry: Dictionary = ws.channels[key]
	entry["flow_dir"] = _normalize_cardinal(flow_dir)
	ws.channels[key] = entry
	ws.bump(_WorldState.DOMAIN_CHANNEL)


static func all_positions() -> Array:
	return _ws().channels.keys()


static func unregister_channel(wx: int, wz: int) -> void:
	var ws = _ws()
	ws.channels.erase(Vector2i(wx, wz))
	ws.bump(_WorldState.DOMAIN_CHANNEL)


static func tick_equilibrium(
	world,
	sim_config,
	delta: float
) -> void:
	var ws = _ws()
	if ws.channels.is_empty() or world == null or sim_config == null:
		return

	var rate: float = float(sim_config.channel_equilibrate_rate) * delta
	if rate <= 0.0:
		return

	var pending: Dictionary = {}
	for key_variant in ws.channels.keys():
		var key: Vector2i = key_variant
		var entry: Dictionary = ws.channels[key]
		var level: float = float(entry.get("water_level", 0.5))
		var flow_dir: Vector2i = entry.get("flow_dir", Vector2i.ZERO)
		var my_h: float = _surface_height(world, key.x, key.y)

		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var neighbor: Vector2i = key + dir
			var n_h: float = _surface_height(world, neighbor.x, neighbor.y)
			var downhill: float = my_h - n_h
			if downhill <= 0.02:
				continue

			var n_level: float = get_water_level(neighbor.x, neighbor.y)
			if not is_channel(neighbor.x, neighbor.y):
				if _is_water_tile(world, neighbor):
					n_level = 1.0
				else:
					continue

			var bias := 1.0
			if flow_dir != Vector2i.ZERO:
				bias = sim_config.channel_along_flow_mult if dir == flow_dir else sim_config.channel_cross_flow_mult

			var transfer: float = minf(
				level * rate * bias,
				downhill * 0.08 * rate * 10.0
			)
			if transfer < 0.001:
				continue
			pending[key] = float(pending.get(key, 0.0)) - transfer
			pending[neighbor] = float(pending.get(neighbor, 0.0)) + transfer * 0.85

	if pending.is_empty():
		return

	ws.begin_batch()
	for key_variant in pending.keys():
		var key: Vector2i = key_variant
		if not ws.channels.has(key):
			if float(pending[key]) > 0.0:
				ws.channels[key] = {
					"water_level": clampf(float(pending[key]), 0.05, 1.0),
					"flow_dir": Vector2i.ZERO,
				}
				ws.bump(_WorldState.DOMAIN_CHANNEL)
			continue
		var entry: Dictionary = ws.channels[key]
		entry["water_level"] = clampf(
			float(entry.get("water_level", 0.5)) + float(pending[key]),
			0.05,
			1.0
		)
		ws.channels[key] = entry
		ws.bump(_WorldState.DOMAIN_CHANNEL)
	ws.end_batch()


static func compute_downhill_dir(world, wx: int, wz: int) -> Vector2i:
	if world == null:
		return Vector2i(0, 1)
	var my_h: float = _surface_height(world, wx, wz)
	var best_dir := Vector2i.ZERO
	var best_drop := 0.0
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n_h: float = _surface_height(world, wx + dir.x, wz + dir.y)
		var drop: float = my_h - n_h
		if drop > best_drop + 0.02:
			best_drop = drop
			best_dir = dir
	return best_dir


static func cardinal_from_vector(v: Vector3) -> Vector2i:
	if absf(v.x) >= absf(v.z):
		return Vector2i(signi(roundi(v.x)), 0)
	return Vector2i(0, signi(roundi(v.z)))


static func _surface_height(world, wx: int, wz: int) -> float:
	return world.get_surface_height(float(wx), float(wz))


static func _is_water_tile(world, pos: Vector2i) -> bool:
	var tile: int = world.get_tile_type(float(pos.x), float(pos.y))
	return _CrystalTypes.is_water_tile(tile)


static func _normalize_cardinal(dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return Vector2i.ZERO
	if absf(dir.x) >= absf(dir.y):
		return Vector2i(signi(dir.x), 0)
	return Vector2i(0, signi(dir.y))


static func to_dict() -> Dictionary:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	var encoded := {}
	for key_variant in ws.channels.keys():
		var key: Vector2i = key_variant
		var entry: Dictionary = ws.channels[key]
		var flow_dir: Vector2i = entry.get("flow_dir", Vector2i.ZERO)
		encoded[_Codec.vec2i_key(key)] = {
			"water_level": float(entry.get("water_level", 0.5)),
			"flow_dir": [flow_dir.x, flow_dir.y],
		}
	return {"channels": encoded}


static func load_from_dict(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	var ws = _ws()
	ws.begin_batch()
	ws.channels.clear()
	var channels: Dictionary = data.get("channels", {})
	for key in channels.keys():
		var entry: Dictionary = channels[key]
		var flow_arr: Array = entry.get("flow_dir", [0, 0])
		var flow_dir := Vector2i(int(flow_arr[0]), int(flow_arr[1]))
		var cell := _Codec.vec2i_from_key(str(key))
		ws.channels[cell] = {
			"water_level": clampf(float(entry.get("water_level", 0.5)), 0.05, 1.0),
			"flow_dir": _normalize_cardinal(flow_dir),
		}
		ws.bump(_WorldState.DOMAIN_CHANNEL)
	ws.end_batch()
