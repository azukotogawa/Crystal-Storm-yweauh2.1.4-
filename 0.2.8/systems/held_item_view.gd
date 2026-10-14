class_name HeldItemView
extends Node3D
## One reused arm box and one voxel mesh for the held item.
## The player body has no rig, so a swing is this node's position.
## Parts are created once and resized. A swing must not allocate.

const _ItemAnim = preload("res://systems/item_anim.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const _BRICK_PATH := "res://assets/art/voxel_brick.png"
const _PART_COUNT := 6

var _arm: MeshInstance3D
var _item: MeshInstance3D
var _parts: Array[MeshInstance3D] = []
var _arm_mat: StandardMaterial3D
var _item_id: String = ""
var _vs: float = 2.0
var _ready_visual: bool = false
static var _brick_tex: Texture2D


func _ready() -> void:
	_ensure_visual()
	set_process(false)


func _ensure_visual() -> void:
	if _ready_visual:
		return
	_vs = _WorldSettings.get_active().voxel_scale
	var arm_box := BoxMesh.new()
	arm_box.size = Vector3(_vs * 0.24, _vs * 0.24, _vs * 0.95)
	_arm = MeshInstance3D.new()
	_arm.name = "Arm"
	_arm.mesh = arm_box
	_arm_mat = _unshaded(Color(0.72, 0.48, 0.32))
	_arm.material_override = _arm_mat
	_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arm)
	for i in _PART_COUNT:
		var mi := MeshInstance3D.new()
		mi.name = "HeldItem" if i == 0 else "Part%d" % i
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _voxel_mat(Color.WHITE)
		mi.visible = false
		if i == 0:
			_item = mi
			add_child(mi)
		else:
			_item.add_child(mi)
		_parts.append(mi)
	_ready_visual = true
	_apply_unit(_ItemAnim.Kind.NONE, 0.0, 0.0)


func show_item(item_id: String) -> void:
	_ensure_visual()
	_item_id = item_id
	var spec: Dictionary = _ItemAnim.spec_for(item_id)
	var kind := int(spec.get("kind", _ItemAnim.Kind.NONE))
	_tint_for(item_id, kind)
	# u = 0 is the ready pose, which is also the first frame of a use.
	_apply_unit(kind, 0.0, float(spec.get("impact_ratio", 0.42)))
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
	var layout: Array = _layout(item_id, kind)
	_item.scale = Vector3.ONE
	for i in _parts.size():
		var mi := _parts[i]
		if i >= layout.size():
			mi.visible = false
			if mi.has_meta("held_role"):
				mi.remove_meta("held_role")
			continue
		var spec: Array = layout[i]
		var box := mi.mesh as BoxMesh
		box.size = spec[1]
		# Part 0 is the HeldItem node. Its position is the hand pose, so the
		# first box stays centered on that node and the rest hang off it.
		if i > 0:
			mi.position = spec[0]
			mi.set_meta("rest_pos", spec[0])
		else:
			mi.set_meta("rest_pos", Vector3.ZERO)
		if _string_part(item_id, i):
			mi.set_meta("held_role", "string")
		elif mi.has_meta("held_role"):
			mi.remove_meta("held_role")
		mi.rotation = Vector3.ZERO
		mi.visible = true
		var mat := mi.material_override as StandardMaterial3D
		mat.albedo_color = spec[2]


