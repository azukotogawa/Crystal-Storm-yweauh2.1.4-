class_name ChannelRegistry
extends RefCounted

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")

const FLUID_WATER := &"water"
const FLUID_CRYSTAL := &"crystal"

## Per-cell channel metadata: fluids map + legacy flow_dir at root when single-fluid.

static var _channels: Dictionary = {}


static func reset() -> void:
	_channels.clear()


static func is_channel(wx: int, wz: int) -> bool:
	return _channels.has(Vector2i(wx, wz))


static func has_fluid(wx: int, wz: int, fluid_id: StringName = FLUID_WATER) -> bool:
	var entry: Dictionary = get_channel(wx, wz)
	var fluids: Dictionary = entry.get("fluids", {})
	return fluids.has(fluid_id)


static func get_channel(wx: int, wz: int) -> Dictionary:
	return _channels.get(Vector2i(wx, wz), {})


static func get_fluid_level(wx: int, wz: int, fluid_id: StringName = FLUID_WATER) -> float:
	var entry: Dictionary = get_channel(wx, wz)
	var fluids: Dictionary = entry.get("fluids", {})
	if fluids.has(fluid_id):
		return float(fluids[fluid_id].get("level", 0.0))
	if fluid_id == FLUID_WATER:
		return float(entry.get("water_level", 0.0))
	return 0.0


static func get_water_level(wx: int, wz: int) -> float:
	return get_fluid_level(wx, wz, FLUID_WATER)


static func get_flow_dir(wx: int, wz: int, fluid_id: StringName = FLUID_WATER) -> Vector2i:
	var entry: Dictionary = get_channel(wx, wz)
	var fluids: Dictionary = entry.get("fluids", {})
	if fluids.has(fluid_id):
		return fluids[fluid_id].get("flow_dir", Vector2i.ZERO)
	return entry.get("flow_dir", Vector2i.ZERO)


static func register_fluid(
	wx: int,
	wz: int,
	fluid_id: StringName,
	flow_dir: Vector2i,
	level: float
) -> void:
	var key := Vector2i(wx, wz)
	var entry: Dictionary = _channels.get(key, {})
	var fluids: Dictionary = entry.get("fluids", {})
	fluids[fluid_id] = {
		"level": clampf(level, 0.05, 1.0),
		"flow_dir": _normalize_cardinal(flow_dir),
	}
	entry["fluids"] = fluids
	if fluid_id == FLUID_WATER:
		entry["water_level"] = fluids[fluid_id]["level"]
		entry["flow_dir"] = fluids[fluid_id]["flow_dir"]
	_channels[key] = entry


static func register_channel(
	wx: int,
	wz: int,
	flow_dir: Vector2i,
	water_level: float = 0.5
) -> void:
	register_fluid(wx, wz, FLUID_WATER, flow_dir, water_level)


static func set_fluid_level(wx: int, wz: int, fluid_id: StringName, level: float) -> float:
	var key := Vector2i(wx, wz)
	if not _channels.has(key):
		return 0.0
	var entry: Dictionary = _channels[key]
	var fluids: Dictionary = entry.get("fluids", {})
	if not fluids.has(fluid_id):
		fluids[fluid_id] = {"level": 0.5, "flow_dir": Vector2i.ZERO}
	var clamped := clampf(level, 0.0, 1.0)
	fluids[fluid_id]["level"] = clamped if clamped >= 0.05 else 0.0
	entry["fluids"] = fluids
	if fluid_id == FLUID_WATER:
		entry["water_level"] = fluids[fluid_id]["level"]
	if fluids[fluid_id]["level"] < 0.05:
		fluids.erase(fluid_id)
		if fluids.is_empty():
			_channels.erase(key)
		else:
			_channels[key] = entry
		return 0.0
	_channels[key] = entry
	return clamped


static func set_water_level(wx: int, wz: int, level: float) -> float:
	return set_fluid_level(wx, wz, FLUID_WATER, level)


static func adjust_fluid_level(wx: int, wz: int, fluid_id: StringName, delta: float) -> float:
	var current := get_fluid_level(wx, wz, fluid_id)
	if current <= 0.0 and not has_fluid(wx, wz, fluid_id):
		return 0.0
	return set_fluid_level(wx, wz, fluid_id, current + delta)


static func adjust_water_level(wx: int, wz: int, delta: float) -> float:
	return adjust_fluid_level(wx, wz, FLUID_WATER, delta)


