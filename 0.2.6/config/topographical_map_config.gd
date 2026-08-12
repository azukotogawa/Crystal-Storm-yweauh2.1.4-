class_name TopographicalMapConfig
extends Resource

@export_group("Resolution")
@export var minimap_size: int = 160
@export var fullscreen_size: int = 512
@export var minimap_radius_cells: int = 128
@export var fullscreen_half_extent_cells: int = 512
@export var sample_stride: int = 2

@export_group("Update")
@export var rebuild_interval_sec: float = 1.5
@export var rebuild_move_threshold_cells: int = 24

@export_group("Colors")
@export var color_plains: Color = Color(0.55, 0.78, 0.38)
@export var color_steppe: Color = Color(0.72, 0.68, 0.42)
@export var color_forest: Color = Color(0.22, 0.48, 0.28)
@export var color_marsh: Color = Color(0.34, 0.42, 0.30)
@export var color_highland: Color = Color(0.58, 0.56, 0.52)
@export var color_ocean: Color = Color(0.12, 0.32, 0.68)
@export var color_mountain: Color = Color(0.38, 0.36, 0.42)
@export var color_water: Color = Color(0.22, 0.48, 0.82)
@export var color_channel: Color = Color(0.18, 0.62, 0.92)
@export var color_crystal: Color = Color(0.78, 0.22, 1.0, 0.92)
@export var color_town: Color = Color(0.95, 0.82, 0.28)
@export var color_ruin: Color = Color(0.92, 0.45, 0.18)
@export var color_spawn_boss: Color = Color(1.0, 0.25, 0.95)
@export var color_spawn_miniboss: Color = Color(0.85, 0.35, 1.0)
@export var color_player: Color = Color(0.95, 0.95, 1.0)
@export var color_height_shadow: Color = Color(0.05, 0.06, 0.08, 0.35)


static func create_default() -> TopographicalMapConfig:
	return TopographicalMapConfig.new()