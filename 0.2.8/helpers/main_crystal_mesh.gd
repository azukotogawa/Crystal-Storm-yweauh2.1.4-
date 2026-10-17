class_name MainCrystalMesh
extends RefCounted

const _Look = preload("res://config/main_crystal_look.gd")


static func attach(anchor: Node3D, marker_size: float, colorblind: bool) -> Node3D:
	var look := _Look.load_active()
	var root := Node3D.new()
	root.name = "HeartCrystal"
	var mat := _material(look, colorblind)
	root.set_meta("crystal_mat", mat)
	var scale := maxf(marker_size, 0.001)
	for i in look.shard_count():
		var shard := MeshInstance3D.new()
		shard.name = "Shard%d" % i
		var box := BoxMesh.new()
		box.size = look.shard_sizes[i] * scale
		shard.mesh = box
		shard.position = look.shard_centers[i] * scale
		shard.material_override = mat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shard)
	anchor.add_child(root)
	return root


static func repaint(root: Node3D, colorblind: bool) -> void:
	if root == null:
		return
	var mat := root.get_meta("crystal_mat", null) as StandardMaterial3D
	if mat == null:
		return
	_paint(mat, _Look.load_active(), colorblind)


static func _material(look: MainCrystalLook, colorblind: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	_paint(mat, look, colorblind)
	return mat


static func _paint(mat: StandardMaterial3D, look: MainCrystalLook, colorblind: bool) -> void:
	mat.albedo_color = look.albedo_color(colorblind)
	mat.emission = look.emission_color(colorblind)
	mat.emission_energy_multiplier = look.energy(colorblind)
	mat.roughness = look.roughness
