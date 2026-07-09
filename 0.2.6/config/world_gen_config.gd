class_name WorldGenConfig
extends Resource

@export_group("Seed & Theme")
@export var default_seed: int = 12349
@export var temperature_roll_seed_offset: int = 777

@export_group("Scale & Relief")
@export var biome_scale: float = 920.0
@export var mountain_freq: float = 1.0
@export var detail_freq: float = 4.5
@export var max_height: float = 158.0
@export var sea_level: float = 38.0
@export var mountain_height_boost: float = 78.0

@export_group("Rivers")
@export var river_target_prevalence: float = 0.16
@export var river_freq_base: float = 0.068
@export var river_scale_factor: float = 2.9
@export var river_core_power: float = 1.95
@export var river_core_offset: float = -0.04
@export var river_core_scale: float = 1.05
@export var river_is_river_threshold: float = 0.19
@export var river_surface_tile_threshold: float = 0.22
@export var river_min_carve_for_tile: float = 0.55
@export var river_max_carve: float = 17.0
@export var river_valley_width_factor: float = 1.05
## Zero-crossing distance for ribbon mask (lower = thinner rivers).
@export var river_mask_threshold: float = 0.013
## Carve depth required to emit RIVER without mask (higher = narrower wet footprint).
@export var river_carve_surface_threshold: float = 11.5
@export var river_warp_strength: float = 11.0
@export var river_meander_mix: float = 0.30

@export_group("Caves")
@export var caves_enabled: bool = true
@export var cave_tunnel_base: float = 0.135
@export var cave_room_base: float = 0.058
@export var cave_scale_factor: float = 1.4
@export var cave_tunnel_weight: float = 0.92
@export var cave_room_weight: float = 1.28
@export var cave_hollow_base: float = 0.39
@export var cave_roof_protect_scale: float = 0.12
@export var cave_surface_breach_min: float = 0.42
@export var cave_mouth_threshold: float = 0.48
@export var cave_surface_breach_chance: float = 0.85

@export_group("Biomes (5 interior regions)")
@export var biome_region_warp: float = 0.22
@export var biome_blend_softness: float = 0.15

@export_group("Ramps & Borders")
@export var ramp_placement_chance: int = 28
@export var ramp_max_surface_height: float = 88.0
@export var mountain_ramp_cutoff_height: float = 72.0
@export var shoreline_flatten_strength: float = 0.65

@export_group("Towns")
@export var small_town_count: int = 2
@export var large_port_count: int = 1
@export var small_town_radius_min: int = 10
@export var small_town_radius_max: int = 14
@export var port_radius_min: int = 18
@export var port_radius_max: int = 24
@export var town_min_separation: float = 220.0

@export_group("Vegetation")
@export var grass_density: float = 0.18
@export var tree_density: float = 0.045
@export var bush_density: float = 0.06
@export var vegetation_scatter_attempts: int = 12000


static func create_default() -> WorldGenConfig:
	return WorldGenConfig.new()