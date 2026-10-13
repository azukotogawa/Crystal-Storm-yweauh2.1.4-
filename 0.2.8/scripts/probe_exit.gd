extends RefCounted
## Harness-only exit: SIGKILL self to skip SceneTree teardown abort(134) after OK markers.


static func finish_tree(tree: SceneTree, exit_code: int, marker: String) -> void:
	print(marker)
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT") == "1":
		# Wrapper matches marker text, not process exit code (kill → 137).
		OS.kill(OS.get_process_id())
		return
	tree.quit(exit_code)