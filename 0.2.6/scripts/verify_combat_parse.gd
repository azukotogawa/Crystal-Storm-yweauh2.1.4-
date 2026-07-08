extends SceneTree

func _init() -> void:
	var paths := [
		"res://systems/combat_hit_resolver.gd",
		"res://systems/combat_log.gd",
		"res://config/combat_def.gd",
		"res://crystal/spawn_point_controller.gd",
		"res://config/spawn_point_def.gd",
		"res://config/spawn_point_registry.gd",
		"res://crystal/crystal_spawn_point.gd",
		"res://crystal/crystal_manager.gd",
		"res://game/game_manager.gd",
		"res://ui/game_overlay.gd",
		"res://systems/topographical_map_builder.gd",
		"res://weapons/weapon_controller.gd",
		"res://entities/world_entity.gd",
		"res://entities/crystal_enemy.gd",
		"res://ui/debug_panel.gd",
		"res://config/performance_quality_config.gd",
		"res://config/game_config.gd",
		"res://systems/performance_service.gd",
		"res://systems/combat_visual_feedback.gd",
		"res://systems/config_service.gd",
		"res://systems/config_json_io.gd",
	]
	var failed := false
	for path in paths:
		var scr: GDScript = load(path) as GDScript
		if scr == null:
			push_error("FAIL load " + path)
			failed = true
			continue
		var err := scr.reload()
		if err != OK:
			push_error("FAIL compile %s err=%s" % [path, err])
			failed = true
		else:
			print("OK ", path)
	if failed:
		quit(1)
	else:
		print("All combat scripts parsed OK")
		quit(0)