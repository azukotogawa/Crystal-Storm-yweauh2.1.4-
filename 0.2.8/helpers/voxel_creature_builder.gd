class_name VoxelCreatureBuilder
extends RefCounted

const USE_PART_RIG := true

const _Model = preload("res://helpers/voxel_model_builder.gd")
const _Pose = preload("res://entities/creature_pose.gd")
const _Settings = preload("res://config/world_settings.gd")
const _Palette = preload("res://ui/crystal_palette.gd")
const _MiteLook = preload("res://config/crystal_mite_look.gd")

const _ANIM_LEN := TAU
const _ANIM_STEPS := 16


static func uses_rig(kind: StringName) -> bool:
	if not USE_PART_RIG:
		return false
	return not parts_for(kind).is_empty()


static func parts_for(kind: StringName) -> Array:
	if kind == &"boar":
		return _boar_parts()
	if kind == &"deer":
		return _deer_parts()
	if kind == &"rabbit":
		return _rabbit_parts()
	if kind == &"bird":
		return _bird_parts()
	if kind == &"town_militia" or kind == &"wandering_trader":
		return _militia_parts()
	if kind == &"crystal_mite":
		return _mite_parts()
	if kind == &"crystal_stag":
		return _stag_parts()
	if kind == &"crystal_wisp":
		return _wisp_parts()
	if kind == &"corrupted_beast":
		return _beast_parts()
	if kind == &"farm_bomber":
		return _bomber_parts()
	if kind == &"thornling" or kind == &"ambush":
		return _thornling_parts()
	if kind == &"shard_guard":
		return _guard_parts()
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
	if kind == &"crystal_mite":
		return PackedColorArray([
			Color(0, 0, 0),
			_mite_albedo(),
			Color(0.05, 0.08, 0.10),
		])
	if kind == &"crystal_wisp":
		return PackedColorArray([
			Color(0, 0, 0),
			_crystal_albedo(),
			Color(0.08, 0.08, 0.08),
		])
	if kind == &"crystal_stag":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.72, 0.52, 0.38),
			Color(0.86, 0.72, 0.54),
			_crystal_albedo(),
			Color(0.08, 0.08, 0.08),
		])
	if kind == &"corrupted_beast":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.48, 0.36, 0.32),
			Color(0.66, 0.50, 0.42),
			Color(0.22, 0.14, 0.12),
			Color(0.08, 0.08, 0.08),
			_crystal_albedo(),
		])
	if kind == &"rabbit":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.72, 0.58, 0.42),
			Color(0.92, 0.86, 0.74),
			Color(0.86, 0.62, 0.58),
			Color(0.08, 0.08, 0.08),
		])
	if kind == &"bird":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.45, 0.58, 0.78),
			Color(0.78, 0.86, 0.94),
			Color(0.90, 0.55, 0.22),
			Color(0.08, 0.08, 0.08),
		])
	if kind == &"town_militia" or kind == &"wandering_trader":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.35, 0.42, 0.62),
			Color(0.82, 0.66, 0.48),
			Color(0.62, 0.64, 0.70),
			Color(0.08, 0.08, 0.08),
		])
	if kind == &"farm_bomber" or kind == &"shard_guard":
		return PackedColorArray([
			Color(0, 0, 0),
			_crystal_albedo(),
			Color(0.08, 0.08, 0.08),
			Color(0.95, 0.45, 0.15),
		])
	if kind == &"thornling" or kind == &"ambush":
		return PackedColorArray([
			Color(0, 0, 0),
			Color(0.32, 0.55, 0.28),
			Color(0.18, 0.36, 0.16),
			_crystal_albedo(),
			Color(0.08, 0.08, 0.08),
		])
	return PackedColorArray()


static func cube_edge() -> float:
	var grid_y := _Model.player_grid_size().y
	if grid_y <= 0:
		return 0.0
	return _Settings.get_active().player_height() / float(grid_y)


static func build(kind: StringName) -> Node3D:
	var rig := build_parts(parts_for(kind), palette_for(kind), cube_edge())
	if rig != null and kind == &"crystal_mite":
		_fit_mite(rig)
	return rig


