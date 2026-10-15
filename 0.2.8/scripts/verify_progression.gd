extends SceneTree

const _Progression = preload("res://systems/progression_service.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_flag_and_curve()
	_check_level_up()
	_check_registered()
	_check_source_amounts()
	_check_source_wiring()
	await _check_level_rewards()
	await _check_live_sources()
	await _check_xp_hud()
	if _failed == 0:
		print("All progression tests OK")
		quit(0)
	else:
		push_error("verify_progression: %d failure(s)" % _failed)
		quit(1)


func _check_flag_and_curve() -> void:
	if not _Progression.XP_ENABLED:
		_fail("XP_ENABLED must default true")
	if _Progression.xp_to_advance(1) != 50:
		_fail("level 1 threshold %d want 50" % _Progression.xp_to_advance(1))
	if _Progression.xp_to_advance(4) != 400:
		_fail("level 4 threshold %d want 400" % _Progression.xp_to_advance(4))
	if _Progression.xp_to_advance(0) != 50:
		_fail("level 0 must use the level 1 threshold")
	for lv in [2, 3, 10]:
		var expect := int(round(50.0 * pow(float(lv), 1.5)))
		var got := _Progression.xp_to_advance(lv)
		if got != expect:
			_fail("level %d threshold %d want %d" % [lv, got, expect])
	if _failed == 0:
		print("OK curve 50 * level^1.5")


func _check_level_up() -> void:
	var svc = _Progression.new()
	var gained: Array = []
	var ups: Array = []
	svc.xp_gained.connect(func(amount: int, total: int) -> void: gained.append([amount, total]))
	svc.level_up.connect(func(lv: int) -> void: ups.append(lv))
	svc.add_xp(0)
	svc.add_xp(-3)
	if svc.xp != 0 or svc.level != 1 or svc.skill_points != 0 or not gained.is_empty() or not ups.is_empty():
		_fail("non-positive xp must not move the bar")
		return
	svc.add_xp(49)
	if svc.level != 1 or svc.xp != 49 or ups.size() != 0 or gained != [[49, 49]]:
		_fail("49 xp should stay level 1, got level %d xp %d" % [svc.level, svc.xp])
		return
	svc.add_xp(1)
	if svc.level != 2 or svc.xp != 0 or svc.skill_points != 1 or ups != [2]:
		_fail("50 xp should reach level 2, got level %d xp %d ups %s" % [svc.level, svc.xp, str(ups)])
		return
	var fresh = _Progression.new()
	var multi: Array = []
	fresh.level_up.connect(func(lv: int) -> void: multi.append(lv))
	var into_3 := _Progression.xp_to_advance(1) + _Progression.xp_to_advance(2)
	fresh.add_xp(into_3)
	if fresh.level != 3 or fresh.xp != 0 or fresh.skill_points != 2 or multi != [2, 3]:
		_fail("stacked grant should reach level 3, got level %d xp %d ups %s" % [fresh.level, fresh.xp, str(multi)])
		return
	var spare := _Progression.xp_to_advance(3) - 1
	fresh.add_xp(spare)
	if fresh.level != 3 or fresh.xp != spare or fresh.skill_points != 2:
		_fail("remainder under the next threshold drifted")
		return
	print("OK level-up")


func _check_registered() -> void:
	var root_src := FileAccess.get_file_as_string("res://systems/composition_root.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/main.tscn")
	if not root_src.contains("ID_PROGRESSION") or not root_src.contains("_register_progression"):
		_fail("composition root does not register progression")
	elif not root_src.contains("&\"progression_service\""):
		_fail("progression service id missing")
	elif not scene_src.contains("ProgressionService") or not scene_src.contains("res://systems/progression_service.gd"):
		_fail("main scene is missing ProgressionService")
	else:
		print("OK progression registered")


func _check_source_amounts() -> void:
	if _Progression.xp_for_kill(0) != 8 or _Progression.xp_for_kill(2) != 20 or _Progression.xp_for_kill(4) != 32:
		_fail("kill xp drifted from 8 + 6 * tier")
		return
	if _Progression.xp_for_kill(-1) != 0:
		_fail("negative kill tier must grant no xp")
		return
	if _Progression.kill_tier(&"origin_warden") != 4 or _Progression.kill_tier(&"shard_guard") != 2:
		_fail("named kill tiers drifted")
		return
	if _Progression.kill_tier(&"town_militia") != -1 or _Progression.kill_tier(&"no_such_kind") != 0:
		_fail("friendly or unknown kill tier drifted")
		return
	if _Progression.xp_for_crystal_hit(0.0, false) != 0:
		_fail("an empty crystal hit must grant no xp")
		return
	if _Progression.xp_for_crystal_hit(0.4, false) != _Progression.XP_CRYSTAL_HIT:
		_fail("crystal hit xp drifted")
		return
	var broken_xp := _Progression.XP_CRYSTAL_HIT + _Progression.XP_CRYSTAL_CELL
	if _Progression.xp_for_crystal_hit(0.4, true) != broken_xp:
		_fail("broken crystal cell xp drifted")
		return
	if _Progression.XP_BLOCK_MINED != 1 or _Progression.XP_STRUCTURE_PLACED != 12:
		_fail("mine or place amounts drifted")
		return
	if _Progression.XP_RUIN_DISCOVERED != 25 or _Progression.XP_POI_DISCOVERED != 20:
		_fail("discovery amounts drifted")
		return
	print("OK xp source amounts")


func _check_source_wiring() -> void:
	var gm := FileAccess.get_file_as_string("res://game/game_manager.gd")
	var rewards := FileAccess.get_file_as_string("res://helpers/combat_rewards.gd")
	var weapon := FileAccess.get_file_as_string("res://weapons/weapon_controller.gd")
	if "kill_tier" not in rewards or "note_enemy_killed" not in rewards:
		_fail("kills must pass a tier into note_enemy_killed")
		return
	if "note_blocks_mined" not in weapon:
		_fail("the dig stroke must note blocks mined")
		return
	var hooks := ["note_crystal_damaged", "note_structure_placed", "note_ruin_discovered", "note_poi_discovered"]
	for hook in hooks:
		if hook not in gm:
			_fail("game manager is missing %s" % hook)
			return
	if "structure_built" not in gm or "ruin_discovered" not in gm or "crystal_mass_hit" not in gm:
		_fail("xp sources are not bound to the existing signals")
		return
	print("OK xp sources wired")


func _check_live_sources() -> void:
	var svc := _Progression.new()
	root.add_child(svc)
	var crystal := _CrystalStub.new()
	root.add_child(crystal)
	crystal.add_to_group("crystal_manager")
	var player := Node3D.new()
	root.add_child(player)
	player.add_to_group("player")
	var weapon := _WeaponStub.new()
	weapon.name = "WeaponController"
	player.add_child(weapon)
	var living := _LivingStub.new()
	root.add_child(living)
	living.add_to_group("living_world_director")
	var gm_script = load("res://game/game_manager.gd")
	var gm = gm_script.new()
	root.add_child(gm)
	for _i in 12:
		await process_frame
		if gm._structure_xp_bound and gm._discovery_xp_bound and gm._stats_bound:
			break
	if not gm._structure_xp_bound or not gm._discovery_xp_bound or not gm._stats_bound:
		_fail("xp source signals did not bind")
		return
	gm.note_enemy_killed(1)
	if gm.enemies_killed != 1 or svc.xp != _Progression.xp_for_kill(1):
		_fail("tier 1 kill xp is %d" % svc.xp)
		return
	var after_kill := svc.xp
	gm.note_enemy_killed(-1)
	if gm.enemies_killed != 2 or svc.xp != after_kill:
		_fail("friendly kill should count and grant no xp")
		return
	crystal.crystal_mass_hit.emit(Vector3.ZERO, 0.4, true)
	var after_crystal := after_kill + _Progression.xp_for_crystal_hit(0.4, true)
	if gm.crystal_cells_broken != 1 or svc.xp != after_crystal:
		_fail("crystal hit left xp %d broken %d" % [svc.xp, gm.crystal_cells_broken])
		return
	weapon.structure_built.emit(&"wall_segment", Vector3.ZERO)
	weapon.structure_built.emit(&"repair", Vector3.ZERO)
	if gm.structures_placed != 1 or svc.xp != after_crystal + _Progression.XP_STRUCTURE_PLACED:
		_fail("structure place xp drifted, placed %d xp %d" % [gm.structures_placed, svc.xp])
		return
	living.ruin_discovered.emit("Forgotten Ruin", Vector2i(3, 4), 6.0)
	living.poi_discovered.emit("Cache")
	gm.note_blocks_mined(4)
	gm.note_blocks_mined(0)
	var total := _Progression.xp_for_kill(1) + _Progression.xp_for_crystal_hit(0.4, true)
	total += _Progression.XP_STRUCTURE_PLACED + _Progression.XP_RUIN_DISCOVERED + _Progression.XP_POI_DISCOVERED
	total += 4 * _Progression.XP_BLOCK_MINED
	var expect_level := 1
	var remain := total
	while remain >= _Progression.xp_to_advance(expect_level):
		remain -= _Progression.xp_to_advance(expect_level)
		expect_level += 1
	if gm.ruins_discovered != 1 or gm.pois_discovered != 1 or gm.blocks_mined != 4:
		_fail("discovery or mine counters drifted")
		return
	if svc.level != expect_level or svc.xp != remain or svc.skill_points != expect_level - 1:
		_fail("source total drifted, level %d xp %d points %d want level %d xp %d" % [svc.level, svc.xp, svc.skill_points, expect_level, remain])
		return
	print("OK xp source grants")


func _check_level_rewards() -> void:
	var stats_script = load("res://stats/stat_component.gd")
	var relic_script = load("res://relics/relic_manager.gd")
	var ids = load("res://stats/stat_ids.gd")
	var player := Node3D.new()
	player.name = "Player"
	var stats = stats_script.new()
	stats.name = "StatComponent"
	player.add_child(stats)
	var relics = relic_script.new()
	relics.name = "RelicManager"
	player.add_child(relics)
	root.add_child(player)
	player.add_to_group("player")
	var svc = _Progression.new()
	root.add_child(svc)
	for _i in 8:
		await process_frame
		if stats.sheet != null and relics.get("_stat_component") != null:
			break
	if stats.sheet == null:
		_fail("stat sheet was not ready for level rewards")
		return
	if not is_equal_approx(stats.get_stat(ids.MAX_HEALTH), 100.0):
		_fail("level 1 max health drifted")
		return
	if svc.skill_points != 0 or not svc.level_reward_modifiers().is_empty():
		_fail("level 1 must store no reward")
		return
	svc.add_xp(_Progression.xp_to_advance(1))
	if svc.level != 2 or svc.skill_points != 1:
		_fail("first level reward did not store a skill point")
		return
	if not is_equal_approx(stats.get_stat(ids.MAX_HEALTH), 100.0 + _Progression.HP_PER_LEVEL):
		_fail("level 2 max health is %s" % stats.get_stat(ids.MAX_HEALTH))
		return
	if not is_equal_approx(stats.get_stat(ids.MELEE_DAMAGE), 1.0 + _Progression.DAMAGE_PER_LEVEL):
		_fail("level 2 melee damage drifted")
		return
	if not is_equal_approx(stats.get_stat(ids.RANGED_DAMAGE), 1.0 + _Progression.DAMAGE_PER_LEVEL):
		_fail("level 2 ranged damage drifted")
		return
	if not is_equal_approx(stats.get_stat(ids.DIG_SPEED), 1.0 + _Progression.DIG_SPEED_PER_LEVEL):
		_fail("level 2 dig speed drifted")
		return
	svc.apply_level_rewards(stats)
	if not is_equal_approx(stats.get_stat(ids.MAX_HEALTH), 100.0 + _Progression.HP_PER_LEVEL):
		_fail("applying the level reward twice stacked max health")
		return
	if not relics.equip(&"mason_glove"):
		_fail("mason glove did not equip beside the level reward")
		return
	var dig_with_glove := (1.0 + _Progression.DIG_SPEED_PER_LEVEL) * 1.35
	if not is_equal_approx(stats.get_stat(ids.DIG_SPEED), dig_with_glove):
		_fail("dig speed did not keep the relic and the level reward, got %s" % stats.get_stat(ids.DIG_SPEED))
		return
	svc.add_xp(_Progression.xp_to_advance(2))
	var two := 2.0
	if svc.skill_points != 2:
		_fail("second level did not store another skill point")
		return
	if not is_equal_approx(stats.get_stat(ids.MAX_HEALTH), 100.0 + _Progression.HP_PER_LEVEL * two):
		_fail("two levels of max health drifted")
		return
	if not is_equal_approx(stats.get_stat(ids.MELEE_DAMAGE), 1.0 + _Progression.DAMAGE_PER_LEVEL * two):
		_fail("two levels of damage drifted")
		return
	if not is_equal_approx(stats.get_stat(ids.DIG_SPEED), (1.0 + _Progression.DIG_SPEED_PER_LEVEL * two) * 1.35):
		_fail("two levels of dig speed dropped the relic")
		return
	root.remove_child(player)
	player.free()
	root.remove_child(svc)
	svc.free()
	print("OK level rewards")


func _drop_group(group_name: String) -> void:
	for node in get_nodes_in_group(group_name):
		if is_instance_valid(node):
			node.free()


func _check_xp_hud() -> void:
	for group_name in ["crystal_manager", "game_manager", "player", "living_world_director", "progression_service", "game_overlay"]:
		_drop_group(group_name)
	await process_frame
	var svc := _Progression.new()
	root.add_child(svc)
	var packed: PackedScene = load("res://ui/game_overlay.tscn")
	if packed == null:
		_fail("game overlay scene missing")
		svc.queue_free()
		return
	var overlay: Node = packed.instantiate()
	root.add_child(overlay)
	for _i in 4:
		await process_frame
	var bar := overlay.get_node_or_null("XpBar/Row/XpFill") as ProgressBar
	var level_label := overlay.get_node_or_null("XpBar/Row/XpLevel") as Label
	var value_label := overlay.get_node_or_null("XpBar/Row/XpValue") as Label
	if bar == null or level_label == null or value_label == null:
		_fail("xp bar nodes missing")
		overlay.queue_free()
		svc.queue_free()
		return
	if int(bar.max_value) != 50 or int(bar.value) != 0 or level_label.text != "Lv 1" or value_label.text != "0 / 50":
		_fail("xp bar start is %s %s value %s/%s" % [level_label.text, value_label.text, str(bar.value), str(bar.max_value)])
	svc.add_xp(20)
	await process_frame
	if int(bar.value) != 20 or value_label.text != "20 / 50" or level_label.text != "Lv 1":
		_fail("xp bar after 20 is %s %s" % [level_label.text, value_label.text])
	svc.add_xp(30)
	await process_frame
	var toast := overlay.get_node_or_null("ToastLabel") as Label
	var need := _Progression.xp_to_advance(2)
	if level_label.text != "Lv 2" or int(bar.value) != 0 or int(bar.max_value) != need:
		_fail("level-up bar is %s %s/%s" % [level_label.text, str(bar.value), str(bar.max_value)])
	if toast == null or not toast.visible or toast.text != "Level up — 2":
		_fail("level-up toast is %s" % (toast.text if toast else "missing"))
	else:
		print("OK xp hud")
	overlay.queue_free()
	svc.queue_free()
	await process_frame


class _CrystalStub extends Node:
	var strength_tier: int = 0
	signal all_spawns_destroyed
	signal crystal_touched_player
	signal spawn_destroyed
	signal crystal_mass_hit(world_pos: Vector3, amount: float, broken: bool)


class _WeaponStub extends Node:
	signal structure_built(build_id: StringName, world_pos: Vector3)


class _LivingStub extends Node:
	signal ruin_discovered(ruin_name: String, center: Vector2i, power_bonus: float)
	signal poi_discovered(poi_name: String)
