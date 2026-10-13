class_name StructureCutawayMaterial
extends RefCounted
## One cached ShaderMaterial per structure look. Built when a mesh is configured,
## never per frame. The shader discards the camera cutaway cone.

const SHADER_PATH := "res://shaders/StructureCutaway.gdshader"
const _SHADER: Shader = preload("res://shaders/StructureCutaway.gdshader")

static var _cache: Dictionary = {}
static var _nearest_checked: bool = false
static var _nearest_ok: bool = false


static func is_cutaway(mat: Material) -> bool:
	if mat == null or not (mat is ShaderMaterial):
		return false
	var sh: Shader = (mat as ShaderMaterial).shader
	if sh == null:
		return false
	return sh == _SHADER or sh.resource_path == SHADER_PATH


static func albedo_texture(mat: Material) -> Texture2D:
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		var value: Variant = (mat as ShaderMaterial).get_shader_parameter("albedo_texture")
		if value is Texture2D:
			return value as Texture2D
	return null


static func binds_albedo(mat: Material) -> bool:
	return albedo_texture(mat) != null


## Nearest filter, same as the old BaseMaterial3D.TEXTURE_FILTER_NEAREST.
static func uses_nearest_filter(mat: Material) -> bool:
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if not is_cutaway(mat):
		return false
	return _shader_uses_nearest()


static func make(
	albedo: Texture2D,
	color: Color,
	roughness: float,
	metallic: float,
	emission: Color,
	emission_energy: float,
	vertex_color_as_albedo: bool = false,
	alpha_scissor: float = 0.0,
	authored_path: String = ""
) -> ShaderMaterial:
	var key := _key(albedo, color, roughness, metallic, emission, emission_energy, vertex_color_as_albedo, alpha_scissor, authored_path)
	if _cache.has(key):
		return _cache[key] as ShaderMaterial
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	if albedo != null:
		mat.set_shader_parameter("albedo_texture", albedo)
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("roughness_amount", roughness)
	mat.set_shader_parameter("metallic_amount", metallic)
	mat.set_shader_parameter("emission_color", Vector3(emission.r, emission.g, emission.b))
	mat.set_shader_parameter("emission_energy", emission_energy)
	mat.set_shader_parameter("vertex_color_as_albedo", 1.0 if vertex_color_as_albedo else 0.0)
	mat.set_shader_parameter("alpha_scissor", alpha_scissor)
	if not authored_path.is_empty():
		mat.set_meta("authored_albedo_path", authored_path)
	mat.set_meta("texture_filter_nearest", true)
	_cache[key] = mat
	return mat


static func _shader_uses_nearest() -> bool:
	if _nearest_checked:
		return _nearest_ok
	_nearest_checked = true
	var code := ""
	if _SHADER != null:
		code = _SHADER.code
	_nearest_ok = "filter_nearest" in code
	return _nearest_ok


static func _key(
	albedo: Texture2D,
	color: Color,
	roughness: float,
	metallic: float,
	emission: Color,
	emission_energy: float,
	vertex_color_as_albedo: bool,
	alpha_scissor: float,
	authored_path: String
) -> String:
	var tex_id := 0
	if albedo != null:
		tex_id = albedo.get_instance_id()
	return "%d|%.4f,%.4f,%.4f,%.4f|%.4f|%.4f|%.4f,%.4f,%.4f|%.4f|%d|%.4f|%s" % [
		tex_id,
		color.r, color.g, color.b, color.a,
		roughness,
		metallic,
		emission.r, emission.g, emission.b,
		emission_energy,
		1 if vertex_color_as_albedo else 0,
		alpha_scissor,
		authored_path,
	]
