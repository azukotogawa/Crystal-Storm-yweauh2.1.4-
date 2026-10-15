extends SceneTree

const _Model = preload("res://helpers/voxel_model_builder.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	if _Model.USE_GRID_PARTS:
		_fail("USE_GRID_PARTS must stay off so current part visuals remain")
	var body_src := FileAccess.get_file_as_string("res://player/player_body_mesh.gd")
	if body_src.find("USE_GRID_PARTS") < 0 or body_src.find("_apply_rig") < 0 or body_src.find("USE_SLAB_BODY") < 0:
		_fail("player body must keep the slab and part-rig fallback")
	var entity_src := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	if entity_src.find("USE_GRID_PARTS") < 0 or entity_src.find("_ensure_sprite") < 0 or entity_src.find("_ensure_voxel_model") < 0:
		_fail("world entity must keep the sprite and voxel-prop fallback")
	if not _Model.parts_for(&"player").is_empty():
		_fail("player grid parts must stay empty until a model is authored")
	var tunic := Color(0.22, 0.42, 0.34)
	var boot := Color(0.20, 0.14, 0.10)
	var palette := PackedColorArray([Color.BLACK, tunic, boot])
	var cube := _Model.build_mesh([Vector4i(0, 0, 0, 1)], palette, 1.0)
	if cube == null:
		_fail("single cube did not build")
		_finish()
		return
	if _Model.face_count(cube) != 6:
		_fail("single cube faces %d" % _Model.face_count(cube))
	else:
		print("OK cube faces 6")
	_check_lit(cube, tunic)
	var block := _Model.build_mesh(_fill(2, 2, 2, 1), palette, 1.0)
	if _Model.face_count(block) != 6:
		_fail("greedy 2x2x2 faces %d" % _Model.face_count(block))
	else:
		print("OK greedy block faces 6")
	var bar := _Model.build_mesh([Vector4i(0, 0, 0, 1), Vector4i(1, 0, 0, 1)], palette, 1.0)
	if _Model.face_count(bar) != 6:
		_fail("same-material bar faces %d" % _Model.face_count(bar))
	else:
		print("OK merged bar faces 6")
	var split := _Model.build_mesh([Vector4i(0, 0, 0, 1), Vector4i(0, 1, 0, 2)], palette, 1.0)
	if _Model.face_count(split) != 10:
		_fail("two-material stack faces %d" % _Model.face_count(split))
	else:
		print("OK split stack faces 10")
	if _Model.build_mesh([], palette, 1.0) != null:
		_fail("empty grid built a mesh")
	var torso_cells := [Vector4i(1, 2, 0, 1)]
	var leg_cells := [Vector4i(0, 0, 0, 2), Vector4i(0, 1, 0, 2)]
	var parts: Array = [
		{"id": "torso", "bone": "Torso", "parent": "Root", "pivot": "bottom", "cells": torso_cells},
		{"id": "leg", "bone": "Leg", "parent": "Torso", "pivot": "top", "cells": leg_cells},
	]
	var rig := _Model.build_rig(parts, palette, 1.0)
	if rig == null:
		_fail("rig did not build")
		_finish()
		return
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	if skel == null:
		_fail("rig has no skeleton")
		_finish()
		return
	var torso_i := skel.find_bone("Torso")
	var leg_i := skel.find_bone("Leg")
	if torso_i < 0 or leg_i < 0:
		_fail("rig missing torso or leg bone")
	else:
		var torso_box := _part_aabb(skel, "torso")
		var leg_box := _part_aabb(skel, "leg")
		var torso_pivot := _Model.pivot_of("bottom", torso_box)
		var leg_pivot := _Model.pivot_of("top", leg_box)
		var torso_rest: Vector3 = skel.get_bone_rest(torso_i).origin
		var leg_rest: Vector3 = skel.get_bone_rest(leg_i).origin
		if not torso_rest.is_equal_approx(torso_pivot):
			_fail("torso rest %s != bottom pivot %s" % [torso_rest, torso_pivot])
		elif not leg_rest.is_equal_approx(leg_pivot - torso_pivot):
			_fail("leg rest %s != pivot delta %s" % [leg_rest, leg_pivot - torso_pivot])
		elif not _mesh_offset(skel, "leg").is_equal_approx(-leg_pivot):
			_fail("leg mesh is not seated on its pivot")
		else:
			print("OK pivots torso %s leg %s" % [torso_pivot, leg_pivot])
	var holder := Node3D.new()
	root.add_child(holder)
	var lone := _Model.build_mesh(leg_cells, palette, 1.0)
	var pivot := _Model.attach_on_pivot(holder, "LegPivot", lone, _Model.pivot_of("top", lone.get_aabb()))
	if pivot == null:
		_fail("pivot attach failed")
	else:
		var mi := pivot.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			_fail("pivot mesh does not cast shadows")
		elif not mi.position.is_equal_approx(-pivot.position):
			_fail("pivot mesh offset %s" % mi.position)
		else:
			print("OK pivot node %s" % pivot.position)
	if _Model.build_rig([{"id": "arm", "bone": "Arm", "parent": "Missing", "cells": torso_cells}], palette, 1.0) != null:
		_fail("a part with no parent bone still built")
	else:
		print("OK missing parent refused")
	holder.free()
	rig.free()
	_finish()


func _check_lit(mesh: ArrayMesh, albedo: Color) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if normals.size() != colors.size() or normals.is_empty():
		_fail("mesh has no normals")
		return
	var axes := {}
	for n in normals:
		if absf(n.length() - 1.0) > 0.001:
			_fail("normal %s is not unit length" % n)
			return
		if maxf(absf(n.x), maxf(absf(n.y), absf(n.z))) < 0.999:
			_fail("normal %s is not a face axis" % n)
			return
		axes[n] = true
	if axes.size() != 6:
		_fail("cube normals %d" % axes.size())
		return
	for col in colors:
		if not _flat_albedo(col, albedo):
			_fail("vertex color %s is not the flat palette %s" % [col, albedo])
			return
	var mat := _Model.make_material()
	if mat.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or not mat.vertex_color_use_as_albedo:
		_fail("material is not lit from vertex color")
	else:
		print("OK lit normals %d" % normals.size())


func _part_aabb(skel: Skeleton3D, part_name: String) -> AABB:
	var att := skel.get_node_or_null(part_name) as BoneAttachment3D
	var mi := att.get_node_or_null("Mesh") as MeshInstance3D
	return mi.mesh.get_aabb()


func _mesh_offset(skel: Skeleton3D, part_name: String) -> Vector3:
	var att := skel.get_node_or_null(part_name) as BoneAttachment3D
	var mi := att.get_node_or_null("Mesh") as MeshInstance3D
	return mi.position


func _flat_albedo(got: Color, albedo: Color) -> bool:
	var step := 1.5 / 255.0
	if absf(got.r - albedo.r) > step or absf(got.g - albedo.g) > step or absf(got.b - albedo.b) > step:
		return false
	if absf(got.r - albedo.r * 0.84) < step:
		return false
	return got.a > 0.99


func _fill(w: int, h: int, d: int, mat: int) -> Array:
	var cells: Array = []
	for z in d:
		for y in h:
			for x in w:
				cells.append(Vector4i(x, y, z, mat))
	return cells


func _finish() -> void:
	if _failed == 0:
		print("All voxel model builder tests OK")
		quit(0)
	else:
		push_error("verify_voxel_model_builder: %d failure(s)" % _failed)
		quit(1)
