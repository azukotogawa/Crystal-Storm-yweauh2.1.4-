extends SceneTree
## Regression: inventory items have procedural voxel icons in visual bundle.


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var gen_scr = load("res://systems/crystal_texture_generator.gd")
	var gen = gen_scr.new()
	var bundle: Dictionary = gen.generate_game_visual_bundle()
	for item_id in ["wooden_sword", "stone_pick", "shortbow", "wood", "stone", "herb"]:
		var key := "item_%s" % item_id
		var tex: Texture2D = bundle.get(key)
		if tex == null:
			push_error("missing bundle key %s" % key)
			failed = true
			continue
		if tex.get_width() < 16 or tex.get_height() < 16:
			push_error("item icon too small for %s" % item_id)
			failed = true
			continue
		print("OK item icon %s %dx%d" % [item_id, tex.get_width(), tex.get_height()])

	var reg_scr = load("res://systems/game_visual_registry.gd")
	var reg = reg_scr.new()
	reg.generate_game_visual_bundle()
	var pick: Texture2D = reg.get_item_texture("stone_pick")
	if pick == null:
		push_error("registry get_item_texture failed")
		failed = true
	else:
		print("OK registry get_item_texture stone_pick")

	var hotbar_src := (load("res://ui/hotbar.gd") as GDScript).source_code
	if "get_item_texture" not in hotbar_src:
		push_error("hotbar must bind item textures")
		failed = true
	else:
		print("OK hotbar item texture binding")

	if failed:
		quit(1)
	print("All item icon tests OK")
	quit(0)