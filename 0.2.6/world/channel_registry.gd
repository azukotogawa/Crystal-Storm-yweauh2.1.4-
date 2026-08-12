class_name ChannelRegistry
extends RefCounted
## Compatibility façade over WorldState channel overlay storage.
## Water is the primary fluid (water_level / flow_dir — save-compatible).
## Extra fluids (e.g. crystal test co-occupancy) live in entry.fluids[id].

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldState = preload("res://world/world_state.gd")

const FLUID_WATER := &"water"
const FLUID_CRYSTAL := &"crystal"

## Player-dug water channels: per-cell water level and preferred flow direction.


static func _ws():
	return _WorldState.get_active()


static func reset() -> void:
	_ws().reset_channels()


static func is_channel(wx: int, wz: int) -> bool:
	return has_fluid(wx, wz, FLUID_WATER)


static func get_channel(wx: int, wz: int) -> Dictionary:
	return _ws().channels.get(Vector2i(wx, wz), {})


static func get_water_level(wx: int, wz: int) -> float:
	return get_fluid_level(wx, wz, FLUID_WATER)


static func get_flow_dir(wx: int, wz: int, fluid_id: StringName = FLUID_WATER) -> Vector2i:
	var entry: Dictionary = get_channel(wx, wz)
	if entry.is_empty():
		return Vector2i.ZERO
	if fluid_id == FLUID_WATER or fluid_id == &"":
		return entry.get("flow_dir", Vector2i.ZERO)
	var fluids: Dictionary = entry.get("fluids", {})
	var sub: Dictionary = fluids.get(fluid_id, {})
	return sub.get("flow_dir", Vector2i.ZERO)


static func register_channel(
	wx: int,
	wz: int,
	flow_dir: Vector2i,
	water_level: float = 0.5
) -> void:
	register_fluid(wx, wz, FLUID_WATER, flow_dir, water_level)


static func set_water_level(wx: int, wz: int, level: float) -> float:
	return set_fluid_level(wx, wz, FLUID_WATER, level)


static func adjust_water_level(wx: int, wz: int, delta: float) -> float:
	var current := get_water_level(wx, wz)
	if current <= 0.0 and not is_channel(wx, wz):
		return 0.0
	return set_water_level(wx, wz, current + delta)


static func set_flow_dir(wx: int, wz: int, flow_dir: Vector2i, fluid_id: StringName = FLUID_WATER) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	if not ws.channels.has(key):
		return
	var entry: Dictionary = ws.channels[key]
	if fluid_id == FLUID_WATER or fluid_id == &"":
		entry["flow_dir"] = _normalize_cardinal(flow_dir)
	else:
		var fluids: Dictionary = entry.get("fluids", {})
		var sub: Dictionary = fluids.get(fluid_id, {"level": 0.05, "flow_dir": Vector2i.ZERO})
		sub["flow_dir"] = _normalize_cardinal(flow_dir)
		fluids[fluid_id] = sub
		entry["fluids"] = fluids
	ws.channels[key] = entry
	ws.bump(_WorldState.DOMAIN_CHANNEL)


static func all_positions() -> Array:
	return all_fluid_positions(FLUID_WATER)


static func unregister_channel(wx: int, wz: int) -> void:
	unregister_fluid(wx, wz, FLUID_WATER)


# --- Multi-fluid API (water primary; extras in entry.fluids) -----------------

static func has_fluid(wx: int, wz: int, fluid_id: StringName) -> bool:
	var entry: Dictionary = get_channel(wx, wz)
	if entry.is_empty():
		return false
	if fluid_id == FLUID_WATER:
		return entry.has("water_level") and float(entry.get("water_level", 0.0)) >= 0.05
	var fluids: Dictionary = entry.get("fluids", {})
	return fluids.has(fluid_id)


static func get_fluid_level(wx: int, wz: int, fluid_id: StringName) -> float:
	var entry: Dictionary = get_channel(wx, wz)
	if entry.is_empty():
		return 0.0
	if fluid_id == FLUID_WATER:
		return float(entry.get("water_level", 0.0))
	var fluids: Dictionary = entry.get("fluids", {})
	var sub: Dictionary = fluids.get(fluid_id, {})
	return float(sub.get("level", 0.0))


