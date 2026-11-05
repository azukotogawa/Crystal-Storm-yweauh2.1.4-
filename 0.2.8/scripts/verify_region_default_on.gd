extends SceneTree
func _init() -> void:
	var RP = load("res://world/region_pack.gd")
	var a = RP.enabled()
	OS.set_environment("CRYSTALSTORM_BAKE_REGION", "0")
	var b = RP.enabled()
	OS.set_environment("CRYSTALSTORM_BAKE_REGION", "1")
	var c = RP.enabled()
	OS.set_environment("CRYSTALSTORM_BAKE_REGION", "")
	var d = RP.enabled()
	print("REGION_DEFAULT_PROOF default_before_set=%s after_0=%s after_1=%s after_empty=%s" % [str(a), str(b), str(c), str(d)])
	var ok = (a == true and b == false and c == true and d == true)
	print("REGION_DEFAULT_PROOF ok=%s" % str(ok))
	quit(0 if ok else 1)