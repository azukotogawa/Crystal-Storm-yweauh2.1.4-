class_name BuildableDef
extends Resource

const _VoxelTypes = preload("res://helpers/voxel_types.gd")

enum Category { TERRAIN_WALL, STRUCTURE, TRAP, CRYSTAL_BAFFLE }

@export var id: StringName = &"stone_wall"
@export var display_name: String = "Stone Wall"
@export var category: Category = Category.TERRAIN_WALL

@export_group("Cost")
@export var material_id: String = "stone"
@export var material_count: int = 1
@export var wood_fallback_count: int = 2

@export_group("Terrain")
@export var height_delta: int = 1
@export var tile_id: int = _VoxelTypes.STONE
@export var max_stack_height: int = 8

@export_group("Crystal")
## 0 = transparent to flow, 1 = nearly blocks lateral spread.
@export var flow_resistance: float = 0.85
@export var redirects_flow: bool = false

@export_group("Stats")
@export var dig_speed_required: float = 0.0
@export var placement_range: float = 2.0