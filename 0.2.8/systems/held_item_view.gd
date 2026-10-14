class_name HeldItemView
extends Node3D
## One reused arm box and one billboard of the item texture.
## The player body has no rig, so a swing is this node's position.

const _ItemAnim = preload("res://systems/item_anim.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _TextureSet = preload("res://helpers/texture_set.gd")

var _arm: MeshInstance3D
var _item: Sprite3D
var _arm_mat: StandardMaterial3D
var _item_id: String = ""
var _vs: float = 2.0
var _ready_visual: bool = false
static var _fallback_tex: Texture2D


func _ready() -> void:
	_ensure_visual()
	set_process(false)


func _ensure_visual() -> void:
	if _ready_visual:
		return
	_vs = _WorldSettings.get_active().voxel_scale
	var box := BoxMesh.new()
	box.size = Vector3(_vs * 0.16, _vs * 0.16, _vs * 0.7)
	_arm = MeshInstance3D.new()
	_arm.name = "Arm"
	_arm.mesh = box
	_arm_mat = _unshaded(Color(0.72, 0.48, 0.32))
	_arm.material_override = _arm_mat
	_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arm)
	_item = Sprite3D.new()
	_item.name = "HeldItem"
	# About one column tall, larger than the old 0.12 stick, so the icon reads at iso zoom.
	_item.pixel_size = _vs * 0.038
	_item.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_item.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_item.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_item.alpha_scissor_threshold = 0.15
	_item.shaded = false
	_item.double_sided = true
	_item.centered = true
	_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_item.render_priority = 4
	_item.texture = _fallback_texture()
	add_child(_item)
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
	var key := _ItemTypes.visual_key(item_id) if item_id != "" else ""
	var tex := _texture_for(key)
	_item.texture = tex if tex != null else _fallback_texture()
	var tint := Color.WHITE
	if tex == null:
		tint = Color(0.62, 0.62, 0.66)
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
	elif item_id == "crystal_hammer":
		# Same pick icon, shifted so the hammer does not read as the pick.
		tint = Color(0.78, 0.62, 1.0)
	_item.modulate = tint
	var sx := 1.05
	var sy := 1.2
	if item_id == "crystal_hammer":
		sx = 1.4
		sy = 1.35
	elif key == "stone_pick":
		sx = 1.15
		sy = 1.3
	elif key == "shortbow":
		sx = 1.3
		sy = 1.15
	elif kind == _ItemAnim.Kind.THRUST:
		sx = 0.85
		sy = 1.45
	elif kind == _ItemAnim.Kind.AIM:
		sx = 1.25
		sy = 1.1
	elif kind == _ItemAnim.Kind.RAISE:
		sx = 0.95
		sy = 0.95
	_item.scale = Vector3(sx, sy, 1.0)


func _apply_unit(kind: int, u: float, impact: float) -> void:
	var vs := _vs
	var chest := vs * 0.95
	var side := vs * 0.85
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
	match kind:
		_ItemAnim.Kind.SWING:
			if _item_id == "crystal_hammer":
				# Raise through the wind-up, then the impact frame is the slam.
				var lift := 0.0
				if phase < 0.0:
					var wind := phase + 1.0
					if wind < 0.65:
						lift = wind / 0.65
					else:
						lift = 1.0 - (wind - 0.65) / 0.35
				item_pos = Vector3(side * 0.55, chest * 0.55 + vs * 1.05 * lift, -vs * (0.28 + 0.55 * (1.0 - lift)))
				arm_pos = Vector3(side * 0.28, chest * 0.5 + vs * 0.55 * lift, -vs * (0.1 + 0.2 * (1.0 - lift)))
				arm_rot = Vector3(-1.15 * lift, 0.0, 0.1)
			else:
				var sweep := sin((phase + 1.0) * PI)
				item_pos = Vector3(
					side + vs * 0.55 * sweep,
					chest + vs * 0.28 * strike,
					-vs * (0.32 + 0.62 * strike)
				)
				arm_pos = Vector3(side * 0.4 + vs * 0.22 * sweep, chest * 0.72 + vs * 0.12 * strike, -vs * (0.1 + 0.22 * strike))
				arm_rot = Vector3(0.25 * strike, 0.0, sweep * 0.8)
		_ItemAnim.Kind.THRUST:
			var lunge := 0.28
			if phase < 0.0:
				lunge = lerpf(0.28, 1.2, phase + 1.0)
			else:
				lunge = lerpf(1.2, 0.28, phase)
			item_pos = Vector3(side * 0.35, chest, -lunge * vs)
			arm_pos = Vector3(side * 0.2, chest * 0.7, -lunge * vs * 0.45)
			arm_rot = Vector3(-0.15 + lunge * 0.35, 0.0, 0.05)
		_ItemAnim.Kind.RAISE:
			var lift := strike
			item_pos = Vector3(side * 0.45, chest * 0.65 + vs * 0.75 * lift, -vs * 0.22)
			arm_pos = Vector3(side * 0.25, chest * 0.6 + vs * 0.4 * lift, -vs * 0.08)
			arm_rot = Vector3(-1.0 * lift, 0.0, 0.1)
		_ItemAnim.Kind.AIM:
			var draw := 0.0
			if phase < 0.0:
				draw = phase + 1.0
			else:
				draw = 1.0 - phase
			item_pos = Vector3(side * 0.9, chest, -vs * (0.62 - 0.38 * draw))
			arm_pos = Vector3(side * 0.4, chest * 0.78, -vs * (0.2 - 0.12 * draw))
			arm_rot = Vector3(-0.2, 0.15 * draw, 0.35)
		_:
			item_pos = Vector3(side, chest * 0.9, -vs * 0.2)
	_arm.position = arm_pos
	_arm.rotation = arm_rot
	_arm.scale = Vector3.ONE
	_item.position = item_pos
	_arm.visible = kind != _ItemAnim.Kind.NONE
	_item.visible = kind != _ItemAnim.Kind.NONE


func _texture_for(key: String) -> Texture2D:
	if key.is_empty():
		return null
	var path := "res://assets/art/items/%s.png" % key
	if not ResourceLoader.exists(path) and _TextureSet.resolved_path(path) == path:
		return null
	return _TextureSet.resolve(path)


static func _fallback_texture() -> Texture2D:
	if _fallback_tex == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_fallback_tex = ImageTexture.create_from_image(image)
	return _fallback_tex


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
