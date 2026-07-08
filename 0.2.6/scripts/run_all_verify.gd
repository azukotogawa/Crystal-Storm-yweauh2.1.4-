extends SceneTree
## Run the full headless verification suite (delegates to run_all_verify.sh for reliable exit codes).
## Usage: godot --headless -s scripts/run_all_verify.gd
## Or directly: bash scripts/run_all_verify.sh

const SHELL_SCRIPT := "res://scripts/run_all_verify.sh"


func _init() -> void:
	var script_path := ProjectSettings.globalize_path(SHELL_SCRIPT)
	if not FileAccess.file_exists(script_path):
		push_error("Missing %s" % SHELL_SCRIPT)
		quit(1)
	var output: Array = []
	var exit_code := OS.execute("bash", [script_path], output, true, false)
	for line in output:
		print(line)
	quit(exit_code)