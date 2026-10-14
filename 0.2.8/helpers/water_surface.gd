class_name WaterSurface
extends RefCounted
## Splits water tops off the chunk mesh the view is about to draw and binds
## the wave shader on that mesh. Flow UV2 comes from the channel registry.

const _SHADER: Shader = preload("res://shaders/water_surface.gdshader")
const _ATLAS: Texture2D = preload("res://assets/tiles/Cube.png")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")

static var _material: ShaderMaterial
static var _time: float = 0.0


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = _SHADER
		_material.set_shader_parameter("texture_atlas", _ATLAS)
		_material.set_shader_parameter("atlas_grid", _VoxelTypes.atlas_grid_vec2())
		_material.set_shader_parameter("water_time", 0.0)
		_material.set_shader_parameter("flow_dir", Vector2(1.0, 0.0))
	return _material


static func advance(delta: float) -> void:
	_time += delta
	shared_material().set_shader_parameter("water_time", _time)


## Pull water tops onto a sibling mesh. Land faces, including water sides, stay.
static func bind_instance(terrain_mi: MeshInstance3D) -> void:
	if terrain_mi == null:
		return
	var parent := terrain_mi.get_parent()
	var water_mi: MeshInstance3D = null
	if parent != null:
		water_mi = parent.get_node_or_null("water_surface_mesh") as MeshInstance3D
	var src := terrain_mi.mesh as ArrayMesh
	if src == null or src.get_surface_count() < 1:
		_clear_water(water_mi)
		return
	var arrays: Array = src.surface_get_arrays(0)
	var split := _partition(arrays)
	if split.is_empty():
		_clear_water(water_mi)
		return
	var land := ArrayMesh.new()
	var land_arrays: Array = split["land"]
	if not (land_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		land.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, land_arrays)
	terrain_mi.mesh = land
	if water_mi == null:
		if parent == null:
			return
		water_mi = MeshInstance3D.new()
		water_mi.name = "water_surface_mesh"
		water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_mi.extra_cull_margin = 0.25
		parent.add_child(water_mi)
	var water := ArrayMesh.new()
	water.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, split["water"])
	water_mi.mesh = water
	water_mi.material_override = shared_material()
	water_mi.visible = true


static func _clear_water(water_mi: MeshInstance3D) -> void:
	if water_mi == null:
		return
	water_mi.mesh = null
	water_mi.material_override = null


static func _is_water_atlas(color: Color) -> bool:
	var ax := int(round(color.r * 255.0))
	var ay := int(round(color.g * 255.0))
	# Ocean row (0, 0) and river / pool (1, 0). Nothing else uses those cells.
	return (ax == 0 and ay == 0) or (ax == 1 and ay == 0)


static func _partition(arrays: Array) -> Dictionary:
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_u: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var src_c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var src_i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if src_v.is_empty() or src_i.is_empty() or src_n.is_empty() or src_c.is_empty():
		return {}
	var land_v := PackedVector3Array()
	var land_n := PackedVector3Array()
	var land_u := PackedVector2Array()
	var land_c := PackedColorArray()
	var land_i := PackedInt32Array()
	var water_v := PackedVector3Array()
	var water_n := PackedVector3Array()
	var water_u := PackedVector2Array()
	var water_c := PackedColorArray()
	var water_uv2 := PackedVector2Array()
	var water_i := PackedInt32Array()
	var i := 0
	while i + 5 < src_i.size():
		var ia := int(src_i[i])
		var ib := int(src_i[i + 1])
		var ic := int(src_i[i + 2])
		var id := int(src_i[i + 5])
		var water_top := src_n[ia].y > 0.9 and _is_water_atlas(src_c[ia])
		if water_top:
			var flow := _flow_for(src_v[ia], src_v[ib], src_v[ic], src_v[id])
			_append_quad(water_v, water_n, water_u, water_c, water_i, src_v, src_n, src_u, src_c, ia, ib, ic, id)
			for _k in 4:
				water_uv2.append(flow)
		else:
			_append_quad(land_v, land_n, land_u, land_c, land_i, src_v, src_n, src_u, src_c, ia, ib, ic, id)
		i += 6
	if water_v.is_empty():
		return {}
	var land := []
	land.resize(Mesh.ARRAY_MAX)
	land[Mesh.ARRAY_VERTEX] = land_v
	land[Mesh.ARRAY_NORMAL] = land_n
	land[Mesh.ARRAY_TEX_UV] = land_u
	land[Mesh.ARRAY_COLOR] = land_c
	land[Mesh.ARRAY_INDEX] = land_i
	var water := []
	water.resize(Mesh.ARRAY_MAX)
	water[Mesh.ARRAY_VERTEX] = water_v
	water[Mesh.ARRAY_NORMAL] = water_n
	water[Mesh.ARRAY_TEX_UV] = water_u
	water[Mesh.ARRAY_COLOR] = water_c
	water[Mesh.ARRAY_TEX_UV2] = water_uv2
	water[Mesh.ARRAY_INDEX] = water_i
	return {"land": land, "water": water}


static func _append_quad(
	dst_v: PackedVector3Array,
	dst_n: PackedVector3Array,
	dst_u: PackedVector2Array,
	dst_c: PackedColorArray,
	dst_i: PackedInt32Array,
	src_v: PackedVector3Array,
	src_n: PackedVector3Array,
	src_u: PackedVector2Array,
	src_c: PackedColorArray,
	ia: int,
	ib: int,
	ic: int,
	id: int
) -> void:
	var base := dst_v.size()
	for s in [ia, ib, ic, id]:
		dst_v.append(src_v[s])
		dst_n.append(src_n[s])
		dst_u.append(src_u[s])
		dst_c.append(src_c[s])
	dst_i.append(base)
	dst_i.append(base + 1)
	dst_i.append(base + 2)
	dst_i.append(base)
	dst_i.append(base + 2)
	dst_i.append(base + 3)


static func _flow_for(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Vector2:
	for p in [a, b, c, d]:
		var flow := _flow_at(p.x, p.z)
		if flow.length_squared() > 0.01:
			return flow
	var mid := (a + b + c + d) * 0.25
	return _flow_at(mid.x, mid.z)


static func _flow_at(world_x: float, world_z: float) -> Vector2:
	var scale: float = maxf(_WorldSettings.get_active().voxel_scale, 0.001)
	var wx := int(floor(world_x / scale))
	var wz := int(floor(world_z / scale))
	var dir: Vector2i = _ChannelRegistry.get_flow_dir(wx, wz)
	return Vector2(float(dir.x), float(dir.y))