static func build_parts(parts: Array, palette: PackedColorArray, cube: float) -> Node3D:
	if cube <= 0.0 or not _spec_ok(parts):
		return null
	var rig: Node3D = _Model.build_rig(parts, palette, cube)
	if rig == null:
		return null
	rig.name = "CreatureRig"
	rig.set_meta("model_height", _span_height(parts, cube))
	_attach_anims(rig)
	return rig


static func repaint(rig: Node3D) -> void:
	if rig == null:
		return
	if bool(rig.get_meta("mite_look", false)):
		var look = _MiteLook.load_active()
		var colorblind := _Palette.is_active()
		_repaint_node(rig, look.albedo_color(colorblind), look.emission_color(colorblind))
		_paint_mite_energy(rig, look.energy(colorblind))
		return
	_repaint_node(rig, _crystal_albedo(), _crystal_glow())


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
	for child in skel.get_children():
		if child is BoneAttachment3D:
			var att := child as BoneAttachment3D
			var bone_i := skel.find_bone(att.bone_name)
			if bone_i >= 0:
				att.transform = skel.get_bone_global_pose(bone_i)


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


static func _mite_parts() -> Array:
	var crystal := 1
	var dark := 2
	var glow := _mite_emission()
	var body: Array = []
	_fill(body, 1, 1, 2, 5, 3, 7, crystal)
	_fill(body, 0, 2, 4, 1, 5, 5, crystal)
	_fill(body, 5, 2, 4, 6, 5, 5, crystal)
	_fill(body, 2, 3, 3, 3, 7, 4, crystal)
	_fill(body, 3, 3, 5, 4, 6, 6, crystal)
	var head: Array = []
	_fill(head, 2, 3, 0, 4, 5, 3, crystal)
	_fill(head, 1, 3, 0, 2, 4, 2, crystal)
	_fill(head, 4, 3, 0, 5, 4, 2, crystal)
	_fill(head, 2, 5, 1, 3, 8, 2, crystal)
	_fill(head, 3, 5, 1, 4, 8, 2, crystal)
	_fill(head, 2, 4, 0, 3, 5, 1, dark)
	_fill(head, 3, 4, 0, 4, 5, 1, dark)
	var leg_l: Array = []
	_fill(leg_l, 1, 0, 3, 2, 1, 4, crystal)
	_fill(leg_l, 1, 0, 5, 2, 1, 6, crystal)
	var leg_r: Array = []
	_fill(leg_r, 4, 0, 3, 5, 1, 4, crystal)
	_fill(leg_r, 4, 0, 5, 5, 1, 6, crystal)
	var tail: Array = []
	_fill(tail, 2, 2, 7, 4, 3, 9, crystal)
	_fill(tail, 2, 3, 8, 3, 6, 9, crystal)
	_fill(tail, 3, 2, 9, 4, 4, 12, crystal)
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit, glow),
		_part("head", "head", "Head", "Body", "bottom", head, emit, glow),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l, emit, glow),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r, emit, glow),
		_part("tail", "tail", "Tail", "Body", "center", tail, emit, glow),
	]


