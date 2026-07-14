class_name BugReporter
extends RefCounted

const MANIFEST_NAME := "manifest.json"
const STATE_NAME := "state.json"
const SCREENSHOT_NAME := "screenshot.png"


static func capture(tree: SceneTree, try_screenshot: bool = true) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
	var rel_dir := "user://bug_reports/%s" % stamp
	var abs_dir := ProjectSettings.globalize_path(rel_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var state: Dictionary = _collect_state(tree)
	var state_path := rel_dir.path_join(STATE_NAME)
	var state_abs := abs_dir.path_join(STATE_NAME)
	var state_file := FileAccess.open(state_path, FileAccess.WRITE)
	if state_file:
		state_file.store_string(JSON.stringify(state, "\t"))
		state_file.close()

	var screenshot_rel := ""
	var screenshot_ok := false
	if try_screenshot:
		screenshot_rel = rel_dir.path_join(SCREENSHOT_NAME)
		screenshot_ok = _capture_screenshot(tree, screenshot_rel)

	var manifest := {
		"timestamp": stamp,
		"state_file": STATE_NAME,
		"screenshot_file": SCREENSHOT_NAME if screenshot_ok else "",
		"screenshot_captured": screenshot_ok,
		"godot_version": Engine.get_version_info(),
	}
	var manifest_path := rel_dir.path_join(MANIFEST_NAME)
	var manifest_file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest_file:
		manifest_file.store_string(JSON.stringify(manifest, "\t"))
		manifest_file.close()

	return {
		"dir": abs_dir,
		"rel_dir": rel_dir,
		"state_path": state_abs,
		"manifest_path": ProjectSettings.globalize_path(manifest_path),
		"screenshot_ok": screenshot_ok,
	}


static func _collect_state(tree: SceneTree) -> Dictionary:
	var out := {
		"scene": "main",
		"fps": Engine.get_frames_per_second(),
		"frame": Engine.get_process_frames(),
		"time_msec": Time.get_ticks_msec(),
		"perf_preset_env": OS.get_environment("CRYSTALSTORM_PERF_PRESET"),
	}
	var player: Node = tree.get_first_node_in_group("player")
	if player:
		if "voxel_position" in player:
			out["player_voxel"] = var_to_str(player.voxel_position)
		if "health" in player:
			out["player_health"] = player.health
	var world: Node = tree.get_first_node_in_group("world")
	if world and "world_seed" in world:
		out["world_seed"] = world.world_seed
	var chunk_manager: ChunkManager = tree.get_first_node_in_group("chunk_manager") as ChunkManager
	if chunk_manager and "chunks" in chunk_manager:
		out["chunks_loaded"] = chunk_manager.chunks.size()
	var crystal: Node = tree.get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("get_debug_stats"):
		out["crystal"] = crystal.get_debug_stats()
	var perf = tree.get_first_node_in_group("performance_service")
	if perf and "quality" in perf and perf.quality:
		out["perf_preset_id"] = int(perf.quality.preset)
	var errors: PackedStringArray = []
	if Engine.has_method("get_error_count"):
		pass
	out["recent_log_hint"] = "See Godot Output for full stack"
	return out


static func _capture_screenshot(tree: SceneTree, rel_path: String) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var root: Window = tree.root
	if root == null:
		return false
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return false
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return false
	return img.save_png(ProjectSettings.globalize_path(rel_path)) == OK