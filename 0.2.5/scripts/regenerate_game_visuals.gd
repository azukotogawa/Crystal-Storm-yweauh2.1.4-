extends SceneTree
## Headless exporter for procedural game visuals.
## Usage: godot --headless -s scripts/regenerate_game_visuals.gd
## Optional env: CRYSTALSTORM_VIS_EXPORT_DIR=user://generated_textures/game_visuals

func _init() -> void:
	var gen = load("res://systems/crystal_texture_generator.gd").new()
	var cfg = load("res://config/crystal_texture_gen_config.gd").create_default()
	gen.set_config(cfg)

	var export_dir := OS.get_environment("CRYSTALSTORM_VIS_EXPORT_DIR")
	if export_dir.is_empty():
		export_dir = "user://generated_textures/game_visuals"

	var path: String = gen.export_game_visual_bundle(export_dir)
	print("Exported game visual bundle to: ", path)
	print("Regenerate complete.")
	quit(0)