static func _stag_parts() -> Array:
	var hide := 1
	var belly := 2
	var crystal := 3
	var pupil := 4
	var body: Array = []
	_fill(body, 3, 5, 5, 7, 9, 12, hide)
	_fill(body, 3, 5, 6, 7, 6, 11, belly)
	_fill(body, 4, 9, 6, 6, 10, 11, crystal)
	var head: Array = []
	_fill(head, 3, 8, 1, 7, 12, 5, hide)
	_fill(head, 4, 8, 0, 6, 10, 2, hide)
	_fill(head, 3, 10, 1, 4, 11, 3, crystal)
	_fill(head, 6, 10, 1, 7, 11, 3, crystal)
	_fill(head, 3, 10, 1, 4, 11, 2, pupil)
	_fill(head, 6, 10, 1, 7, 11, 2, pupil)
	_fill(head, 3, 12, 2, 4, 15, 3, crystal)
	_fill(head, 6, 12, 2, 7, 15, 3, crystal)
	var leg_l: Array = []
	_fill(leg_l, 2, 1, 5, 4, 5, 7, hide)
	_fill(leg_l, 2, 0, 5, 4, 1, 7, pupil)
	_fill(leg_l, 2, 1, 9, 4, 5, 11, hide)
	_fill(leg_l, 2, 0, 9, 4, 1, 11, pupil)
	var leg_r: Array = []
	_fill(leg_r, 6, 1, 5, 8, 5, 7, hide)
	_fill(leg_r, 6, 0, 5, 8, 1, 7, pupil)
	_fill(leg_r, 6, 1, 9, 8, 5, 11, hide)
	_fill(leg_r, 6, 0, 9, 8, 1, 11, pupil)
	var tail: Array = []
	_fill(tail, 4, 8, 12, 6, 9, 14, belly)
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit),
		_part("head", "head", "Head", "Body", "bottom", head, emit),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l, emit),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r, emit),
		_part("tail", "tail", "Tail", "Body", "center", tail, emit),
	]


static func _beast_parts() -> Array:
	var hide := 1
	var belly := 2
	var dark := 3
	var pupil := 4
	var crystal := 5
	var body: Array = []
	_fill(body, 2, 3, 4, 8, 7, 11, hide)
	_fill(body, 3, 3, 5, 7, 4, 10, belly)
	_fill(body, 4, 7, 5, 6, 8, 10, crystal)
	var head: Array = []
	_fill(head, 3, 4, 0, 7, 7, 4, hide)
	_fill(head, 4, 4, 0, 6, 5, 2, dark)
	_fill(head, 3, 6, 1, 4, 7, 2, pupil)
	_fill(head, 6, 6, 1, 7, 7, 2, pupil)
	_fill(head, 3, 3, 0, 4, 4, 2, crystal)
	_fill(head, 6, 3, 0, 7, 4, 2, crystal)
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
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit),
		_part("head", "head", "Head", "Body", "bottom", head, emit),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l, emit),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r, emit),
		_part("tail", "tail", "Tail", "Body", "center", tail, emit),
	]


static func _wisp_parts() -> Array:
	var crystal := 1
	var dark := 2
	var body: Array = []
	_fill(body, 3, 2, 3, 7, 5, 8, crystal)
	var head: Array = []
	_fill(head, 3, 5, 1, 7, 8, 4, crystal)
	_fill(head, 3, 6, 1, 4, 7, 2, dark)
	_fill(head, 6, 6, 1, 7, 7, 2, dark)
	_fill(head, 4, 5, 0, 6, 6, 1, dark)
	var leg_l: Array = []
	_fill(leg_l, 3, 0, 4, 4, 2, 6, crystal)
	_fill(leg_l, 3, 0, 6, 4, 2, 8, crystal)
	var leg_r: Array = []
	_fill(leg_r, 6, 0, 4, 7, 2, 6, crystal)
	_fill(leg_r, 6, 0, 6, 7, 2, 8, crystal)
	var wing_l: Array = []
	_fill(wing_l, 0, 4, 3, 3, 5, 7, crystal)
	var wing_r: Array = []
	_fill(wing_r, 7, 4, 3, 10, 5, 7, crystal)
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit),
		_part("head", "head", "Head", "Body", "bottom", head, emit),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l, emit),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r, emit),
		_part("wing_l", "wing", "Wing_L", "Body", "center", wing_l, emit),
		_part("wing_r", "wing", "Wing_R", "Body", "center", wing_r, emit),
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


