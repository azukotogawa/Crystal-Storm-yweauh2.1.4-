class_name WorldSettings
extends Resource

## ═══════════════════════════════════════════════════════════════════════════
## CHANGE VOXEL SIZE HERE — single knob for world scale.
## Assign this resource on ConfigService (or edit res://config/default_world_settings.tres).
## ═══════════════════════════════════════════════════════════════════════════

@export_group("Voxel Scale (change these first)")
@export_range(0.25, 8.0, 0.25)
var voxel_scale: float = 2.0:
	set(v):
		voxel_scale = maxf(v, 0.25)
		_sync_derived()

## Hard cap on generated terrain height, measured in voxel layers (not world units).
@export_range(4, 64, 1)
var max_world_height_voxels: int = 20:
	set(v):
		max_world_height_voxels = maxi(v, 4)
		_sync_derived()

@export_group("Chunk Layout")
@export var chunk_size_voxels: int = 16

@export_group("Derived (read-only in inspector)")
@export var max_height_world_units: float = 40.0
@export var legacy_height_reference: float = 158.0

static var _active = null


static func get_active():
	if _active == null:
		_active = create_default()
	return _active


static func apply_active(settings) -> void:
	_active = settings if settings else create_default()
	if _active:
		_active._sync_derived()


static func create_default():
	var s = load("res://config/world_settings.gd").new()
	s._sync_derived()
	return s


func _sync_derived() -> void:
	max_height_world_units = float(max_world_height_voxels) * voxel_scale


# --- Convenience accessors (use these instead of magic numbers) ---

func layer_height() -> float:
	return voxel_scale


func half_layer() -> float:
	return voxel_scale * 0.5


func walkable_surface_offset() -> float:
	## Feet sit on top of the solid voxel column (surface_y + layer_height).
	return layer_height()


func voxel_top_y(surface_y: float) -> float:
	return surface_y + layer_height()


func max_height_units() -> float:
	return max_height_world_units


func height_generation_scale() -> float:
	return max_height_units() / legacy_height_reference


func step_height_min() -> float:
	return layer_height() * 0.85


func step_height_max() -> float:
	return layer_height() * 1.35


func cliff_height() -> float:
	return layer_height() * 1.05


func column_to_world(column: float) -> float:
	return column * voxel_scale


func world_to_column(world: float) -> float:
	return world / maxf(voxel_scale, 0.001)


func chunk_world_size() -> float:
	return float(chunk_size_voxels) * voxel_scale


func player_height() -> float:
	return layer_height() * 0.4


func player_radius() -> float:
	return layer_height() * 0.2


func floor_snap_distance() -> float:
	return layer_height() * 0.3


func max_step_up_walk() -> float:
	## Full voxel-layer step while walking (plus small epsilon for float error).
	return layer_height() * 1.08


func max_step_up_jump() -> float:
	return layer_height() * 5.0


@export_group("Player Physics (CharacterBody3D)")
@export_range(0.5, 3.0, 0.05)
var player_gravity_scale: float = 1.0
@export_range(0.5, 2.0, 0.05)
var player_jump_scale: float = 1.0
@export_range(0.05, 0.5, 0.01)
var player_floor_probe_radius: float = 0.22
@export_range(20.0, 60.0, 1.0)
var player_slope_limit_degrees: float = 48.0
@export_range(0.01, 0.2, 0.01)
var player_safe_margin: float = 0.06
@export var player_use_character_body: bool = true


func chunk_height_bound() -> int:
	return maxi(maxi(max_world_height_voxels + 8, 32), 48)