func _apply_unit(kind: int, u: float, impact: float) -> void:
	var vs := _vs
	# Outside the body radius so the billboard is not hidden in the torso.
	var chest := vs * 1.05
	var side := vs * 1.50
	var at := clampf(impact, 0.05, 0.92)
	var phase: float
	if u < at:
		phase = -1.0 + u / at
	else:
		phase = (u - at) / maxf(1.0 - at, 0.001)
	phase = clampf(phase, -1.0, 1.0)
	# 0 at the ready pose and at the end, 1 on the impact frame.
	var strike := sin(clampf((phase + 1.0) * 0.5, 0.0, 1.0) * PI)
	var arm_pos := Vector3(side * 0.45, chest * 0.75, -vs * 0.12)
	var item_pos := Vector3(side, chest, -vs * 0.4)
	var arm_rot := Vector3.ZERO
	var item_rot := Vector3.ZERO
	var string_draw := 0.0
	match kind:
		_ItemAnim.Kind.SWING:
			if _item_id == "crystal_hammer":
				# Raise through the wind-up, then the impact frame is the slam.
				# The 0.65 split is the pre-hit hold: most of the wind-up is the raise,
				# and the drop lands on the impact sample. Do not move that split.
				var lift := 0.0
				if phase < 0.0:
					var wind := phase + 1.0
					if wind < 0.65:
						lift = wind / 0.65
					else:
						lift = 1.0 - (wind - 0.65) / 0.35
				item_pos = Vector3(side * 0.72, chest * 0.55 + vs * 1.65 * lift, -vs * (0.35 + 0.75 * (1.0 - lift)))
				arm_pos = Vector3(side * 0.42, chest * 0.48 + vs * 0.9 * lift, -vs * (0.12 + 0.3 * (1.0 - lift)))
				arm_rot = Vector3(-1.2 * lift, 0.0, 0.12)
				# Head cocks back with the raise. Impact (lift 0) is the downward hit.
				item_rot = Vector3(-1.35 * lift, 0.0, 0.18 * lift)
			elif _item_id == "stone_pick":
				# Overhead chop. Cocked back at the ready pose, buried forward on the hit.
				var chop := strike
				item_pos = Vector3(
					side * 0.72,
					chest * 0.7 + vs * (0.7 * (1.0 - chop) - 0.25 * chop),
					-vs * (0.35 + 0.9 * chop)
				)
				arm_pos = Vector3(side * 0.4, chest * 0.5 + vs * 0.4 * (1.0 - chop), -vs * (0.1 + 0.28 * chop))
				arm_rot = Vector3(lerpf(-1.05, 0.75, chop), 0.0, 0.06)
				item_rot = Vector3(lerpf(1.15, -1.2, chop), 0.0, 0.0)
			else:
				var sweep := sin((phase + 1.0) * PI)
				item_pos = Vector3(
					side + vs * 0.95 * sweep,
					chest + vs * 0.5 * strike,
					-vs * (0.4 + 0.95 * strike)
				)
				arm_pos = Vector3(side * 0.5 + vs * 0.4 * sweep, chest * 0.7 + vs * 0.22 * strike, -vs * (0.12 + 0.38 * strike))
				arm_rot = Vector3(0.3 * strike, 0.0, sweep * 0.95)
				# Blade arcs across the body. Ready is rolled up; the hit is the follow-through.
				item_rot = Vector3(lerpf(0.25, 1.05, strike), 0.0, lerpf(1.2, -1.1, strike))
		_ItemAnim.Kind.THRUST:
			var lunge := 0.4
			if phase < 0.0:
				lunge = lerpf(0.4, 1.85, phase + 1.0)
			else:
				lunge = lerpf(1.85, 0.4, phase)
			item_pos = Vector3(side * 0.55, chest, -lunge * vs)
			arm_pos = Vector3(side * 0.32, chest * 0.68, -lunge * vs * 0.5)
			arm_rot = Vector3(-0.15 + lunge * 0.32, 0.0, 0.05)
			var thrust_u := clampf((phase + 1.0) * 0.5, 0.0, 1.0)
			item_rot = Vector3(lerpf(0.85, 0.05, thrust_u), 0.0, 0.0)
		_ItemAnim.Kind.RAISE:
			var lift := strike
			item_pos = Vector3(side * 0.62, chest * 0.62 + vs * 1.15 * lift, -vs * 0.3)
			arm_pos = Vector3(side * 0.36, chest * 0.55 + vs * 0.65 * lift, -vs * 0.1)
			arm_rot = Vector3(-1.1 * lift, 0.0, 0.12)
			item_rot = Vector3(-1.15 * lift, 0.0, 0.08)
		_ItemAnim.Kind.AIM:
			var draw := 0.0
			if phase < 0.0:
				draw = phase + 1.0
			else:
				draw = 1.0 - phase
			item_pos = Vector3(side * 1.08, chest, -vs * (0.9 - 0.6 * draw))
			arm_pos = Vector3(side * 0.55, chest * 0.75, -vs * (0.28 - 0.2 * draw))
			arm_rot = Vector3(-0.28, 0.22 * draw, 0.42)
			string_draw = draw
			item_rot = Vector3(-0.2, 0.2 * draw, 0.1)
		_:
			item_pos = Vector3(side, chest * 0.9, -vs * 0.2)
	_arm.position = arm_pos
	_arm.rotation = arm_rot
	_arm.scale = Vector3.ONE
	_item.position = item_pos
	_item.rotation = item_rot
	_set_string_draw(string_draw)
	_arm.visible = kind != _ItemAnim.Kind.NONE
	_item.visible = kind != _ItemAnim.Kind.NONE


func _string_part(item_id: String, index: int) -> bool:
	if index != 5:
		return false
	if item_id == "shortbow" or item_id == "sling":
		return true
	if item_id == "":
		return false
	return _ItemTypes.visual_key(item_id) == "shortbow"


## Pull the string back toward the player. The bow mesh itself only shifts a little.
func _set_string_draw(draw: float) -> void:
	var pull := _vs * 0.62 * clampf(draw, 0.0, 1.0)
	for mi in _parts:
		if str(mi.get_meta("held_role", "")) != "string":
			continue
		var rest: Vector3 = mi.get_meta("rest_pos", Vector3.ZERO)
		mi.position = rest + Vector3(0.0, 0.0, pull)