static func _rabbit_parts() -> Array:
	var hide := 1
	var belly := 2
	var ear := 3
	var eye := 4
	var body: Array = []
	_fill(body, 3, 2, 4, 7, 5, 9, hide)
	_fill(body, 3, 2, 5, 7, 3, 8, belly)
	var head: Array = []
	_fill(head, 3, 4, 1, 7, 7, 4, hide)
	_fill(head, 3, 7, 2, 4, 11, 3, ear)
	_fill(head, 6, 7, 2, 7, 11, 3, ear)
	_fill(head, 3, 5, 1, 4, 6, 2, eye)
	_fill(head, 6, 5, 1, 7, 6, 2, eye)
	var leg_l: Array = []
	_fill(leg_l, 2, 0, 4, 4, 2, 6, hide)
	_fill(leg_l, 2, 0, 7, 4, 2, 9, hide)
	var leg_r: Array = []
	_fill(leg_r, 6, 0, 4, 8, 2, 6, hide)
	_fill(leg_r, 6, 0, 7, 8, 2, 9, hide)
	var tail: Array = []
	_fill(tail, 4, 4, 9, 6, 6, 11, belly)
	return [
		_part("body", "body", "Body", "Root", "bottom", body),
		_part("head", "head", "Head", "Body", "bottom", head),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r),
		_part("tail", "tail", "Tail", "Body", "center", tail),
	]


static func _bird_parts() -> Array:
	var body_c := 1
	var wing := 2
	var beak := 3
	var eye := 4
	var body: Array = []
	_fill(body, 4, 2, 4, 7, 5, 9, body_c)
	_fill(body, 4, 2, 5, 7, 3, 8, wing)
	var head: Array = []
	_fill(head, 4, 4, 1, 7, 7, 4, body_c)
	_fill(head, 5, 4, 0, 6, 5, 1, beak)
	_fill(head, 4, 5, 1, 5, 6, 2, eye)
	_fill(head, 6, 5, 1, 7, 6, 2, eye)
	var leg_l: Array = []
	_fill(leg_l, 4, 0, 5, 5, 2, 6, beak)
	_fill(leg_l, 4, 0, 7, 5, 2, 8, beak)
	var leg_r: Array = []
	_fill(leg_r, 6, 0, 5, 7, 2, 6, beak)
	_fill(leg_r, 6, 0, 7, 7, 2, 8, beak)
	var wing_l: Array = []
	_fill(wing_l, 0, 3, 4, 4, 4, 8, wing)
	var wing_r: Array = []
	_fill(wing_r, 7, 3, 4, 11, 4, 8, wing)
	var tail: Array = []
	_fill(tail, 5, 3, 9, 6, 4, 12, wing)
	return [
		_part("body", "body", "Body", "Root", "bottom", body),
		_part("head", "head", "Head", "Body", "bottom", head),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r),
		_part("wing_l", "wing", "Wing_L", "Body", "center", wing_l),
		_part("wing_r", "wing", "Wing_R", "Body", "center", wing_r),
		_part("tail", "tail", "Tail", "Body", "center", tail),
	]


static func _militia_parts() -> Array:
	var cloth := 1
	var skin := 2
	var metal := 3
	var eye := 4
	var body: Array = []
	_fill(body, 3, 4, 3, 7, 9, 7, cloth)
	_fill(body, 3, 4, 4, 7, 6, 6, metal)
	var head: Array = []
	_fill(head, 3, 9, 3, 7, 12, 6, skin)
	_fill(head, 3, 11, 3, 7, 13, 6, metal)
	_fill(head, 3, 10, 5, 4, 11, 6, eye)
	_fill(head, 6, 10, 5, 7, 11, 6, eye)
	var leg_l: Array = []
	_fill(leg_l, 3, 1, 3, 5, 4, 5, cloth)
	_fill(leg_l, 3, 0, 3, 5, 1, 5, metal)
	var leg_r: Array = []
	_fill(leg_r, 5, 1, 4, 7, 4, 6, cloth)
	_fill(leg_r, 5, 0, 4, 7, 1, 6, metal)
	var tail: Array = []
	_fill(tail, 3, 5, 6, 7, 8, 8, cloth)
	return [
		_part("body", "body", "Body", "Root", "bottom", body),
		_part("head", "head", "Head", "Body", "bottom", head),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r),
		_part("tail", "tail", "Tail", "Body", "center", tail),
	]


