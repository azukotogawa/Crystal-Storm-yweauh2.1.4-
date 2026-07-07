extends Control

const _GameManager = preload("res://game/game_manager.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/VBox/Title
@onready var _subtitle: Label = $Panel/VBox/Subtitle
@onready var _phase_label: Label = $PhaseLabel

var _game_manager: Node


func _ready() -> void:
	_panel.visible = false
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	if _game_manager:
		_game_manager.phase_changed.connect(_on_phase_changed)
		_game_manager.run_state_changed.connect(_on_run_state_changed)
		_on_phase_changed(_game_manager.phase)
	_update_map_temp_label()


func _update_map_temp_label() -> void:
	var world = get_tree().get_first_node_in_group("world")
	var temp_label := ""
	if world and "map_temperature_label" in world:
		temp_label = " | %s map" % world.map_temperature_label
	if _game_manager and _game_manager.phase == _GameManager.Phase.MAZE:
		_phase_label.text = "Phase: Maze — build routes, gather power%s" % temp_label
	else:
		_phase_label.text = "Phase: Assault — push back to the origin%s" % temp_label


func _process(_delta: float) -> void:
	if _game_manager == null:
		_game_manager = get_tree().get_first_node_in_group("game_manager")
		return
	if Input.is_action_just_pressed("interact") and _panel.visible:
		if _game_manager.has_method("restart_run"):
			_game_manager.restart_run()


func _on_phase_changed(_new_phase: int) -> void:
	_update_map_temp_label()


func _on_run_state_changed(new_state: int) -> void:
	_panel.visible = true
	if new_state == _GameManager.RunState.WON:
		_title.text = "Crystal Destroyed"
		_subtitle.text = "You reached the source and shattered every spawn.\nPress R to restart."
	elif new_state == _GameManager.RunState.LOST:
		_title.text = "Run Over"
		_subtitle.text = "The corruption won this time.\nPress R to restart."