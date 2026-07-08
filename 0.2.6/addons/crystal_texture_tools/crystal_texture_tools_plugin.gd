@tool
extends EditorPlugin

const _DockScene = preload("res://addons/crystal_texture_tools/texture_gen_dock.tscn")

var _dock: Control


func _enter_tree() -> void:
	_dock = _DockScene.instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null