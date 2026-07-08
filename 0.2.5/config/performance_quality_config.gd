class_name PerformanceQualityConfig
extends Resource

const _SCRIPT = preload("res://config/performance_quality_config.gd")

enum Preset { LOW, MEDIUM, HIGH, SAFE, CUSTOM }

@export var preset: Preset = Preset.MEDIUM

@export_group("Frame Budget (main thread)")
## Target max time spent uploading chunks per frame (microseconds).
@export_range(500, 12000, 100)
var chunk_upload_budget_us: int = 3500
## Soft cap for tracked main-thread work per frame (microseconds).
@export_range(2000, 20000, 500)
var main_thread_budget_us: int = 8000

@export_group("Chunk Streaming")
@export var prebuild_chunk_buffers: bool = true
@export_range(1, 8, 1)
var render_distance: int = 2
@export_range(1, 8, 1)
var max_chunks_per_frame: int = 1
@export_range(1, 12, 1)
var max_inflight_chunks: int = 4

@export_group("World Generation")
@export var caves_enabled: bool = true
@export var mesh_caves: bool = false

@export_group("Crystal Simulation")
@export var crystal_sim_enabled: bool = true
@export_range(4.0, 60.0, 1.0)
var crystal_sim_hz: float = 20.0
@export var use_fast_terrain_for_crystal: bool = true
@export_range(1, 6, 1)
var flow_substeps: int = 1
## Skip N frames between crystal sim ticks (2 = run every 3rd frame).
@export_range(0, 6, 1)
var crystal_sim_skip_frames: int = 1
@export_range(1, 8, 1)
var max_crystal_chunk_rebuilds_per_frame: int = 2
## Cap crystal flow cells processed per substep (0 = unlimited).
@export_range(0, 2000, 50)
var max_crystal_flow_cells: int = 0
## Rotating scan cap for plant/animal absorption per frame.
@export_range(8, 512, 8)
var max_absorption_cells_per_tick: int = 64

@export_group("UI / Map")
@export var minimap_enabled: bool = true
@export var map_fullscreen_enabled: bool = true
@export_range(0.5, 12.0, 0.25)
var map_rebuild_interval_sec: float = 3.0
@export_range(64, 256, 16)
var minimap_pixel_size: int = 128
@export_range(1, 8, 1)
var map_sample_stride: int = 2
## Spread map pixel rows across frames (higher = faster rebuild, more CPU spike).
@export_range(1, 64, 1)
var map_rows_per_frame: int = 8
@export var debug_panel_enabled: bool = true
@export_range(4, 64, 2)
var debug_update_every: int = 24
@export var debug_expensive_queries: bool = false
## Tile-based map coloring (skips per-pixel get_biome).
@export var fast_map_sampling: bool = true

@export_group("Entities & Vegetation")
@export var entity_spawning_enabled: bool = true
@export_range(0, 256, 8)
var max_entities: int = 128
@export_range(0, 8, 1)
var animals_per_biome_chunk: int = 2
@export_range(0, 6, 1)
var entity_physics_skip_frames: int = 0
## Single-sample entity height (much faster than 8-probe floor sampling).
@export var use_lightweight_entity_nav: bool = true
@export_range(0.0, 1.0, 0.05)
var vegetation_scatter_multiplier: float = 1.0

@export_group("Vegetation Growth")
@export var vegetation_growth_enabled: bool = true
@export_range(0.5, 20.0, 0.5)
var vegetation_growth_hz: float = 4.0
@export_range(1, 128, 1)
var vegetation_plants_per_tick: int = 24
@export_range(1, 16, 1)
var vegetation_env_check_interval: int = 4
@export_range(2.0, 30.0, 1.0)
var vegetation_index_refresh_sec: float = 8.0

@export_group("Combat Visuals")
@export var combat_visuals_enabled: bool = true
@export_range(2, 16, 1)
var max_damage_labels: int = 6
@export_range(2, 16, 1)
var max_burst_sprites: int = 6
@export_range(0.4, 2.0, 0.1)
var damage_number_lifetime: float = 0.9

@export_group("Profiling")
@export var perf_profiler_enabled: bool = true


static func create_default() -> PerformanceQualityConfig:
	return apply_preset(Preset.MEDIUM)


static func apply_safe_mode() -> PerformanceQualityConfig:
	var c: PerformanceQualityConfig = _SCRIPT.new()
	c.preset = Preset.SAFE
	c.chunk_upload_budget_us = 2500
	c.main_thread_budget_us = 6000
	c.prebuild_chunk_buffers = true
	c.render_distance = 1
	c.max_chunks_per_frame = 1
	c.max_inflight_chunks = 2
	c.caves_enabled = false
	c.mesh_caves = false
	c.crystal_sim_enabled = false
	c.crystal_sim_hz = 6.0
	c.crystal_sim_skip_frames = 3
	c.max_crystal_chunk_rebuilds_per_frame = 1
	c.max_crystal_flow_cells = 200
	c.max_absorption_cells_per_tick = 16
	c.minimap_enabled = false
	c.map_fullscreen_enabled = false
	c.map_rebuild_interval_sec = 30.0
	c.minimap_pixel_size = 64
	c.map_sample_stride = 6
	c.map_rows_per_frame = 2
	c.fast_map_sampling = true
	c.debug_panel_enabled = true
	c.debug_update_every = 60
	c.debug_expensive_queries = false
	c.entity_spawning_enabled = false
	c.max_entities = 0
	c.animals_per_biome_chunk = 0
	c.entity_physics_skip_frames = 3
	c.use_lightweight_entity_nav = true
	c.vegetation_scatter_multiplier = 0.0
	c.vegetation_growth_enabled = false
	c.vegetation_growth_hz = 1.0
	c.vegetation_plants_per_tick = 4
	c.combat_visuals_enabled = false
	c.max_damage_labels = 0
	c.max_burst_sprites = 0
	c.perf_profiler_enabled = true
	return c


