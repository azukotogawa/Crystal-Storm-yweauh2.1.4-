class_name VoxelCreatureBuilder
extends RefCounted

const USE_PART_RIG := true

const _Model = preload("res://helpers/voxel_model_builder.gd")
const _Pose = preload("res://entities/creature_pose.gd")
const _Settings = preload("res://config/world_settings.gd")

const _ANIM_LEN := TAU
const _ANIM_STEPS := 16


static func uses_rig(kind: StringName) -> bool:
	if not USE_PART_RIG:
		return false
	return kind == &"boar" or kind == &"deer"


static func parts_for(kind: StringName) -> Array:
	if kind == &"boar":
		return _boar_parts()
	if kind == &"deer":
		return _deer_parts()
	return []


static func palette_for(kind: StringName) -> PackedColorArray:
	if kind == &"boar":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.48, 0.36, 0.32),
			Color(0.66, 0.50, 0.42),
			Color(0.22, 0.14, 0.12),
			Color(0.08, 0.08, 0.08),
		])
	if kind == &"deer":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.72, 0.52, 0.38),
			Color(0.86, 0.72, 0.54),
			Color(0.32, 0.20, 0.12),
			Color(0.08, 0.08, 0.08),
		])
	return PackedColorArray()


static func cube_edge() -> float:
	var grid_y := _Model.player_grid_size().y
	if grid_y <= 0:
		return 0.0
	return _Settings.get_active().player_height() / float(grid_y)


static func build(kind: StringName) -> Node3D:
	return build_parts(parts_for(kind), palette_for(kind), cube_edge())


static func build_parts(parts: Array, palette: PackedColorArray, cube: float) -> Node3D:
	if cube <= 0.0 or not _spec_ok(parts):
		return null
	var rig: Node3D = _Model.build_rig(parts, palette, cube)
	if rig == null:
		return null
	rig.name = "CreatureRig"
	rig.set_meta("model_height", _span_height(parts, cube))
	_mute_shadows(rig)
	_attach_anims(rig)
	return rig


static func play(rig: Node3D, pose: String, phase: float) -> void:
	if rig == null:
		return
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	var player := rig.get_node_or_null("CreatureAnim") as AnimationPlayer
	if skel == null or player == null:
		return
	var clip := pose if player.has_animation(pose) else "idle"
	if str(player.assigned_animation) != clip:
		player.play(clip)
	var anim := player.get_animation(clip)
	var length := _ANIM_LEN if anim == null else anim.length
	skel.reset_bone_poses()
	player.seek(fposmod(phase, maxf(length, 0.001)), true)
	if skel.has_method("force_update_all_bone_transforms"):
		skel.force_update_all_bone_transforms()


static func _boar_parts() -> Array:
	var hide := 1
	var belly := 2
	var dark := 3
	var eye := 4
	var body: Array = []
	_fill(body, 2, 3, 4, 8, 7, 11, hide)
	_fill(body, 3, 3, 5, 7, 4, 10, belly)
	var head: Array = []
	_fill(head, 3, 4, 0, 7, 7, 4, hide)
	_fill(head, 4, 4, 0, 6, 5, 2, dark)
	_fill(head, 3, 6, 1, 4, 7, 2, eye)
	_fill(head, 6, 6, 1, 7, 7, 2, eye)
	var leg_l: Array = []
	_fill(leg_l, 1, 1, 4, 3, 3, 6, hide)
	_fill(leg_l, 1, 0, 4, 3, 1, 6, dark)
	_fill(leg_l, 1, 1, 8, 3, 3, 10, hide)
	_fill(leg_l, 1, 0, 8, 3, 1, 10, dark)
	var leg_r: Array = []
	_fill(leg_r, 7, 1, 4, 9, 3, 6, hide)
	_fill(leg_r, 7, 0, 4, 9, 1, 6, dark)
	_fill(leg_r, 7, 1, 8, 9, 3, 10, hide)
	_fill(leg_r, 7, 0, 8, 9, 1, 10, dark)
	var tail: Array = []
	_fill(tail, 4, 6, 11, 6, 7, 14, hide)
	return [
		_part("body", "body", "Body", "Root", "bottom", body),
		_part("head", "head", "Head", "Body", "bottom", head),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r),
		_part("tail", "tail", "Tail", "Body", "center", tail),
	]


static func _deer_parts() -> Array:
	var hide := 1
	var belly := 2
	var horn := 3
	var eye := 4
	var body: Array = []
	_fill(body, 3, 5, 5, 7, 9, 12, hide)
	_fill(body, 3, 5, 6, 7, 6, 11, belly)
	var head: Array = []
	_fill(head, 3, 8, 1, 7, 12, 5, hide)
	_fill(head, 4, 8, 0, 6, 10, 2, hide)
	_fill(head, 3, 10, 1, 4, 11, 2, eye)
	_fill(head, 6, 10, 1, 7, 11, 2, eye)
	_fill(head, 3, 12, 2, 4, 15, 3, horn)
	_fill(head, 6, 12, 2, 7, 15, 3, horn)
	var leg_l: Array = []
	_fill(leg_l, 2, 1, 5, 4, 5, 7, hide)
	_fill(leg_l, 2, 0, 5, 4, 1, 7, horn)
	_fill(leg_l, 2, 1, 9, 4, 5, 11, hide)
	_fill(leg_l, 2, 0, 9, 4, 1, 11, horn)
	var leg_r: Array = []
	_fill(leg_r, 6, 1, 5, 8, 5, 7, hide)
	_fill(leg_r, 6, 0, 5, 8, 1, 7, horn)
	_fill(leg_r, 6, 1, 9, 8, 5, 11, hide)
	_fill(leg_r, 6, 0, 9, 8, 1, 11, horn)
	var tail: Array = []
	_fill(tail, 4, 8, 12, 6, 9, 14, belly)
	return [
		_part("body", "body", "Body", "Root", "bottom", body),
		_part("head", "head", "Head", "Body", "bottom", head),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r),
		_part("tail", "tail", "Tail", "Body", "center", tail),
	]