static func _bomber_parts() -> Array:
	var crystal := 1
	var dark := 2
	var fuse := 3
	var body: Array = []
	_fill(body, 2, 2, 3, 8, 6, 9, crystal)
	var head: Array = []
	_fill(head, 3, 5, 1, 7, 8, 4, crystal)
	_fill(head, 3, 6, 1, 4, 7, 2, dark)
	_fill(head, 6, 6, 1, 7, 7, 2, dark)
	var leg_l: Array = []
	_fill(leg_l, 2, 0, 4, 4, 2, 6, crystal)
	_fill(leg_l, 2, 0, 7, 4, 2, 9, crystal)
	var leg_r: Array = []
	_fill(leg_r, 6, 0, 4, 8, 2, 6, crystal)
	_fill(leg_r, 6, 0, 7, 8, 2, 9, crystal)
	var tail: Array = []
	_fill(tail, 4, 6, 5, 6, 8, 7, fuse)
	_fill(tail, 4, 8, 5, 6, 10, 7, crystal)
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit),
		_part("head", "head", "Head", "Body", "bottom", head, emit),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l, emit),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r, emit),
		_part("tail", "tail", "Tail", "Body", "center", tail, emit),
	]


static func _thornling_parts() -> Array:
	var leaf := 1
	var dark := 2
	var crystal := 3
	var eye := 4
	var body: Array = []
	_fill(body, 4, 2, 4, 6, 8, 7, leaf)
	_fill(body, 3, 4, 4, 4, 7, 6, crystal)
	_fill(body, 6, 5, 4, 7, 8, 6, crystal)
	var head: Array = []
	_fill(head, 4, 8, 3, 6, 11, 6, leaf)
	_fill(head, 4, 9, 3, 5, 10, 4, eye)
	_fill(head, 5, 9, 3, 6, 10, 4, eye)
	var leg_l: Array = []
	_fill(leg_l, 3, 0, 4, 5, 2, 6, dark)
	_fill(leg_l, 3, 0, 6, 5, 2, 8, dark)
	var leg_r: Array = []
	_fill(leg_r, 5, 0, 4, 7, 2, 6, dark)
	_fill(leg_r, 5, 0, 6, 7, 2, 8, dark)
	var tail: Array = []
	_fill(tail, 4, 6, 7, 6, 8, 10, crystal)
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit),
		_part("head", "head", "Head", "Body", "bottom", head),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r),
		_part("tail", "tail", "Tail", "Body", "center", tail, emit),
	]


static func _guard_parts() -> Array:
	var crystal := 1
	var dark := 2
	var body: Array = []
	_fill(body, 3, 4, 3, 7, 10, 7, crystal)
	var head: Array = []
	_fill(head, 3, 10, 3, 7, 13, 6, crystal)
	_fill(head, 3, 11, 5, 4, 12, 6, dark)
	_fill(head, 6, 11, 5, 7, 12, 6, dark)
	_fill(head, 4, 13, 4, 6, 16, 6, crystal)
	var leg_l: Array = []
	_fill(leg_l, 3, 0, 3, 5, 4, 5, crystal)
	_fill(leg_l, 3, 0, 3, 5, 1, 5, dark)
	var leg_r: Array = []
	_fill(leg_r, 5, 0, 4, 7, 4, 6, crystal)
	_fill(leg_r, 5, 0, 4, 7, 1, 6, dark)
	var tail: Array = []
	_fill(tail, 3, 7, 6, 4, 12, 7, crystal)
	var emit: Array = [crystal]
	return [
		_part("body", "body", "Body", "Root", "bottom", body, emit),
		_part("head", "head", "Head", "Body", "bottom", head, emit),
		_part("leg_l", "leg", "Leg_L", "Root", "top", leg_l, emit),
		_part("leg_r", "leg", "Leg_R", "Root", "top", leg_r, emit),
		_part("tail", "tail", "Tail", "Body", "center", tail, emit),
	]


