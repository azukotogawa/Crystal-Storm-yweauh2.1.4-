class_name PerformanceQualityConfig
extends Resource

const _SCRIPT = preload("res://config/performance_quality_config.gd")

enum Preset { LOW, MEDIUM, HIGH, CUSTOM }

@export var preset: Preset = Preset.LOW

@export_group("Chunk Streaming")
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

@export_group("UI / Map")
@export var minimap_enabled: bool = true
@export var map_fullscreen_enabled: bool = true
@export_range(0.5, 12.0, 0.25)
var map_rebuild_interval_sec: float = 3.0
@export_range(64, 256, 16)
var minimap_pixel_size: int = 128
@export_range(1, 8, 1)
var map_sample_stride: int = 2
@export var debug_panel_enabled: bool = true
@export_range(4, 64, 2)
var debug_update_every: int = 24

@export_group("Entities & Vegetation")
@export var entity_spawning_enabled: bool = true
@export_range(0, 256, 8)
var max_entities: int = 128
@export_range(0, 8, 1)
var animals_per_biome_chunk: int = 2
@export_range(0.0, 1.0, 0.05)
var vegetation_scatter_multiplier: float = 1.0

@export_group("Combat Visuals")
@export var combat_visuals_enabled: bool = true
@export_range(2, 16, 1)
var max_damage_labels: int = 6
@export_range(2, 16, 1)
var max_burst_sprites: int = 6
@export_range(0.4, 2.0, 0.1)
var damage_number_lifetime: float = 0.9


static func create_default() -> PerformanceQualityConfig:
	return apply_preset(Preset.LOW)


static func apply_preset(which: Preset) -> PerformanceQualityConfig:
	var c: PerformanceQualityConfig = _SCRIPT.new()
	c.preset = which
	match which:
		Preset.LOW:
			c.render_distance = 1
			c.max_chunks_per_frame = 1
			c.max_inflight_chunks = 2
			c.caves_enabled = false
			c.mesh_caves = false
			c.crystal_sim_enabled = true
			c.flow_substeps = 1
			c.crystal_sim_skip_frames = 2
			c.max_crystal_chunk_rebuilds_per_frame = 1
			c.max_crystal_flow_cells = 400
			c.minimap_enabled = true
			c.map_fullscreen_enabled = true
			c.map_rebuild_interval_sec = 5.0
			c.minimap_pixel_size = 96
			c.map_sample_stride = 4
			c.debug_panel_enabled = true
			c.debug_update_every = 48
			c.entity_spawning_enabled = true
			c.max_entities = 48
			c.animals_per_biome_chunk = 0
			c.vegetation_scatter_multiplier = 0.35
			c.combat_visuals_enabled = false
			c.max_damage_labels = 0
			c.max_burst_sprites = 0
		Preset.MEDIUM:
			c.render_distance = 3
			c.max_chunks_per_frame = 2
			c.max_inflight_chunks = 6
			c.caves_enabled = true
			c.mesh_caves = false
			c.crystal_sim_enabled = true
			c.flow_substeps = 2
			c.crystal_sim_skip_frames = 0
			c.max_crystal_chunk_rebuilds_per_frame = 3
			c.max_crystal_flow_cells = 0
			c.minimap_enabled = true
			c.map_fullscreen_enabled = true
			c.map_rebuild_interval_sec = 1.5
			c.minimap_pixel_size = 160
			c.map_sample_stride = 2
			c.debug_panel_enabled = true
			c.debug_update_every = 12
			c.entity_spawning_enabled = true
			c.max_entities = 96
			c.animals_per_biome_chunk = 1
			c.vegetation_scatter_multiplier = 0.7
			c.combat_visuals_enabled = true
			c.max_damage_labels = 6
			c.max_burst_sprites = 6
		Preset.HIGH:
			c.render_distance = 4
			c.max_chunks_per_frame = 3
			c.max_inflight_chunks = 8
			c.caves_enabled = true
			c.mesh_caves = false
			c.crystal_sim_enabled = true
			c.flow_substeps = 3
			c.crystal_sim_skip_frames = 0
			c.max_crystal_chunk_rebuilds_per_frame = 5
			c.max_crystal_flow_cells = 0
			c.minimap_enabled = true
			c.map_fullscreen_enabled = true
			c.map_rebuild_interval_sec = 1.0
			c.minimap_pixel_size = 160
			c.map_sample_stride = 2
			c.debug_panel_enabled = true
			c.debug_update_every = 8
			c.entity_spawning_enabled = true
			c.max_entities = 128
			c.animals_per_biome_chunk = 2
			c.vegetation_scatter_multiplier = 1.0
			c.combat_visuals_enabled = true
			c.max_damage_labels = 10
			c.max_burst_sprites = 12
		_:
			pass
	return c