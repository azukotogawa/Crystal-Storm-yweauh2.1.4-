extends SceneTree
func _init() -> void:
	var s = load("res://scripts/profile_crystal_stress_release.gd")
	print("PROBE_LOAD ok=%s" % str(s != null))
	quit(0 if s != null else 1)