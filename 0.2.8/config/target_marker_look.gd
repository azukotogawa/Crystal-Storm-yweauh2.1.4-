class_name TargetMarkerLook
extends Resource

const RESOURCE_PATH := "res://config/default_target_marker_look.tres"

@export var edge_thickness: float = 0.026

@export var dig_fill: Color = Color(0.94, 0.97, 1.0, 1.0)
@export var dig_fill_alpha: float = 0.08
@export var dig_fill_alpha_pulse: float = 0.04
@export var dig_emission: Color = Color(0.9, 0.95, 1.0, 1.0)
@export var dig_energy: float = 0.22
@export var dig_energy_pulse: float = 0.12

@export var dig_edge: Color = Color(0.96, 0.98, 1.0, 0.72)
@export var dig_edge_emission: Color = Color(0.93, 0.97, 1.0, 1.0)
@export var dig_edge_energy: float = 0.95

@export var dig_face: Color = Color(0.97, 0.98, 1.0, 0.38)
@export var dig_face_emission: Color = Color(0.94, 0.97, 1.0, 1.0)
@export var dig_face_energy: float = 0.55

@export var build_fill: Color = Color(0.28, 0.55, 1.0, 1.0)
@export var build_fill_alpha: float = 0.18
@export var build_fill_alpha_pulse: float = 0.05
@export var build_place_alpha: float = 0.08
@export var build_emission: Color = Color(0.22, 0.48, 1.0, 1.0)
@export var build_flash: Color = Color(0.7, 0.88, 1.0, 1.0)
@export var build_energy: float = 0.42
@export var build_energy_pulse: float = 0.18
@export var build_place_energy: float = 0.5

@export var build_edge: Color = Color(0.42, 0.7, 1.0, 0.78)
@export var build_edge_emission: Color = Color(0.28, 0.58, 1.0, 1.0)
@export var build_edge_energy: float = 0.9

@export var build_face: Color = Color(0.5, 0.75, 1.0, 0.36)
@export var build_face_emission: Color = Color(0.32, 0.6, 1.0, 1.0)
@export var build_face_energy: float = 0.6

@export var structure_fill: Color = Color(0.3, 0.58, 1.0, 0.2)
@export var structure_emission: Color = Color(0.24, 0.5, 1.0, 1.0)
@export var structure_energy: float = 0.45

@export var blocked_fill: Color = Color(1.0, 0.15, 0.12, 1.0)
@export var blocked_fill_alpha: float = 0.32
@export var blocked_fill_alpha_pulse: float = 0.12
@export var blocked_emission: Color = Color(0.9, 0.1, 0.08, 1.0)
@export var blocked_energy: float = 0.45
@export var blocked_energy_pulse: float = 0.35
@export var blocked_edge: Color = Color(1.0, 0.35, 0.3, 0.7)
@export var blocked_edge_emission: Color = Color(0.95, 0.18, 0.14, 1.0)
@export var blocked_edge_energy: float = 0.7
@export var structure_blocked: Color = Color(1.0, 0.15, 0.12, 0.38)
@export var structure_blocked_emission: Color = Color(0.9, 0.1, 0.08, 1.0)

@export var attack_fill: Color = Color(1.0, 0.22, 0.18, 1.0)
@export var attack_fill_alpha: float = 0.3
@export var attack_fill_alpha_pulse: float = 0.14
@export var attack_emission: Color = Color(0.95, 0.2, 0.15, 1.0)
@export var attack_energy: float = 0.5
@export var attack_energy_pulse: float = 0.45

@export var ranged_fill: Color = Color(0.45, 0.75, 1.0, 1.0)
@export var ranged_fill_alpha: float = 0.28
@export var ranged_fill_alpha_pulse: float = 0.14
@export var ranged_emission: Color = Color(0.4, 0.7, 1.0, 1.0)
@export var ranged_energy: float = 0.5
@export var ranged_energy_pulse: float = 0.4

@export var fallback_fill: Color = Color(0.35, 0.95, 0.45, 0.3)
@export var fallback_emission: Color = Color(0.3, 0.9, 0.4, 1.0)
@export var fallback_energy: float = 0.5


static func load_active() -> TargetMarkerLook:
	var script: Script = load("res://config/target_marker_look.gd")
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded: Resource = load(RESOURCE_PATH)
		if loaded != null and loaded.get_script() == script:
			return loaded as TargetMarkerLook
	return script.new() as TargetMarkerLook


func fill_albedo(mode: StringName, pulse: float, place_boost: float, blocked: bool) -> Color:
	if blocked:
		return _with_alpha(blocked_fill, blocked_fill_alpha + blocked_fill_alpha_pulse * pulse)
	match mode:
		&"dig":
			return _with_alpha(dig_fill, dig_fill_alpha + dig_fill_alpha_pulse * pulse)
		&"build":
			return _with_alpha(build_fill, build_fill_alpha + build_fill_alpha_pulse * pulse + build_place_alpha * place_boost)
		&"attack":
			return _with_alpha(attack_fill, attack_fill_alpha + attack_fill_alpha_pulse * pulse)
		&"ranged":
			return _with_alpha(ranged_fill, ranged_fill_alpha + ranged_fill_alpha_pulse * pulse)
		_:
			return fallback_fill


func fill_emission(mode: StringName, place_boost: float, blocked: bool) -> Color:
	if blocked:
		return blocked_emission
	match mode:
		&"dig":
			return dig_emission
		&"build":
			return build_emission.lerp(build_flash, place_boost)
		&"attack":
			return attack_emission
		&"ranged":
			return ranged_emission
		_:
			return fallback_emission


func fill_energy(mode: StringName, pulse: float, place_boost: float, blocked: bool) -> float:
	if blocked:
		return blocked_energy + blocked_energy_pulse * pulse
	match mode:
		&"dig":
			return dig_energy + dig_energy_pulse * pulse
		&"build":
			return build_energy + build_energy_pulse * pulse + build_place_energy * place_boost
		&"attack":
			return attack_energy + attack_energy_pulse * pulse
		&"ranged":
			return ranged_energy + ranged_energy_pulse * pulse
		_:
			return fallback_energy


func edge_albedo(mode: StringName, blocked: bool) -> Color:
	if blocked:
		return blocked_edge
	if mode == &"build":
		return build_edge
	return dig_edge


func edge_emission(mode: StringName, blocked: bool) -> Color:
	if blocked:
		return blocked_edge_emission
	if mode == &"build":
		return build_edge_emission
	return dig_edge_emission


func edge_energy(mode: StringName, blocked: bool) -> float:
	if blocked:
		return blocked_edge_energy
	if mode == &"build":
		return build_edge_energy
	return dig_edge_energy


func face_albedo(mode: StringName, blocked: bool) -> Color:
	if blocked:
		return blocked_edge
	if mode == &"build":
		return build_face
	return dig_face


func face_emission(mode: StringName, blocked: bool) -> Color:
	if blocked:
		return blocked_edge_emission
	if mode == &"build":
		return build_face_emission
	return dig_face_emission


func face_energy(mode: StringName, blocked: bool) -> float:
	if blocked:
		return blocked_edge_energy
	if mode == &"build":
		return build_face_energy
	return dig_face_energy


func structure_tint(valid: bool) -> Color:
	if valid:
		return structure_fill
	return structure_blocked


func structure_glow(valid: bool) -> Color:
	if valid:
		return structure_emission
	return structure_blocked_emission


func _with_alpha(rgb: Color, alpha: float) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, clampf(alpha, 0.0, 1.0))
