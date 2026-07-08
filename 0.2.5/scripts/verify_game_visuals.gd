extends SceneTree

func _init() -> void:
	var failed := false
	var paths := [
		"res://systems/crystal_texture_generator.gd",
		"res://systems/game_visual_registry.gd",
		"res://world/feature_visual_layer.gd",
		"res://systems/combat_visual_feedback.gd",
		"res://entities/world_entity.gd",
		"res://entities/crystal_enemy.gd",
	]
	for p in paths:
		var scr: GDScript = load(p) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL compile %s" % p)
			failed = true
		else:
			print("OK ", p)

	var gen = load("res://systems/crystal_texture_generator.gd").new()
	var tex = gen.generate_texture(gen.Category.ENTITY, &"rabbit", 48)
	if tex == null or tex.get_width() < 16:
		push_error("entity texture generation failed")
		failed = true
	else:
		print("OK entity rabbit texture ", tex.get_width(), "x", tex.get_height())

	var veg = gen.generate_texture(gen.Category.VEGETATION, &"tree_s2", 40)
	if veg == null:
		push_error("vegetation texture failed")
		failed = true
	else:
		print("OK vegetation tree_s2")

	var bundle: Dictionary = gen.generate_game_visual_bundle()
	if bundle.size() < 20:
		push_error("game visual bundle too small: %d" % bundle.size())
		failed = true
	else:
		print("OK game visual bundle keys=", bundle.size())

	var reg_scr = load("res://systems/game_visual_registry.gd")
	var reg = reg_scr.new()
	var required_methods := [
		"generate_game_visual_bundle",
		"refresh_all",
		"get_sprite_texture",
		"get_billboard_texture",
		"apply_to_sprite3d",
		"configure_building_mesh",
		"is_ready",
	]
	for method_name in required_methods:
		if not reg.has_method(method_name):
			push_error("GameVisualRegistry missing method: %s" % method_name)
			failed = true
	if not failed:
		print("OK registry public API methods")
	var bundle_reg: Dictionary = reg.generate_game_visual_bundle()
	if bundle_reg.size() < 20:
		push_error("registry generate_game_visual_bundle too small: %d" % bundle_reg.size())
		failed = true
	else:
		print("OK registry bundle keys=", bundle_reg.size())
	reg.refresh_all()
	var veg_tex = reg.get_vegetation_texture(&"tree", 2)
	if veg_tex == null:
		push_error("vegetation cache key mismatch for tree_s2")
		failed = true
	else:
		print("OK vegetation tree_s2 via registry")

	var sprite_tex = reg.get_sprite_texture("rabbit")
	if sprite_tex == null:
		push_error("get_sprite_texture(rabbit) failed")
		failed = true
	else:
		print("OK get_sprite_texture rabbit")

	var billboard_tex = reg.get_billboard_texture("tree_s2")
	if billboard_tex == null:
		push_error("get_billboard_texture(tree_s2) failed")
		failed = true
	else:
		print("OK get_billboard_texture tree_s2")

	var probe_sprite := Sprite3D.new()
	reg.configure_sprite3d(probe_sprite, tex, Color(0.8, 0.7, 0.6), 0.01)
	if probe_sprite.texture == null:
		push_error("configure_sprite3d should keep sprite texture")
		failed = true
	elif not probe_sprite.material_override is StandardMaterial3D:
		push_error("configure_sprite3d should assign billboard material")
		failed = true
	else:
		var bmat := probe_sprite.material_override as StandardMaterial3D
		if bmat.albedo_texture == null:
			push_error("billboard material missing albedo_texture")
			failed = true
		else:
			print("OK configure_sprite3d billboard material")
	probe_sprite.free()

	var wvc = load("res://helpers/world_visual_coords.gd")
	var ws = load("res://config/world_settings.gd").get_active()
	var p: Vector3 = wvc.column_to_world_pos(4.5, 10.0, 6.5)
	if not is_equal_approx(p.x, 4.5 * ws.voxel_scale):
		push_error("column_to_world_pos X mismatch")
		failed = true
	else:
		print("OK column_to_world_pos scale=", ws.voxel_scale)

	var med = load("res://config/performance_quality_config.gd").apply_preset(1)
	if not med.entity_sprites_enabled or not med.feature_billboards_enabled:
		push_error("MEDIUM should enable entity sprites and billboards")
		failed = true
	else:
		print("OK MEDIUM visuals enabled")

	var low = load("res://config/performance_quality_config.gd").apply_preset(0)
	if low.feature_billboards_enabled or low.combat_visuals_enabled:
		push_error("LOW should disable billboards and combat VFX")
		failed = true
	elif not low.entity_sprites_enabled or low.animals_per_biome_chunk <= 0:
		push_error("LOW should keep entity sprites with minimal spawns")
		failed = true
	else:
		print("OK LOW visuals throttled")

	reg.apply_performance_config(low)
	if reg.get_billboard_texture("tree_s2") != null:
		push_error("LOW preset should disable billboard textures")
		failed = true
	elif reg.get_sprite_texture("rabbit") == null:
		push_error("LOW preset should keep entity sprites")
		failed = true
	else:
		print("OK preset gates sprite vs billboard lookups")
	reg.apply_performance_config(med)

	if failed:
		quit(1)
	print("All game visual tests OK")
	quit(0)