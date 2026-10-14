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
		"res://systems/juice.gd",
		"res://systems/vfx_pool.gd",
		"res://systems/item_anim.gd",
		"res://systems/held_item_view.gd",
		"res://systems/aim_indicator.gd",
		"res://systems/hit_markers.gd",
		"res://systems/block_break_fx.gd",
		"res://scripts/verify_item_animations.gd",
		"res://scripts/verify_block_break_place_fx.gd",
		"res://systems/audio_manager.gd",
		"res://systems/player_settings.gd",
		"res://config/audio_manifest.gd",
		"res://weapons/projectile.gd",
		"res://player/player.gd",
		"res://ui/pause_menu.gd",
		"res://ui/relic_choice_panel.gd",
		"res://systems/input_bindings.gd",
		"res://ui/crystal_palette.gd",
		"res://ui/theme/theme_builder.gd",
		"res://ui/tooltip_text.gd",
		"res://ui/tooltip_panel.gd",
		"res://ui/settings_menu.gd",
		"res://ui/tutorial_overlay.gd",
		"res://ui/run_summary_panel.gd",
		"res://ui/frontend_root.gd",
		"res://ui/hotbar.gd",
		"res://ui/inventory_panel.gd",
		"res://ui/slot_drag.gd",
		"res://scripts/verify_inventory_drag.gd",
		"res://scripts/verify_player_health_bar.gd",
		"res://scripts/verify_player_knockback.gd",
		"res://scripts/verify_full_map_toggle.gd",
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