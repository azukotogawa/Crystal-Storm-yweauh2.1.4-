class_name VoxelPropBuilder
extends RefCounted

const _WorldSettings = preload("res://config/world_settings.gd")


static func unit(voxel_scale: float = -1.0) -> float:
	var vs: float = voxel_scale if voxel_scale > 0.0 else _WorldSettings.get_active().voxel_scale
	return vs * 0.85


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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
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
		"crystal_mite":
			return _crystal_cluster_boxes(u, body, accent, 1.15, 5)
		"thornling":
			body = body if tint != Color.WHITE else Color(0.3, 0.75, 0.35)
			accent = Color(0.45, 0.92, 0.42)
			return [
				{"center": Vector3(0, u * 0.9, 0), "size": Vector3(u * 1.4, u * 1.2, u * 1.4), "color": body.darkened(0.12)},
				{"center": Vector3(-u * 0.42, u * 1.5, u * 0.1), "size": Vector3(u * 0.35, u * 1.35, u * 0.35), "color": accent},
				{"center": Vector3(u * 0.38, u * 1.55, -u * 0.08), "size": Vector3(u * 0.34, u * 1.4, u * 0.34), "color": accent},
				{"center": Vector3(0, u * 2.0, u * 0.32), "size": Vector3(u * 0.32, u * 1.2, u * 0.32), "color": body.lightened(0.08)},
				{"center": Vector3(u * 0.12, u * 2.15, -u * 0.28), "size": Vector3(u * 0.3, u * 1.1, u * 0.3), "color": dark},
			]
		"shard_guard":
			return [
				{"center": Vector3(0, u * 1.6, 0), "size": Vector3(u * 1.5, u * 2.6, u * 1.5), "color": body},
				{"center": Vector3(0, u * 3.4, 0), "size": Vector3(u * 1.1, u * 1.4, u * 1.1), "color": accent},
				{"center": Vector3(-u * 0.75, u * 2.4, 0), "size": Vector3(u * 0.45, u * 1.5, u * 0.55), "color": accent},
				{"center": Vector3(u * 0.75, u * 2.4, 0), "size": Vector3(u * 0.45, u * 1.5, u * 0.55), "color": accent},
				{"center": Vector3(0, u * 4.1, 0), "size": Vector3(u * 0.55, u * 0.75, u * 0.55), "color": Color(0.95, 0.75, 1.0)},
			]
		"farm_bomber":
			body = body if tint != Color.WHITE else Color(0.95, 0.55, 0.2)
			return [
				{"center": Vector3(0, u * 1.1, 0), "size": Vector3(u * 2.2, u * 1.8, u * 2.2), "color": body},
				{"center": Vector3(0, u * 2.2, u * 0.35), "size": Vector3(u * 0.45, u * 0.9, u * 0.45), "color": Color(0.35, 0.32, 0.28)},
				{"center": Vector3(u * 0.55, u * 2.0, -u * 0.2), "size": Vector3(u * 0.35, u * 0.35, u * 0.8), "color": accent},
				{"center": Vector3(-u * 0.5, u * 2.0, u * 0.25), "size": Vector3(u * 0.35, u * 0.35, u * 0.75), "color": accent},
			]
		"crystal_stag":
			return [
				{"center": Vector3(0, u * 1.5, 0), "size": Vector3(u * 1.4, u * 2.2, u * 1.8), "color": body},
				{"center": Vector3(-u * 0.55, u * 3.0, u * 0.15), "size": Vector3(u * 0.4, u * 1.8, u * 0.4), "color": accent},
				{"center": Vector3(u * 0.55, u * 3.0, u * 0.15), "size": Vector3(u * 0.4, u * 1.8, u * 0.4), "color": accent},
				{"center": Vector3(-u * 0.25, u * 3.8, u * 0.35), "size": Vector3(u * 0.32, u * 1.1, u * 0.32), "color": Color(0.82, 0.55, 1.0)},
				{"center": Vector3(u * 0.25, u * 3.8, u * 0.35), "size": Vector3(u * 0.32, u * 1.1, u * 0.32), "color": Color(0.82, 0.55, 1.0)},
			]
		"corrupted_beast":
			body = body if tint != Color.WHITE else Color(0.45, 0.18, 0.55)
			return [
				{"center": Vector3(0, u * 1.4, 0), "size": Vector3(u * 2.4, u * 2.0, u * 3.0), "color": body},
				{"center": Vector3(0, u * 2.8, u * 1.1), "size": Vector3(u * 1.6, u * 1.5, u * 1.5), "color": body.darkened(0.1)},
				{"center": Vector3(-u * 0.65, u * 2.2, u * 0.9), "size": Vector3(u * 0.55, u * 1.2, u * 0.55), "color": accent},
				{"center": Vector3(u * 0.65, u * 2.2, u * 0.9), "size": Vector3(u * 0.55, u * 1.2, u * 0.55), "color": accent},
				{"center": Vector3(0, u * 3.5, 0), "size": Vector3(u * 1.2, u * 1.0, u * 1.2), "color": Color(0.78, 0.35, 0.92)},
			]
		_:
			body = Color(0.68, 0.32, 0.88)
			return [
				{"center": Vector3(0, u * 1.5, 0), "size": Vector3(u * 2.0, u * 2.2, u * 2.0), "color": body},
				{"center": Vector3(0, u * 3.0, 0), "size": Vector3(u * 1.4, u * 1.2, u * 1.4), "color": Color(0.92, 0.55, 1.0)},
			]


