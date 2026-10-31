class_name VoxelPropBuilder
extends RefCounted

const _Lit = preload("res://helpers/voxel_lit_material.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _BRICK_PATH := "res://assets/art/voxel_brick.png"

static var _brick_tex: Texture2D


static func _brick_texture() -> Texture2D:
	if _brick_tex == null:
		_brick_tex = load(_BRICK_PATH) as Texture2D
	return _brick_tex


static func unit(voxel_scale: float = -1.0) -> float:
	var vs: float = voxel_scale if voxel_scale > 0.0 else _WorldSettings.get_active().voxel_scale
	return vs * 0.62


static func build_entity(entity_id: StringName, tint: Color = Color.WHITE) -> Node3D:
	var root := Node3D.new()
	root.name = "VoxelProp"
	var u := unit()
	var boxes: Array = _entity_boxes(entity_id, u, tint)
	for i in boxes.size():
		var spec: Dictionary = boxes[i]
		root.add_child(_box_instance(spec.center, spec.size, spec.color))
	return root


static func build_plant(plant_id: String, stage: int, tint: Color = Color.WHITE, biome: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = "VoxelProp"
	var u := unit()
	var growth := float(stage + 1) / 3.0
	var boxes: Array = _plant_boxes(plant_id, u, growth, tint, biome)
	for spec in boxes:
		root.add_child(_box_instance(spec.center, spec.size, spec.color))
	return root


static func build_scatter_prop(kind: String) -> Node3D:
	var node := _scatter_node(kind)
	_Lit.apply(node)
	return node


static func _scatter_node(kind: String) -> Node3D:
	match kind:
		"bush":
			var bush := build_plant("bush", 2)
			bush.name = "VoxelProp"
			return bush
		"flower":
			var flower := build_plant("wildflower", 2)
			flower.name = "VoxelProp"
			return flower
		"log":
			return _assemble_prop(_log_boxes(unit()))
		"flower_red":
			return _assemble_prop(_flower_boxes(unit(), Color(0.86, 0.22, 0.2)))
		"flower_yellow":
			return _assemble_prop(_flower_boxes(unit(), Color(0.95, 0.82, 0.24)))
		"flower_blue":
			return _assemble_prop(_flower_boxes(unit(), Color(0.36, 0.5, 0.92)))
		"flower_white":
			return _assemble_prop(_flower_boxes(unit(), Color(0.94, 0.93, 0.88)))
		"grass_tuft":
			return _assemble_prop(_tuft_boxes(unit(), Color(0.42, 0.66, 0.3)))
		"fern":
			return _assemble_prop(_fern_boxes(unit()))
		"boulder":
			return _assemble_prop(_boulder_boxes(unit()))
		"stump":
			return _assemble_prop(_stump_boxes(unit()))
		"reeds":
			return _assemble_prop(_reed_boxes(unit()))
		"sapling":
			return _assemble_prop(_sapling_boxes(unit()))
		"dead_bush":
			return _assemble_prop(_dead_bush_boxes(unit()))
		"mushroom":
			return _assemble_prop(_mushroom_boxes(unit()))
		"fence":
			return _assemble_prop(_fence_boxes(unit()))
		_:
			return _assemble_prop(_rock_boxes(unit()))


static func _assemble_prop(boxes: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "VoxelProp"
	for spec in boxes:
		root.add_child(_box_instance(spec.center, spec.size, spec.color))
	return root


static func _rock_boxes(u: float) -> Array:
	var stone := Color(0.55, 0.54, 0.5)
	return [
		{"center": Vector3(0, u * 0.38, 0), "size": Vector3(u * 1.35, u * 0.7, u * 1.15), "color": stone},
		{"center": Vector3(u * 0.28, u * 0.72, u * 0.08), "size": Vector3(u * 0.85, u * 0.55, u * 0.75), "color": stone.lightened(0.08)},
		{"center": Vector3(-u * 0.35, u * 0.28, u * 0.22), "size": Vector3(u * 0.55, u * 0.4, u * 0.5), "color": stone.darkened(0.12)},
	]


static func _log_boxes(u: float) -> Array:
	var bark := Color(0.42, 0.28, 0.16)
	var cut := Color(0.62, 0.48, 0.28)
	var length := u * 2.4
	return [
		{"center": Vector3(0, u * 0.38, 0), "size": Vector3(length, u * 0.7, u * 0.7), "color": bark},
		{"center": Vector3(-length * 0.48, u * 0.38, 0), "size": Vector3(u * 0.12, u * 0.62, u * 0.62), "color": cut},
		{"center": Vector3(length * 0.48, u * 0.38, 0), "size": Vector3(u * 0.12, u * 0.62, u * 0.62), "color": cut},
	]


static func _flower_boxes(u: float, petal: Color) -> Array:
	var stem := Color(0.36, 0.6, 0.26)
	return [
		{"center": Vector3(0, u * 0.32, 0), "size": Vector3(u * 0.1, u * 0.64, u * 0.1), "color": stem},
		{"center": Vector3(u * 0.16, u * 0.18, 0), "size": Vector3(u * 0.26, u * 0.08, u * 0.14), "color": stem.lightened(0.1)},
		{"center": Vector3(0, u * 0.7, 0), "size": Vector3(u * 0.34, u * 0.16, u * 0.34), "color": petal},
		{"center": Vector3(0, u * 0.74, 0), "size": Vector3(u * 0.12, u * 0.12, u * 0.12), "color": Color(0.96, 0.84, 0.3) if petal.b > 0.5 or petal.r > 0.9 and petal.g > 0.9 else Color(0.4, 0.26, 0.12)},
	]


static func _tuft_boxes(u: float, green: Color) -> Array:
	return [
		{"center": Vector3(0, u * 0.25, 0), "size": Vector3(u * 0.12, u * 0.5, u * 0.12), "color": green},
		{"center": Vector3(u * 0.16, u * 0.18, u * 0.06), "size": Vector3(u * 0.1, u * 0.36, u * 0.1), "color": green.lightened(0.12)},
		{"center": Vector3(-u * 0.14, u * 0.2, -u * 0.08), "size": Vector3(u * 0.1, u * 0.4, u * 0.1), "color": green.darkened(0.1)},
		{"center": Vector3(u * 0.04, u * 0.14, -u * 0.16), "size": Vector3(u * 0.1, u * 0.28, u * 0.1), "color": green.lightened(0.05)},
	]


static func _fern_boxes(u: float) -> Array:
	var g := Color(0.3, 0.58, 0.28)
	return [
		{"center": Vector3(0, u * 0.12, 0), "size": Vector3(u * 0.16, u * 0.24, u * 0.16), "color": g.darkened(0.15)},
		{"center": Vector3(u * 0.34, u * 0.3, 0), "size": Vector3(u * 0.7, u * 0.06, u * 0.22), "color": g},
		{"center": Vector3(-u * 0.34, u * 0.32, 0), "size": Vector3(u * 0.7, u * 0.06, u * 0.22), "color": g.lightened(0.08)},
		{"center": Vector3(0, u * 0.34, u * 0.34), "size": Vector3(u * 0.22, u * 0.06, u * 0.7), "color": g.lightened(0.04)},
		{"center": Vector3(0, u * 0.28, -u * 0.34), "size": Vector3(u * 0.22, u * 0.06, u * 0.7), "color": g},
	]


static func _boulder_boxes(u: float) -> Array:
	var stone := Color(0.5, 0.5, 0.48)
	return [
		{"center": Vector3(0, u * 0.7, 0), "size": Vector3(u * 2.2, u * 1.4, u * 1.9), "color": stone},
		{"center": Vector3(u * 0.4, u * 1.45, -u * 0.1), "size": Vector3(u * 1.3, u * 0.6, u * 1.2), "color": stone.lightened(0.07)},
		{"center": Vector3(-u * 0.9, u * 0.35, u * 0.6), "size": Vector3(u * 0.8, u * 0.7, u * 0.7), "color": stone.darkened(0.1)},
		{"center": Vector3(u * 0.2, u * 1.4, u * 0.6), "size": Vector3(u * 0.5, u * 0.2, u * 0.5), "color": Color(0.38, 0.55, 0.3)},
	]


static func _stump_boxes(u: float) -> Array:
	var bark := Color(0.42, 0.29, 0.17)
	return [
		{"center": Vector3(0, u * 0.3, 0), "size": Vector3(u * 0.8, u * 0.6, u * 0.8), "color": bark},
		{"center": Vector3(0, u * 0.61, 0), "size": Vector3(u * 0.66, u * 0.04, u * 0.66), "color": Color(0.66, 0.52, 0.32)},
		{"center": Vector3(u * 0.45, u * 0.08, 0), "size": Vector3(u * 0.3, u * 0.16, u * 0.2), "color": bark.darkened(0.1)},
	]


static func _reed_boxes(u: float) -> Array:
	var g := Color(0.52, 0.62, 0.3)
	var top := Color(0.5, 0.36, 0.2)
	return [
		{"center": Vector3(0, u * 0.6, 0), "size": Vector3(u * 0.08, u * 1.2, u * 0.08), "color": g},
		{"center": Vector3(u * 0.2, u * 0.5, u * 0.1), "size": Vector3(u * 0.08, u * 1.0, u * 0.08), "color": g.darkened(0.08)},
		{"center": Vector3(-u * 0.18, u * 0.55, -u * 0.12), "size": Vector3(u * 0.08, u * 1.1, u * 0.08), "color": g.lightened(0.08)},
		{"center": Vector3(0, u * 1.24, 0), "size": Vector3(u * 0.12, u * 0.24, u * 0.12), "color": top},
		{"center": Vector3(u * 0.2, u * 1.04, u * 0.1), "size": Vector3(u * 0.12, u * 0.2, u * 0.12), "color": top},
	]


static func _sapling_boxes(u: float) -> Array:
	var leaf := Color(0.38, 0.66, 0.32)
	return [
		{"center": Vector3(0, u * 0.55, 0), "size": Vector3(u * 0.14, u * 1.1, u * 0.14), "color": Color(0.46, 0.32, 0.18)},
		{"center": Vector3(0, u * 1.2, 0), "size": Vector3(u * 0.7, u * 0.5, u * 0.7), "color": leaf},
		{"center": Vector3(u * 0.12, u * 1.55, -u * 0.06), "size": Vector3(u * 0.4, u * 0.3, u * 0.4), "color": leaf.lightened(0.1)},
	]


static func _dead_bush_boxes(u: float) -> Array:
	var twig := Color(0.56, 0.44, 0.3)
	return [
		{"center": Vector3(0, u * 0.25, 0), "size": Vector3(u * 0.12, u * 0.5, u * 0.12), "color": twig},
		{"center": Vector3(u * 0.22, u * 0.42, 0), "size": Vector3(u * 0.44, u * 0.08, u * 0.08), "color": twig.lightened(0.06)},
		{"center": Vector3(-u * 0.18, u * 0.5, u * 0.1), "size": Vector3(u * 0.36, u * 0.08, u * 0.08), "color": twig.darkened(0.06)},
		{"center": Vector3(0, u * 0.36, -u * 0.2), "size": Vector3(u * 0.08, u * 0.08, u * 0.4), "color": twig},
	]


static func _mushroom_boxes(u: float) -> Array:
	return [
		{"center": Vector3(0, u * 0.45, 0), "size": Vector3(u * 0.28, u * 0.9, u * 0.28), "color": Color(0.86, 0.82, 0.7)},
		{"center": Vector3(0, u * 0.95, 0), "size": Vector3(u * 1.15, u * 0.38, u * 1.15), "color": Color(0.72, 0.18, 0.16)},
		{"center": Vector3(-u * 0.28, u * 1.08, u * 0.12), "size": Vector3(u * 0.22, u * 0.12, u * 0.22), "color": Color(0.92, 0.9, 0.82)},
		{"center": Vector3(u * 0.22, u * 1.06, -u * 0.18), "size": Vector3(u * 0.18, u * 0.1, u * 0.18), "color": Color(0.92, 0.9, 0.82)},
	]


static func _fence_boxes(u: float) -> Array:
	var wood := Color(0.45, 0.32, 0.18)
	var dark := Color(0.32, 0.22, 0.12)
	var post_h := u * 1.35
	var span := u * 1.7
	return [
		{"center": Vector3(-span, post_h * 0.5, 0), "size": Vector3(u * 0.28, post_h, u * 0.28), "color": dark},
		{"center": Vector3(span, post_h * 0.5, 0), "size": Vector3(u * 0.28, post_h, u * 0.28), "color": dark},
		{"center": Vector3(0, post_h * 0.42, 0), "size": Vector3(span * 2.0, u * 0.18, u * 0.16), "color": wood},
		{"center": Vector3(0, post_h * 0.78, 0), "size": Vector3(span * 2.0, u * 0.16, u * 0.14), "color": wood},
	]


static func model_height(node: Node3D) -> float:
	if node == null:
		return 0.0
	var max_y := 0.0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mesh := mi.mesh as BoxMesh
			if mesh:
				max_y = maxf(max_y, mi.position.y + mesh.size.y * 0.5)
	return max_y


static func _box_instance(center: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = center
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = _brick_texture()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.disable_receive_shadows = false
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 0.92
	mat.metallic = 0.0
	mi.material_override = mat
	return mi


static func _entity_boxes(entity_id: StringName, u: float, tint: Color) -> Array:
	var id := str(entity_id)
	var body := tint if tint != Color.WHITE else Color(0.78, 0.68, 0.55)
	var dark := body.darkened(0.22)
	var accent := body.lightened(0.12)
	match id:
		"rabbit":
			return [
				{"center": Vector3(0, u * 1.1, 0), "size": Vector3(u * 2.2, u * 1.6, u * 2.6), "color": body},
				{"center": Vector3(0, u * 2.2, u * 0.35), "size": Vector3(u * 1.6, u * 1.4, u * 1.6), "color": accent},
				{"center": Vector3(-u * 0.55, u * 3.0, u * 0.2), "size": Vector3(u * 0.5, u * 1.0, u * 0.35), "color": dark},
				{"center": Vector3(u * 0.55, u * 3.0, u * 0.2), "size": Vector3(u * 0.5, u * 1.0, u * 0.35), "color": dark},
			]
		"deer":
			body = Color(0.72, 0.52, 0.38)
			return [
				{"center": Vector3(0, u * 1.4, 0), "size": Vector3(u * 2.0, u * 2.0, u * 3.6), "color": body},
				{"center": Vector3(0, u * 2.8, u * 1.2), "size": Vector3(u * 1.2, u * 1.6, u * 1.4), "color": body.lightened(0.08)},
				{"center": Vector3(-u * 0.35, u * 3.8, u * 1.0), "size": Vector3(u * 0.35, u * 1.4, u * 0.35), "color": body.darkened(0.15)},
				{"center": Vector3(u * 0.35, u * 3.8, u * 1.0), "size": Vector3(u * 0.35, u * 1.4, u * 0.35), "color": body.darkened(0.15)},
			]
		"boar":
			body = Color(0.48, 0.36, 0.32)
			return [
				{"center": Vector3(0, u * 1.2, 0), "size": Vector3(u * 2.6, u * 1.8, u * 3.2), "color": body},
				{"center": Vector3(0, u * 2.0, u * 1.4), "size": Vector3(u * 1.8, u * 1.4, u * 1.6), "color": body.darkened(0.12)},
			]
		"crystal_mite":
			return [
				{"center": Vector3(0, u * 0.7, 0), "size": Vector3(u * 1.4, u * 0.7, u * 1.6), "color": Color(0.55, 0.22, 0.82)},
				{"center": Vector3(0, u * 1.35, u * 0.35), "size": Vector3(u * 0.9, u * 0.7, u * 0.9), "color": Color(0.78, 0.45, 1.0)},
				{"center": Vector3(-u * 0.35, u * 1.9, u * 0.2), "size": Vector3(u * 0.28, u * 0.55, u * 0.28), "color": Color(0.9, 0.7, 1.0)},
				{"center": Vector3(u * 0.35, u * 1.9, u * 0.2), "size": Vector3(u * 0.28, u * 0.55, u * 0.28), "color": Color(0.9, 0.7, 1.0)},
			]
		"thornling":
			return [
				{"center": Vector3(0, u * 1.3, 0), "size": Vector3(u * 0.7, u * 2.4, u * 0.7), "color": Color(0.32, 0.55, 0.28)},
				{"center": Vector3(-u * 0.45, u * 2.2, 0), "size": Vector3(u * 0.35, u * 1.3, u * 0.35), "color": Color(0.62, 0.28, 0.85)},
				{"center": Vector3(u * 0.5, u * 2.6, u * 0.1), "size": Vector3(u * 0.32, u * 1.6, u * 0.32), "color": Color(0.78, 0.4, 0.95)},
				{"center": Vector3(0, u * 3.4, 0), "size": Vector3(u * 0.4, u * 1.5, u * 0.4), "color": Color(0.9, 0.65, 1.0)},
			]
		"shard_guard":
			return [
				{"center": Vector3(0, u * 1.6, 0), "size": Vector3(u * 1.8, u * 2.6, u * 1.4), "color": Color(0.42, 0.18, 0.68)},
				{"center": Vector3(0, u * 3.3, 0), "size": Vector3(u * 1.2, u * 1.1, u * 1.2), "color": Color(0.72, 0.4, 0.95)},
				{"center": Vector3(-u * 0.7, u * 2.4, 0), "size": Vector3(u * 0.45, u * 1.8, u * 0.45), "color": Color(0.85, 0.55, 1.0)},
				{"center": Vector3(u * 0.15, u * 4.4, 0), "size": Vector3(u * 0.4, u * 1.6, u * 0.4), "color": Color(0.95, 0.75, 1.0)},
			]
		"farm_bomber":
			return [
				{"center": Vector3(0, u * 1.1, 0), "size": Vector3(u * 2.0, u * 1.6, u * 2.0), "color": Color(0.48, 0.22, 0.62)},
				{"center": Vector3(0, u * 2.1, u * 0.2), "size": Vector3(u * 1.3, u * 1.0, u * 1.3), "color": Color(0.7, 0.35, 0.9)},
				{"center": Vector3(0, u * 3.2, 0), "size": Vector3(u * 0.35, u * 1.4, u * 0.35), "color": Color(0.95, 0.8, 0.4)},
				{"center": Vector3(0, u * 4.0, 0), "size": Vector3(u * 0.55, u * 0.55, u * 0.55), "color": Color(1.0, 0.45, 0.25)},
			]
		"crystal_stag":
			body = Color(0.58, 0.28, 0.88)
			return [
				{"center": Vector3(0, u * 1.5, 0), "size": Vector3(u * 2.0, u * 2.0, u * 3.4), "color": body},
				{"center": Vector3(0, u * 2.9, u * 1.15), "size": Vector3(u * 1.2, u * 1.4, u * 1.3), "color": body.lightened(0.12)},
				{"center": Vector3(-u * 0.4, u * 4.2, u * 0.9), "size": Vector3(u * 0.28, u * 1.6, u * 0.28), "color": Color(0.9, 0.6, 1.0)},
				{"center": Vector3(u * 0.4, u * 4.3, u * 0.9), "size": Vector3(u * 0.28, u * 1.7, u * 0.28), "color": Color(0.85, 0.5, 1.0)},
			]
		"corrupted_beast":
			body = Color(0.4, 0.16, 0.55)
			return [
				{"center": Vector3(0, u * 1.3, 0), "size": Vector3(u * 2.8, u * 1.8, u * 3.4), "color": body},
				{"center": Vector3(0, u * 2.2, u * 1.5), "size": Vector3(u * 1.8, u * 1.4, u * 1.5), "color": body.lightened(0.1)},
				{"center": Vector3(-u * 0.55, u * 3.6, u * 1.2), "size": Vector3(u * 0.4, u * 1.5, u * 0.4), "color": Color(0.8, 0.4, 1.0)},
				{"center": Vector3(u * 0.55, u * 3.8, u * 1.2), "size": Vector3(u * 0.4, u * 1.6, u * 0.4), "color": Color(0.9, 0.55, 1.0)},
			]
		"crystal_wisp":
			return [
				{"center": Vector3(0, u * 2.2, 0), "size": Vector3(u * 1.1, u * 1.1, u * 1.1), "color": Color(0.72, 0.45, 1.0)},
				{"center": Vector3(0, u * 3.15, 0), "size": Vector3(u * 0.45, u * 0.9, u * 0.45), "color": Color(0.92, 0.75, 1.0)},
				{"center": Vector3(0, u * 1.35, 0), "size": Vector3(u * 0.35, u * 0.7, u * 0.35), "color": Color(0.4, 0.16, 0.62)},
			]
		"bird":
			body = Color(0.55, 0.65, 0.82)
			return [
				{"center": Vector3(0, u * 1.6, 0), "size": Vector3(u * 1.2, u * 1.0, u * 2.2), "color": body},
				{"center": Vector3(0, u * 2.2, -u * 0.2), "size": Vector3(u * 2.4, u * 0.35, u * 1.2), "color": accent},
			]
		"town_militia":
			body = Color(0.55, 0.58, 0.72)
			return [
				{"center": Vector3(0, u * 1.8, 0), "size": Vector3(u * 1.6, u * 2.4, u * 1.4), "color": body},
				{"center": Vector3(0, u * 3.4, 0), "size": Vector3(u * 1.2, u * 1.2, u * 1.2), "color": Color(0.82, 0.72, 0.58)},
			]
		_:
			body = Color(0.68, 0.32, 0.88)
			return [
				{"center": Vector3(0, u * 1.5, 0), "size": Vector3(u * 2.0, u * 2.2, u * 2.0), "color": body},
				{"center": Vector3(0, u * 3.0, 0), "size": Vector3(u * 1.4, u * 1.2, u * 1.4), "color": Color(0.92, 0.55, 1.0)},
			]


static func _steppe_grass_colors() -> Array:
	return [
		Color(0.62, 0.58, 0.28),
		Color(0.72, 0.66, 0.34),
		Color(0.55, 0.5, 0.24),
		Color(0.68, 0.62, 0.3),
	]


static func _plant_boxes(plant_id: String, u: float, growth: float, _tint: Color, biome: String = "") -> Array:
	var steppe: bool = biome == "steppe" or biome == "savanna"
	match plant_id:
		"grass_tuft", "grass":
			var h := u * (1.4 + growth * 1.8)
			var cols: Array = _steppe_grass_colors() if steppe else [
				Color(0.32, 0.72, 0.28), Color(0.42, 0.82, 0.35),
				Color(0.28, 0.65, 0.25), Color(0.36, 0.76, 0.32),
			]
			return [
				{"center": Vector3(-u * 0.3, h * 0.5, 0), "size": Vector3(u * 0.42, h, u * 0.42), "color": cols[0]},
				{"center": Vector3(u * 0.22, h * 0.55, u * 0.12), "size": Vector3(u * 0.38, h * 1.1, u * 0.38), "color": cols[1]},
				{"center": Vector3(0, h * 0.48, -u * 0.22), "size": Vector3(u * 0.36, h * 0.95, u * 0.36), "color": cols[2]},
				{"center": Vector3(u * 0.05, h * 0.42, u * 0.28), "size": Vector3(u * 0.34, h * 0.88, u * 0.34), "color": cols[3]},
			]
		"tall_grass":
			var th := u * (2.4 + growth * 2.6)
			var tcols: Array = _steppe_grass_colors() if steppe else [
				Color(0.3, 0.68, 0.26), Color(0.38, 0.78, 0.32),
				Color(0.26, 0.6, 0.22), Color(0.34, 0.74, 0.3),
			]
			return [
				{"center": Vector3(-u * 0.18, th * 0.5, u * 0.08), "size": Vector3(u * 0.36, th, u * 0.36), "color": tcols[0]},
				{"center": Vector3(u * 0.22, th * 0.52, -u * 0.04), "size": Vector3(u * 0.38, th * 1.12, u * 0.38), "color": tcols[1]},
				{"center": Vector3(0, th * 0.48, 0), "size": Vector3(u * 0.34, th * 1.0, u * 0.34), "color": tcols[2]},
				{"center": Vector3(-u * 0.08, th * 0.46, -u * 0.18), "size": Vector3(u * 0.32, th * 0.92, u * 0.32), "color": tcols[3]},
			]
		"wildflower":
			var fh := u * (0.9 + growth * 0.8)
			var petal := Color(0.92, 0.42, 0.62) if growth > 0.45 else Color(0.95, 0.78, 0.28)
			return [
				{"center": Vector3(0, fh * 0.35, 0), "size": Vector3(u * 0.18, fh * 0.7, u * 0.18), "color": Color(0.34, 0.7, 0.28)},
				{"center": Vector3(0, fh * 0.85, 0), "size": Vector3(u * 0.55, u * 0.35, u * 0.55), "color": petal},
			]
		"fern":
			var fh2 := u * (1.1 + growth * 1.5)
			return [
				{"center": Vector3(-u * 0.35, fh2 * 0.45, 0), "size": Vector3(u * 0.55, u * 0.25, u * 0.7), "color": Color(0.22, 0.58, 0.3)},
				{"center": Vector3(u * 0.35, fh2 * 0.45, 0), "size": Vector3(u * 0.55, u * 0.25, u * 0.7), "color": Color(0.28, 0.66, 0.34)},
				{"center": Vector3(0, fh2 * 0.55, -u * 0.15), "size": Vector3(u * 0.45, u * 0.22, u * 0.6), "color": Color(0.2, 0.52, 0.28)},
			]
		"bush":
			var r := u * (1.0 + growth * 0.8)
			return [
				{"center": Vector3(0, r * 0.55, 0), "size": Vector3(r * 1.6, r * 1.1, r * 1.5), "color": Color(0.28, 0.58, 0.28)},
				{"center": Vector3(-r * 0.35, r * 0.85, r * 0.2), "size": Vector3(r * 0.9, r * 0.8, r * 0.9), "color": Color(0.38, 0.72, 0.32)},
				{"center": Vector3(r * 0.3, r * 0.75, -r * 0.15), "size": Vector3(r * 0.85, r * 0.75, r * 0.85), "color": Color(0.32, 0.68, 0.3)},
			]
		"crystal_grass":
			var ch := u * (1.3 + growth * 1.6)
			return [
				{"center": Vector3(-u * 0.28, ch * 0.5, 0), "size": Vector3(u * 0.28, ch, u * 0.28), "color": Color(0.62, 0.32, 0.92)},
				{"center": Vector3(u * 0.18, ch * 0.62, u * 0.1), "size": Vector3(u * 0.24, ch * 1.15, u * 0.24), "color": Color(0.78, 0.48, 1.0)},
				{"center": Vector3(0, ch * 0.4, -u * 0.16), "size": Vector3(u * 0.22, ch * 0.8, u * 0.22), "color": Color(0.42, 0.18, 0.68)},
			]
		"crystal_bush":
			var cr := u * (0.9 + growth * 0.7)
			return [
				{"center": Vector3(0, cr * 0.55, 0), "size": Vector3(cr * 1.5, cr * 1.0, cr * 1.4), "color": Color(0.48, 0.22, 0.78)},
				{"center": Vector3(-cr * 0.3, cr * 0.9, cr * 0.15), "size": Vector3(cr * 0.7, cr * 0.7, cr * 0.7), "color": Color(0.72, 0.4, 0.95)},
				{"center": Vector3(cr * 0.28, cr * 0.75, -cr * 0.1), "size": Vector3(cr * 0.45, cr * 0.9, cr * 0.45), "color": Color(0.9, 0.7, 1.0)},
			]
		"shard_tree":
			var sh := u * (2.0 + growth * 1.6)
			return [
				{"center": Vector3(0, sh * 0.45, 0), "size": Vector3(u * 0.7, sh, u * 0.7), "color": Color(0.55, 0.28, 0.82)},
				{"center": Vector3(0, sh + u * 0.8, 0), "size": Vector3(u * 1.8, u * 1.6, u * 1.8), "color": Color(0.42, 0.16, 0.7)},
				{"center": Vector3(-u * 0.4, sh + u * 1.5, 0), "size": Vector3(u * 0.35, u * 1.1, u * 0.35), "color": Color(0.85, 0.55, 1.0)},
				{"center": Vector3(u * 0.45, sh + u * 1.35, u * 0.1), "size": Vector3(u * 0.3, u * 0.9, u * 0.3), "color": Color(0.78, 0.42, 0.95)},
			]
		"tree":
			var trunk_h := u * (2.2 + growth * 1.8)
			var canopy_r := u * (2.0 + growth * 2.2)
			return [
				{"center": Vector3(0, trunk_h * 0.5, 0), "size": Vector3(u * 0.85, trunk_h, u * 0.85), "color": Color(0.42, 0.28, 0.18)},
				{"center": Vector3(0, trunk_h + canopy_r * 0.42, 0), "size": Vector3(canopy_r * 2.2, canopy_r * 1.6, canopy_r * 2.2), "color": Color(0.22, 0.52, 0.26)},
				{"center": Vector3(0, trunk_h + canopy_r * 0.92, 0), "size": Vector3(canopy_r * 1.5, canopy_r * 1.1, canopy_r * 1.5), "color": Color(0.32, 0.7, 0.34)},
			]
		_:
			var trunk_h2 := u * (1.8 + growth * 1.4)
			var canopy_r2 := u * (1.6 + growth * 1.8)
			return [
				{"center": Vector3(0, trunk_h2 * 0.5, 0), "size": Vector3(u * 0.75, trunk_h2, u * 0.75), "color": Color(0.42, 0.28, 0.18)},
				{"center": Vector3(0, trunk_h2 + canopy_r2 * 0.45, 0), "size": Vector3(canopy_r2 * 2.0, canopy_r2 * 1.5, canopy_r2 * 2.0), "color": Color(0.25, 0.55, 0.28)},
				{"center": Vector3(0, trunk_h2 + canopy_r2 * 0.95, 0), "size": Vector3(canopy_r2 * 1.3, canopy_r2 * 1.0, canopy_r2 * 1.3), "color": Color(0.35, 0.72, 0.35)},
			]


static func apply_tint(root: Node3D, color: Color) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D:
			var mat := ((child as MeshInstance3D).material_override as StandardMaterial3D).duplicate()
			mat.albedo_color = mat.albedo_color.lerp(color, 0.35)
			(child as MeshInstance3D).material_override = mat


static func flash_tint(root: Node3D, flash: Color) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D:
			((child as MeshInstance3D).material_override as StandardMaterial3D).albedo_color = flash