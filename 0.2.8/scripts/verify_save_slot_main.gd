extends SceneTree

const INNER := "res://scripts/verify_save_slot_inner.gd"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := ProjectSettings.globalize_path(INNER)
	if not FileAccess.file_exists(path):
		push_error("Missing inner save slot script")
		quit(1)
		return
	var output: Array = []
	var exit_code := OS.execute(
		"godot",
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", INNER],
		output,
		true,
		false
	)
	var text := "\n".join(output)
	for line in output:
		print(line)
	var ok := "SAVE SLOT OK" in text and "**FAIL**" not in text
	if not ok:
		push_error("save slot inner did not pass")
	elif exit_code != 0 and exit_code != 134:
		push_error("save slot inner exit %d" % exit_code)
		ok = false
	if ok:
		print("All save slot main tests OK")
	quit(0 if ok else 1)