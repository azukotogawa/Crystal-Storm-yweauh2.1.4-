class_name ContactShadow
extends RefCounted
## One pooled ground quad per host. No shadow maps and no per-frame work.

const GROUP := "contact_shadow"
const _BLOB_SIZE := 32

static var enabled: bool = true
static var _quad: QuadMesh
static var _material: StandardMaterial3D
static var _blob: Texture2D


static func attach(host: Node3D, y: float, diameter: float) -> MeshInstance3D:
	if host == null or not is_instance_valid(host):
		return null
	var existing := host.get_node_or_null("ContactShadow") as MeshInstance3D
	if not enabled:
		if existing:
			existing.visible = false
		return null
	var inst := existing
	if inst == null:
		inst = MeshInstance3D.new()
		inst.name = "ContactShadow"
		inst.mesh = _shared_quad()
		inst.material_override = _shared_material()
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# QuadMesh faces +Z. Tip it onto the ground.
		inst.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		host.add_child(inst)
		if not inst.is_in_group(GROUP):
			inst.add_to_group(GROUP)
	inst.visible = true
	inst.position = Vector3(0.0, y, 0.0)
	inst.scale = Vector3(maxf(diameter, 0.05), maxf(diameter, 0.05), 1.0)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


static func set_globally_enabled(on: bool) -> void:
	enabled = on
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if not on:
		for node in tree.get_nodes_in_group(GROUP):
			if node is Node3D:
				(node as Node3D).visible = false
		return
	for group_name in ["player", "world_entity", "crystal_enemy", "world_item"]:
		for node in tree.get_nodes_in_group(group_name):
			if not (node is Node3D):
				continue
			var host := node as Node3D
			var existing := host.get_node_or_null("ContactShadow") as MeshInstance3D
			if existing:
				existing.visible = true
			else:
				attach(host, _y_for(host), _diameter_for(host))


static func _y_for(host: Node3D) -> float:
	if host != null and host.is_in_group("player"):
		return 0.05
	return 0.06


static func _diameter_for(host: Node3D) -> float:
	if host != null and host.is_in_group("player"):
		return 1.6
	if host != null and host.is_in_group("world_item"):
		return 0.9
	return 1.2


static func _shared_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1.0, 1.0)
	return _quad


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
		mat.albedo_texture = _blob_texture()
		_material = mat
	return _material


static func _blob_texture() -> Texture2D:
	if _blob != null:
		return _blob
	var img := Image.create(_BLOB_SIZE, _BLOB_SIZE, false, Image.FORMAT_RGBA8)
	var center := float(_BLOB_SIZE - 1) * 0.5
	var radius := float(_BLOB_SIZE) * 0.5
	for y in _BLOB_SIZE:
		for x in _BLOB_SIZE:
			var d := Vector2(float(x) - center, float(y) - center).length() / radius
			var t := clampf((d - 0.35) / 0.65, 0.0, 1.0)
			var s := t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 - s))
	_blob = ImageTexture.create_from_image(img)
	_blob.resource_name = "contact_shadow_blob"
	return _blob
