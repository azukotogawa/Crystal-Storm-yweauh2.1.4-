extends SceneTree

const _AO = preload("res://helpers/terrain_vertex_ao.gd")
const _Lighting = preload("res://helpers/terrain_lighting.gd")
const _Shadow = preload("res://helpers/contact_shadow.gd")
const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Quality = preload("res://config/performance_quality_config.gd")
const _Types = preload("res://helpers/voxel_types.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	_check_pure()
	_check_mesh()
	_check_quality()
	_AO.bake_enabled = true
	_Lighting.apply_preset(int(_Quality.Preset.MEDIUM))
	if _failed > 0:
		print("Lighting AO tests failed: %d" % _failed)
		quit(1)
		return
	print("All lighting AO tests OK")
	quit(0)


func _check_pure() -> void:
	var exposed := _AO.corner_ao(false, false, false)
	var one_side := _AO.corner_ao(true, false, false)
	var enclosed := _AO.corner_ao(true, true, true)
	if exposed < 0.95:
		_fail("exposed corner AO %.3f" % exposed)
	if enclosed < 0.35 or enclosed > 0.60:
		_fail("enclosed corner AO %.3f" % enclosed)
	if not (enclosed < one_side and one_side < exposed):
		_fail("AO order enclosed %.3f one %.3f exposed %.3f" % [enclosed, one_side, exposed])
	if _AO.neighbor_solid(4.0, 4.0, 2.0):
		_fail("same-height neighbor occluded a top corner")
	if not _AO.neighbor_solid(8.0, 4.0, 2.0):
		_fail("step-up neighbor did not occlude")
	if _AO.neighbor_solid(_AO.HEIGHT_MISSING, 4.0, 2.0):
		_fail("missing neighbor occluded")


func _check_mesh() -> void:
	_AO.bake_enabled = true
	var data = _ChunkData.new(Vector2i.ZERO)
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			data.patch_local_column(x, z, 4.0, _Types.GRASSLAND)
	data.patch_local_column(3, 2, 8.0, _Types.GRASSLAND)
	data.patch_local_column(2, 3, 8.0, _Types.GRASSLAND)
	data.patch_local_column(3, 3, 8.0, _Types.GRASSLAND)
	var low := _AO.sample_surface(data, 1, 2)
	var high := _AO.sample_surface(data, 3, 2)
	if low < 3.5 or high < 7.5:
		_fail("surface sample low=%.2f high=%.2f" % [low, high])
		return
	var quads: Array = [
		{"x": 2, "z": 2, "y": 4.0, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "face_code": 0, "type": _Types.GRASSLAND},
		{"x": 4, "z": 4, "y": 4.0, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "face_code": 3, "type": _Types.GRASSLAND},
		{
			"x": 5, "z": 5, "y": 4.0, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0,
			"face_code": 7, "type": _Types.GRASSLAND, "ramp_dir_x": 1, "ramp_dir_z": 0,
		},
	]
	var built: Dictionary = _Builder.build_surface_arrays_from_terrain_quads(data, quads)
	var colors: PackedColorArray = built.get("colors", PackedColorArray())
	if colors.size() < 8:
		_fail("mesh colors %d" % colors.size())
		return
	var top0: Color = colors[0]
	var top2: Color = colors[2]
	if top0.a < 0.95:
		_fail("exposed top alpha %.3f" % top0.a)
	if top2.a < 0.35 or top2.a > 0.60:
		_fail("enclosed top alpha %.3f" % top2.a)
	if top2.a >= top0.a:
		_fail("enclosed alpha %.3f is not below exposed %.3f" % [top2.a, top0.a])
	if not is_equal_approx(top0.r, top2.r) or not is_equal_approx(top0.g, top2.g) or not is_equal_approx(top0.b, top2.b):
		_fail("top RGB changed across the AO corners")
	var side_dark := false
	for i in range(4, 8):
		if colors[i].a < 0.95:
			side_dark = true
		if colors[i].a < 0.35 or colors[i].a > 0.85:
			_fail("flat side alpha %.3f at %d" % [colors[i].a, i])
			break
		if not is_equal_approx(colors[i].r, colors[4].r) or not is_equal_approx(colors[i].b, colors[4].b):
			_fail("side RGB changed at %d" % i)
			break
	if not side_dark:
		_fail("flat side face stayed fully lit")
	for i in range(8, colors.size()):
		if not is_equal_approx(colors[i].a, 1.0):
			_fail("ramp alpha %.3f at %d" % [colors[i].a, i])
			break
	var open_quads: Array = [
		{"x": 10, "z": 10, "y": 40.0, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "face_code": 4, "type": _Types.GRASSLAND},
	]
	var open_built: Dictionary = _Builder.build_surface_arrays_from_terrain_quads(data, open_quads)
	var open_colors: PackedColorArray = open_built.get("colors", PackedColorArray())
	if open_colors.size() < 4 or open_colors[0].a < 0.95:
		_fail("exposed side alpha %.3f" % (open_colors[0].a if open_colors.size() > 0 else -1.0))
	_AO.bake_enabled = false
	var flat := _AO.top_corner_ao(data, 2, 2, 1, 1, 4.0)
	if flat.distance_to(Vector4.ONE) > 0.001:
		_fail("bake off still sampled AO %s" % flat)
	var side_off := _AO.face_corner_ao(data, 3, 4, 4, 1, 1, 4.0, 1.0)
	if side_off.distance_to(Vector4.ONE) > 0.001:
		_fail("bake off still sampled side AO %s" % side_off)
	_AO.bake_enabled = true


func _check_quality() -> void:
	_Lighting.apply_preset(int(_Quality.Preset.LOW))
	if _AO.bake_enabled or _Shadow.enabled:
		_fail("LOW left AO or contact shadows on")
	var host := Node3D.new()
	host.name = "ShadowHost"
	root.add_child(host)
	if _Shadow.attach(host, 0.05, 1.0) != null:
		_fail("LOW attach created a contact shadow")
	_Lighting.apply_preset(int(_Quality.Preset.MEDIUM))
	var quad := _Shadow.attach(host, 0.05, 1.0)
	if quad == null:
		_fail("MEDIUM attach missed the contact shadow")
	elif quad.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("contact shadow casts a shadow map")
	_Lighting.apply_preset(int(_Quality.Preset.SAFE))
	if _AO.bake_enabled or _Shadow.enabled:
		_fail("SAFE left AO or contact shadows on")
	if quad != null and quad.visible:
		_fail("SAFE left the contact shadow visible")
	host.queue_free()
