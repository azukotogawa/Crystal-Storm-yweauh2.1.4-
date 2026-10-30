class_name DevCommandGate
extends RefCounted


static func allowed() -> bool:
	var path := ""
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		path = str(loop.get_script().resource_path)
	return allowed_for(path, OS.is_debug_build(), env_blocks())


static func env_blocks() -> bool:
	if OS.get_environment("CRYSTALSTORM_DEV_COMMANDS") == "0":
		return true
	if OS.get_environment("CRYSTALSTORM_SHOWCASE") == "1":
		return true
	if OS.get_environment("CRYSTALSTORM_HARNESS") == "1":
		return true
	return false


static func allowed_for(script_path: String, debug_build: bool, blocked_env: bool) -> bool:
	if blocked_env or not debug_build:
		return false
	var base := script_path.get_file()
	if base == "verify_honest_bot_showcase.gd":
		return false
	if base == "verify_honest_bot_scenario.gd":
		return false
	return true