static func set_fluid_level(wx: int, wz: int, fluid_id: StringName, level: float) -> float:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var clamped := clampf(level, 0.05, 1.0)
	if fluid_id == FLUID_WATER:
		if not ws.channels.has(key):
			return 0.0
		var entry: Dictionary = ws.channels[key]
		entry["water_level"] = clamped
		ws.channels[key] = entry
		ws.bump(_WorldState.DOMAIN_CHANNEL)
		return clamped
	if not ws.channels.has(key):
		# Extra fluids may co-occupy; home entry without water until water is registered.
		ws.channels[key] = {
			"flow_dir": Vector2i.ZERO,
			"fluids": {},
		}
	var entry2: Dictionary = ws.channels[key]
	var fluids2: Dictionary = entry2.get("fluids", {})
	var sub2: Dictionary = fluids2.get(fluid_id, {"level": clamped, "flow_dir": Vector2i.ZERO})
	sub2["level"] = clamped
	fluids2[fluid_id] = sub2
	entry2["fluids"] = fluids2
	ws.channels[key] = entry2
	ws.bump(_WorldState.DOMAIN_CHANNEL)
	return clamped


static func register_fluid(
	wx: int,
	wz: int,
	fluid_id: StringName,
	flow_dir: Vector2i,
	level: float = 0.5
) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	var clamped := clampf(level, 0.05, 1.0)
	var dir := _normalize_cardinal(flow_dir)
	if fluid_id == FLUID_WATER:
		var existing: Dictionary = ws.channels.get(key, {})
		var fluids: Dictionary = existing.get("fluids", {})
		ws.channels[key] = {
			"water_level": clamped,
			"flow_dir": dir,
			"fluids": fluids,
		}
		ws.bump(_WorldState.DOMAIN_CHANNEL)
		return
	var entry: Dictionary = ws.channels.get(key, {
		"flow_dir": Vector2i.ZERO,
		"fluids": {},
	})
	var fluids2: Dictionary = entry.get("fluids", {})
	fluids2[fluid_id] = {"level": clamped, "flow_dir": dir}
	entry["fluids"] = fluids2
	if not entry.has("flow_dir"):
		entry["flow_dir"] = Vector2i.ZERO
	ws.channels[key] = entry
	ws.bump(_WorldState.DOMAIN_CHANNEL)


static func unregister_fluid(wx: int, wz: int, fluid_id: StringName) -> void:
	var ws = _ws()
	var key := Vector2i(wx, wz)
	if not ws.channels.has(key):
		return
	var entry: Dictionary = ws.channels[key]
	if fluid_id == FLUID_WATER:
		var fluids: Dictionary = entry.get("fluids", {})
		if fluids.is_empty():
			ws.channels.erase(key)
		else:
			# Keep cell for co-occupying fluids; drop water presence.
			entry.erase("water_level")
			entry["flow_dir"] = Vector2i.ZERO
			ws.channels[key] = entry
		ws.bump(_WorldState.DOMAIN_CHANNEL)
		return
	var fluids2: Dictionary = entry.get("fluids", {})
	fluids2.erase(fluid_id)
	if fluids2.is_empty() and float(entry.get("water_level", 0.0)) < 0.05 and not entry.has("water_level"):
		ws.channels.erase(key)
	elif fluids2.is_empty() and not entry.has("water_level"):
		ws.channels.erase(key)
	else:
		entry["fluids"] = fluids2
		ws.channels[key] = entry
	ws.bump(_WorldState.DOMAIN_CHANNEL)


static func all_fluid_positions(fluid_id: StringName) -> Array:
	var out: Array = []
	for key_variant in _ws().channels.keys():
		var key: Vector2i = key_variant
		if has_fluid(key.x, key.y, fluid_id):
			out.append(key)
	return out


## Load registry water into a VoxelFluidEngine depth map (subset leave to caller).
static func sync_depth_from_engine(engine) -> void:
	if engine == null:
		return
	for key_variant in all_fluid_positions(FLUID_WATER):
		var key: Vector2i = key_variant
		var level: float = get_fluid_level(key.x, key.y, FLUID_WATER)
		if level >= 0.05:
			engine.depth[key] = level


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
		if not has_fluid(key.x, key.y, FLUID_WATER):
			continue
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
		if not ws.channels.has(key) or not has_fluid(key.x, key.y, FLUID_WATER):
			if float(pending[key]) > 0.0:
				register_fluid(key.x, key.y, FLUID_WATER, Vector2i.ZERO, float(pending[key]))
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
		# Persist primary water only (runtime extras are re-derived / non-authoritative).
		if not has_fluid(key.x, key.y, FLUID_WATER):
			continue
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
