extends SceneTree

const _Builder = preload("res://helpers/voxel_creature_builder.gd")
const _Model = preload("res://helpers/voxel_model_builder.gd")
const _Pose = preload("res://entities/creature_pose.gd")
const _Entity = preload("res://entities/world_entity.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	var builder_src := FileAccess.get_file_as_string("res://helpers/voxel_creature_builder.gd")
	if builder_src.find("CANVAS") >= 0 or builder_src.find("Sprite3D") >= 0 or builder_src.find("DEPTH_STEPS") >= 0:
		_fail("creature builder still cuts a sprite canvas")
	if builder_src.find("if not USE_PART_RIG") < 0:
		_fail("part rig flag no longer gates the voxel creatures")
	var entity_src := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	if entity_src.find("uses_rig") < 0 or entity_src.find("_ensure_voxel_model") < 0 or entity_src.find("_ensure_sprite") < 0:
		_fail("world entity must keep the sprite and voxel-prop fallback")
	if not _Builder.USE_PART_RIG:
		_fail("USE_PART_RIG is off, so boar and deer stay on the old visual")
	if _Builder.uses_rig(&"rabbit") or _Builder.uses_rig(&"bird"):
		_fail("unconverted creatures must stay off the part rig")
	if not _Builder.uses_rig(&"boar") or not _Builder.uses_rig(&"deer"):
		_fail("boar and deer must use the part rig")
	if not _Builder.parts_for(&"rabbit").is_empty():
		_fail("rabbit has no voxel part spec")
	_check_kind(&"boar")
	_check_kind(&"deer")
	_check_optional_wing()
	_check_entities()
	_finish()


func _check_kind(kind: StringName) -> void:
	var parts: Array = _Builder.parts_for(kind)
	if not _has_kinds(parts, true, false):
		_fail("%s spec is not head, body, two legs, and a tail" % kind)
		return
	for part in parts:
		var spec: Dictionary = part
		if spec.has("w") or spec.has("h"):
			_fail("%s part %s still has a sprite rectangle" % [kind, spec.get("id", "")])
		var cells: Array = spec.get("cells", [])
		if cells.is_empty() or not (cells[0] is Vector4i):
			_fail("%s part %s is not a voxel grid" % [kind, spec.get("id", "")])
	var rig := _Builder.build(kind)
	if rig == null:
		_fail("%s did not build" % kind)
		return
	root.add_child(rig)
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	var player := rig.get_node_or_null("CreatureAnim") as AnimationPlayer
	if skel == null or player == null:
		_fail("%s rig is missing the skeleton or the animation player" % kind)
		rig.free()
		return
	for clip in ["idle", "walk", "attack"]:
		if not player.has_animation(clip):
			_fail("%s missing clip %s" % [kind, clip])
	for bone_name in ["Body", "Head", "Leg_L", "Leg_R", "Tail"]:
		if skel.find_bone(bone_name) < 0:
			_fail("%s missing bone %s" % [kind, bone_name])
	if skel.find_bone("Wing_L") >= 0:
		_fail("%s built a wing it does not have" % kind)
	var cube := _Builder.cube_edge()
	var body_mi := _part_mi(skel, "body")
	var body: ArrayMesh = body_mi.mesh as ArrayMesh if body_mi != null else null
	if body == null:
		_fail("%s body has no mesh" % kind)
	else:
		var box := body.get_aabb()
		if box.size.x <= cube * 1.5 or box.size.y <= cube * 1.5 or box.size.z <= cube * 1.5:
			_fail("%s body is a slab %s" % [kind, box.size])
		elif _Model.face_count(body) < 6:
			_fail("%s body faces %d" % [kind, _Model.face_count(body)])
		elif body_mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("%s body casts a shadow" % kind)
		else:
			print("OK %s body %s faces %d" % [kind, box.size, _Model.face_count(body)])
	_Builder.play(rig, "idle", 1.2)
	var head_y := skel.get_bone_pose_position(skel.find_bone("Head")).y
	var idle_lift := sin(1.2) * _Pose.IDLE_LIFT
	if absf(head_y - idle_lift) > 0.04:
		_fail("%s idle head y %.3f want %.3f" % [kind, head_y, idle_lift])
	else:
		print("OK %s idle head %.3f" % [kind, head_y])
	_Builder.play(rig, "walk", 1.2)
	var leg_q := skel.get_bone_pose_rotation(skel.find_bone("Leg_L"))
	var leg_z := skel.get_bone_pose_position(skel.find_bone("Leg_L")).z
	var walk_z := sin(1.2) * -1.0 * _Pose.WALK_STEP
	if leg_q.is_equal_approx(Quaternion.IDENTITY):
		_fail("%s walk left the leg at rest" % kind)
	elif absf(leg_z - walk_z) > 0.05:
		_fail("%s walk leg z %.3f want %.3f" % [kind, leg_z, walk_z])
	else:
		print("OK %s walk leg %s" % [kind, leg_q])
	_Builder.play(rig, "attack", 0.4)
	var lunge := skel.get_bone_pose_position(skel.find_bone("Body")).z
	var leg_attack := skel.get_bone_pose_rotation(skel.find_bone("Leg_R"))
	if absf(lunge - (-_Pose.ATTACK_LUNGE)) > 0.04:
		_fail("%s attack lunge %.3f" % [kind, lunge])
	elif leg_attack.is_equal_approx(Quaternion.IDENTITY):
		_fail("%s attack left the leg at rest" % kind)
	else:
		print("OK %s attack lunge %.3f" % [kind, lunge])
	rig.free()


func _has_kinds(parts: Array, want_tail: bool, want_wing: bool) -> bool:
	var head := 0
	var body := 0
	var legs := 0
	var tail := 0
	var wing := 0
	for part in parts:
		var kind := str((part as Dictionary).get("kind", ""))
		if kind == "head":
			head += 1
		elif kind == "body":
			body += 1
		elif kind == "leg":
			legs += 1
		elif kind == "tail":
			tail += 1
		elif kind == "wing":
			wing += 1
	if head != 1 or body != 1 or legs != 2:
		return false
	if want_tail != (tail == 1):
		return false
	if want_wing != (wing >= 1):
		return false
	return true


func _part_mi(skel: Skeleton3D, part_name: String) -> MeshInstance3D:
	var att := skel.get_node_or_null(part_name)
	if att == null:
		return null
	return att.get_node_or_null("Mesh") as MeshInstance3D


func _check_optional_wing() -> void:
	var parts: Array = _Builder.parts_for(&"deer").duplicate(true)
	parts.append({
		"id": "wing_l",
		"kind": "wing",
		"bone": "Wing_L",
		"parent": "Body",
		"pivot": "center",
		"cells": [Vector4i(0, 6, 7, 1), Vector4i(1, 6, 7, 1), Vector4i(0, 7, 7, 1)],
	})
	var rig := _Builder.build_parts(parts, _Builder.palette_for(&"deer"), _Builder.cube_edge())
	if rig == null:
		_fail("a spec with a wing did not build")
	else:
		var skel := rig.get_node("Skeleton") as Skeleton3D
		if skel.find_bone("Wing_L") < 0:
			_fail("wing part did not add a bone")
		else:
			print("OK optional wing")
		rig.free()
	var broken: Array = []
	for part in _Builder.parts_for(&"boar"):
		if str((part as Dictionary).get("kind", "")) == "body":
			continue
		broken.append(part)
	if _Builder.build_parts(broken, _Builder.palette_for(&"boar"), _Builder.cube_edge()) != null:
		_fail("a spec with no body still built")
	else:
		print("OK missing body refused")


func _check_entities() -> void:
	var holder := Node.new()
	root.add_child(holder)
	var rabbit := _Entity.new()
	rabbit.entity_kind = &"rabbit"
	holder.add_child(rabbit)
	rabbit._ensure_visual(Color.WHITE)
	if rabbit.get_node_or_null("CreatureRig") != null:
		_fail("rabbit spawned a part rig")
	elif rabbit.get_node_or_null("MeshInstance3D") == null:
		_fail("rabbit lost the capsule fallback")
	else:
		print("OK rabbit fallback capsule")
	for kind in [&"boar", &"deer"]:
		var entity := _Entity.new()
		entity.entity_kind = kind
		holder.add_child(entity)
		entity._ensure_visual(Color.WHITE)
		var rig := entity.get_node_or_null("CreatureRig")
		var anim := entity.get_node_or_null("CreatureRig/CreatureAnim") as AnimationPlayer
		if rig == null or not rig.visible:
			_fail("%s did not spawn a visible part rig" % kind)
		elif anim == null or not anim.has_animation("walk"):
			_fail("%s rig has no walk clip" % kind)
		elif (entity.get_node_or_null("MeshInstance3D") as MeshInstance3D) != null and (entity.get_node("MeshInstance3D") as MeshInstance3D).visible:
			_fail("%s kept the capsule beside the rig" % kind)
		else:
			print("OK %s entity rig" % kind)
	holder.free()


func _finish() -> void:
	if _failed == 0:
		print("All voxel creature tests OK")
		quit(0)
	else:
		push_error("verify_voxel_creature: %d failure(s)" % _failed)
		quit(1)
