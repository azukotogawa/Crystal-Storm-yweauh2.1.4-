class_name HeldItemView
extends Node3D
## One reused arm box and one reused item box. Poses are samples of ItemAnim.Playback.
## The player body has no rig, so the swing is this node's transform.

const _ItemAnim = preload("res://systems/item_anim.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _arm: MeshInstance3D
var _item: MeshInstance3D
var _arm_mat: StandardMaterial3D
var _item_mat: StandardMaterial3D
var _item_id: String = ""
var _vs: float = 2.0
var _ready_visual: bool = false


func _ready() -> void:
	_ensure_visual()
	set_process(false)


func _ensure_visual() -> void:
	if _ready_visual:
		return
	_vs = _WorldSettings.get_active().voxel_scale
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, 0.72)
	_arm = MeshInstance3D.new()
	_arm.name = "Arm"
	_arm.mesh = box
	_arm_mat = _unshaded(Color(0.72, 0.48, 0.32))
	_arm.material_override = _arm_mat
	_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arm)
	_item = MeshInstance3D.new()
	_item.name = "HeldItem"
	_item.mesh = box
	_item_mat = _unshaded(Color(0.75, 0.6, 0.35))
	_item.material_override = _item_mat
	_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_item)
	_ready_visual = true
	_apply_unit(_ItemAnim.Kind.NONE, 0.0, 0.0)


func show_item(item_id: String) -> void:
	_ensure_visual()
	_item_id = item_id
	var spec: Dictionary = _ItemAnim.spec_for(item_id)
	var kind := int(spec.get("kind", _ItemAnim.Kind.NONE))
	_tint_for(item_id, kind)
	var idle := 0.34 if kind == _ItemAnim.Kind.AIM else 0.0
	_apply_unit(kind, idle, float(spec.get("impact_ratio", 0.42)))
	visible = kind != _ItemAnim.Kind.NONE and item_id != ""


func apply_playback(pb) -> void:
	if pb == null:
		return
	_ensure_visual()
	var item_id := str(pb.item_id)
	if item_id != _item_id:
		_item_id = item_id
		_tint_for(item_id, int(pb.kind))
	_apply_unit(int(pb.kind), pb.unit(), float(pb.impact_ratio))
	visible = int(pb.kind) != _ItemAnim.Kind.NONE


func face(forward: Vector3) -> void:
	if not is_inside_tree():
		return
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.0001:
		return
	look_at(global_position + flat, Vector3.UP)


func visual_child_count() -> int:
	_ensure_visual()
	return get_child_count()


func _tint_for(item_id: String, kind: int) -> void:
	var key := _ItemTypes.visual_key(item_id) if item_id != "" else ""
	var tint := Color(0.62, 0.62, 0.66)
	match key:
		"wooden_sword":
			tint = Color(0.72, 0.52, 0.28)
		"stone_pick":
			tint = Color(0.55, 0.57, 0.62)
		"shortbow":
			tint = Color(0.48, 0.32, 0.18)
		"stone":
			tint = Color(0.5, 0.5, 0.52)
		"wood":
			tint = Color(0.62, 0.42, 0.22)
		"herb":
			tint = Color(0.35, 0.72, 0.32)
		"crystal_shard":
			tint = Color(0.72, 0.4, 0.95)
		_:
			if kind == _ItemAnim.Kind.AIM:
				tint = Color(0.48, 0.32, 0.18)
			elif kind == _ItemAnim.Kind.THRUST:
				tint = Color(0.68, 0.5, 0.3)
	_item_mat.albedo_color = tint
	var thick := 1.0
	var long := 1.0
	if item_id == "crystal_hammer":
		thick = 1.45
		long = 0.72
	elif key == "stone_pick":
		thick = 1.2
		long = 0.9
	elif kind == _ItemAnim.Kind.THRUST:
		long = 1.35
	elif kind == _ItemAnim.Kind.AIM:
		long = 1.15
		thick = 0.7
	elif kind == _ItemAnim.Kind.RAISE:
		long = 0.55
		thick = 0.9
	_item.scale = Vector3(thick, thick, long)


func _apply_unit(kind: int, u: float, impact: float) -> void:
	var vs := _vs
	var chest := vs * 0.85
	var side := vs * 0.22
	var at := clampf(impact, 0.05, 0.92)
	var phase: float
	if u < at:
		phase = -1.0 + u / at
	else:
		phase = (u - at) / maxf(1.0 - at, 0.001)
	phase = clampf(phase, -1.0, 1.0)
	var arm_pos := Vector3(side * 0.65, chest * 0.82, -vs * 0.06)
	var item_pos := Vector3(side, chest, -vs * 0.28)
	var arm_rot := Vector3.ZERO
	var item_rot := Vector3.ZERO
	match kind:
		_ItemAnim.Kind.SWING:
			item_rot = Vector3(0.15, phase * 1.25, 0.55)
			arm_rot = Vector3(0.35, phase * 0.85, 0.15)
			item_pos.y += vs * 0.12 * (1.0 - absf(phase))
			item_pos.z -= vs * 0.18 * (1.0 - absf(phase))
		_ItemAnim.Kind.THRUST:
			var lunge := 0.15
			if phase < 0.0:
				lunge = lerpf(0.08, 0.62, phase + 1.0)
			else:
				lunge = lerpf(0.62, 0.2, phase)
			item_pos = Vector3(side * 0.25, chest, -lunge * vs)
			item_rot = Vector3(0.0, 0.0, 0.15)
			arm_rot = Vector3(-0.2 + lunge * 0.4, 0.0, 0.05)
			arm_pos.z = -lunge * vs * 0.45
		_ItemAnim.Kind.RAISE:
			var lift := 0.0
			if phase < 0.0:
				lift = phase + 1.0
			else:
				lift = 1.0 - phase * 0.75
			item_pos = Vector3(side * 0.4, chest * 0.7 + vs * 0.55 * lift, -vs * 0.16)
			item_rot = Vector3(-1.1 * lift, 0.2, 0.15)
			arm_rot = Vector3(-0.9 * lift, 0.1, 0.0)
			arm_pos.y = chest * 0.75 + vs * 0.28 * lift
		_ItemAnim.Kind.AIM:
			var draw := 0.0
			if phase < 0.0:
				draw = phase + 1.0
			else:
				draw = 1.0 - phase
			item_pos = Vector3(side * 0.85, chest, -vs * (0.22 + 0.16 * draw))
			item_rot = Vector3(-0.12, 0.35 * draw, 1.05)
			arm_rot = Vector3(-0.15, 0.25 * draw, 0.4)
		_:
			item_pos = Vector3(side, chest * 0.9, -vs * 0.12)
	_arm.position = arm_pos
	_arm.rotation = arm_rot
	_arm.scale = Vector3(0.55, 0.55, 0.85)
	_item.position = item_pos
	_item.rotation = item_rot
	_arm.visible = kind != _ItemAnim.Kind.NONE
	_item.visible = kind != _ItemAnim.Kind.NONE


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