static func set_flow_dir(wx: int, wz: int, flow_dir: Vector2i, fluid_id: StringName = FLUID_WATER) -> void:
	var key := Vector2i(wx, wz)
	if not _channels.has(key):
		return
	var entry: Dictionary = _channels[key]
	var fluids: Dictionary = entry.get("fluids", {})
	if fluids.has(fluid_id):
		fluids[fluid_id]["flow_dir"] = _normalize_cardinal(flow_dir)
		entry["fluids"] = fluids
	if fluid_id == FLUID_WATER:
		entry["flow_dir"] = _normalize_cardinal(flow_dir)
	_channels[key] = entry


static func unregister_fluid(wx: int, wz: int, fluid_id: StringName) -> void:
	var key := Vector2i(wx, wz)
	if not _channels.has(key):
		return
	var entry: Dictionary = _channels[key]
	var fluids: Dictionary = entry.get("fluids", {})
	fluids.erase(fluid_id)
	if fluids.is_empty():
		_channels.erase(key)
	else:
		entry["fluids"] = fluids
		_channels[key] = entry


static func all_positions() -> Array:
	return _channels.keys()


static func all_fluid_positions(fluid_id: StringName = FLUID_WATER) -> Array:
	var out: Array = []
	for key_variant in _channels.keys():
		var key: Vector2i = key_variant
		if has_fluid(key.x, key.y, fluid_id):
			out.append(key)
	return out


static func unregister_channel(wx: int, wz: int) -> void:
	unregister_fluid(wx, wz, FLUID_WATER)


static func sync_depth_from_engine(engine, fluid_id: StringName = FLUID_WATER) -> void:
	if engine == null:
		return
	for key_variant in _channels.keys():
		var key: Vector2i = key_variant
		if not has_fluid(key.x, key.y, fluid_id):
			continue
		engine.depth[key] = get_fluid_level(key.x, key.y, fluid_id)
	for pos_variant in engine.depth.keys():
		var pos: Vector2i = pos_variant
		if not is_channel(pos.x, pos.y):
			continue
		set_fluid_level(pos.x, pos.y, fluid_id, float(engine.depth[pos]))


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
	var encoded := {}
	for key_variant in _channels.keys():
		var key: Vector2i = key_variant
		var entry: Dictionary = _channels[key]
		var fluids_out: Dictionary = {}
		var fluids: Dictionary = entry.get("fluids", {})
		for fluid_key in fluids.keys():
			var f_entry: Dictionary = fluids[fluid_key]
			var flow_dir: Vector2i = f_entry.get("flow_dir", Vector2i.ZERO)
			fluids_out[str(fluid_key)] = {
				"level": float(f_entry.get("level", 0.5)),
				"flow_dir": [flow_dir.x, flow_dir.y],
			}
		if fluids_out.is_empty() and entry.has("water_level"):
			var legacy_dir: Vector2i = entry.get("flow_dir", Vector2i.ZERO)
			fluids_out["water"] = {
				"level": float(entry.get("water_level", 0.5)),
				"flow_dir": [legacy_dir.x, legacy_dir.y],
			}
		encoded[_Codec.vec2i_key(key)] = {"fluids": fluids_out}
	return {"channels": encoded}


static func load_from_dict(data: Dictionary) -> void:
	const _Codec = preload("res://systems/save_codec.gd")
	reset()
	var channels: Dictionary = data.get("channels", {})
	for key in channels.keys():
		var entry: Dictionary = channels[key]
		var cell := _Codec.vec2i_from_key(str(key))
		if entry.has("fluids"):
			for fluid_key in entry["fluids"].keys():
				var f_entry: Dictionary = entry["fluids"][fluid_key]
				var flow_arr: Array = f_entry.get("flow_dir", [0, 0])
				var flow_dir := Vector2i(int(flow_arr[0]), int(flow_arr[1]))
				register_fluid(
					cell.x, cell.y, StringName(str(fluid_key)), flow_dir,
					float(f_entry.get("level", 0.5))
				)
		else:
			var flow_arr: Array = entry.get("flow_dir", [0, 0])
			var flow_dir := Vector2i(int(flow_arr[0]), int(flow_arr[1]))
			register_channel(cell.x, cell.y, flow_dir, float(entry.get("water_level", 0.5)))