extends Node3D
## Translucent fill drawn when a channel's water level changes.
## Thickness is the 0–1 fill times one voxel layer, sitting on the column top.

const _WorldSettings = preload("res://config/world_settings.gd")
const _TEX_PATH := "res://assets/tiles/water_surface.png"

var _cells: Dictionary = {}
var _tex: Texture2D


func _ready() -> void:
	_tex = _load_tex()


func set_level(pos: Vector2i, level: float, surface_y: float) -> void:
	if level < 0.05:
		_remove_cell(pos)
		return
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var vs: float = ws.voxel_scale
	var fill: float = clampf(level, 0.0, 1.0)
	var h: float = fill * layer * 0.55
	var mesh_i: MeshInstance3D = _cells.get(pos) as MeshInstance3D
	if mesh_i == null:
		mesh_i = MeshInstance3D.new()
		mesh_i.name = "Water_%d_%d" % [pos.x, pos.y]
		var box := BoxMesh.new()
		box.size = Vector3(vs * 0.92, 1.0, vs * 0.92)
		mesh_i.mesh = box
		mesh_i.material_override = _make_material(fill)
		mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_i)
		_cells[pos] = mesh_i
	else:
		var mat := mesh_i.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = lerpf(0.38, 0.9, fill)
	mesh_i.scale = Vector3(1.0, h, 1.0)
	mesh_i.position = Vector3(
		ws.column_to_world(float(pos.x) + 0.5),
		surface_y + layer + h * 0.5,
		ws.column_to_world(float(pos.y) + 0.5)
	)


func cell_height(pos: Vector2i) -> float:
	var mesh_i: MeshInstance3D = _cells.get(pos) as MeshInstance3D
	if mesh_i == null:
		return 0.0
	return mesh_i.scale.y


func cell_count() -> int:
	return _cells.size()


func _remove_cell(pos: Vector2i) -> void:
	var mesh_i: MeshInstance3D = _cells.get(pos) as MeshInstance3D
	if mesh_i == null:
		return
	_cells.erase(pos)
	mesh_i.queue_free()


func _make_material(fill: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_color = Color(0.55, 0.82, 0.95, lerpf(0.38, 0.9, fill))
	if _tex == null:
		_tex = _load_tex()
	if _tex:
		mat.albedo_texture = _tex
	return mat


func _load_tex() -> Texture2D:
	if ResourceLoader.exists(_TEX_PATH):
		var loaded: Texture2D = load(_TEX_PATH) as Texture2D
		if loaded != null:
			return loaded
	var img := Image.load_from_file(ProjectSettings.globalize_path(_TEX_PATH))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