## Boxes in metres. Part 0 is centered on the hand (the pose owns that node).
## The rest are offsets from the hand. Tall enough to read at ortho 16.
## u is one voxel (voxel_scale). Every part is thick on X and Z so the iso
## camera sees a side, not a paper edge.
func _layout(item_id: String, kind: int) -> Array:
	var u := _vs
	var wood := Color(0.62, 0.40, 0.18)
	var wood_dark := Color(0.40, 0.24, 0.12)
	var blade := Color(0.78, 0.62, 0.32)
	var stone := Color(0.55, 0.56, 0.60)
	var stone_dark := Color(0.36, 0.38, 0.42)
	var crystal := Color(0.58, 0.28, 0.90)
	var crystal_lite := Color(0.82, 0.62, 1.0)
	var id := item_id
	if id != "wooden_sword" and id != "spear" and id != "stone_pick" and id != "crystal_hammer" and id != "shortbow" and id != "sling":
		var key := _ItemTypes.visual_key(item_id) if item_id != "" else ""
		if key == "shortbow" or kind == _ItemAnim.Kind.AIM:
			id = "shortbow"
		elif id == "crystal_hammer" or (key == "stone_pick" and kind == _ItemAnim.Kind.SWING and item_id == "crystal_hammer"):
			id = "crystal_hammer"
		elif kind == _ItemAnim.Kind.THRUST:
			id = "spear"
		elif key == "stone_pick":
			id = "stone_pick"
		elif kind == _ItemAnim.Kind.SWING or key == "wooden_sword":
			id = "wooden_sword"
	match id:
		"wooden_sword":
			return [
				[Vector3.ZERO, Vector3(0.22 * u, 0.72 * u, 0.20 * u), wood_dark],
				[Vector3(0, 0.46 * u, 0), Vector3(0.72 * u, 0.16 * u, 0.22 * u), wood],
				[Vector3(0, 1.20 * u, 0), Vector3(0.18 * u, 1.40 * u, 0.18 * u), blade],
				[Vector3(0, 2.00 * u, 0), Vector3(0.14 * u, 0.32 * u, 0.14 * u), blade.lightened(0.12)],
			]
		"spear":
			return [
				[Vector3.ZERO, Vector3(0.18 * u, 2.40 * u, 0.18 * u), wood],
				[Vector3(0, 1.28 * u, 0), Vector3(0.32 * u, 0.22 * u, 0.32 * u), wood_dark],
				[Vector3(0, 1.62 * u, 0), Vector3(0.24 * u, 0.50 * u, 0.24 * u), stone],
			]
		"stone_pick":
			return [
				[Vector3.ZERO, Vector3(0.18 * u, 1.90 * u, 0.18 * u), wood],
				[Vector3(0, 0.95 * u, 0), Vector3(0.95 * u, 0.30 * u, 0.32 * u), stone],
				[Vector3(0.55 * u, 0.95 * u, 0), Vector3(0.28 * u, 0.22 * u, 0.50 * u), stone_dark],
			]
		"crystal_hammer":
			return [
				[Vector3.ZERO, Vector3(0.24 * u, 1.90 * u, 0.24 * u), wood_dark],
				[Vector3(0, 0.88 * u, 0), Vector3(1.05 * u, 0.58 * u, 0.58 * u), crystal],
				[Vector3(0.62 * u, 0.88 * u, 0), Vector3(0.36 * u, 0.36 * u, 0.72 * u), crystal_lite],
			]
		"shortbow", "sling":
			return [
				[Vector3.ZERO, Vector3(0.20 * u, 0.48 * u, 0.22 * u), wood_dark],
				[Vector3(0, 0.85 * u, 0), Vector3(0.16 * u, 0.95 * u, 0.16 * u), wood],
				[Vector3(0.28 * u, 1.38 * u, 0), Vector3(0.42 * u, 0.16 * u, 0.16 * u), wood],
				[Vector3(0, -0.85 * u, 0), Vector3(0.16 * u, 0.95 * u, 0.16 * u), wood],
				[Vector3(0.28 * u, -1.38 * u, 0), Vector3(0.42 * u, 0.16 * u, 0.16 * u), wood],
				[Vector3(0.36 * u, 0, 0.10 * u), Vector3(0.10 * u, 2.60 * u, 0.12 * u), Color(0.90, 0.86, 0.72)],
			]
		_:
			if kind == _ItemAnim.Kind.NONE or item_id == "":
				return []
			var tint := Color(0.62, 0.62, 0.66)
			if item_id == "herb":
				tint = Color(0.35, 0.72, 0.32)
			elif item_id == "wood":
				tint = wood
			elif item_id == "stone":
				tint = stone
			return [[Vector3(0, 0.2 * u, 0), Vector3(0.36 * u, 0.36 * u, 0.36 * u), tint]]


func _voxel_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = color
	mat.albedo_texture = _brick_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.92
	mat.metallic = 0.0
	return mat


static func _brick_texture() -> Texture2D:
	if _brick_tex == null and ResourceLoader.exists(_BRICK_PATH):
		_brick_tex = load(_BRICK_PATH) as Texture2D
	return _brick_tex


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