static func _crystal_cluster_boxes(
	u: float,
	body: Color,
	accent: Color,
	scale: float,
	shards: int
) -> Array:
	var out: Array = []
	var offsets: Array = [
		Vector3(0, u * 0.55 * scale, 0),
		Vector3(-u * 0.28 * scale, u * 0.42 * scale, u * 0.18 * scale),
		Vector3(u * 0.24 * scale, u * 0.48 * scale, -u * 0.16 * scale),
		Vector3(u * 0.1 * scale, u * 0.38 * scale, u * 0.26 * scale),
		Vector3(-u * 0.12 * scale, u * 0.36 * scale, -u * 0.22 * scale),
	]
	var heights: Array = [1.15, 0.95, 1.05, 0.88, 0.82]
	for i in mini(shards, offsets.size()):
		var h: float = u * float(heights[i]) * scale
		var c: Color = accent if i % 2 == 1 else body
		out.append({
			"center": offsets[i],
			"size": Vector3(u * 0.42 * scale, h, u * 0.42 * scale),
			"color": c,
		})
	return out


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
			var h := u * (1.8 + growth * 2.2)
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
			var th := u * (3.0 + growth * 3.2)
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
			var fh := u * (1.1 + growth * 1.0)
			var petal := Color(0.92, 0.42, 0.62) if growth > 0.45 else Color(0.95, 0.78, 0.28)
			return [
				{"center": Vector3(0, fh * 0.32, 0), "size": Vector3(u * 0.2, fh * 0.64, u * 0.2), "color": Color(0.34, 0.7, 0.28)},
				{"center": Vector3(0, fh * 0.82, 0), "size": Vector3(u * 0.62, u * 0.38, u * 0.62), "color": petal},
				{"center": Vector3(u * 0.18, fh * 0.78, u * 0.1), "size": Vector3(u * 0.28, u * 0.22, u * 0.28), "color": petal.lightened(0.08)},
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
		"tree":
			var trunk_h := u * (2.8 + growth * 2.2)
			var canopy_r := u * (2.4 + growth * 2.6)
			return [
				{"center": Vector3(0, trunk_h * 0.5, 0), "size": Vector3(u * 1.0, trunk_h, u * 1.0), "color": Color(0.42, 0.28, 0.18)},
				{"center": Vector3(0, trunk_h + canopy_r * 0.42, 0), "size": Vector3(canopy_r * 2.4, canopy_r * 1.7, canopy_r * 2.4), "color": Color(0.22, 0.52, 0.26)},
				{"center": Vector3(0, trunk_h + canopy_r * 0.92, 0), "size": Vector3(canopy_r * 1.6, canopy_r * 1.2, canopy_r * 1.6), "color": Color(0.32, 0.7, 0.34)},
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