static func _part(id: String, kind: String, bone: String, parent: String, pivot: String, cells: Array) -> Dictionary:
	return {
		"id": id,
		"kind": kind,
		"bone": bone,
		"parent": parent,
		"pivot": pivot,
		"cells": cells,
	}


static func _fill(into: Array, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, mat: int) -> void:
	for z in range(z0, z1):
		for y in range(y0, y1):
			for x in range(x0, x1):
				into.append(Vector4i(x, y, z, mat))


static func _spec_ok(parts: Array) -> bool:
	var head := 0
	var body := 0
	var legs := 0
	for part in parts:
		if not (part is Dictionary):
			return false
		var spec: Dictionary = part
		var kind := str(spec.get("kind", ""))
		if kind != "head" and kind != "body" and kind != "leg" and kind != "tail" and kind != "wing":
			return false
		var cells: Array = spec.get("cells", [])
		if cells.is_empty():
			return false
		if kind == "head":
			head += 1
		elif kind == "body":
			body += 1
		elif kind == "leg":
			legs += 1
	return head >= 1 and body >= 1 and legs >= 2


static func _span_height(parts: Array, cube: float) -> float:
	var max_y := 0
	for part in parts:
		for cell in (part as Dictionary).get("cells", []):
			if cell is Vector4i:
				max_y = maxi(max_y, (cell as Vector4i).y + 1)
	return float(max_y) * cube


static func _mute_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_mute_shadows(child)


static func _attach_anims(rig: Node3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "CreatureAnim"
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.add_child(player)
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _anim_idle())
	lib.add_animation(&"walk", _anim_walk())
	lib.add_animation(&"attack", _anim_attack())
	player.add_animation_library(&"", lib)


static func _anim_idle() -> Animation:
	var anim := _clip()
	_pos_sin(anim, "Head", Vector3.ZERO, _Pose.IDLE_LIFT, 1.0)
	return anim


static func _anim_walk() -> Animation:
	var anim := _clip()
	_pos_abs_sin(anim, "Head", _Pose.WALK_BOB, 2.0)
	_leg_gait(anim, "Leg_L", -1.0)
	_leg_gait(anim, "Leg_R", 1.0)
	return anim


static func _anim_attack() -> Animation:
	var anim := _clip()
	_pos_hold(anim, "Body", Vector3(0.0, 0.0, -_Pose.ATTACK_LUNGE))
	_rot_hold(anim, "Leg_L", -_Pose.ATTACK_LEG)
	_rot_hold(anim, "Leg_R", _Pose.ATTACK_LEG)
	return anim


static func _leg_gait(anim: Animation, bone_name: String, side: float) -> void:
	var rot := _track(anim, Animation.TYPE_ROTATION_3D, bone_name)
	var pos := _track(anim, Animation.TYPE_POSITION_3D, bone_name)
	for i in _ANIM_STEPS:
		var t := _ANIM_LEN * float(i) / float(_ANIM_STEPS)
		var swing := sin(t)
		var kick := swing * side
		anim.rotation_track_insert_key(rot, t, Quaternion(Vector3.RIGHT, kick * _Pose.WALK_LEG))
		anim.position_track_insert_key(pos, t, Vector3(0.0, absf(swing) * _Pose.WALK_LIFT, kick * _Pose.WALK_STEP))


static func _clip() -> Animation:
	var anim := Animation.new()
	anim.length = _ANIM_LEN
	anim.loop_mode = Animation.LOOP_LINEAR
	return anim


static func _bone_path(bone_name: String) -> NodePath:
	return NodePath("Skeleton:" + bone_name)


static func _track(anim: Animation, kind: Animation.TrackType, bone_name: String) -> int:
	var track := anim.add_track(kind)
	anim.track_set_path(track, _bone_path(bone_name))
	anim.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	return track


static func _pos_sin(anim: Animation, bone_name: String, base: Vector3, lift: float, freq: float) -> void:
	var track := _track(anim, Animation.TYPE_POSITION_3D, bone_name)
	for i in _ANIM_STEPS:
		var t := _ANIM_LEN * float(i) / float(_ANIM_STEPS)
		anim.position_track_insert_key(track, t, base + Vector3(0.0, sin(t * freq) * lift, 0.0))


static func _pos_abs_sin(anim: Animation, bone_name: String, lift: float, freq: float) -> void:
	var track := _track(anim, Animation.TYPE_POSITION_3D, bone_name)
	for i in _ANIM_STEPS:
		var t := _ANIM_LEN * float(i) / float(_ANIM_STEPS)
		anim.position_track_insert_key(track, t, Vector3(0.0, absf(sin(t * freq)) * lift, 0.0))


static func _pos_hold(anim: Animation, bone_name: String, offset: Vector3) -> void:
	var track := _track(anim, Animation.TYPE_POSITION_3D, bone_name)
	anim.position_track_insert_key(track, 0.0, offset)


static func _rot_hold(anim: Animation, bone_name: String, angle: float) -> void:
	var track := _track(anim, Animation.TYPE_ROTATION_3D, bone_name)
	anim.rotation_track_insert_key(track, 0.0, Quaternion(Vector3.RIGHT, angle))
