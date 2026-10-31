extends RefCounted

const _SHADER = preload("res://shaders/VoxelProp.gdshader")

static var _cache: Dictionary = {}


static func from_standard(src: Material) -> Material:
	var sm := src as StandardMaterial3D
	if sm == null or sm.emission_enabled:
		return src
	var tex_path := sm.albedo_texture.resource_path if sm.albedo_texture != null else ""
	var key := "%s|%s|%s|%s|%s" % [sm.albedo_color, tex_path, sm.vertex_color_use_as_albedo, 0, 0]
	if _cache.has(key):
		return _cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("albedo_color", sm.albedo_color)
	if sm.albedo_texture != null:
		mat.set_shader_parameter("albedo_texture", sm.albedo_texture)
		mat.set_shader_parameter("use_texture", 1.0)
	mat.set_shader_parameter("use_vertex_color", 1.0 if sm.vertex_color_use_as_albedo else 0.0)
	_cache[key] = mat
	return mat


static func apply(root: Node) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.material_override != null:
			mi.material_override = from_standard(mi.material_override)
	for ch in root.get_children():
		apply(ch)
