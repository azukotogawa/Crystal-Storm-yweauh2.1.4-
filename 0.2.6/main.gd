extends Node3D
## Root scene script for scenes/main.tscn.
##
## Boot order (async, deferred across child nodes):
##   ConfigService → PerformanceService → GameVisualRegistry
##   WorldFeatures (town/veg/ruin/entity seeds) → VoxelWorld creates ChunkManager
##   on_chunk_manager_ready → TerrainEditor, EntityManager, perf/chunk config
##   CrystalManager sim → Player spawn poll → WorldVisuals refresh on visuals_ready