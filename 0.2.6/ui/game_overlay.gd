extends Control

const _GameManager = preload("res://game/game_manager.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")

@onready var _panel: PanelContainer = $Panel
@onready var _title: Label = $Panel/VBox/Title
@onready var _subtitle: Label = $Panel/VBox/Subtitle
@onready var _phase_label: Label = $PhaseLabel
@onready var _game_hud: Label = $GameHud

var _game_manager: Node
var _crystal: CrystalManager
var _progression_bound: bool = false
var _unlocked_enemies: Array[StringName] = []
var _equipped_relic_names: Array[String] = []
var _toast: Label = null
var _toast_timer: float = 0.0


func _ready() -> void:
	_panel.visible = false
	_ensure_toast()
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	if _game_manager:
		_game_manager.phase_changed.connect(_on_phase_changed)
		_game_manager.run_state_changed.connect(_on_run_state_changed)
		_on_phase_changed(_game_manager.phase)
	if _crystal and _crystal.has_signal("spawn_destroyed"):
		_crystal.spawn_destroyed.connect(_on_spawn_destroyed)
	call_deferred("_bind_progression")
	_update_map_temp_label()


func _ensure_toast() -> void:
	_toast = get_node_or_null("ToastLabel") as Label
	if _toast != null:
		return
	_toast = Label.new()
	_toast.name = "ToastLabel"
	_toast.visible = false
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 0.12
	_toast.anchor_bottom = 0.12
	_toast.offset_left = -280.0
	_toast.offset_right = 280.0
	_toast.offset_top = 0.0
	_toast.offset_bottom = 28.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast)


func _bind_progression() -> void:
	if _progression_bound:
		return
	if _crystal == null:
		_crystal = get_tree().get_first_node_in_group("crystal_manager")
	if _crystal and _crystal.evolution and _crystal.evolution.has_signal("enemy_unlocked"):
		if not _crystal.evolution.enemy_unlocked.is_connected(_on_enemy_unlocked):
			_crystal.evolution.enemy_unlocked.connect(_on_enemy_unlocked)
		for eid in _crystal.evolution.unlocked_enemies:
			if eid not in _unlocked_enemies:
				_unlocked_enemies.append(eid)
	var player = get_tree().get_first_node_in_group("player")
	var relic_mgr = null
	if player:
		relic_mgr = player.get_node_or_null("RelicManager")
	if relic_mgr == null:
		relic_mgr = get_tree().get_first_node_in_group("relic_manager")
	if relic_mgr:
		if relic_mgr.has_signal("relic_equipped") and not relic_mgr.relic_equipped.is_connected(_on_relic_equipped):
			relic_mgr.relic_equipped.connect(_on_relic_equipped)
		_refresh_equipped_relic_names(relic_mgr)
		_progression_bound = true
	elif _crystal and _crystal.evolution:
		_progression_bound = true


func _refresh_equipped_relic_names(relic_mgr) -> void:
	_equipped_relic_names.clear()
	_RelicRegistry.ensure_builtins()
	if relic_mgr == null or not ("equipped" in relic_mgr):
		return
	for rid in relic_mgr.equipped:
		var def = _RelicRegistry.get_def(rid)
		if def:
			_equipped_relic_names.append(def.display_name)
		else:
			_equipped_relic_names.append(str(rid))


func _on_enemy_unlocked(enemy_id: StringName) -> void:
	if enemy_id not in _unlocked_enemies:
		_unlocked_enemies.append(enemy_id)
	_show_toast("Enemy unlocked: %s" % str(enemy_id))


func _on_relic_equipped(relic_id: StringName) -> void:
	_RelicRegistry.ensure_builtins()
	var def = _RelicRegistry.get_def(relic_id)
	var name: String = def.display_name if def else str(relic_id)
	if name not in _equipped_relic_names:
		_equipped_relic_names.append(name)
	_show_toast("Relic equipped: %s" % name)
	_update_game_hud()


func _show_toast(text: String) -> void:
	_ensure_toast()
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_timer = 4.0


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
	elif _game_manager and _game_manager.run_state == _GameManager.RunState.LOST:
		_phase_label.text = "Phase: Defeat%s" % temp_label
	elif _game_manager and _game_manager.phase == _GameManager.Phase.MAZE:
		_phase_label.text = "Phase: Maze — dig, build, collect, steer the crystal%s" % temp_label
	elif goal != "":
		_phase_label.text = "Phase: Assault — %s%s" % [goal, temp_label]
	else:
		_phase_label.text = "Phase: Assault — push back to the origin%s" % temp_label


const _GameplayInput = preload("res://helpers/gameplay_input.gd")


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast:
			_toast.visible = false
	if not _progression_bound:
		_bind_progression()
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
	var relic_line := ""
	if not _equipped_relic_names.is_empty():
		relic_line = "  |  Relics: %s" % ", ".join(_equipped_relic_names)
	_game_hud.text = (
		"Crystal %.1f%% / %.0f%%  |  %s%s  |  Pick dig  RMB build  LMB fight  M map  I inventory"
		% [cov_pct, max_cov, spawns_line, relic_line]
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
		var reason := ""
		if _game_manager and "last_loss_reason" in _game_manager:
			reason = str(_game_manager.last_loss_reason)
		if reason != "":
			_subtitle.text = "%s\nPress R to restart." % reason
		else:
			_subtitle.text = "The corruption won this time.\nPress R to restart."
	_update_map_temp_label()
