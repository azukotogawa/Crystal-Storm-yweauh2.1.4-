extends Control

const _GameManager = preload("res://game/game_manager.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _CrystalPalette = preload("res://ui/crystal_palette.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _TutorialOverlay = preload("res://ui/tutorial_overlay.gd")
const _RunSummaryPanel = preload("res://ui/run_summary_panel.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _GameConfig = preload("res://config/game_config.gd")
const _Progression = preload("res://systems/progression_service.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _Passives = preload("res://player/skill_passives.gd")
const _HudLayout = preload("res://config/hud_layout.gd")

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
var _toast_beat: String = ""
var _skills_bound: bool = false
var _stage_bound: bool = false
var _stage_seen: Dictionary = {}
var _living_world = null
var _current_biome: String = ""
var _opening_toast_shown: bool = false
var _mite_threat_toast_shown: bool = false
var _pressure_toast_shown: bool = false
var _assault_toast_shown: bool = false
var _last_phase_for_toast: int = -1
var _terrain_crystal_toast_cd: float = 0.0
var _phase_label_pulse: float = 0.0
var _phase_label_base_mod: Color = Color.WHITE
var _bake_chip: Label = null
var _objective_panel: PanelContainer = null
var _objective_phase: Label = null
var _objective_spawns: Label = null
var _objective_coverage: Label = null
var _objective_bearing: Label = null
var _objective_arrow: Label = null
var _crystal_hp_bar: ProgressBar = null
var _crystal_hp_label: Label = null
var _boss_warned: bool = false
var _boss: Node = null
var _boss_panel: PanelContainer = null
var _boss_label: Label = null
var _boss_bar: ProgressBar = null
var _boss_shown_hp: int = -1
var _hud_player: Node = null
var _arrow_play_color: Color = Color(0.95, 0.75, 1.0)
var _vitals_plate: Panel = null
var _hp_panel: PanelContainer = null
var _hp_bar: ProgressBar = null
var _hp_value_label: Label = null
var _hp_fill: StyleBoxFlat = null
var _hp_panel_style: StyleBoxFlat = null
var _hp_bound_player: Node = null
var _hp_last: float = -1.0
var _hp_last_max: float = -1.0
var _hp_shown: int = -99999
var _hp_shown_max: int = -99999
var _hp_band: int = -1
var _hp_colorblind: bool = false
var _xp_panel: PanelContainer = null
var _xp_bar: ProgressBar = null
var _xp_level_label: Label = null
var _xp_value_label: Label = null
var _xp_fill: StyleBoxFlat = null
var _xp_service: Node = null
var _xp_bound: bool = false
var _xp_shown_level: int = -1
var _xp_shown: int = -1
var _xp_shown_need: int = -1
var _run_summary: _RunSummaryPanel = null
var _hud_frame: int = -999
var _hud_skip: bool = false
var _hk_cell: Vector2i = Vector2i(2147483647, 0)
var _hk_tiles: int = -999999
var _hk_phase: int = -999
var _hk_run: int = -999
var _hk_place: int = -999
var _hk_biome: int = 0
var _hk_relics: int = -1
var _hk_crystal_hp: int = -999999
var _hk_boss_warn: int = -1
var _spawn_cell: Vector2i = Vector2i(999999, 999999)
var _spawn_known: bool = false
var _bake_done: int = -1
var _bake_total: int = -1


func _ready() -> void:
	add_to_group("game_overlay")
	_panel.visible = false
	_ensure_toast()
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	_claim_crystal()
	if _game_manager:
		_game_manager.phase_changed.connect(_on_phase_changed)
		_game_manager.run_state_changed.connect(_on_run_state_changed)
		_on_phase_changed(_game_manager.phase)
	if _crystal and _crystal.has_signal("spawn_destroyed"):
		_crystal.spawn_destroyed.connect(_on_spawn_destroyed)
	if _crystal and _crystal.has_signal("power_changed"):
		_crystal.power_changed.connect(_on_crystal_power_changed)
	call_deferred("_bind_progression")
	call_deferred("_bind_living_world")
	call_deferred("_bind_enemy_spawner")
	call_deferred("_bind_build_feedback")
	call_deferred("_bind_terrain_crystal_feedback")
	call_deferred("_schedule_opening_toast")
	_update_map_temp_label()
	if _phase_label:
		_phase_label_base_mod = _phase_label.modulate
		_phase_label.clip_text = true
	call_deferred("_ensure_leave_world_button")
	_ensure_bake_chip()
	_ensure_objective_hud()
	_ensure_player_health_bar()
	_ensure_xp_bar()
	_bind_xp_hud()
	_ThemeBuilder.apply(self)
	apply_hud_palette(_PlayerSettings.colorblind_palette)
	_update_player_health()
	call_deferred("_maybe_show_tutorial")


func _ensure_bake_chip() -> void:
	if _bake_chip != null:
		return
	_bake_chip = Label.new()
	_bake_chip.name = "BakeChip"
	_bake_chip.visible = false
	_bake_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bake_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_bake_chip.anchor_left = 1.0
	_bake_chip.anchor_right = 1.0
	_bake_chip.anchor_top = 1.0
	_bake_chip.anchor_bottom = 1.0
	_bake_chip.offset_left = -280.0
	_bake_chip.offset_top = -28.0
	_bake_chip.offset_right = -12.0
	_bake_chip.offset_bottom = -8.0
	_bake_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bake_chip.add_theme_font_size_override("font_size", 12)
	_bake_chip.add_theme_color_override("font_color", Color(0.7, 0.82, 0.95, 0.75))
	add_child(_bake_chip)


func _update_bake_chip() -> void:
	if _bake_chip == null:
		return
	if _GameplayInput.world_loading:
		if _bake_chip.visible:
			_bake_chip.visible = false
		return
	var bake = _WorldBakeService.get_active()
	if bake == null or not ("bake_in_progress" in bake) or not bool(bake.bake_in_progress):
		if _bake_chip.visible:
			_bake_chip.visible = false
		_bake_done = -1
		return
	var done := int(bake._fill_done) if "_fill_done" in bake else -1
	var total := int(bake._fill_total) if "_fill_total" in bake else -1
	if _bake_chip.visible and done == _bake_done and total == _bake_total:
		return
	_bake_chip.visible = true
	_bake_chip.text = "Background bake %d / %d" % [done, total]
	_bake_done = done
	_bake_total = total


func _ensure_leave_world_button() -> void:
	var wm = load("res://systems/world_manager.gd")
	if wm == null or not bool(wm.launched_from_catalog):
		return
	if get_node_or_null("LeaveWorld") != null:
		return
	var b := Button.new()
	b.name = "LeaveWorld"
	b.text = "Leave World"
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.offset_left = 12
	b.offset_top = 12
	b.offset_right = 140
	b.offset_bottom = 40
	b.pressed.connect(_on_leave_world)
	add_child(b)


func _on_leave_world() -> void:
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		game = get_tree().current_scene
	if game and game.has_method("return_to_world_select"):
		game.return_to_world_select()
	else:
		load("res://systems/world_manager.gd").request_return_to_select()
		get_tree().change_scene_to_file("res://scenes/frontend.tscn")


func _bind_build_feedback() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var weapon = player.get_node_or_null("WeaponController")
	if weapon and weapon.has_signal("structure_built") \
			and not weapon.structure_built.is_connected(_on_structure_built):
		weapon.structure_built.connect(_on_structure_built)


func _bind_terrain_crystal_feedback() -> void:
	var editor = get_tree().get_first_node_in_group("terrain_editor")
	if editor == null:
		return
	if editor.has_signal("terrain_edited") \
			and not editor.terrain_edited.is_connected(_on_terrain_edited_near_crystal):
		editor.terrain_edited.connect(_on_terrain_edited_near_crystal)


func _on_terrain_edited_near_crystal(wx: int, wz: int, kind: StringName) -> void:
	if _terrain_crystal_toast_cd > 0.0:
		return
	if _game_manager and _game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	if _crystal == null or not _crystal.has_method("get_depth_at"):
		return
	var near := false
	var min_d: float = 0.04
	if "sim_config" in _crystal and _crystal.sim_config:
		min_d = float(_crystal.sim_config.min_depth)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			if _crystal.get_depth_at(wx + dx, wz + dz) >= min_d:
				near = true
				break
		if near:
			break
	if not near:
		return
	_terrain_crystal_toast_cd = 7.5
	var k := str(kind)
	if k == "dig":
		_show_toast("Trench cut — purple front follows lower ground")
	elif k == "water":
		_show_toast("Bank to water — crystal slows on wet ground")
	elif k == "gate":
		_show_toast("Gate holds a crawl path — crystal slows, you pass")
	elif k == "bridge":
		_show_toast("Bridge spans the cut — crystal still feels the drop")
	else:
		_show_toast("Wall raised — crystal slows here; it will find another way")


func _on_structure_built(build_id: StringName, _world_pos: Vector3) -> void:
	if build_id == &"gate":
		_show_toast("Gate placed — walk through · slows crystal")
	elif build_id == &"bridge":
		_show_toast("Bridge placed — span digs & low ground")


func _schedule_opening_toast() -> void:
	var ls = get_node_or_null("../../LoadingLayer/LoadingScreen")
	if ls == null:
		ls = get_tree().root.find_child("LoadingScreen", true, false)
	if ls != null and ls.visible and float(ls.modulate.a) > 0.05:
		return
	_show_opening_toast()


func notify_loading_finished() -> void:
	_show_opening_toast()


func _show_opening_toast() -> void:
	if _opening_toast_shown:
		return
	_opening_toast_shown = true
	_show_toast("Watch the purple front — dig trenches & walls where it advances")


func _on_crystal_power_changed(_power: float, tier: int) -> void:
	if _pressure_toast_shown or tier < 1:
		return
	if _game_manager and _game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	_pressure_toast_shown = true
	_show_toast("Crystal pressure rising — terrain slows it, it never stops")


func _bind_enemy_spawner() -> void:
	var spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if spawner == null:
		return
	if spawner.has_signal("enemy_spawned") and not spawner.enemy_spawned.is_connected(_on_crystal_enemy_spawned):
		spawner.enemy_spawned.connect(_on_crystal_enemy_spawned)


func _on_crystal_enemy_spawned(enemy_id: StringName, _world_pos: Vector2i) -> void:
	if _GameConfig.SINGLE_CRYSTAL and enemy_id == &"origin_warden":
		_note_boss_warning(true)
		return
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
	add_child(_toast)
	_place_toast()


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
	if _living_world.has_signal("landmark_discovered") and not _living_world.landmark_discovered.is_connected(_on_landmark_discovered):
		_living_world.landmark_discovered.connect(_on_landmark_discovered)
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
	var lore := str(result.get("lore", ""))
	if lore != "":
		parts.append(lore)
	var line := " · ".join(parts)
	if bool(result.get("treasure_site", false)):
		_show_beat("treasure", line)
	else:
		_show_toast(line)
	_update_game_hud()


func _on_biome_first_visit(biome_name: String, gift_item: String, gift_count: int) -> void:
	_show_toast("First steps in %s — +%d %s" % [biome_name.capitalize(), gift_count, gift_item])


func _on_militia_toast(town_name: String, count: int) -> void:
	_show_toast("%s calls %d militia!" % [town_name, count])


func _on_town_rallied(town_name: String, _center: Vector2i, militia: int, health_restored: float) -> void:
	_show_toast("You rallied %s! +%.0f HP · +%d militia" % [town_name, health_restored, militia])


func _on_town_threat_changed(town_name: String, state_label: String, _center: Vector2i) -> void:
	if state_label == "SAFE":
		return
	_show_toast("%s is under %s!" % [town_name, state_label])


func _bind_progression() -> void:
	if _progression_bound:
		return
	_claim_crystal()
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
	_show_beat("relic", "Relic equipped: %s" % name)
	_update_game_hud()


func _banner_seconds() -> float:
	if not is_inside_tree():
		return 2.5
	var feel := get_node_or_null("/root/GameFeel")
	if feel == null or not feel.has_method("banner_seconds"):
		return 2.5
	var seconds := float(feel.banner_seconds())
	if seconds <= 0.0:
		return 2.5
	return seconds


func _place_toast() -> void:
	if _toast == null:
		return
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -220.0
	_toast.offset_right = 220.0
	_toast.offset_top = 200.0
	_toast.offset_bottom = 236.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _show_toast(text: String) -> void:
	_ensure_toast()
	if _toast == null:
		return
	_place_toast()
	_toast_beat = ""
	_toast.text = text
	_toast.visible = true
	_toast_timer = _banner_seconds()


func _show_beat(beat_id: String, text: String) -> void:
	_ensure_toast()
	if _toast == null:
		return
	_place_toast()
	_toast_beat = beat_id
	_toast.text = text
	_toast.visible = true
	_toast_timer = _beat_seconds(beat_id)
	if not is_inside_tree():
		return
	var feel := get_node_or_null("/root/GameFeel")
	if feel != null and feel.has_method("play_beat"):
		feel.play_beat(beat_id)


func _beat_seconds(beat_id: String) -> float:
	if not is_inside_tree():
		return 2.5
	var feel := get_node_or_null("/root/GameFeel")
	if feel == null or not feel.has_method("banner_seconds"):
		return 2.5
	var seconds := float(feel.banner_seconds(beat_id))
	if seconds <= 0.0:
		return 2.5
	return seconds


func _on_spawn_destroyed(_spawn) -> void:
	if _game_manager and _game_manager.run_state == _GameManager.RunState.PLAYING:
		_update_map_temp_label()


func _spawn_goal_line() -> String:
	if _crystal == null or not _crystal.has_method("get_spawn_progress"):
		return ""
	var prog: Dictionary = _crystal.get_spawn_progress()
	if _GameConfig.SINGLE_CRYSTAL:
		return _single_crystal_goal_line(prog)
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


func _single_crystal_goal_line(prog: Dictionary) -> String:
	var line := "Destroy the crystal"
	var max_hp := float(prog.get("crystal_max_health", 0.0))
	if max_hp > 0.0:
		line = "Destroy the crystal  %d/%d" % [int(round(float(prog.get("crystal_health", 0.0)))), int(round(max_hp))]
	if _boss_warning_on(prog):
		line += " | Boss warning"
	return line


func _boss_warning_on(prog: Dictionary) -> bool:
	return _boss_warned or bool(prog.get("boss_spawned", false)) or _tracked_boss_alive()


func _tracked_boss_alive() -> bool:
	if _boss == null or not is_instance_valid(_boss):
		return false
	if "health" in _boss and float(_boss.health) <= 0.0:
		return false
	return true


func _note_boss_warning(active: bool) -> void:
	if not _GameConfig.SINGLE_CRYSTAL or not active or _boss_warned:
		return
	_boss_warned = true
	_show_beat("boss_spawn", "Boss warning — a warden guards the crystal")


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
		_phase_label.text = _victory_phase_text(suffix)
	elif _game_manager and _game_manager.run_state == _GameManager.RunState.LOST:
		_phase_label.text = "Phase: Defeat%s" % suffix
	elif _game_manager and _game_manager.phase == _GameManager.Phase.MAZE:
		_phase_label.text = "Phase: Maze — dig & build routes · terrain buys time%s" % suffix
	elif _GameConfig.SINGLE_CRYSTAL:
		var crystal_goal := goal if goal != "" else "Destroy the crystal"
		_phase_label.text = "Phase: Assault — %s%s" % [crystal_goal, suffix]
	elif goal != "":
		_phase_label.text = "Phase: Assault — fight the crystal · %s%s" % [goal, suffix]
	else:
		_phase_label.text = "Phase: Assault — push to the origin heart%s" % suffix


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
	if _terrain_crystal_toast_cd > 0.0:
		_terrain_crystal_toast_cd = maxf(_terrain_crystal_toast_cd - delta, 0.0)
	if _phase_label_pulse > 0.0 and _phase_label:
		_phase_label_pulse = maxf(_phase_label_pulse - delta, 0.0)
		var t: float = _phase_label_pulse / 2.2
		_phase_label.modulate = _phase_label_base_mod.lerp(Color(1.0, 0.45, 1.0), t)
	elif _phase_label and _phase_label.modulate != _phase_label_base_mod:
		_phase_label.modulate = _phase_label_base_mod
	if not _progression_bound:
		_bind_progression()
	if not _skills_bound:
		_bind_skills()
	if _game_manager == null:
		_game_manager = get_tree().get_first_node_in_group("game_manager")
	_claim_crystal()
	_bind_crystal_beats()
	_update_game_hud()
	_update_objective_hud()
	_update_player_health()
	_update_xp_bar()
	_update_boss_bar()
	_update_bake_chip()
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


func _hud_should_skip() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _hud_frame:
		return _hud_skip
	_hud_frame = frame
	var cell := Vector2i(2147483647, 0)
	var player := _cached_player()
	if player and player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		cell = Vector2i(floori(v.x), floori(v.z))
	var tiles := 0
	if _crystal and "covered_cells" in _crystal:
		tiles = int(_crystal.covered_cells)
	var phase := -1
	var run_state := -1
	if _game_manager:
		phase = int(_game_manager.phase)
		run_state = int(_game_manager.run_state)
	var place := 0
	if player:
		var weapon = player.get_node_or_null("WeaponController")
		if weapon and "place_index" in weapon:
			place = int(weapon.place_index)
	var biome_h := _current_biome.hash()
	var relics := _equipped_relic_names.size()
	var crystal_hp := _hk_crystal_hp
	var boss_warn := _hk_boss_warn
	if _GameConfig.SINGLE_CRYSTAL and _crystal and _crystal.has_method("get_spawn_progress"):
		var crystal_prog: Dictionary = _crystal.get_spawn_progress()
		crystal_hp = int(round(float(crystal_prog.get("crystal_health", -1.0))))
		boss_warn = 1 if _boss_warning_on(crystal_prog) else 0
	var changed := (
		cell != _hk_cell or tiles != _hk_tiles or phase != _hk_phase
		or run_state != _hk_run or place != _hk_place or biome_h != _hk_biome
		or relics != _hk_relics or crystal_hp != _hk_crystal_hp or boss_warn != _hk_boss_warn
	)
	if changed:
		_hk_cell = cell
		_hk_tiles = tiles
		_hk_phase = phase
		_hk_run = run_state
		_hk_place = place
		_hk_biome = biome_h
		_hk_relics = relics
		_hk_crystal_hp = crystal_hp
		_hk_boss_warn = boss_warn
	_hud_skip = (not changed) and (posmod(frame, 20) != 0)
	return _hud_skip


func _update_game_hud() -> void:
	if _game_hud == null:
		return
	if _crystal == null or _game_manager == null:
		return
	if _hud_should_skip():
		return
	if _game_manager.run_state != _GameManager.RunState.PLAYING:
		_game_hud.visible = false
		return
	_game_hud.visible = true
	var cov_pct: float = _crystal.get_coverage_ratio() * 100.0
	var max_cov: float = float(_game_manager.max_crystal_coverage) * 100.0
	var tiles: int = int(_crystal.covered_cells) if "covered_cells" in _crystal else 0
	var crystal_bit := "Crystal %.1f%% / %.0f%%" % [cov_pct, max_cov]
	# Map-wide percent rounds to 0.0% for thousands of cells; live tile count is
	# the existing sim field the player can actually see changing. Do not print
	# the 0.0% that made the threat look absent.
	if tiles > 0 and cov_pct < 0.05:
		crystal_bit = "Crystal %dc · cap %.0f%%" % [tiles, max_cov]
	if _game_manager.has_method("coverage_hud_note"):
		var cap_note: String = str(_game_manager.coverage_hud_note(cov_pct / 100.0))
		if cap_note != "":
			crystal_bit = "%s · %s" % [crystal_bit, cap_note]
	var bearing := _crystal_bearing_bit()
	if bearing != "":
		crystal_bit = "%s · %s" % [crystal_bit, bearing]
	var wet_bit := _wet_crawl_bit()
	if wet_bit != "":
		crystal_bit = "%s · %s" % [crystal_bit, wet_bit]
	var prog: Dictionary = _crystal.get_spawn_progress() if _crystal.has_method("get_spawn_progress") else {}
	var spawns_line := "%d/%d spawns" % [int(prog.get("active", 0)), int(prog.get("total", 0))]
	if _GameConfig.SINGLE_CRYSTAL:
		spawns_line = _crystal_hud_bit(prog)
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
	var tool_line := "WASD move · Space jump · LMB break · RMB place · Tab cycle"
	var weapon = null
	var player := _cached_player()
	if player:
		weapon = player.get_node_or_null("WeaponController")
	var place_name := "Fill"
	if weapon and weapon.has_method("get_place_label"):
		place_name = str(weapon.get_place_label())
	if weapon and weapon.has_method("get_active_item"):
		var slot = weapon.get_active_item()
		if slot != null:
			var sid := str(slot.id)
			if _ItemTypes.breaks_blocks(sid):
				tool_line = "WASD · Space jump · LMB break · RMB %s" % place_name
			elif _ItemTypes.has_right_click_ability(sid):
				tool_line = "WASD · Space jump · RMB use"
			elif _is_fight_item(sid):
				var verb := "LMB attack"
				if int(_ItemTypes.get_def(sid).get("category", -1)) == _ItemTypes.Category.ARMOR:
					verb = "LMB wear"
				tool_line = "FIGHT · WASD · Space jump · %s · RMB %s" % [verb, place_name]
			else:
				tool_line = "WASD · Space jump · RMB %s" % place_name
		else:
			tool_line = "WASD · Space jump · RMB %s" % place_name
	else:
		tool_line = "WASD · Space jump · RMB %s" % place_name
	var phase_tag := "MAZE"
	if _game_manager.phase == _GameManager.Phase.ASSAULT:
		phase_tag = "ASSAULT"
	elif _game_manager.phase == _GameManager.Phase.VICTORY:
		phase_tag = "VICTORY"
	var tier_line := ""
	if "strength_tier" in _crystal:
		tier_line = "  |  T%d" % int(_crystal.strength_tier)
	_game_hud.text = (
		"%s  |  %s%s  |  %s%s%s%s%s  |  %s"
		% [phase_tag, crystal_bit, tier_line, spawns_line, relic_line, biome_line, town_line, ruins_line, tool_line]
	)


func _crystal_hud_bit(prog: Dictionary) -> String:
	var max_hp := float(prog.get("crystal_max_health", 0.0))
	var bit := "Destroy the crystal"
	if max_hp > 0.0:
		bit = "Crystal %d/%d" % [int(round(float(prog.get("crystal_health", 0.0)))), int(round(max_hp))]
	if _boss_warning_on(prog):
		bit += " · boss warning"
	return bit


func _is_fight_item(item_id: String) -> bool:
	var def := _ItemTypes.get_def(item_id)
	if def.is_empty():
		return false
	if bool(def.get("throwable", false)):
		return true
	var category := int(def.get("category", -1))
	if category == _ItemTypes.Category.ARMOR:
		return true
	return category == _ItemTypes.Category.WEAPON and int(def.get("weapon_kind", -1)) != _ItemTypes.WeaponKind.DIG


func _win_banner() -> String:
	if _GameConfig.SINGLE_CRYSTAL and _victory_reason() != "boss":
		return "Victory — the crystal was destroyed"
	if _victory_reason() == "boss":
		return "Victory — the warden fell"
	return "Victory — the crystal shattered"


func _victory_reason() -> String:
	if _game_manager and "victory_reason" in _game_manager:
		return str(_game_manager.victory_reason)
	return ""


func _victory_phase_text(suffix: String) -> String:
	if _GameConfig.SINGLE_CRYSTAL and _victory_reason() != "boss":
		return "Phase: Victory — the crystal was destroyed%s" % suffix
	if _victory_reason() == "boss":
		return "Phase: Victory — the Origin Warden fell%s" % suffix
	return "Phase: Victory — all spawns destroyed%s" % suffix


func track_boss(boss: Node) -> void:
	if boss == null:
		return
	_boss = boss
	_boss_shown_hp = -1
	_ensure_boss_bar()
	if _GameConfig.SINGLE_CRYSTAL:
		_note_boss_warning(true)


func _ensure_boss_bar() -> void:
	if _boss_panel != null:
		return
	_boss_panel = PanelContainer.new()
	_boss_panel.name = "BossHpBar"
	_boss_panel.visible = false
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.offset_left = -170.0
	_boss_panel.offset_right = 170.0
	_boss_panel.offset_top = 8.0
	_boss_panel.offset_bottom = 52.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.03, 0.06, 0.86)
	panel_style.border_color = Color(0.9, 0.22, 0.38, 0.95)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(6)
	_boss_panel.add_theme_stylebox_override("panel", panel_style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_boss_panel.add_child(box)
	_boss_label = Label.new()
	_boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_label.add_theme_font_size_override("font_size", 13)
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.86))
	_boss_label.text = "Boss warning" if _GameConfig.SINGLE_CRYSTAL else "Origin Warden"
	box.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.custom_minimum_size = Vector2(300, 12)
	_boss_bar.max_value = 240.0
	_boss_bar.value = 240.0
	_boss_bar.show_percentage = false
	box.add_child(_boss_bar)
	add_child(_boss_panel)
	apply_hud_palette(_PlayerSettings.colorblind_palette)


func _update_boss_bar() -> void:
	if _boss_panel == null:
		return
	if _boss == null or not is_instance_valid(_boss):
		_boss = null
		_boss_panel.visible = false
		return
	var hp := float(_boss.get("health"))
	var max_hp := maxf(float(_boss.get("max_health")), 1.0)
	if hp <= 0.0:
		_boss_panel.visible = false
		_boss = null
		return
	var engaged := hp < max_hp - 0.5
	if not engaged:
		var player := _cached_player()
		if player and player.has_method("get_voxel_position") and _boss is Node3D:
			var pv: Vector3 = player.get_voxel_position()
			var ws = _WorldSettings.get_active()
			var body := _boss as Node3D
			var flat := Vector2(
				ws.world_to_column(body.global_position.x) - pv.x,
				ws.world_to_column(body.global_position.z) - pv.z
			)
			engaged = flat.length() <= 22.0
	_boss_panel.visible = engaged
	if not engaged:
		return
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp
	var shown := int(round(hp))
	if shown != _boss_shown_hp:
		_boss_shown_hp = shown
		var phase := int(_boss.get("boss_phase"))
		if _GameConfig.SINGLE_CRYSTAL:
			_boss_label.text = "Boss warning  %d / %d" % [shown, int(max_hp)]
		else:
			_boss_label.text = "Origin Warden  %d / %d  ·  phase %d" % [shown, int(max_hp), phase]


func _ensure_vitals_backing() -> void:
	if _vitals_plate != null:
		return
	var layout := _HudLayout.load_active()
	_vitals_plate = Panel.new()
	_vitals_plate.name = "VitalsBacking"
	_vitals_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vitals_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_vitals_plate.offset_left = layout.vitals_left
	_vitals_plate.offset_right = layout.vitals_right
	_vitals_plate.offset_top = layout.vitals_top
	_vitals_plate.offset_bottom = layout.vitals_bottom
	var plate := StyleBoxFlat.new()
	plate.bg_color = layout.backing
	plate.set_corner_radius_all(6)
	_vitals_plate.add_theme_stylebox_override("panel", plate)
	add_child(_vitals_plate)


func _ensure_player_health_bar() -> void:
	if _hp_panel != null:
		return
	_ensure_vitals_backing()
	_hp_panel = PanelContainer.new()
	_hp_panel.name = "PlayerHealthBar"
	_hp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_panel.visible = false
	_hp_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hp_panel.offset_left = -130.0
	_hp_panel.offset_right = 130.0
	_hp_panel.offset_top = -118.0
	_hp_panel.offset_bottom = -82.0
	_hp_panel_style = StyleBoxFlat.new()
	_hp_panel_style.bg_color = Color(0.05, 0.07, 0.06, 0.84)
	_hp_panel_style.border_color = Color(0.4, 0.75, 0.42, 0.9)
	_hp_panel_style.set_border_width_all(1)
	_hp_panel_style.set_content_margin_all(6)
	_hp_panel.add_theme_stylebox_override("panel", _hp_panel_style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_hp_panel.add_child(row)
	var name_label := Label.new()
	name_label.text = "HP"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86))
	row.add_child(name_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HpFill"
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.show_percentage = false
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.custom_minimum_size = Vector2(120, 14)
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.08, 1.0)
	track.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", track)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.32, 0.78, 0.38)
	_hp_fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	row.add_child(_hp_bar)
	_hp_value_label = Label.new()
	_hp_value_label.text = "100 / 100"
	_hp_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_value_label.custom_minimum_size = Vector2(72, 0)
	_hp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_value_label.add_theme_font_size_override("font_size", 14)
	_hp_value_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.94))
	row.add_child(_hp_value_label)
	add_child(_hp_panel)


