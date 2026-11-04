extends Node

const _Day = preload("res://helpers/day_night.gd")
const _Terrain = preload("res://helpers/terrain_lighting.gd")
const _Gate = preload("res://helpers/gameplay_input.gd")

var _elapsed := 0.0
var _base_ambient := -1.0
var _base_fog := -1.0
var _base_sun := -1.0
var _sun_basis := Basis.IDENTITY
var _have_basis := false


func _ready() -> void:
	add_to_group("day_night")
	process_priority = 8
	_elapsed = _Day.DAY_LENGTH_SEC * _Day.NOON_PHASE
	_capture()
	_apply()


func _process(delta: float) -> void:
	if not _Gate.blocks_actions():
		_elapsed += delta
	_apply()


func force_phase(phase: float) -> void:
	_elapsed = _Day.DAY_LENGTH_SEC * phase
	if _base_ambient < 0.0:
		_capture()
	_apply()


func ambient_energy() -> float:
	var env := _environment()
	if env == null:
		return -1.0
	return env.ambient_light_energy


func sun_energy() -> float:
	var light := _light()
	if light == null:
		return -1.0
	return light.light_energy


func _capture() -> void:
	var env := _environment()
	if env != null:
		_base_ambient = env.ambient_light_energy
		_base_fog = env.fog_light_energy
	var light := _light()
	if light != null:
		_base_sun = light.light_energy
		_sun_basis = _Terrain.SUN_BASIS if light.transform.basis.is_equal_approx(_Terrain.SUN_BASIS.transposed()) else light.transform.basis
		_have_basis = true


func _apply() -> void:
	var phase := _Day.phase_of(_elapsed)
	var amb := _Day.ambient_factor(phase)
	var sun := _Day.sun_factor(phase)
	var gain := _Day.terrain_gain(phase)
	var env := _environment()
	if env != null and _base_ambient >= 0.0:
		env.ambient_light_energy = _base_ambient * amb
		if _base_fog >= 0.0:
			env.fog_light_energy = _base_fog * amb
	var light := _light()
	if light != null and _base_sun >= 0.0:
		light.light_energy = _base_sun * sun
		if _have_basis:
			light.transform = Transform3D(_sun_basis, light.transform.origin)
	_Terrain.ensure_globals()
	RenderingServer.global_shader_parameter_set("terrain_day_gain", gain)
	RenderingServer.global_shader_parameter_set("terrain_sun_dir", _Terrain.SUN)


func _environment() -> Environment:
	var host := get_parent()
	if host == null:
		return null
	var named := host.get_node_or_null("WorldEnvironment")
	var world_env: WorldEnvironment = named as WorldEnvironment
	if world_env == null:
		world_env = host.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_env == null:
		return null
	return world_env.environment


func _light() -> DirectionalLight3D:
	var host := get_parent()
	if host == null:
		return null
	var named := host.get_node_or_null("DirectionalLight3D")
	if named is DirectionalLight3D:
		return named
	return host.find_child("DirectionalLight3D", true, false) as DirectionalLight3D
