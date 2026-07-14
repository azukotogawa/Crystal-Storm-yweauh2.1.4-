extends SceneTree
## P1 regression: spawn marker textures have crystal core + ring; voxel vegetation scale baseline.


const _VoxelPropBuilder = preload("res://helpers/voxel_prop_builder.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _GeneratorScript = preload("res://systems/crystal_texture_generator.gd")


func _init() -> void:
	var failed := false
	var gen := _GeneratorScript.new()

	for boss in [false, true]:
		var variant := &"spawn_boss" if boss else &"spawn_miniboss"
		var tex: Texture2D = gen.generate_texture(_GeneratorScript.Category.PARTICLE, variant, 48 if boss else 32)
		if tex == null:
			push_error("%s texture generation failed" % variant)
			failed = true
			continue
		var stats := _alpha_stats(tex.get_image())
		if stats.core_alpha < 0.35:
			push_error("%s missing opaque core (%.2f)" % [variant, stats.core_alpha])
			failed = true
		elif stats.ring_alpha < 0.25:
			push_error("%s missing ring halo (%.2f)" % [variant, stats.ring_alpha])
			failed = true
		else:
			print("OK %s core=%.2f ring=%.2f" % [variant, stats.core_alpha, stats.ring_alpha])

	var unit := _VoxelPropBuilder.unit()
	var vs: float = _WorldSettings.get_active().voxel_scale
	var min_unit := vs * 0.8
	if unit < min_unit:
		push_error("voxel prop unit too small: %.3f < %.3f" % [unit, min_unit])
		failed = true
	else:
		print("OK voxel prop unit=%.3f (vs=%.2f)" % [unit, vs])

	var tree := _VoxelPropBuilder.build_plant("tree", 2)
	var tree_h := _VoxelPropBuilder.model_height(tree)
	var min_tree_h := vs * 3.2
	if tree_h < min_tree_h:
		push_error("tree voxel prop too short: %.2f < %.2f" % [tree_h, min_tree_h])
		failed = true
	else:
		print("OK tree voxel height=%.2f" % tree_h)

	var grass := _VoxelPropBuilder.build_plant("grass_tuft", 2)
	if grass.get_child_count() < 3:
		push_error("grass_tuft must use multi-blade voxel prop")
		failed = true
	else:
		print("OK grass_tuft blades=%d" % grass.get_child_count())

	if failed:
		quit(1)
	print("All spawn marker visual tests OK")
	quit(0)


func _alpha_stats(image: Image) -> Dictionary:
	var dim := image.get_width()
	var cx := dim / 2
	var cy := dim / 2
	var core_sum := 0.0
	var core_n := 0
	var ring_sum := 0.0
	var ring_n := 0
	for y in dim:
		for x in dim:
			var dx := float(x - cx) / float(dim)
			var dy := float(y - cy) / float(dim)
			var d := Vector2(dx, dy).length()
			var a := image.get_pixel(x, y).a
			if d < 0.12:
				core_sum += a
				core_n += 1
			elif absf(d - 0.3) < 0.07:
				ring_sum += a
				ring_n += 1
	return {
		"core_alpha": core_sum / float(maxi(core_n, 1)),
		"ring_alpha": ring_sum / float(maxi(ring_n, 1)),
	}