func _update_player_health() -> void:
	var player := _cached_player()
	if player == null or not ("health" in player):
		if _hp_panel:
			_hp_panel.visible = false
		_hp_bound_player = null
		return
	if _hp_bound_player != player:
		if _hp_bound_player != null and is_instance_valid(_hp_bound_player) \
				and _hp_bound_player.has_signal("health_changed") \
				and _hp_bound_player.health_changed.is_connected(_on_player_health_changed):
			_hp_bound_player.health_changed.disconnect(_on_player_health_changed)
		_hp_bound_player = player
		_hp_last = -1.0
		if player.has_signal("health_changed") \
				and not player.health_changed.is_connected(_on_player_health_changed):
			player.health_changed.connect(_on_player_health_changed)
	var mx := float(player.max_health) if "max_health" in player else 100.0
	_apply_player_health(float(player.health), mx)


func _on_player_health_changed(current: float, maximum: float) -> void:
	_apply_player_health(current, maximum)


func _apply_player_health(hp: float, mx: float) -> void:
	_ensure_player_health_bar()
	if _hp_panel == null:
		return
	_hp_panel.visible = true
	mx = maxf(mx, 1.0)
	if absf(hp - _hp_last) < 0.02 and absf(mx - _hp_last_max) < 0.02 and _hp_band >= 0:
		return
	_hp_last = hp
	_hp_last_max = mx
	_hp_bar.max_value = mx
	_hp_bar.value = clampf(hp, 0.0, mx)
	var shown := int(round(hp))
	var shown_max := int(round(mx))
	if shown != _hp_shown or shown_max != _hp_shown_max:
		_hp_shown = shown
		_hp_shown_max = shown_max
		_hp_value_label.text = "%d / %d" % [shown, shown_max]
	_paint_hp_fill(clampf(hp / mx, 0.0, 1.0))