static func _part(id: String, kind: String, bone: String, parent: String, pivot: String, cells: Array, emit_ids: Array = [], glow_color: Color = Color(-1, -1, -1)) -> Dictionary:
	var spec := {
		"id": id,
		"kind": kind,
		"bone": bone,
		"parent": parent,
		"pivot": pivot,
		"cells": cells,
	}
	if not emit_ids.is_empty():
		spec["emit"] = emit_ids
		spec["glow"] = _crystal_glow() if glow_color.r < 0.0 else glow_color
	return spec


static func _fit_mite(rig: Node3D) -> void:
	var look = _MiteLook.load_active()
	var scale: float = float(look.visual_scale)
	rig.scale = Vector3(scale, scale, scale)
	rig.set_meta("mite_look", true)
	_paint_mite_energy(rig, look.energy(_Palette.is_active()))


static func _mite_albedo() -> Color:
	return _MiteLook.load_active().albedo_color(_Palette.is_active())


static func _mite_emission() -> Color:
	return _MiteLook.load_active().emission_color(_Palette.is_active())


static func _paint_mite_energy(node: Node, energy: float) -> void:
	if node is MeshInstance3D and bool(node.get_meta("crystal_glow", false)):
		var mat := (node as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = energy
	for child in node.get_children():
		_paint_mite_energy(child, energy)


static func _crystal_albedo() -> Color:
	return _Palette.mass_albedo(_Palette.is_active())


static func _crystal_glow() -> Color:
	return _Palette.mass_emission(_Palette.is_active())


static func _repaint_node(node: Node, albedo: Color, glow: Color) -> void:
	if node is MeshInstance3D and bool(node.get_meta("crystal_glow", false)):
		var mi := node as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh != null:
			mi.mesh = _recolor_mesh(mesh, albedo)
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = true
			mat.emission = glow
	for child in node.get_children():
		_repaint_node(child, albedo, glow)


static func _recolor_mesh(mesh: ArrayMesh, albedo: Color) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colors.size():
		colors[i] = albedo
	arrays[Mesh.ARRAY_COLOR] = colors
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


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


static func _attach_anims(rig: Node3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "CreatureAnim"
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.add_child(player)
	var skel := rig.get_node_or_null("Skeleton") as Skeleton3D
	var winged := skel != null and skel.find_bone("Wing_L") >= 0
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _anim_idle(winged))
	lib.add_animation(&"walk", _anim_walk(winged))
	lib.add_animation(&"attack", _anim_attack())
	player.add_animation_library(&"", lib)


static func _anim_idle(winged: bool) -> Animation:
	var anim := _clip()
	_pos_sin(anim, "Head", Vector3.ZERO, _Pose.IDLE_LIFT, 1.0)
	_pos_sin(anim, "Body", Vector3.ZERO, _Pose.IDLE_LIFT * 0.45, 1.0)
	if winged:
		_wing_flap(anim, 1.0)
	return anim


static func _anim_walk(winged: bool) -> Animation:
	var anim := _clip()
	_pos_abs_sin(anim, "Head", _Pose.WALK_BOB, 2.0)
	_leg_gait(anim, "Leg_L", -1.0)
	_leg_gait(anim, "Leg_R", 1.0)
	if winged:
		_wing_flap(anim, 2.0)
	return anim


static func _anim_attack() -> Animation:
	var anim := _clip()
	_pos_hold(anim, "Body", Vector3(0.0, 0.0, -_Pose.ATTACK_LUNGE))
	_rot_hold(anim, "Leg_L", -_Pose.ATTACK_LEG)
	_rot_hold(anim, "Leg_R", _Pose.ATTACK_LEG)
	return anim


static func _wing_flap(anim: Animation, freq: float) -> void:
	_wing_bone(anim, "Wing_L", -1.0, freq)
	_wing_bone(anim, "Wing_R", 1.0, freq)


static func _wing_bone(anim: Animation, bone_name: String, side: float, freq: float) -> void:
	var track := _track(anim, Animation.TYPE_ROTATION_3D, bone_name)
	for i in _ANIM_STEPS:
		var t := _ANIM_LEN * float(i) / float(_ANIM_STEPS)
		anim.rotation_track_insert_key(track, t, Quaternion(Vector3.FORWARD, sin(t * freq) * side * 0.65))


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
