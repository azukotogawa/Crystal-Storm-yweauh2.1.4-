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
var _living_world = null
var _current_biome: String = ""
var _opening_toast_shown: bool = false
var _mite_threat_toast_shown: bool = false


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
	call_deferred("_bind_living_world")
	call_deferred("_bind_enemy_spawner")
	call_deferred("_show_opening_toast")
	_update_map_temp_label()


func _show_opening_toast() -> void:
	if _opening_toast_shown:
		return
	_opening_toast_shown = true
	# Immediate orientation: crystal is the pressure, dig buys time.
	_show_toast("Maze phase — dig trenches. Crystal blooms at the origin.")


func _bind_enemy_spawner() -> void:
	var spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if spawner == null:
		return
	if spawner.has_signal("enemy_spawned") and not spawner.enemy_spawned.is_connected(_on_crystal_enemy_spawned):
		spawner.enemy_spawned.connect(_on_crystal_enemy_spawned)


func _on_crystal_enemy_spawned(enemy_id: StringName, _world_pos: Vector2i) -> void:
	if _mite_threat_toast_shown:
		return
	_mite_threat_toast_shown = true
	var label := str(enemy_id).replace("_", " ")
	_show_toast("Crystal hostiles rise (%s) — dig a trench or fight!" % label)


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


func _bind_living_world() -> void:
	_living_world = get_tree().get_first_node_in_group("living_world_director")
	if _living_world == null:
		return
	if _living_world.has_signal("biome_changed") and not _living_world.biome_changed.is_connected(_on_biome_changed):
		_living_world.biome_changed.connect(_on_biome_changed)
	if _living_world.has_signal("ruin_discovered") and not _living_world.ruin_discovered.is_connected(_on_ruin_discovered):
		_living_world.ruin_discovered.connect(_on_ruin_discovered)
	if _living_world.has_signal("ruin_expedition_completed") and not _living_world.ruin_expedition_completed.is_connected(_on_ruin_expedition):
		_living_world.ruin_expedition_completed.connect(_on_ruin_expedition)
	if _living_world.has_signal("biome_first_visited") and not _living_world.biome_first_visited.is_connected(_on_biome_first_visit):
		_living_world.biome_first_visited.connect(_on_biome_first_visit)
	if _living_world.has_signal("town_militia_called") and not _living_world.town_militia_called.is_connected(_on_militia_toast):
		_living_world.town_militia_called.connect(_on_militia_toast)
	if _living_world.has_signal("town_rallied") and not _living_world.town_rallied.is_connected(_on_town_rallied):
		_living_world.town_rallied.connect(_on_town_rallied)
	if _living_world.has_signal("town_threat_changed") and not _living_world.town_threat_changed.is_connected(_on_town_threat_changed):
		_living_world.town_threat_changed.connect(_on_town_threat_changed)
	if _living_world.has_method("get_player_biome_name"):
		_current_biome = str(_living_world.get_player_biome_name())


func _on_biome_changed(biome_name: String) -> void:
	_current_biome = biome_name
	_update_map_temp_label()
	_update_game_hud()


func _on_ruin_discovered(ruin_name: String, _center: Vector2i, power_bonus: float) -> void:
	# Base stir toast; full expedition toast may follow from ruin_expedition_completed.
	_show_toast("Discovered %s — the crystal stirs (+%.0f power)" % [ruin_name, power_bonus])


func _on_ruin_expedition(result: Dictionary) -> void:
	var ruin_name: String = str(result.get("name", "Ruin"))
	var loot: Dictionary = result.get("loot", {})
	var relic_id: String = str(result.get("relic_id", ""))
	var guardians: int = int(result.get("guardians", 0))
	var parts: PackedStringArray = PackedStringArray()
	parts.append("Plundered %s" % ruin_name)
	if int(loot.get("stone", 0)) > 0 or int(loot.get("herb", 0)) > 0:
		parts.append("+%d stone +%d herb" % [int(loot.get("stone", 0)), int(loot.get("herb", 0))])
	if relic_id != "":
		_RelicRegistry.ensure_builtins()
		var def = _RelicRegistry.get_def(StringName(relic_id))
		var rname: String = def.display_name if def else relic_id
		parts.append("Relic: %s" % rname)
	if guardians > 0:
		parts.append("%d guardians wake!" % guardians)
	_show_toast(" · ".join(parts))
	_update_game_hud()