func _paint_hp_fill(ratio: float) -> void:
	if _hp_fill == null:
		return
	var band := 2
	if ratio > 0.55:
		band = 0
	elif ratio > 0.28:
		band = 1
	var colorblind := _PlayerSettings.colorblind_palette
	if band == _hp_band and colorblind == _hp_colorblind:
		return
	_hp_band = band
	_hp_colorblind = colorblind
	var fill := Color(0.88, 0.24, 0.28)
	var border := Color(0.85, 0.28, 0.3, 0.95)
	if colorblind:
		if band == 0:
			fill = Color(0.95, 0.82, 0.18)
		elif band == 1:
			fill = Color(0.98, 0.55, 0.12)
		else:
			fill = Color(0.35, 0.72, 1.0)
		border = Color(0.95, 0.82, 0.18, 0.95)
	else:
		if band == 0:
			fill = Color(0.32, 0.78, 0.38)
			border = Color(0.4, 0.75, 0.42, 0.9)
		elif band == 1:
			fill = Color(0.92, 0.7, 0.2)
			border = Color(0.85, 0.62, 0.18, 0.95)
	_hp_fill.bg_color = fill
	if _hp_panel_style:
		_hp_panel_style.border_color = border


func _ensure_xp_bar() -> void:
	if _xp_panel != null:
		return
	_ensure_vitals_backing()
	_xp_panel = PanelContainer.new()
	_xp_panel.name = "XpBar"
	_xp_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_panel.visible = false
	_xp_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_xp_panel.offset_left = -130.0
	_xp_panel.offset_right = 130.0
	_xp_panel.offset_top = -164.0
	_xp_panel.offset_bottom = -128.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.05, 0.1, 0.84)
	panel_style.border_color = Color(0.62, 0.45, 0.95, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(6)
	_xp_panel.add_theme_stylebox_override("panel", panel_style)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_xp_panel.add_child(row)
	_xp_level_label = Label.new()
	_xp_level_label.name = "XpLevel"
	_xp_level_label.text = "Lv 1"
	_xp_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_level_label.custom_minimum_size = Vector2(44, 0)
	_xp_level_label.add_theme_font_size_override("font_size", 14)
	_xp_level_label.add_theme_color_override("font_color", Color(0.86, 0.78, 1.0))
	row.add_child(_xp_level_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XpFill"
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.show_percentage = false
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = float(_Progression.xp_to_advance(1))
	_xp_bar.value = 0.0
	_xp_bar.custom_minimum_size = Vector2(120, 14)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.1, 1.0)
	track.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("background", track)
	_xp_fill = StyleBoxFlat.new()
	_xp_fill.bg_color = _xp_fill_color()
	_xp_fill.set_corner_radius_all(3)
	_xp_bar.add_theme_stylebox_override("fill", _xp_fill)
	row.add_child(_xp_bar)
	_xp_value_label = Label.new()
	_xp_value_label.name = "XpValue"
	_xp_value_label.text = "0 / %d" % _Progression.xp_to_advance(1)
	_xp_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_value_label.custom_minimum_size = Vector2(72, 0)
	_xp_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_value_label.add_theme_font_size_override("font_size", 14)
	_xp_value_label.add_theme_color_override("font_color", Color(0.94, 0.92, 1.0))
	row.add_child(_xp_value_label)
	add_child(_xp_panel)


func _xp_fill_color() -> Color:
	if _PlayerSettings.colorblind_palette:
		return Color(0.35, 0.72, 1.0)
	return Color(0.62, 0.45, 0.95)


func _bind_xp_hud() -> void:
	if _xp_bound and _xp_service != null and is_instance_valid(_xp_service):
		return
	var svc = _Progression.get_active()
	if svc == null and is_inside_tree():
		svc = get_tree().get_first_node_in_group("progression_service")
	if svc == null:
		return
	if _xp_service != null and is_instance_valid(_xp_service) and _xp_service != svc:
		if _xp_service.has_signal("xp_gained") and _xp_service.xp_gained.is_connected(_on_xp_gained):
			_xp_service.xp_gained.disconnect(_on_xp_gained)
		if _xp_service.has_signal("level_up") and _xp_service.level_up.is_connected(_on_xp_level_up):
			_xp_service.level_up.disconnect(_on_xp_level_up)
	_xp_service = svc
	if svc.has_signal("xp_gained") and not svc.xp_gained.is_connected(_on_xp_gained):
		svc.xp_gained.connect(_on_xp_gained)
	if svc.has_signal("level_up") and not svc.level_up.is_connected(_on_xp_level_up):
		svc.level_up.connect(_on_xp_level_up)
	_xp_bound = true
	_apply_xp_bar()


func _on_xp_gained(_amount: int, _total: int) -> void:
	_apply_xp_bar()


func _on_xp_level_up(level: int) -> void:
	_apply_xp_bar()
	_show_beat("level_up", "Level up — %d" % level)


func _bind_skills() -> void:
	if _skills_bound:
		return
	var skills = get_tree().get_first_node_in_group("skill_service")
	if skills == null:
		return
	if skills.has_signal("skill_unlocked") and not skills.skill_unlocked.is_connected(_on_skill_unlocked_beat):
		skills.skill_unlocked.connect(_on_skill_unlocked_beat)
	_skills_bound = true


func _on_skill_unlocked_beat(skill_id: StringName) -> void:
	_show_beat("skill_unlock", "Skill unlocked — %s" % _skill_banner_name(skill_id))


func _skill_banner_name(skill_id: StringName) -> String:
	match skill_id:
		_Passives.FIGHTER:
			return "Tough"
		_Passives.MINER:
			return "Quick Mine"
		_Passives.BUILDER:
			return "Sturdy"
		&"dash":
			return "Dash"
		&"ground_slam":
			return "Ground Slam"
		&"crystal_pulse":
			return "Crystal Pulse"
		&"quick_wall":
			return "Quick Wall"
		_:
			return str(skill_id).replace("_", " ")


func _claim_crystal() -> void:
	if _crystal != null:
		return
	var found = get_tree().get_first_node_in_group("crystal_manager")
	if found is CrystalManager:
		_crystal = found


func _bind_crystal_beats() -> void:
	if _stage_bound:
		return
	var crystal = _crystal
	if crystal == null and is_inside_tree():
		crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_signal("spawn_damaged"):
		return
	if not crystal.spawn_damaged.is_connected(_on_crystal_stage):
		crystal.spawn_damaged.connect(_on_crystal_stage)
	_stage_bound = true


func _on_crystal_stage(spawn, amount: float) -> void:
	if not _is_crystal_heart(spawn):
		return
	var max_hp := float(spawn.max_health)
	if max_hp <= 0.0:
		return
	var after := float(spawn.health)
	var before := after + amount
	var lowest := -1
	for ratio in [0.75, 0.50, 0.25]:
		var mark := int(round(ratio * 100.0))
		if _stage_seen.has(mark):
			continue
		var line: float = max_hp * float(ratio)
		if before > line + 0.001 and after <= line + 0.001:
			_stage_seen[mark] = true
			lowest = mark
	if lowest < 0:
		return
	_show_beat("crystal_damage_stage", "Crystal cracked — %d%%" % lowest)


func _is_crystal_heart(spawn) -> bool:
	if spawn == null:
		return false
	if _GameConfig.SINGLE_CRYSTAL:
		return true
	if bool(spawn.get("is_boss")):
		return true
	return int(spawn.get("kind")) == _CrystalTypes.SpawnKind.ORIGIN


func _on_landmark_discovered(landmark_name: String) -> void:
	_show_beat("landmark_discovery", "Landmark — %s" % landmark_name)


func _update_xp_bar() -> void:
	if not _xp_bound or _xp_service == null or not is_instance_valid(_xp_service):
		_bind_xp_hud()
		return
	_apply_xp_bar()


func _apply_xp_bar() -> void:
	_ensure_xp_bar()
	if _xp_panel == null or _xp_service == null or not is_instance_valid(_xp_service):
		return
	if not _Progression.XP_ENABLED:
		_xp_panel.visible = false
		return
	_xp_panel.visible = true
	var level := int(_xp_service.get("level"))
	var xp_now := int(_xp_service.get("xp"))
	var need := maxi(_Progression.xp_to_advance(level), 1)
	_xp_bar.max_value = float(need)
	_xp_bar.value = clampf(float(xp_now), 0.0, float(need))
	if level != _xp_shown_level:
		_xp_shown_level = level
		_xp_level_label.text = "Lv %d" % level
	if xp_now != _xp_shown or need != _xp_shown_need:
		_xp_shown = xp_now
		_xp_shown_need = need
		_xp_value_label.text = "%d / %d" % [xp_now, need]
	if _xp_fill:
		_xp_fill.bg_color = _xp_fill_color()


func _cached_player() -> Node:
	if _hud_player != null and is_instance_valid(_hud_player):
		return _hud_player
	_hud_player = get_tree().get_first_node_in_group("player")
	return _hud_player


func _ensure_objective_hud() -> void:
	if _objective_panel != null:
		return
	_objective_panel = PanelContainer.new()
	_objective_panel.name = "ObjectiveHud"
	_objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := _HudLayout.load_active()
	var spot := layout.objective_rect()
	_objective_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_objective_panel.offset_left = spot.position.x
	_objective_panel.offset_top = spot.position.y
	_objective_panel.offset_right = spot.end.x
	_objective_panel.offset_bottom = spot.end.y
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.04, 0.1, 0.78)
	panel_style.border_color = Color(0.62, 0.32, 0.9, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_content_margin_all(8)
	_objective_panel.add_theme_stylebox_override("panel", panel_style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_objective_panel.add_child(box)
	var title := Label.new()
	title.text = "OBJECTIVE"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0))
	box.add_child(title)
	_objective_phase = _objective_line(box, "Phase: Maze")
	_objective_spawns = _objective_line(box, "Destroy the crystal" if _GameConfig.SINGLE_CRYSTAL else "Spawns: — remaining")
	_objective_coverage = _objective_line(box, "Crystal: 0.00%")
	if _GameConfig.SINGLE_CRYSTAL:
		_ensure_crystal_hp_bar(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	_objective_arrow = Label.new()
	_objective_arrow.name = "SpawnArrow"
	_objective_arrow.text = "▲"
	_objective_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_arrow.custom_minimum_size = Vector2(28, 28)
	_objective_arrow.pivot_offset = Vector2(14, 14)
	_objective_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_objective_arrow.add_theme_font_size_override("font_size", 20)
	_objective_arrow.add_theme_color_override("font_color", Color(0.95, 0.75, 1.0))
	row.add_child(_objective_arrow)
	_objective_bearing = _objective_line(row, "Crystal" if _GameConfig.SINGLE_CRYSTAL else "Nearest spawn")
	add_child(_objective_panel)


func _ensure_crystal_hp_bar(box: Node) -> void:
	if _crystal_hp_bar != null:
		return
	_crystal_hp_label = _objective_line(box, "Crystal HP")
	_crystal_hp_bar = ProgressBar.new()
	_crystal_hp_bar.name = "CrystalHpBar"
	_crystal_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crystal_hp_bar.show_percentage = false
	_crystal_hp_bar.min_value = 0.0
	_crystal_hp_bar.max_value = 1.0
	_crystal_hp_bar.value = 1.0
	_crystal_hp_bar.custom_minimum_size = Vector2(220, 12)
	box.add_child(_crystal_hp_bar)
	if _objective_panel:
		var layout := _HudLayout.load_active()
		_objective_panel.offset_bottom = layout.objective_rect().end.y


func _objective_line(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.98))
	parent.add_child(label)
	return label


