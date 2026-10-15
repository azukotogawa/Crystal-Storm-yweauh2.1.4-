extends SceneTree

const _Builder = preload("res://helpers/voxel_creature_builder.gd")
const _Entity = preload("res://entities/world_entity.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	if _Builder.USE_PART_RIG:
		_fail("USE_PART_RIG must stay off until a creature is switched")
	var src := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	if src.find("USE_PART_RIG") < 0 or src.find("_ensure_voxel_model") < 0 or src.find("_ensure_sprite") < 0:
		_fail("world entity must keep the sprite and voxel-prop fallback")
	var parts: Array = _Builder.parts_for(&"rabbit")
	if not _Builder.parts_fit_canvas(parts):
		_fail("default parts leave the 32px canvas")
	var rig := _Builder.build(_paint(parts), parts, 1.6, Color(0.8, 0.7, 0.6))
	if rig == null:
		_fail("full spec did not build")
		_finish()
		return
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	if skel == null:
		_fail("rig has no skeleton")
		_finish()
		return
	for bone_name in ["Body", "Head", "Leg_L", "Leg_R", "Tail", "Wing_L", "Wing_R"]:
		if skel.find_bone(bone_name) < 0:
			_fail("missing bone %s" % bone_name)
	var meshes := 0
	var min_y := 1.0e9
	var max_y := -1.0e9
	for child in skel.get_children():
		var mi := child.get_node_or_null("Mesh") as MeshInstance3D
		if mi == null or mi.mesh == null:
			_fail("part %s has no mesh" % child.name)
			continue
		meshes += 1
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() < 8:
			_fail("part %s mesh is empty" % child.name)
		for v in verts:
			var y := rig.position.y + v.y
			min_y = minf(min_y, y)
			max_y = maxf(max_y, y)
	if meshes < 7:
		_fail("expected 7 part meshes, got %d" % meshes)
	elif min_y > 0.08 or max_y < 1.4:
		_fail("rig span y %.3f..%.3f is not the requested height" % [min_y, max_y])
	else:
		print("OK rig bones %d meshes span %.3f..%.3f" % [skel.get_bone_count(), min_y, max_y])
	_Builder.apply_pose(rig, "walk", 1.2)
	var leg_q := skel.get_bone_pose_rotation(skel.find_bone("Leg_L"))
	var tail_q := skel.get_bone_pose_rotation(skel.find_bone("Tail"))
	var wing_q := skel.get_bone_pose_rotation(skel.find_bone("Wing_L"))
	if leg_q.is_equal_approx(Quaternion.IDENTITY):
		_fail("walk left the leg at rest")
	elif tail_q.is_equal_approx(Quaternion.IDENTITY):
		_fail("walk left the tail at rest")
	elif wing_q.is_equal_approx(Quaternion.IDENTITY):
		_fail("walk left the wing at rest")
	else:
		print("OK walk pose leg %s" % leg_q)
	var slim: Array = []
	for part in parts:
		var kind := str(part["kind"])
		if kind == "tail" or kind == "wing":
			continue
		slim.append(part)
	var slim_rig := _Builder.build(_paint(slim), slim, 1.2)
	if slim_rig == null:
		_fail("spec without tail or wings did not build")
	else:
		var slim_skel := slim_rig.get_node("Skeleton") as Skeleton3D
		if slim_skel.find_bone("Tail") >= 0 or slim_skel.find_bone("Wing_L") >= 0:
			_fail("optional parts were built from a spec that omitted them")
		elif slim_skel.find_bone("Head") < 0 or slim_skel.find_bone("Leg_R") < 0:
			_fail("trimmed spec dropped a required bone")
		else:
			print("OK trimmed spec bones %d" % slim_skel.get_bone_count())
		slim_rig.free()
	var broken: Array = []
	for part in slim:
		if str(part["kind"]) == "body":
			continue
		broken.append(part)
	if _Builder.build(_paint(broken), broken, 1.2) != null:
		_fail("a spec with no body still built")
	else:
		print("OK missing body refused")
	if _Builder.build(null, parts, 1.2) != null:
		_fail("a null image still built")
	var holder := Node.new()
	root.add_child(holder)
	var entity := _Entity.new()
	holder.add_child(entity)
	entity._ensure_visual(Color.WHITE)
	if entity.get_node_or_null("CreatureRig") != null:
		_fail("flag off still spawned a part rig")
	elif entity.get_node_or_null("MeshInstance3D") == null:
		_fail("flag off did not keep the capsule fallback")
	else:
		print("OK entity fallback capsule")
	holder.free()
	rig.free()
	_finish()


func _paint(parts: Array) -> Image:
	var img := Image.create(_Builder.CANVAS, _Builder.CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var n := 0
	for part in parts:
		var tint := Color(0.25 + 0.1 * float(n % 4), 0.45, 0.32, 1.0)
		n += 1
		for y in int(part["h"]):
			for x in int(part["w"]):
				img.set_pixel(int(part["x"]) + x, int(part["y"]) + y, tint)
	return img


func _finish() -> void:
	if _failed == 0:
		print("All voxel creature tests OK")
		quit(0)
	else:
		push_error("verify_voxel_creature: %d failure(s)" % _failed)
		quit(1)
