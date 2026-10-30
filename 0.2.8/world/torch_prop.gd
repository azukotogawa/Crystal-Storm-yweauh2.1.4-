class_name TorchProp
extends Node3D

const RANGE := 6.0
const LIT_ENERGY := 1.15
const POLE_COLOR := Color(0.42, 0.28, 0.14, 1)
const FLAME_COLOR := Color(1.0, 0.55, 0.16, 1)
const LIGHT_COLOR := Color(1.0, 0.72, 0.38, 1)
const POLE_SIZE := Vector3(0.16, 0.92, 0.16)
const FLAME_SIZE := Vector3(0.22, 0.28, 0.22)

var lit := true
var _light: OmniLight3D
var _flame_mat: StandardMaterial3D


func _ready() -> void:
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = POLE_SIZE
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, POLE_SIZE.y * 0.5, 0.0)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pole_mat := StandardMaterial3D.new()
	pole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pole_mat.albedo_color = POLE_COLOR
	pole.material_override = pole_mat
	add_child(pole)

	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var flame_mesh := BoxMesh.new()
	flame_mesh.size = FLAME_SIZE
	flame.mesh = flame_mesh
	flame.position = Vector3(0.0, POLE_SIZE.y + FLAME_SIZE.y * 0.5, 0.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.albedo_color = FLAME_COLOR
	_flame_mat.emission_enabled = true
	_flame_mat.emission = FLAME_COLOR
	_flame_mat.emission_energy_multiplier = 0.45
	flame.material_override = _flame_mat
	add_child(flame)

	_light = OmniLight3D.new()
	_light.name = "TorchLight"
	_light.position = flame.position
	_light.light_color = LIGHT_COLOR
	_light.omni_range = RANGE
	_light.omni_attenuation = 1.8
	_light.shadow_enabled = false
	_light.light_specular = 0.0
	_light.light_energy = LIT_ENERGY
	add_child(_light)


func set_lit(on: bool) -> void:
	lit = on
	if _light != null:
		_light.light_energy = LIT_ENERGY if on else 0.0
		_light.shadow_enabled = false
	if _flame_mat != null:
		_flame_mat.emission_energy_multiplier = 0.45 if on else 0.0


func toggle() -> void:
	set_lit(not lit)


func light_energy() -> float:
	if _light == null:
		return 0.0
	return _light.light_energy


func mesh_height() -> float:
	return POLE_SIZE.y + FLAME_SIZE.y
