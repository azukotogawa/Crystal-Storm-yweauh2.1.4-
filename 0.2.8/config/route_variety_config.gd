class_name RouteVarietyConfig
extends Resource

const RESOURCE_PATH := "res://config/default_route_variety.tres"

@export var enabled: bool = true
@export var hill_layers: float = 0.85
@export var hill_wavelength: float = 20.0
@export var band_radius: float = 18.0
@export var fade_columns: float = 8.0
@export var path_radius: float = 0.86
@export var shoulder_radius: float = 2.6
@export var path_tile: int = 49
@export var shoulder_tiles: PackedInt32Array = PackedInt32Array([41, 42, 9, 10, 25, 34, 11])
@export var link_columns: float = 72.0
@export var max_links: int = 36
@export var long_walk_cap: float = 1500.0
@export var spawn_clear: float = 28.0
@export var prop_spacing: float = 9.0
@export var prop_near: float = 2.8
@export var prop_far: float = 5.4
@export var props_per_chunk: int = 4
@export var prop_kinds: PackedStringArray = PackedStringArray(["rock", "bush", "flower", "log", "mushroom", "bush", "flower", "rock"])


static func load_default():
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded = load(RESOURCE_PATH)
		if loaded != null:
			return loaded
	return (load("res://config/route_variety_config.gd") as GDScript).new()
