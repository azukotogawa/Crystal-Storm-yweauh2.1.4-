extends SceneTree

const _Look = preload("res://config/crystal_ground_look.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _Types = preload("res://helpers/crystal_types.gd")
const _Marks = preload("res://world/distant_landmarks.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var look: Resource = _Look.load_active()
	if look == null:
		push_error("crystal ground look did not load")
		quit(1)
		return
	var energy := float(look.emission_energy)
	if energy <= 0.0 or energy >= 1.0:
		push_error("crystal ground emission %.3f is still a flat glare" % energy)
		failed = true
	else:
		print("OK crystal ground emission %.2f" % energy)
	if bool(look.show_debug_markers):
		push_error("debug markers default on")
		failed = true
	else:
		print("OK debug markers default off")

	var shader := load("res://shaders/crystal_pulse.gdshader") as Shader
	var src := "" if shader == null else shader.code
	if shader == null or "cs_sample_atlas" not in src or "texture_atlas" not in src or "albedo_tex" in src:
		push_error("crystal mass shader does not sample the biome atlas")
		failed = true
	else:
		print("OK crystal mass samples the biome atlas")

	var crystal := _CrystalManager.new()
	crystal.name = "CrystalManager"
	crystal.cancel_bootstrap()
	crystal.set_process(false)
	root.add_child(crystal)
	await process_frame
	var mat := crystal._crystal_material as ShaderMaterial
	if mat == null:
		push_error("crystal mass material missing")
		quit(1)
		return
	var bound := float(mat.get_shader_parameter("emission_energy"))
	if absf(bound - energy) > 0.001:
		push_error("mass emission %.3f != look %.3f" % [bound, energy])
		failed = true
	var atlas: Texture2D = mat.get_shader_parameter("texture_atlas")
	if atlas == null:
		push_error("mass material has no atlas")
		failed = true
	else:
		print("OK mass atlas %s" % atlas.resource_path)
	var cell: Vector2 = mat.get_shader_parameter("ground_cell")
	if int(cell.x) != int(look.ground_col) or int(cell.y) != int(look.ground_row):
		push_error("ground cell %s != %d,%d" % [cell, look.ground_col, look.ground_row])
		failed = true
	else:
		print("OK ground cell %d,%d" % [int(cell.x), int(cell.y)])

	var layer := crystal._make_chunk_layer(Vector2i.ZERO)
	var mass := _CrystalCell.new(Vector2i(4, 4), 0.0, 2.4, 1)
	mass.neighbor_mask = 15
	layer.rebuild([mass])
	var mesh := layer.get_node_or_null("CrystalFluid") as MultiMeshInstance3D
	if mesh == null or mesh.material_override != mat:
		push_error("drawn crystal ground is not the atlas material")
		failed = true
	else:
		print("OK drawn crystal ground uses the atlas material")

	var spire := _Marks.build_visual("rock_spire")
	var textured := 0
	var bare := 0
	for child in spire.get_children():
		if not (child is MeshInstance3D):
			continue
		var sm := (child as MeshInstance3D).material_override as StandardMaterial3D
		if sm == null or not (sm.albedo_texture is AtlasTexture):
			bare += 1
		else:
			textured += 1
			var region := (sm.albedo_texture as AtlasTexture).region
			var expect_x := float(look.stone_col) * region.size.x
			var expect_y := float(look.stone_row) * region.size.y
			if absf(region.position.x - expect_x) > 0.5 or absf(region.position.y - expect_y) > 0.5:
				push_error("spire cell %s is not stone %d,%d" % [region, look.stone_col, look.stone_row])
				failed = true
	if textured < 1 or bare > 0:
		push_error("rock spire textured %d bare %d" % [textured, bare])
		failed = true
	else:
		print("OK rock spire atlas cells %d" % textured)
	spire.free()

	var spawn := _Spawn.new(1, Vector2i(6, 8), _Types.SpawnKind.RUIN, 100.0, false)
	crystal._spawn_points.append(spawn)
	crystal._refresh_spawn_markers()
	var anchor: Node3D = crystal._spawn_markers.get(1) as Node3D
	if anchor == null:
		push_error("spawn anchor missing")
		failed = true
	elif anchor.get_node_or_null("FallbackPrism") != null:
		push_error("pink debug cube is visible with markers off")
		failed = true
	else:
		var sprite := anchor.get_node_or_null("Sprite") as Sprite3D
		if sprite == null or sprite.texture == null:
			push_error("spawn marker has no crystal texture")
			failed = true
		else:
			print("OK spawn marker uses %s and hides the debug cube" % sprite.texture.resource_path)

	crystal.free()
	if failed:
		quit(1)
		return
	print("All crystal ground look tests OK")
	quit(0)
