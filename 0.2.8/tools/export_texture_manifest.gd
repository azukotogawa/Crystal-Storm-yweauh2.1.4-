extends SceneTree

const _Manifest = preload("res://tools/texture_manifest.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var doc: Dictionary = _Manifest.write_project()
	print("slots=%d art=%d missing=%d placeholder=%d" % [
		int(doc.get("slot_count", 0)),
		int(doc.get("art_count", 0)),
		int(doc.get("missing_count", 0)),
		int(doc.get("placeholder_count", 0)),
	])
	print("All texture manifest export OK")
	quit(0)
