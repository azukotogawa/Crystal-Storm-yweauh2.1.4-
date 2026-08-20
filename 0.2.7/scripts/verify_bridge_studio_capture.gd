extends SceneTree
## Isolated iso studio shot of the authored bridge mesh (no main-scene streaming).
## Usage: godot --path . -s scripts/verify_bridge_studio_capture.gd


const OUT := "C:/users/cwith/weed/crystalstorm/.tmp_bridge_capture/studio_bridge.png"
const MESH := "res://assets/structures/bridge/bridge.obj"
const ALBEDO := "res://assets/structures/bridge/bridge_albedo.png"
const WOOD := "res://assets/structures/wood_wall/wood_wall.obj"
const WOOD_ALBEDO := "res://assets/structures/wood_wall/wood_wall_albedo.png"
const GATE := "res://assets/structures/gate/gate.obj"
const GATE_ALBEDO := "res://assets/structures/gate/gate_albedo.png"

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("C:/users/cwith/weed/crystalstorm/.tmp_bridge_capture")
	var world := Node3D.new()
	world.name = "Studio"
	root.add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 45, 0)
	light.light_energy = 1.15
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -120, 0)
	fill.light_energy = 0.35
	world.add_child(fill)

	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8, 0.08, 8)
	ground.mesh = box
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.28, 0.32, 0.30)
	ground.material_override = gmat
	ground.position = Vector3(0, -0.04, 0)
	world.add_child(ground)

	_spawn(world, MESH, ALBEDO, Vector3(0, 0, 0), Vector3(2, 1.15, 2), Color(0.78, 0.88, 1.05))
	_spawn(world, WOOD, WOOD_ALBEDO, Vector3(-2.4, 0, 0), Vector3(2, 0.55, 2), Color(1.0, 0.92, 0.8))
	_spawn(world, GATE, GATE_ALBEDO, Vector3(2.6, 0, 0), Vector3(2, 1.0, 2), Color(1.08, 0.95, 0.72))

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 7.5
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	cam.position = Vector3(6.5, 6.6, 6.5)
	cam.current = true
	world.add_child(cam)

	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

	var vp := root.get_viewport()
	var img: Image = vp.get_texture().get_image() if vp and vp.get_texture() else null
	if img == null or img.is_empty():
		_failed += 1
		push_error("studio capture empty")
	else:
		img.save_png(OUT)
		print("SHOT %s %dx%d" % [OUT, img.get_width(), img.get_height()])
	if _failed == 0:
		print("BRIDGE STUDIO CAPTURE OK")
		quit(0)
	else:
		quit(1)


func _spawn(parent: Node3D, mesh_path: String, albedo_path: String, pos: Vector3, scale: Vector3, tint: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = load(mesh_path) as Mesh
	var tex: Texture2D = load(albedo_path) as Texture2D
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
	if mi.mesh == null:
		_failed += 1
		push_error("missing mesh %s" % mesh_path)