func _update_objective_hud() -> void:
	if _objective_panel == null:
		_ensure_objective_hud()
	if _objective_panel == null:
		return
	if _hud_should_skip():
		_objective_panel.visible = true
		_spin_objective_arrow()
		return
	_objective_panel.visible = true
	var phase_name := "Maze"
	var playing := true
	if _game_manager:
		playing = _game_manager.run_state == _GameManager.RunState.PLAYING
		if _game_manager.run_state == _GameManager.RunState.WON:
			phase_name = "Victory"
		elif _game_manager.run_state == _GameManager.RunState.LOST:
			phase_name = "Defeat"
		elif _game_manager.phase == _GameManager.Phase.ASSAULT:
			phase_name = "Assault"
		elif _game_manager.phase == _GameManager.Phase.VICTORY:
			phase_name = "Victory"
	var active := 0
	var total := 0
	var crystal_hp := 0.0
	var crystal_max := 0.0
	var boss_warning := false
	if _crystal and _crystal.has_method("get_spawn_progress"):
		var prog: Dictionary = _crystal.get_spawn_progress()
		active = int(prog.get("active", 0))
		total = int(prog.get("total", 0))
		crystal_hp = float(prog.get("crystal_health", 0.0))
		crystal_max = float(prog.get("crystal_max_health", 0.0))
		boss_warning = _boss_warning_on(prog)
		if _GameConfig.SINGLE_CRYSTAL:
			_note_boss_warning(boss_warning)
	var coverage := 0.0
	var tiles := 0
	if _crystal and _crystal.has_method("get_coverage_ratio"):
		coverage = float(_crystal.get_coverage_ratio())
	if _crystal and "covered_cells" in _crystal:
		tiles = int(_crystal.covered_cells)
	var bearing := _nearest_spawn_bearing()
	var lines := build_objective_lines(phase_name, active, total, coverage, tiles, bearing.text)
	if _GameConfig.SINGLE_CRYSTAL:
		lines = build_single_crystal_objective_lines(phase_name, crystal_hp, crystal_max, coverage, tiles, bearing.text, boss_warning)
		_apply_crystal_hp_bar(crystal_hp, crystal_max)
	var parts := lines.split("\n")
	if parts.size() >= 4:
		_objective_phase.text = parts[0]
		_objective_spawns.text = parts[1]
		_objective_coverage.text = parts[2]
		if _game_manager and _game_manager.has_method("coverage_hud_note"):
			var cap_note: String = str(_game_manager.coverage_hud_note(coverage))
			if cap_note != "":
				_objective_coverage.text = "%s · %s" % [_objective_coverage.text, cap_note]
		_objective_bearing.text = parts[3]
	if _objective_arrow:
		_objective_arrow.rotation = bearing.rotation
		_objective_arrow.modulate = _arrow_play_color if playing else Color(0.7, 0.7, 0.75)


