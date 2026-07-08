class_name PlantableDef
extends Resource

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

@export var id: StringName = &"grass_tuft"
@export var display_name: String = "Grass Tuft"
@export var tile_id: int = VoxelTypes.GRASS_TUFT
@export var feature_kind: int = _WorldFeatureTypes.FeatureKind.GRASS_PATCH
@export var material_id: String = "herb"
@export var material_cost: int = 1

@export_group("Crystal — Mature")
@export var crystal_flow_factor: float = 0.55
@export var absorb_rate: float = 0.14

@export_group("Growth")
## Number of stages (seed → mature). Mature index = count - 1.
@export var growth_stage_count: int = 2
@export var growth_seconds_per_stage: float = 10.0
## Flow resistance per stage (index 0 = seedling, last = mature).
@export var stage_flow_factors: PackedFloat32Array = PackedFloat32Array([0.82, 0.55])
## Crystal absorption rate per stage when covered.
@export var stage_absorb_rates: PackedFloat32Array = PackedFloat32Array([0.06, 0.14])

@export_group("Area Denial")
## Radius in cells around a mature plant that slows crystal spread.
@export var denial_radius: int = 0
## Flow factor applied inside denial zone (lower = stronger maze defense).
@export var mature_denial_flow_factor: float = 0.12
@export var denial_requires_mature: bool = true


func flow_factor_for_stage(stage: int) -> float:
	if stage_flow_factors.is_empty():
		return crystal_flow_factor
	var idx := clampi(stage, 0, stage_flow_factors.size() - 1)
	return float(stage_flow_factors[idx])


func absorb_rate_for_stage(stage: int) -> float:
	if stage_absorb_rates.is_empty():
		return absorb_rate
	var idx := clampi(stage, 0, stage_absorb_rates.size() - 1)
	return float(stage_absorb_rates[idx])


func mature_stage() -> int:
	return maxi(growth_stage_count - 1, 0)