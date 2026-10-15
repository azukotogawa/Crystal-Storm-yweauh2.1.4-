extends RefCounted


static func finish_tree(tree: SceneTree, exit_code: int, marker: String) -> void:
	print(marker)
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT") == "1":
		OS.kill(OS.get_process_id())
		return
	tree.quit(exit_code)