extends RefCounted

const _Settings = preload("res://config/world_settings.gd")

const STONE_MESH := "res://assets/structures/stone_wall/stone_wall.obj"
const STONE_ALBEDO := "res://assets/structures/stone_wall/stone_wall_albedo.png"
const GATE_MESH := "res://assets/structures/gate/gate.obj"
const GATE_ALBEDO := "res://assets/structures/gate/gate_albedo.png"
const TOWER_MESH := "res://assets/structures/ruin_pillar/ruin_pillar.obj"
const TOWER_ALBEDO := "res://assets/structures/ruin_pillar/ruin_pillar_albedo.png"


static func capture(tree: SceneTree, piece: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("%s visual capture needs a window" % piece)
		tree.quit(1)
		return
	var folder := OS.get_environment("CRYSTALSTORM_STRUCTURE_DIR").strip_edges()
	if folder.is_empty():
		folder = "D:/csmerge/verify-evidence/structures"
	DirAccess.make_dir_recursive_absolute(folder)
	DisplayServer.window_set_title("Crystal Storm %s" % piece)
	DisplayServer.window_set_size(Vector2i(960, 540))
	var world := Node3D.new()
	world.name = "Studio"
	tree.root.add_child(world)
	_lights(world)
	_ground(world)
	if not _layout(world, piece):
		tree.quit(1)
		return
	var vs: float = _Settings.get_active().voxel_scale
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = vs * 6.0
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	cam.position = Vector3(vs * 4.0, vs * 3.6, vs * 4.0)
	cam.current = true
	world.add_child(cam)
	for _i in 8:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var vp := tree.root.get_viewport()
	var img: Image = vp.get_texture().get_image() if vp and vp.get_texture() else null
	var path := "%s/%s.png" % [folder, piece]
	if img == null or img.is_empty() or img.get_width() < 8:
		push_error("%s visual capture empty" % piece)
		tree.quit(1)
		return
	if img.save_png(path) != OK:
		push_error("%s visual capture save failed" % piece)
		tree.quit(1)
		return
	print("SHOT %s %dx%d" % [path, img.get_width(), img.get_height()])
	print("%s VISUAL CAPTURE OK" % piece)
	tree.quit(0)


static func _lights(world: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 45, 0)
	key.light_energy = 1.15
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.35
	world.add_child(fill)


static func _ground(world: Node3D) -> void:
	var vs: float = _Settings.get_active().voxel_scale
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(vs * 8.0, 0.08, vs * 8.0)
	ground.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.34, 0.28)
	ground.material_override = mat
	ground.position = Vector3(0, -0.04, 0)
	world.add_child(ground)


static func _layout(world: Node3D, piece: String) -> bool:
	var vs: float = _Settings.get_active().voxel_scale
	var stone := Vector3(vs, 0.68, vs)
	var gate := Vector3(vs, 1.0, vs)
	var pillar := Vector3(vs, 1.0, vs)
	if piece == "wall_segment":
		for x in 3:
			if not _spawn(world, STONE_MESH, STONE_ALBEDO, Vector3((float(x) - 1.0) * vs, 0.0, 0.0), stone, Color(0.95, 0.94, 0.92)):
				return false
			if not _spawn(world, STONE_MESH, STONE_ALBEDO, Vector3((float(x) - 1.0) * vs, vs * 0.55, 0.0), stone, Color(0.88, 0.87, 0.85)):
				return false
		return true
	if piece == "wall_corner":
		var cells := [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
		for cell in cells:
			var pos := Vector3((cell.x - 0.5) * vs, 0.0, (cell.y - 0.5) * vs)
			if not _spawn(world, STONE_MESH, STONE_ALBEDO, pos, stone, Color(0.95, 0.94, 0.92)):
				return false
			pos.y = vs * 0.55
			if not _spawn(world, STONE_MESH, STONE_ALBEDO, pos, stone, Color(0.88, 0.87, 0.85)):
				return false
		return true
	if piece == "gate":
		if not _spawn(world, STONE_MESH, STONE_ALBEDO, Vector3(-vs, 0.0, 0.0), stone, Color(0.95, 0.94, 0.92)):
			return false
		if not _spawn(world, GATE_MESH, GATE_ALBEDO, Vector3(0.0, 0.0, 0.0), gate, Color(1.08, 0.95, 0.72)):
			return false
		if not _spawn(world, STONE_MESH, STONE_ALBEDO, Vector3(vs, 0.0, 0.0), stone, Color(0.95, 0.94, 0.92)):
			return false
		return true
	if piece == "stairs":
		for x in 3:
			var pos := Vector3((float(x) - 1.0) * vs, float(x) * vs * 0.45, 0.0)
			if not _spawn(world, STONE_MESH, STONE_ALBEDO, pos, stone, Color(0.95, 0.94, 0.92)):
				return false
		return true
	if piece == "tower":
		for x in 2:
			for z in 2:
				var pos := Vector3((float(x) - 0.5) * vs, 0.0, (float(z) - 0.5) * vs)
				if not _spawn(world, TOWER_MESH, TOWER_ALBEDO, pos, pillar, Color(0.86, 0.84, 0.78)):
					return false
		return true
	push_error("unknown structure piece %s" % piece)
	return false


static func _spawn(parent: Node3D, mesh_path: String, albedo_path: String, pos: Vector3, scale: Vector3, tint: Color) -> bool:
	var mesh: Mesh = load(mesh_path) as Mesh
	var tex: Texture2D = load(albedo_path) as Texture2D
	if mesh == null or tex == null:
		push_error("missing authored asset %s" % mesh_path)
		return false
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.roughness = 0.82
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return true