static func build_objective_lines(
	phase_name: String,
	spawns_remaining: int,
	spawns_total: int,
	coverage_ratio: float,
	tiles: int,
	bearing_text: String
) -> String:
	var pct := coverage_ratio * 100.0
	var cov := "Crystal: %.2f%%" % pct
	if tiles > 0:
		cov = "%s · %d tiles" % [cov, tiles]
	var spawns := "Spawns: %d remaining" % spawns_remaining
	if spawns_total > 0:
		spawns = "%s (%d/%d)" % [spawns, spawns_remaining, spawns_total]
	var bearing := bearing_text if bearing_text != "" else "Nearest spawn: —"
	return "Phase: %s\n%s\n%s\n%s" % [phase_name, spawns, cov, bearing]


static func build_single_crystal_objective_lines(
	phase_name: String,
	health: float,
	max_health: float,
	coverage_ratio: float,
	tiles: int,
	bearing_text: String,
	boss_warning: bool
) -> String:
	var goal := "Destroy the crystal"
	if max_health > 0.0:
		goal = "Destroy the crystal  %d/%d" % [int(round(health)), int(round(max_health))]
	if boss_warning:
		goal += " · Boss warning"
	var pct := coverage_ratio * 100.0
	var cov := "Crystal: %.2f%%" % pct
	if tiles > 0:
		cov = "%s · %d tiles" % [cov, tiles]
	var bearing := bearing_text if bearing_text != "" else "Crystal: —"
	bearing = bearing.replace("Nearest spawn:", "Crystal:")
	return "Phase: %s\n%s\n%s\n%s" % [phase_name, goal, cov, bearing]


