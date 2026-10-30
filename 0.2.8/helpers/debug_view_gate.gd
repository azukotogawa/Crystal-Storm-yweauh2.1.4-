class_name DebugViewGate
extends RefCounted

const ENV := "CRYSTALSTORM_DEV_VIEWS"
const VIEWS: Array[String] = [
	"chunk_borders",
	"crystal_frontier",
	"collision",
	"perf_overlay",
]

static var _player_build_override: bool = false


static func reset_player_build_override() -> void:
	_player_build_override = false


static func force_player_build(on: bool) -> void:
	_player_build_override = on


static func is_player_build() -> bool:
	if not OS.is_debug_build():
		return true
	if OS.has_feature("release"):
		return true
	return _player_build_override


static func dev_flag_on() -> bool:
	return dev_flag_on_for(is_player_build(), OS.get_environment(ENV))


static func dev_flag_on_for(player_build: bool, env_value: String) -> bool:
	if player_build:
		return false
	var raw := env_value.strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on"
