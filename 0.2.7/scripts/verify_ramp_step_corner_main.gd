extends SceneTree
## Regression: production player floor probe walks L-shaped step corners (synthetic chunk).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _SmokeProbeHelpers = preload("res://scripts/smoke_probe_helpers.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Ramp step-corner main FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	for _attempt in 600:
		player = get_first_node_in_group("player")
		if player != null and bool(player.get("world_ready")):
			break
		await process_frame

	if player == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Ramp step-corner main FAILED")
		return

	for _w in 60:
		await process_frame

	var floor_probe = player.get("_floor_probe")
	if floor_probe == null:
		push_error("player floor probe missing")
		_ProbeExit.finish_tree(self, 1, "Ramp step-corner main FAILED")
		return

	var player_src := (load("res://player/player.gd") as GDScript).source_code
	if "_try_move_delta" not in player_src:
		push_error("player must use corner-slip guard for ramp walk parity")
		failed = true
	else:
		print("OK player corner-slip guard present")

	var audit: Dictionary = _SmokeProbeHelpers.audit_ramp_step_corner_walk(floor_probe)
	if not audit.get("ok", false):
		push_error("step-corner audit: %s" % audit.get("reason", "?"))
		failed = true
	else:
		print(
			"OK main step-corner walk feet=%.2f center=%.2f steps=%d"
			% [audit.get("corner_feet", 0.0), audit.get("center_h", 0.0), audit.get("steps", 0)]
		)

	if failed:
		_ProbeExit.finish_tree(self, 1, "Ramp step-corner main FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All ramp step-corner main tests OK")