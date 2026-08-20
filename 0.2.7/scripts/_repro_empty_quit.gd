extends SceneTree
func _init():
	call_deferred("_go")
func _go():
	print("[REPRO] empty tree quit")
	quit(0)
