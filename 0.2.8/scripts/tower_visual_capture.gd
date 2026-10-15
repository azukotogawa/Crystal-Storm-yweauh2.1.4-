extends SceneTree

const _Studio = preload("res://scripts/structure_visual_studio.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _Studio.capture(self, "tower")