func _apply_crystal_hp_bar(health: float, max_health: float) -> void:
	if _crystal_hp_bar == null:
		return
	var mx := maxf(max_health, 1.0)
	_crystal_hp_bar.max_value = mx
	_crystal_hp_bar.value = clampf(health, 0.0, mx)
	if _crystal_hp_label:
		_crystal_hp_label.text = "Crystal HP  %d / %d" % [int(round(health)), int(round(mx))]


static func compass_from_delta(dx: float, dz: float) -> String:
	var dist := Vector2(dx, dz).length()
	if dist < 6.0:
		return "Nearest spawn: here"
	var deg := rad_to_deg(atan2(dx, -dz))
	if deg < 0.0:
		deg += 360.0
	var dirs: PackedStringArray = PackedStringArray(["N", "NE", "E", "SE", "S", "SW", "W", "NW"])
	var idx := int(round(deg / 45.0)) % 8
	return "Nearest spawn: %s  %.0fc" % [dirs[idx], dist]


static func arrow_rotation(world_delta: Vector2, cam_forward: Vector2, cam_right: Vector2) -> float:
	if world_delta.length_squared() < 0.25:
		return 0.0
	var d := world_delta.normalized()
	var f := cam_forward
	if f.length_squared() < 0.0001:
		return 0.0
	f = f.normalized()
	var r := cam_right
	if r.length_squared() < 0.0001:
		r = Vector2(f.y, -f.x)
	else:
		r = r.normalized()
	return atan2(d.dot(r), d.dot(f))


