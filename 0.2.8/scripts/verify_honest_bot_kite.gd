extends SceneTree

const _Fight = preload("res://scripts/honest_bot/honest_fight.gd")
const _Brain = preload("res://scripts/honest_bot/honest_brain.gd")
const _Exit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _sources_clean():
		_Exit.finish_tree(self, 1, "HONEST BOT KITE FAIL")
		return
	var fight = _Fight.new()
	var probe = preload("res://scripts/honest_bot/honest_kite_probe.gd").new()
	if not probe.run(fight):
		_Exit.finish_tree(self, 1, "HONEST BOT KITE FAIL")
		return
	if fight.brain == null or not (fight.brain is _Brain):
		print("FAIL kite brain missing")
		_Exit.finish_tree(self, 1, "HONEST BOT KITE FAIL")
		return
	_Exit.finish_tree(self, 0, "HONEST BOT KITE OK")


func _sources_clean() -> bool:
	var banned := ["voxel_position =", "global_position =", "take_damage", "add_xp", "grant_xp", "health ="]
	var paths := [
		"res://scripts/honest_bot/honest_brain.gd",
		"res://scripts/honest_bot/honest_fight.gd",
	]
	for path in paths:
		var body := FileAccess.get_file_as_string(path)
		for token in banned:
			if token in body:
				print("FAIL kite source %s contains %s" % [path, token])
				return false
	return true