static func apply_preset(which: Preset) -> PerformanceQualityConfig:
	var c: PerformanceQualityConfig = _SCRIPT.new()
	c.preset = which
	match which:
		Preset.LOW:
			c.chunk_upload_budget_us = 2500
			c.main_thread_budget_us = 6500
			c.prebuild_chunk_buffers = true
			c.render_distance = 1
			c.max_chunks_per_frame = 1
			c.max_inflight_chunks = 2
			c.caves_enabled = false
			c.mesh_caves = false
			c.crystal_sim_enabled = true
			c.crystal_sim_hz = 10.0
			c.use_fast_terrain_for_crystal = true
			c.flow_substeps = 1
			c.crystal_sim_skip_frames = 2
			c.max_crystal_chunk_rebuilds_per_frame = 1
			c.max_crystal_flow_cells = 400
			c.max_absorption_cells_per_tick = 32
			c.minimap_enabled = true
			c.map_fullscreen_enabled = true
			c.map_rebuild_interval_sec = 5.0
			c.minimap_pixel_size = 96
			c.map_sample_stride = 4
			c.map_rows_per_frame = 4
			c.debug_panel_enabled = true
			c.debug_update_every = 48
			c.debug_expensive_queries = false
			c.fast_map_sampling = true
			c.entity_spawning_enabled = true
			c.max_entities = 48
			c.animals_per_biome_chunk = 0
			c.entity_physics_skip_frames = 2
			c.use_lightweight_entity_nav = true
			c.vegetation_scatter_multiplier = 0.35
			c.vegetation_growth_hz = 2.0
			c.vegetation_plants_per_tick = 8
			c.vegetation_env_check_interval = 8
			c.vegetation_index_refresh_sec = 12.0
			c.combat_visuals_enabled = false
			c.max_damage_labels = 0
			c.max_burst_sprites = 0
			c.perf_profiler_enabled = true
		Preset.MEDIUM:
			c.chunk_upload_budget_us = 3500
			c.main_thread_budget_us = 8000
			c.prebuild_chunk_buffers = true
			c.render_distance = 2
			c.max_chunks_per_frame = 1
			c.max_inflight_chunks = 4
			c.caves_enabled = true
			c.mesh_caves = false
			c.crystal_sim_enabled = true
			c.crystal_sim_hz = 14.0
			c.use_fast_terrain_for_crystal = true
			c.flow_substeps = 1
			c.crystal_sim_skip_frames = 1
			c.max_crystal_chunk_rebuilds_per_frame = 2
			c.max_crystal_flow_cells = 500
			c.max_absorption_cells_per_tick = 64
			c.minimap_enabled = true
			c.map_fullscreen_enabled = true
			c.map_rebuild_interval_sec = 2.5
			c.minimap_pixel_size = 112
			c.map_sample_stride = 4
			c.map_rows_per_frame = 6
			c.debug_panel_enabled = true
			c.debug_update_every = 20
			c.debug_expensive_queries = false
			c.fast_map_sampling = true
			c.entity_spawning_enabled = true
			c.max_entities = 64
			c.animals_per_biome_chunk = 1
			c.entity_physics_skip_frames = 1
			c.use_lightweight_entity_nav = true
			c.vegetation_scatter_multiplier = 0.55
			c.vegetation_growth_hz = 3.0
			c.vegetation_plants_per_tick = 16
			c.vegetation_env_check_interval = 4
			c.vegetation_index_refresh_sec = 8.0
			c.combat_visuals_enabled = true
			c.max_damage_labels = 4
			c.max_burst_sprites = 4
			c.perf_profiler_enabled = true
		Preset.HIGH:
			c.chunk_upload_budget_us = 5000
			c.main_thread_budget_us = 10000
			c.prebuild_chunk_buffers = true
			c.render_distance = 3
			c.max_chunks_per_frame = 2
			c.max_inflight_chunks = 6
			c.caves_enabled = true
			c.mesh_caves = false
			c.crystal_sim_enabled = true
			c.crystal_sim_hz = 18.0
			c.use_fast_terrain_for_crystal = true
			c.flow_substeps = 1
			c.crystal_sim_skip_frames = 0
			c.max_crystal_chunk_rebuilds_per_frame = 3
			c.max_crystal_flow_cells = 1200
			c.max_absorption_cells_per_tick = 128
			c.minimap_enabled = true
			c.map_fullscreen_enabled = true
			c.map_rebuild_interval_sec = 2.0
			c.minimap_pixel_size = 144
			c.map_sample_stride = 3
			c.map_rows_per_frame = 16
			c.debug_panel_enabled = true
			c.debug_update_every = 12
			c.debug_expensive_queries = true
			c.fast_map_sampling = false
			c.entity_spawning_enabled = true
			c.max_entities = 96
			c.animals_per_biome_chunk = 2
			c.entity_physics_skip_frames = 0
			c.use_lightweight_entity_nav = false
			c.vegetation_scatter_multiplier = 1.0
			c.vegetation_growth_hz = 8.0
			c.vegetation_plants_per_tick = 48
			c.vegetation_env_check_interval = 2
			c.vegetation_index_refresh_sec = 6.0
			c.combat_visuals_enabled = true
			c.max_damage_labels = 8
			c.max_burst_sprites = 8
			c.perf_profiler_enabled = true
		_:
			pass
	return c