func _spin_objective_arrow() -> void:
	if _objective_arrow == null or not _spawn_known:
		return
	var player := _cached_player()
	if player == null or not player.has_method("get_voxel_position"):
		return
	var pv: Vector3 = player.get_voxel_position()
	var dx := float(_spawn_cell.x) + 0.5 - pv.x
	var dz := float(_spawn_cell.y) + 0.5 - pv.z
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	_objective_arrow.rotation = arrow_rotation(Vector2(dx, dz), Vector2(fwd.x, fwd.z), Vector2(right.x, right.z))


func _nearest_spawn_bearing() -> Dictionary:
	var empty := {"text": "Crystal: —" if _GameConfig.SINGLE_CRYSTAL else "Nearest spawn: —", "rotation": 0.0}
	_spawn_known = false
	var player := _cached_player() if is_inside_tree() else null
	if player == null or not player.has_method("get_voxel_position"):
		return empty
	var pv: Vector3 = player.get_voxel_position()
	var cell := Vector2i(999999, 999999)
	if _crystal and _crystal.has_method("get_nearest_active_spawn"):
		var info: Dictionary = _crystal.get_nearest_active_spawn(Vector2(pv.x, pv.z))
		if info.is_empty():
			return empty
		cell = info.get("cell", cell)
	elif _crystal and _crystal.has_method("get_origin_cell"):
		cell = _crystal.get_origin_cell()
	if cell.x == 999999:
		return empty
	_spawn_cell = cell
	_spawn_known = true
	var dx := float(cell.x) + 0.5 - pv.x
	var dz := float(cell.y) + 0.5 - pv.z
	var text := compass_from_delta(dx, dz)
	if _GameConfig.SINGLE_CRYSTAL:
		text = text.replace("Nearest spawn:", "Crystal:")
	var rotation := 0.0
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		var fwd := -cam.global_transform.basis.z
		var right := cam.global_transform.basis.x
		rotation = arrow_rotation(Vector2(dx, dz), Vector2(fwd.x, fwd.z), Vector2(right.x, right.z))
	return {"text": text, "rotation": rotation}


