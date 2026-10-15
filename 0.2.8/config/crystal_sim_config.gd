class_name CrystalSimConfig
extends Resource

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

@export_group("Depth & Pressure Flow")
@export var min_depth: float = 0.04
@export var max_depth: float = 12.0
@export var min_flow_diff: float = 0.05
@export var pressure_flow_rate: float = 1.1
@export var max_flow_per_cell: float = 1.6
@export var max_outflow_ratio: float = 0.42
@export var cliff_height: float = 1.05
@export var flow_substeps: int = 2
@export var lateral_spread_bias: float = 0.08
@export var uphill_flow_penalty: float = 0.35
@export var downhill_flow_bonus: float = 0.55

@export_group("Water & Rivers")
@export var river_flow_factor: float = 0.06
@export var water_build_over_rate: float = 0.35

@export_group("Player Channels")
@export var channel_base_flow_factor: float = 0.1
@export var channel_along_flow_mult: float = 2.4
@export var channel_cross_flow_mult: float = 0.3
@export var channel_water_level_flow_scale: float = 1.5
@export var channel_equilibrate_rate: float = 0.4
@export var channel_raise_step: float = 0.2
@export var channel_lower_step: float = 0.2

@export_group("Vegetation Growth")
@export var growth_near_water_bonus: float = 1.35
@export var growth_near_crystal_penalty: float = 0.35
@export var denial_stack_diminish: float = 0.6

@export_group("Emitters")
@export var origin_emit_rate: float = 1.6
@export var ruin_emit_rate: float = 1.1
@export var artifact_emit_rate: float = 0.7
@export var initial_spawn_depth: float = 2.5
@export var ruin_spawn_count: int = 2
@export var artifact_spawn_count: int = 1
@export var ruin_min_distance: float = 72.0
@export var ruin_max_distance: float = 180.0

@export_group("Power & Tiers")
@export var power_per_volume: float = 0.0025
@export var tier_thresholds: PackedFloat32Array = PackedFloat32Array([
		0.0, 20.0, 60.0, 140.0, 300.0, 600.0,
	])

@export_group("Terrain Interaction")
@export var grass_flow_factor: float = 0.55
@export var bush_flow_factor: float = 0.38
@export var tree_flow_factor: float = 0.22
@export var farmland_flow_factor: float = 0.45
@export var built_wall_flow_factor: float = 0.12
@export var structure_block_flow_factor: float = 0.0
@export var structure_erode_rate: float = 1.0

@export_group("Absorption")
@export var grass_absorb_rate: float = 0.14
@export var bush_absorb_rate: float = 0.09
@export var tree_absorb_rate: float = 0.05
@export var farmland_absorb_rate: float = 0.11
@export var grass_absorb_power: float = 1.5
@export var bush_absorb_power: float = 3.5
@export var tree_absorb_power: float = 8.0
@export var farmland_absorb_power: float = 6.5

@export_group("Corruption")
@export var biome_spread: Dictionary = {}
@export var biome_reserve: Dictionary = {}
@export var biome_mob: Dictionary = {}
@export var scar_heal_seconds: float = 18.0
@export var animal_convert_seconds: float = 3.5

const DEFAULT_BIOME_SPREAD := {
	"plains": 1.35,
	"steppe": 1.28,
	"forest": 1.0,
	"marsh": 0.85,
	"highland": 0.55,
	"mountain": 0.5,
}
const DEFAULT_BIOME_RESERVE := {
	"plains": 1.0,
	"steppe": 1.0,
	"forest": 1.05,
	"marsh": 1.1,
	"highland": 1.65,
	"mountain": 1.75,
}
const DEFAULT_BIOME_MOB := {
	"plains": 1.55,
	"steppe": 1.4,
	"forest": 1.0,
	"marsh": 0.9,
	"highland": 0.65,
	"mountain": 0.6,
}

@export_group("Lose / Win")
@export var max_coverage_ratio: float = 0.72
@export var player_contact_defeat_enabled: bool = false
@export var player_defeat_depth: float = 0.35
@export var player_defeat_min_tier: int = 2


func emit_rate_for(kind: int) -> float:
	match kind:
		_CrystalTypes.SpawnKind.ORIGIN:
			return origin_emit_rate
		_CrystalTypes.SpawnKind.RUIN:
			return ruin_emit_rate
		_CrystalTypes.SpawnKind.ARTIFACT:
			return artifact_emit_rate
		_:
			return ruin_emit_rate


func tier_from_power(power: float) -> int:
	var tier := 0
	for i in tier_thresholds.size():
		if power >= tier_thresholds[i]:
			tier += 1
	return maxi(tier - 1, 0)


func canonical_biome(biome_name: String) -> String:
	var n := biome_name.strip_edges().to_lower()
	if n.contains("highland") or n.contains("hill"):
		return "highland"
	if n.contains("mountain") or n.contains("peak") or n.contains("alpine"):
		return "mountain"
	if n.contains("steppe") or n.contains("savanna"):
		return "steppe"
	if n.contains("plain"):
		return "plains"
	if n.contains("marsh") or n.contains("swamp") or n.contains("wetland"):
		return "marsh"
	if n.contains("forest") or n.contains("pine") or n.contains("woods"):
		return "forest"
	return n


func biome_spread_mult(biome_name: String) -> float:
	return _biome_value(biome_spread, DEFAULT_BIOME_SPREAD, biome_name)


func biome_reserve_mult(biome_name: String) -> float:
	return _biome_value(biome_reserve, DEFAULT_BIOME_RESERVE, biome_name)


func biome_mob_mult(biome_name: String) -> float:
	return _biome_value(biome_mob, DEFAULT_BIOME_MOB, biome_name)


func _biome_value(override: Dictionary, defaults: Dictionary, biome_name: String) -> float:
	var key := canonical_biome(biome_name)
	if override.has(key):
		return float(override[key])
	return float(defaults.get(key, 1.0))


func vegetation_flow_factor(tile_id: int) -> float:
	if tile_id == _VoxelTypes.RIVER or tile_id == _VoxelTypes.WATER:
		return river_flow_factor
	if tile_id == _VoxelTypes.GRASS_TUFT:
		return grass_flow_factor
	if tile_id == _VoxelTypes.BUSH:
		return bush_flow_factor
	if tile_id == _VoxelTypes.TREE_TRUNK:
		return tree_flow_factor
	if tile_id == _VoxelTypes.FARMLAND:
		return farmland_flow_factor
	if tile_id == _VoxelTypes.STONE or tile_id == _VoxelTypes.DIRT:
		return built_wall_flow_factor
	return 1.0


static func create_default() -> CrystalSimConfig:
	return CrystalSimConfig.new()