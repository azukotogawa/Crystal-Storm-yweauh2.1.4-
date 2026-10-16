class_name CrystalGroundLook
extends Resource

const RESOURCE_PATH := "res://config/default_crystal_ground.tres"

@export var atlas_path: String = "res://assets/tiles/Cube.png"
@export var atlas_columns: int = 7
@export var atlas_rows: int = 10
@export var ground_col: int = 6
@export var ground_row: int = 3
@export var stone_col: int = 0
@export var stone_row: int = 4
@export var crystal_col: int = 6
@export var crystal_row: int = 2
@export var emission_energy: float = 0.16
@export var albedo_tint: float = 0.0
@export var show_debug_markers: bool = false
@export var spawn_fallback_path: String = "res://assets/art/crystal/amethyst.png"


static func load_active() -> CrystalGroundLook:
	var script: Script = load("res://config/crystal_ground_look.gd")
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded: Resource = load(RESOURCE_PATH)
		if loaded is CrystalGroundLook:
			return loaded as CrystalGroundLook
	return (script.new() as CrystalGroundLook)


func debug_markers_allowed() -> bool:
	return OS.is_debug_build() and show_debug_markers
