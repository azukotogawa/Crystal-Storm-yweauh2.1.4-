class_name TexturePaletteJsonIO
extends RefCounted

const _GenConfig = preload("res://config/crystal_texture_gen_config.gd")
const _Palette = preload("res://config/crystal_texture_palette.gd")

const DEFAULT_PATH := "user://texture_palettes.json"


static func export_palettes(cfg, path: String = DEFAULT_PATH) -> Error:
	if cfg == null:
		return ERR_INVALID_PARAMETER
	cfg.ensure_default_palettes()
	var data := {
		"version": 1,
		"master_seed": cfg.master_seed,
		"default_texture_size": cfg.default_texture_size,
		"noise_frequency": cfg.noise_frequency,
		"detail_frequency": cfg.detail_frequency,
		"crystal_palettes": _palette_array_to_dict(cfg.crystal_palettes),
		"biome_palettes": _palette_array_to_dict(cfg.biome_palettes),
		"ore_palettes": _palette_array_to_dict(cfg.ore_palettes),
		"ground_palettes": _palette_array_to_dict(cfg.ground_palettes),
	}
	return write_json(path, data)


static func import_palettes(path: String = DEFAULT_PATH):
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return null
	return _deserialize_config(parsed)


static func write_json(path: String, data: Dictionary) -> Error:
	var json := JSON.stringify(data, "\t")
	return _write_text(path, json)


static func _deserialize_config(data: Dictionary):
	var cfg = _GenConfig.create_default()
	cfg.master_seed = int(data.get("master_seed", cfg.master_seed))
	cfg.default_texture_size = int(data.get("default_texture_size", cfg.default_texture_size))
	cfg.noise_frequency = float(data.get("noise_frequency", cfg.noise_frequency))
	cfg.detail_frequency = float(data.get("detail_frequency", cfg.detail_frequency))
	cfg.crystal_palettes = _dict_to_palette_array(data.get("crystal_palettes", []))
	cfg.biome_palettes = _dict_to_palette_array(data.get("biome_palettes", []))
	cfg.ore_palettes = _dict_to_palette_array(data.get("ore_palettes", []))
	cfg.ground_palettes = _dict_to_palette_array(data.get("ground_palettes", []))
	cfg.ensure_default_palettes()
	return cfg


static func _palette_array_to_dict(arr: Array) -> Array:
	var out: Array = []
	for item in arr:
		if item and item.has_method("to_dict"):
			out.append(item.to_dict())
	return out


static func _dict_to_palette_array(data: Variant) -> Array:
	var out: Array = []
	if not data is Array:
		return out
	for entry in data:
		if entry is Dictionary:
			out.append(_Palette.from_dict(entry))
	return out


static func _write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK