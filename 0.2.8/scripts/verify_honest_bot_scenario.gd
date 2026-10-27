extends SceneTree

const _Run = preload("res://scripts/honest_bot/honest_scenario.gd")
const _Exit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	Engine.physics_jitter_fix = 0.0
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	var name := OS.get_environment("CRYSTALSTORM_SCENARIO").strip_edges()
	if name == "":
		name = "dig"
	var pace_env := OS.get_environment("CRYSTALSTORM_CONTENT_PACE").strip_edges()
	if pace_env.is_valid_float():
		GameFeelConfig.pace_override = pace_env.to_float()
		print("HARNESS content_pace override %.2f" % GameFeelConfig.pace_override)
	var run = _Run.new()
	var code: int = await run.play(self, name)
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if code == 0:
		_Exit.finish_tree(self, 0, "HARNESS SCENARIO OK %s" % name)
		return
	_Exit.finish_tree(self, 1, "HARNESS SCENARIO FAIL %s" % name)