func _on_biome_first_visit(biome_name: String, gift_item: String, gift_count: int) -> void:
	_show_toast("First steps in %s — +%d %s" % [biome_name.capitalize(), gift_count, gift_item])


func _on_militia_toast(town_name: String, count: int) -> void:
	_show_toast("%s calls %d militia!" % [town_name, count])


func _on_town_rallied(town_name: String, _center: Vector2i, militia: int, health_restored: float) -> void:
	# Surprise: player arrival can save a settlement mid-siege.
	_show_toast("You rallied %s! +%.0f HP · +%d militia" % [town_name, health_restored, militia])


func _on_town_threat_changed(town_name: String, state_label: String, _center: Vector2i) -> void:
	if state_label == "SAFE":
		return
	_show_toast("%s is under %s!" % [town_name, state_label])


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
	var biome_label := ""
	if _current_biome != "":
		biome_label = " | Biome: %s" % _current_biome.capitalize()
	elif world and _game_manager:
		var player = get_tree().get_first_node_in_group("player")
		if player and player.has_method("get_voxel_position") and world.has_method("get_biome"):
			var v: Vector3 = player.get_voxel_position()
			var b: Dictionary = world.get_biome(v.x, 0.0, v.z)
			_current_biome = str(b.get("name", ""))
			if _current_biome != "":
				biome_label = " | Biome: %s" % _current_biome.capitalize()
	var goal := _spawn_goal_line()
	var suffix := "%s%s" % [temp_label, biome_label]
	if _game_manager and _game_manager.run_state == _GameManager.RunState.WON:
		_phase_label.text = "Phase: Victory — all spawns destroyed%s" % suffix
	elif _game_manager and _game_manager.run_state == _GameManager.RunState.LOST:
		_phase_label.text = "Phase: Defeat%s" % suffix
	elif _game_manager and _game_manager.phase == _GameManager.Phase.MAZE:
		_phase_label.text = "Phase: Maze — dig, build, collect, defend the living world%s" % suffix
	elif goal != "":
		_phase_label.text = "Phase: Assault — %s%s" % [goal, suffix]
	else:
		_phase_label.text = "Phase: Assault — push back to the origin%s" % suffix


const _GameplayInput = preload("res://helpers/gameplay_input.gd")


func _process(delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("ui_overlay")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("GameOverlay::_process")
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
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("GameOverlay::_process")
		if profiler and profiler.has_method("end"):
			profiler.end("ui_overlay")
		return
	if Input.is_action_just_pressed("interact") and _panel.visible:
		if _game_manager and _game_manager.has_method("restart_run"):
			_game_manager.restart_run()
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("GameOverlay::_process")
	if profiler and profiler.has_method("end"):
		profiler.end("ui_overlay")


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
	var biome_line := ""
	if _current_biome != "":
		biome_line = "  |  %s" % _current_biome.capitalize()
	var town_line := ""
	if _living_world and _living_world.has_method("get_town_hud_line"):
		var tl: String = str(_living_world.get_town_hud_line())
		if tl != "":
			town_line = "  |  %s" % tl
	var ruins_line := ""
	if _living_world and _living_world.has_method("get_ruins_hud_line"):
		var rl: String = str(_living_world.get_ruins_hud_line())
		if rl != "":
			ruins_line = "  |  %s" % rl
	_game_hud.text = (
		"Crystal %.1f%% / %.0f%%  |  %s%s%s%s%s  |  Pick dig  RMB build  LMB fight  M map  I inventory"
		% [cov_pct, max_cov, spawns_line, relic_line, biome_line, town_line, ruins_line]
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
