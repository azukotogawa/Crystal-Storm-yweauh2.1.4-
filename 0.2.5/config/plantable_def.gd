class_name PlantableDef
extends Resource

const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

@export var id: StringName = &"grass_tuft"
@export var display_name: String = "Grass Tuft"
@export var tile_id: int = VoxelTypes.GRASS_TUFT
@export var feature_kind: int = _WorldFeatureTypes.FeatureKind.GRASS_PATCH
@export var material_id: String = "herb"
@export var material_cost: int = 1
@export var crystal_flow_factor: float = 0.55
@export var absorb_rate: float = 0.14