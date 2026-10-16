class_name CrystalMiteLook
extends Resource

const RESOURCE_PATH := "res://config/default_crystal_mite_look.tres"

@export var visual_scale: float = 2.0
@export var albedo: Color = Color(0.12, 0.95, 1.0, 1.0)
@export var emission: Color = Color(0.2, 1.0, 1.0, 1.0)
@export var emission_energy: float = 2.6
@export var colorblind_albedo: Color = Color(1.0, 0.92, 0.18, 1.0)
@export var colorblind_emission: Color = Color(1.0, 0.88, 0.08, 1.0)
@export var colorblind_emission_energy: float = 2.6


static func load_active() -> CrystalMiteLook:
	var script: Script = load("res://config/crystal_mite_look.gd")
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded: Resource = load(RESOURCE_PATH)
		if loaded is CrystalMiteLook:
			return loaded as CrystalMiteLook
	return (script.new() as CrystalMiteLook)


func albedo_color(colorblind: bool) -> Color:
	return colorblind_albedo if colorblind else albedo


func emission_color(colorblind: bool) -> Color:
	return colorblind_emission if colorblind else emission


func energy(colorblind: bool) -> float:
	return colorblind_emission_energy if colorblind else emission_energy
