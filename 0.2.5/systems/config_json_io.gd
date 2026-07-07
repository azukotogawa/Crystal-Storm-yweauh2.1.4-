class_name ConfigJsonIO
extends RefCounted

const _GameConfig = preload("res://config/game_config.gd")
const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CombatDef = preload("res://config/combat_def.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")

const DEFAULT_EXPORT_PATH := "user://crystal_storm_config.json"


static func export_game_config(cfg, path: String = DEFAULT_EXPORT_PATH) -> Error:
	if cfg == null:
		return ERR_INVALID_PARAMETER
	var data := _serialize_game_config(cfg)
	var json := JSON.stringify(data, "\t")
	return _write_text(path, json)


static func import_game_config(path: String = DEFAULT_EXPORT_PATH):
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return null
	return _deserialize_game_config(parsed)


static func _serialize_game_config(cfg) -> Dictionary:
	cfg.ensure_defaults()
	return {
		"version": 1,
		"assault_distance": cfg.assault_distance,
		"maze_min_distance": cfg.maze_min_distance,
		"crystal_damage_per_second": cfg.crystal_damage_per_second,
		"town_fall_depth": cfg.town_fall_depth,
		"world_gen": _resource_to_dict(cfg.world_gen),
		"crystal_sim": _resource_to_dict(cfg.crystal_sim),
		"combat": _resource_to_dict(cfg.combat),
		"spawn_points": _resource_array_to_dicts(cfg.spawn_points),
		"performance": _resource_to_dict(cfg.performance),
	}


static func _deserialize_game_config(data: Dictionary):
	var cfg = _GameConfig.create_default()
	cfg.assault_distance = float(data.get("assault_distance", cfg.assault_distance))
	cfg.maze_min_distance = float(data.get("maze_min_distance", cfg.maze_min_distance))
	cfg.crystal_damage_per_second = float(data.get("crystal_damage_per_second", cfg.crystal_damage_per_second))
	cfg.town_fall_depth = float(data.get("town_fall_depth", cfg.town_fall_depth))
	var wg_data: Dictionary = data.get("world_gen", {})
	var cs_data: Dictionary = data.get("crystal_sim", {})
	if not wg_data.is_empty():
		cfg.world_gen = _dict_to_resource(_WorldGenConfig.create_default(), wg_data)
	if not cs_data.is_empty():
		cfg.crystal_sim = _dict_to_resource(_CrystalSimConfig.create_default(), cs_data)
	var combat_data: Dictionary = data.get("combat", {})
	if not combat_data.is_empty():
		cfg.combat = _dict_to_resource(_CombatDef.create_default(), combat_data)
	var spawn_rows: Array = data.get("spawn_points", [])
	if not spawn_rows.is_empty():
		cfg.spawn_points = _dicts_to_resource_array(spawn_rows, _SpawnPointDef.new())
	var perf_data: Dictionary = data.get("performance", {})
	if not perf_data.is_empty():
		cfg.performance = _dict_to_resource(_PerformanceQualityConfig.create_default(), perf_data)
	return cfg


static func _resource_array_to_dicts(arr: Array) -> Array:
	var out: Array = []
	for item in arr:
		if item is Resource:
			out.append(_resource_to_dict(item))
	return out


static func _dicts_to_resource_array(rows: Array, template: Resource) -> Array:
	var out: Array = []
	for row in rows:
		if row is Dictionary:
			out.append(_dict_to_resource(template.duplicate(true), row))
	return out


static func _resource_to_dict(res: Resource) -> Dictionary:
	if res == null:
		return {}
	var out := {}
	for prop in res.get_property_list():
		if prop.name.begins_with("_"):
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if prop.name == "resource_path" or prop.name == "resource_name":
			continue
		var val = res.get(prop.name)
		if val is PackedFloat32Array:
			out[prop.name] = Array(val)
		elif typeof(val) in [TYPE_DICTIONARY, TYPE_ARRAY, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			out[prop.name] = val
	return out


static func _dict_to_resource(template: Resource, data: Dictionary) -> Resource:
	var res := template.duplicate(true)
	for key in data.keys():
		if res.get(key) == null and not _has_property(res, key):
			continue
		var val = data[key]
		if val is Array and res.get(key) is PackedFloat32Array:
			res.set(key, PackedFloat32Array(val))
		else:
			res.set(key, val)
	return res


static func _has_property(res: Resource, key: String) -> bool:
	for prop in res.get_property_list():
		if prop.name == key:
			return true
	return false


static func _write_text(path: String, text: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	return OK