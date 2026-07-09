extends Control

const _GameManager = preload("res://game/game_manager.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/VBox/Title
@onready var _subtitle: Label = $Panel/VBox/Subtitle
@onready var _phase_label: Label = $PhaseLabel
@onready var _game_hud: Label = $GameHud

var _game_manager: Node
var _crystal: CrystalManager


func _ready() -> void:
	_panel.visible = false
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	if _game_manager:
		_game_manager.phase_changed.connect(_on_phase_changed)
		_game_manager.run_state_changed.connect(_on_run_state_changed)
		_on_phase_changed(_game_manager.phase)
	if _crystal and _crystal.has_signal("spawn_destroyed"):
		_crystal.spawn_destroyed.connect(_on_spawn_destroyed)
	_update_map_temp_label()


func _on_spawn_destroyed(_spawn) -> void:
	if _game_manager and _game_manager.run_state == _GameManager.RunState.PLAYING:
		_update_map_temp_label()


func _spawn_goal_line() -> String:
	if _crystal == null or not _crystal.has_method("get_spawn_progress"):
		return ""
	var prog: Dictionary = _crystal.get_spawn_progress()
	var active: int = int(prog.get("active", 0))
	var total: int = int(prog.get("total", 0))
	if total <= 0:
		return ""
	var last: String = str(prog.get("last_destroyed", ""))
	var boss_sealed: bool = bool(prog.get("boss_sealed", false))
	var line := "Destroy spawns %d/%d remain" % [active, total]
	if boss_sealed:
		line += " | Origin boss sealed — clear minors first"
	elif bool(prog.get("boss_active", false)):
		line += " | Origin boss active"
	if last != "":
		line += " | Last: %s" % last
	return line


func _update_map_temp_label() -> void:
	var world = get_tree().get_first_node_in_group("world")
	var temp_label := ""
	if world and "map_temperature_label" in world:
		temp_label = " | %s map" % world.map_temperature_label
	var goal := _spawn_goal_line()
	if _game_manager and _game_manager.run_state == _GameManager.RunState.WON:
		_phase_label.text = "Phase: Victory — all spawns destroyed%s" % temp_label
	elif _game_manager and _game_manager.phase == _GameManager.Phase.MAZE:
		_phase_label.text = "Phase: Maze — dig, build, collect, steer the crystal%s" % temp_label
	elif goal != "":
		_phase_label.text = "Phase: Assault — %s%s" % [goal, temp_label]
	else:
		_phase_label.text = "Phase: Assault — push back to the origin%s" % temp_label


const _GameplayInput = preload("res://helpers/gameplay_input.gd")


func _process(_delta: float) -> void:
	if _game_manager == null:
		_game_manager = get_tree().get_first_node_in_group("game_manager")
	if _crystal == null:
		_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_update_game_hud()
	if _GameplayInput.blocks_actions():
		return
	if Input.is_action_just_pressed("interact") and _panel.visible:
		if _game_manager and _game_manager.has_method("restart_run"):
			_game_manager.restart_run()


func _update_game_hud() -> void:
	if _game_hud == null:
		return
	if _crystal == null or _game_manager == null:
		return
	if _game_manager.run_state != _GameManager.RunState.PLAYING:
		_game_hud.visible = false
		return
	_game_hud.visible = true
	var cov_pct: float = _crystal.get_coverage_ratio() * 100.0
	var max_cov: float = float(_game_manager.max_crystal_coverage) * 100.0
	var prog: Dictionary = _crystal.get_spawn_progress() if _crystal.has_method("get_spawn_progress") else {}
	var spawns_line := "%d/%d spawns" % [int(prog.get("active", 0)), int(prog.get("total", 0))]
	_game_hud.text = (
		"Crystal %.1f%% / %.0f%%  |  %s  |  Pick dig  RMB build  LMB fight  M map  I inventory"
		% [cov_pct, max_cov, spawns_line]
	)


func _on_phase_changed(_new_phase: int) -> void:
	_update_map_temp_label()


func _on_run_state_changed(new_state: int) -> void:
	_panel.visible = true
	if new_state == _GameManager.RunState.WON:
		_title.text = "Victory — Crystal Shattered"
		var prog := ""
		if _crystal and _crystal.has_method("get_spawn_progress"):
			var p: Dictionary = _crystal.get_spawn_progress()
			prog = "\nAll %d spawn points destroyed." % int(p.get("total", 0))
		_subtitle.text = "You shattered every crystal heart.%s\nPress R to restart." % prog
	elif new_state == _GameManager.RunState.LOST:
		_title.text = "Run Over"
		_subtitle.text = "The corruption won this time.\nPress R to restart."