func _wet_crawl_bit() -> String:
	if _crystal == null or not _crystal.has_method("count_wet_crystal_near"):
		return ""
	var player := _cached_player()
	if player == null or not player.has_method("get_voxel_position"):
		return ""
	var pv: Vector3 = player.get_voxel_position()
	var info: Dictionary = _crystal.count_wet_crystal_near(floori(pv.x), floori(pv.z), 5)
	if int(info.get("wet", 0)) <= 0:
		return ""
	return "wet crawl"


func _crystal_bearing_bit() -> String:
	if _crystal == null or not _crystal.has_method("get_origin_cell"):
		return ""
	var player := _cached_player()
	if player == null or not player.has_method("get_voxel_position"):
		return ""
	var pv: Vector3 = player.get_voxel_position()
	var origin: Vector2i = _crystal.get_origin_cell()
	var dx := float(origin.x) - pv.x
	var dz := float(origin.y) - pv.z
	var dist := Vector2(dx, dz).length()
	if dist < 4.0:
		return "front"
	var deg := rad_to_deg(atan2(dx, -dz))
	if deg < 0.0:
		deg += 360.0
	var dirs: PackedStringArray = PackedStringArray(["N", "NE", "E", "SE", "S", "SW", "W", "NW"])
	var idx := int(round(deg / 45.0)) % 8
	return "%.0fc %s" % [dist, dirs[idx]]


func _on_phase_changed(new_phase: int) -> void:
	_update_map_temp_label()
	if _game_manager and _game_manager.run_state != _GameManager.RunState.PLAYING:
		return
	if new_phase == _GameManager.Phase.ASSAULT:
		_phase_label_pulse = 2.2
		if not _assault_toast_shown:
			_assault_toast_shown = true
			_show_toast("ASSAULT — you are on the purple front. Fight or pull back and rebuild")
	elif new_phase == _GameManager.Phase.MAZE and _last_phase_for_toast == int(_GameManager.Phase.ASSAULT):
		_show_toast("Maze again — distance bought time. Reshape, then re-engage")
	_last_phase_for_toast = new_phase


static func loss_panel_lines(reason: String) -> PackedStringArray:
	var why := reason.strip_edges()
	if why == "":
		why = "You died."
	var title := "You died" if why == "You died." else why.trim_suffix(".")
	return PackedStringArray([title, "%s\nPress R to restart." % why])


func _on_run_state_changed(new_state: int) -> void:
	_panel.visible = true
	if new_state == _GameManager.RunState.WON:
		_show_beat("win", _win_banner())
		if _GameConfig.SINGLE_CRYSTAL and _victory_reason() != "boss":
			_title.text = "Victory — Crystal Destroyed"
			_subtitle.text = "You destroyed the crystal.\nPress R to restart."
		elif _victory_reason() == "boss":
			_title.text = "Victory — Origin Warden Fell"
			_subtitle.text = "The warden is down. The storm breaks.\nPress R to restart."
		else:
			_title.text = "Victory — Crystal Shattered"
			var prog := ""
			if _crystal and _crystal.has_method("get_spawn_progress"):
				var p: Dictionary = _crystal.get_spawn_progress()
				prog = "\nAll %d spawn points destroyed." % int(p.get("total", 0))
			_subtitle.text = "You shattered every crystal heart.%s\nPress R to restart." % prog
	elif new_state == _GameManager.RunState.LOST:
		var reason := ""
		if _game_manager and "last_loss_reason" in _game_manager:
			reason = str(_game_manager.last_loss_reason)
		var lines := loss_panel_lines(reason)
		_title.text = lines[0]
		_subtitle.text = lines[1]
	if new_state == _GameManager.RunState.WON or new_state == _GameManager.RunState.LOST:
		_show_run_summary()
	_update_map_temp_label()


func _maybe_show_tutorial() -> void:
	if not _TutorialOverlay.should_show():
		return
	_TutorialOverlay.open(get_tree(), false)


func apply_hud_palette(colorblind: bool) -> void:
	_arrow_play_color = _CrystalPalette.hud_arrow(colorblind)
	if _objective_arrow:
		_objective_arrow.add_theme_color_override("font_color", _arrow_play_color)
		_objective_arrow.modulate = _arrow_play_color
	if _boss_label:
		_boss_label.add_theme_color_override("font_color", _CrystalPalette.boss_label_color(colorblind))
	if _hp_fill != null:
		_hp_colorblind = not colorblind
		_hp_band = -1
		if _hp_last_max > 0.0:
			_paint_hp_fill(clampf(_hp_last / _hp_last_max, 0.0, 1.0))
	if _xp_fill != null:
		_xp_fill.bg_color = _xp_fill_color()


func _show_run_summary() -> void:
	if _game_manager == null or not _game_manager.has_method("run_summary"):
		return
	if _run_summary == null:
		_run_summary = _RunSummaryPanel.new()
		_run_summary.name = "RunSummary"
		var box := get_node_or_null("Panel/VBox")
		if box:
			box.add_child(_run_summary)
		else:
			add_child(_run_summary)
	_panel.offset_left = -260.0
	_panel.offset_right = 260.0
	_panel.offset_top = -230.0
	_panel.offset_bottom = 230.0
	_run_summary.show_summary(_game_manager.run_summary())
