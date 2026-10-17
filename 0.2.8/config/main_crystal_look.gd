class_name MainCrystalLook
extends Resource

const RESOURCE_PATH := "res://config/default_main_crystal_look.tres"

@export var albedo: Color = Color(0.62, 0.16, 0.92, 1.0)
@export var emission: Color = Color(0.78, 0.22, 1.0, 1.0)
@export var emission_energy: float = 2.2
@export var colorblind_albedo: Color = Color(0.98, 0.82, 0.12, 1.0)
@export var colorblind_emission: Color = Color(1.0, 0.9, 0.2, 1.0)
@export var colorblind_emission_energy: float = 2.2
@export var roughness: float = 0.18
@export var shard_centers: Array[Vector3] = [
	Vector3(0.02, -0.10, -0.04),
	Vector3(0.18, 0.46, 0.08),
	Vector3(-0.30, -0.24, 0.10),
	Vector3(0.04, 0.10, 0.42),
	Vector3(-0.10, -0.40, -0.20),
	Vector3(0.24, 0.80, -0.12),
	Vector3(-0.16, 0.28, -0.18),
]
@export var shard_sizes: Array[Vector3] = [
	Vector3(0.46, 0.98, 0.38),
	Vector3(0.20, 0.70, 0.16),
	Vector3(0.30, 0.52, 0.22),
	Vector3(0.16, 0.44, 0.36),
	Vector3(0.26, 0.30, 0.18),
	Vector3(0.12, 0.36, 0.14),
	Vector3(0.18, 0.28, 0.16),
]


static func load_active() -> MainCrystalLook:
	var script: Script = load("res://config/main_crystal_look.gd")
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded: Resource = load(RESOURCE_PATH)
		if loaded is MainCrystalLook:
			return loaded as MainCrystalLook
	return (script.new() as MainCrystalLook)


func albedo_color(colorblind: bool) -> Color:
	return colorblind_albedo if colorblind else albedo


func emission_color(colorblind: bool) -> Color:
	return colorblind_emission if colorblind else emission


func energy(colorblind: bool) -> float:
	return colorblind_emission_energy if colorblind else emission_energy


func shard_count() -> int:
	return mini(shard_centers.size(), shard_sizes.size())
