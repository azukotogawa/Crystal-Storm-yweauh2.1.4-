extends SceneTree

const _Skills = preload("res://systems/skill_service.gd")
const _Progression = preload("res://systems/progression_service.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_flag_and_shape()
	_check_registered()
	_check_unlock_and_slots()
	_check_cooldowns()
	_check_hotkeys()
	_check_save_round_trip()
	_check_dash()
	_check_ground_slam()
	_check_crystal_pulse()
	_check_quick_wall()
	_check_passives()
	_check_skill_tree()
	if _failed == 0:
		print("All skills tests OK")
		quit(0)
	else:
		push_error("verify_skills: %d failure(s)" % _failed)
		quit(1)


func _check_flag_and_shape() -> void:
	if not _Skills.SKILLS_ENABLED:
		_fail("SKILLS_ENABLED must default true")
		return
	if _Skills.ACTIVE_SLOTS != 3 or _Skills.HOTKEY_ACTIONS.size() != 3:
		_fail("active slots must be 3")
		return
	if _Skills.HOTKEY_ACTIONS != ["skill_1", "skill_2", "skill_3"]:
		_fail("hotkey actions drifted")
		return
	var project := FileAccess.get_file_as_string("res://project.godot")
	if not project.contains("skill_1=") or not project.contains("skill_2=") or not project.contains("skill_3="):
		_fail("project input is missing skill hotkeys")
		return
	if project.find("physical_keycode\":67") < 0 or project.find("physical_keycode\":72") < 0 or project.find("physical_keycode\":74") < 0:
		_fail("skill hotkeys must be C, H, and J")
		return
	for tree in [_Skills.TREE_FIGHTER, _Skills.TREE_MINER, _Skills.TREE_BUILDER]:
		var ids: Array = _Skills.new().tree_ids(tree)
		if ids.size() < 1:
			_fail("tree %s is empty" % String(tree))
			return
	if not _Skills.CATALOG.has(&"dash") or not _Skills.CATALOG.has(&"ground_slam"):
		_fail("starter catalog is missing the planned actives")
		return
	if not _Skills.CATALOG.has(&"crystal_pulse") or not _Skills.CATALOG.has(&"quick_wall"):
		_fail("starter catalog is missing crystal pulse or quick wall")
		return
	print("OK skills flag and 3 slots")


func _check_registered() -> void:
	var root_src := FileAccess.get_file_as_string("res://systems/composition_root.gd")
	var scene_src := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var save_src := FileAccess.get_file_as_string("res://systems/save_game_service.gd")
	if not root_src.contains("ID_SKILLS") or not root_src.contains("_register_skills"):
		_fail("composition root does not register skills")
	elif not root_src.contains("&\"skill_service\""):
		_fail("skill service id missing")
	elif not scene_src.contains("SkillService") or not scene_src.contains("res://systems/skill_service.gd"):
		_fail("main scene is missing SkillService")
	elif not save_src.contains("snapshot[\"skills\"]") or not save_src.contains("skills.import_state"):
		_fail("run save does not store skills")
	else:
		print("OK skills registered")


func _host() -> Node:
	var host := Node.new()
	host.name = "SkillHost"
	root.add_child(host)
	return host


func _pair(points: int):
	var host := _host()
	var prog = _Progression.new()
	var skills = _Skills.new()
	host.add_child(prog)
	host.add_child(skills)
	prog.skill_points = points
	return {"host": host, "prog": prog, "skills": skills}


func _drop(pair: Dictionary) -> void:
	var host: Node = pair.host
	host.free()


func _check_unlock_and_slots() -> void:
	var dry = _pair(0)
	if dry.skills.unlock(&"dash"):
		_fail("unlock must refuse when progression has no skill points")
		_drop(dry)
		return
	if dry.prog.skill_points != 0:
		_fail("a refused unlock spent a point")
		_drop(dry)
		return
	_drop(dry)
	var pair = _pair(2)
	var skills = pair.skills
	var prog = pair.prog
	if skills.unlock(&"no_such_skill"):
		_fail("unknown skill unlocked")
		_drop(pair)
		return
	if not skills.unlock(&"dash") or prog.skill_points != 1 or not skills.is_unlocked(&"dash"):
		_fail("dash unlock did not spend one progression point")
		_drop(pair)
		return
	if skills.unlock(&"dash") or prog.skill_points != 1:
		_fail("a second unlock spent another point")
		_drop(pair)
		return
	if skills.equip(0, &"ground_slam"):
		_fail("a locked skill equipped")
		_drop(pair)
		return
	if not skills.unlock(&"fighter_passive") or prog.skill_points != 0:
		_fail("passive unlock did not spend the last point")
		_drop(pair)
		return
	if skills.equip(0, &"fighter_passive"):
		_fail("a passive took an active slot")
		_drop(pair)
		return
	if not skills.equip(0, &"dash") or skills.slot_skill(0) != &"dash":
		_fail("dash did not equip into slot 0")
		_drop(pair)
		return
	if skills.equip(1, &"dash"):
		_fail("the same skill equipped twice")
		_drop(pair)
		return
	if skills.equip(3, &"dash"):
		_fail("slot 3 exists")
		_drop(pair)
		return
	_drop(pair)
	var rich = _pair(3)
	rich.skills.unlock(&"dash")
	rich.skills.unlock(&"ground_slam")
	rich.skills.unlock(&"crystal_pulse")
	if not rich.skills.equip(0, &"dash") or not rich.skills.equip(1, &"ground_slam") or not rich.skills.equip(2, &"crystal_pulse"):
		_fail("three actives did not fill the slots")
		_drop(rich)
		return
	if rich.prog.skill_points != 0:
		_fail("three unlocks left points behind")
		_drop(rich)
		return
	_drop(rich)
	print("OK unlock spends progression points")


func _check_cooldowns() -> void:
	var pair = _pair(1)
	var skills = pair.skills
	skills.unlock(&"ground_slam")
	skills.equip(0, &"ground_slam")
	var fired: Array = []
	skills.skill_activated.connect(func(slot: int, skill_id: StringName) -> void: fired.append([slot, String(skill_id)]))
	if not skills.try_activate(0) or fired != [[0, "ground_slam"]]:
		_fail("equipped ground slam did not activate")
		_drop(pair)
		return
	if skills.cooldown_left(0) != _Skills.DEFAULT_COOLDOWN:
		_fail("cooldown did not start at the catalog length")
		_drop(pair)
		return
	if skills.try_activate(0):
		_fail("a cooling skill activated again")
		_drop(pair)
		return
	skills._process(0.4)
	if absf(skills.cooldown_left(0) - 0.6) > 0.001:
		_fail("cooldown did not tick, left %s" % str(skills.cooldown_left(0)))
		_drop(pair)
		return
	_GameplayInput.pause_open = true
	skills._process(1.0)
	_GameplayInput.pause_open = false
	if absf(skills.cooldown_left(0) - 0.6) > 0.001:
		_fail("pause moved the cooldown")
		_drop(pair)
		return
	skills._process(0.6)
	if skills.cooldown_left(0) > 0.001 or not skills.try_activate(0):
		_fail("cooldown did not finish")
		_drop(pair)
		return
	if skills.try_activate(1):
		_fail("an empty slot activated")
		_drop(pair)
		return
	_drop(pair)
	print("OK cooldowns")


func _check_hotkeys() -> void:
	var pair = _pair(3)
	var skills = pair.skills
	skills.unlock(&"dash")
	skills.unlock(&"ground_slam")
	skills.unlock(&"quick_wall")
	skills.equip(0, &"dash")
	skills.equip(1, &"ground_slam")
	skills.equip(2, &"quick_wall")
	var fired: Array = []
	skills.skill_activated.connect(func(slot: int, skill_id: StringName) -> void: fired.append([slot, String(skill_id)]))
	if not InputMap.has_action("skill_1") or not InputMap.has_action("skill_2") or not InputMap.has_action("skill_3"):
		_fail("InputMap is missing a skill hotkey")
		_drop(pair)
		return
	Input.action_press("skill_2")
	skills._process(0.0)
	Input.action_release("skill_2")
	skills._process(0.0)
	if fired != [[1, "ground_slam"]]:
		_fail("skill_2 did not fire slot 1, got %s" % str(fired))
		_drop(pair)
		return
	Input.action_press("skill_2")
	skills._process(0.0)
	Input.action_release("skill_2")
	if fired.size() != 1:
		_fail("skill_2 fired through the cooldown")
		_drop(pair)
		return
	_GameplayInput.map_open = true
	Input.action_press("skill_1")
	skills._process(5.0)
	Input.action_release("skill_1")
	_GameplayInput.map_open = false
	if fired.size() != 1 or skills.cooldown_left(1) <= 0.0:
		_fail("the map let a hotkey through or ticked a cooldown")
		_drop(pair)
		return
	_drop(pair)
	print("OK hotkeys")


func _check_save_round_trip() -> void:
	var pair = _pair(2)
	var skills = pair.skills
	skills.unlock(&"quick_wall")
	skills.unlock(&"builder_passive")
	skills.equip(2, &"quick_wall")
	skills.try_activate(2)
	var blob: Dictionary = skills.export_state()
	var other = _pair(9)
	other.skills.import_state(blob)
	if not other.skills.is_unlocked(&"quick_wall") or not other.skills.is_unlocked(&"builder_passive"):
		_fail("import dropped an unlock")
		_drop(pair)
		_drop(other)
		return
	if other.skills.slot_skill(2) != &"quick_wall" or other.skills.slot_skill(0) != &"":
		_fail("import moved the equipped slot")
		_drop(pair)
		_drop(other)
		return
	if absf(other.skills.cooldown_left(2) - _Skills.DEFAULT_COOLDOWN) > 0.001:
		_fail("import dropped the cooldown")
		_drop(pair)
		_drop(other)
		return
	if other.prog.skill_points != 9:
		_fail("skill import rewrote progression points")
		_drop(pair)
		_drop(other)
		return
	var before: Dictionary = other.skills.export_state()
	other.skills.import_state({})
	if other.skills.export_state() != before:
		_fail("an empty skills block wiped the run")
		_drop(pair)
		_drop(other)
		return
	_drop(other)
	_drop(pair)
	print("OK skills save round trip")


func _check_dash() -> void:
	var dash = preload("res://player/dash_skill.gd")
	var spec: Dictionary = _Skills.CATALOG[&"dash"]
	if float(spec.get("cooldown", 0.0)) != dash.COOLDOWN or dash.COOLDOWN <= _Skills.DEFAULT_COOLDOWN:
		_fail("dash cooldown must be its own clock, got %s" % str(spec.get("cooldown", 0.0)))
		return
	if dash.DISTANCE <= 0.0 or dash.DURATION <= 0.0 or dash.INVULN < dash.DURATION:
		_fail("dash burst or invulnerability is not a short window past the slide")
		return
	var left: float = float(dash.DISTANCE)
	var moved := 0.0
	var elapsed := 0.0
	var guard := 0
	while left > 0.001 and guard < 30:
		var step: float = dash.step_columns(left, 1.0 / 60.0)
		if step <= 0.0:
			_fail("dash step stalled")
			return
		left -= step
		moved += step
		elapsed += 1.0 / 60.0
		guard += 1
	if absf(moved - dash.DISTANCE) > 0.001 or elapsed + 0.0001 < dash.DURATION or elapsed > dash.DURATION + (1.0 / 60.0) + 0.001:
		_fail("dash travel %.3f in %.3f s, want %.3f in %.3f s" % [moved, elapsed, dash.DISTANCE, dash.DURATION])
		return
	var pair = _pair(1)
	var skills = pair.skills
	skills.unlock(&"dash")
	skills.equip(0, &"dash")
	var player := Player.new()
	player.health = 80.0
	player.max_health = 100.0
	player.voxel_position = Vector3(3.0, 1.0, 5.0)
	player.locked_yaw_degrees = 0.0
	player._wish_xz = Vector2(0.0, 1.0)
	player._bind_dash()
	if not skills.skill_activated.is_connected(player._on_skill_activated):
		_fail("player did not listen for dash")
		_drop(pair)
		player.free()
		return
	if not skills.try_activate(0):
		_fail("activating dash did not start")
		_drop(pair)
		player.free()
		return
	if player._dash_left > 0.0:
		_fail("dash moved before its telegraph")
		_drop(pair)
		player.free()
		return
	player.finish_skill_feel()
	if player._dash_dir.y < 0.9 or absf(player._dash_left - dash.DISTANCE) > 0.001:
		_fail("activating dash did not aim the burst along the wish")
		_drop(pair)
		player.free()
		return
	if absf(skills.cooldown_left(0) - dash.COOLDOWN) > 0.001:
		_fail("dash activate did not start its cooldown")
		_drop(pair)
		player.free()
		return
	player._knock_left = 1.5
	if player.begin_dash(Vector2(-1.0, 0.0)):
		_fail("a second dash refreshed the window")
		_drop(pair)
		player.free()
		return
	if player._knock_left < 1.0:
		_fail("a refused dash cleared knockback")
		_drop(pair)
		player.free()
		return
	player.take_damage(12.0)
	player.damage_source_hint = &"crystal_field"
	player.take_damage(5.0, &"crystal_field")
	if absf(player.health - 80.0) > 0.01 or player._knock_left < 1.0:
		_fail("dash invulnerability let a hit or crystal pressure through")
		_drop(pair)
		player.free()
		return
	player._tick_dash_invuln(dash.INVULN)
	player.damage_source_hint = &"hit"
	player.take_damage(5.0, &"hit")
	if player.health >= 80.0:
		_fail("damage did not land after the dash window")
		_drop(pair)
		player.free()
		return
	player._dash_invuln = 0.0
	player._dash_left = dash.DISTANCE
	player._dash_dir = Vector2(1.0, 0.0)
	var x := player.voxel_position.x
	player._tick_dash_move(0.05, false)
	if player._dash_left > 0.0 or absf(player.voxel_position.x - x) > 0.001:
		_fail("a dash with no floor probe stuck or skipped the probe")
		_drop(pair)
		player.free()
		return
	player._wish_xz = Vector2.ZERO
	player._dash_left = 0.0
	player._dash_invuln = 0.0
	player.locked_yaw_degrees = 0.0
	player._on_skill_activated(0, &"dash")
	player.finish_skill_feel()
	if player._dash_dir.y > -0.9 or absf(player._dash_dir.x) > 0.1:
		_fail("an idle dash should face the camera forward, got %s" % player._dash_dir)
		_drop(pair)
		player.free()
		return
	_GameplayInput.pause_open = true
	player._dash_left = 0.0
	player._dash_invuln = 0.0
	player._on_skill_activated(0, &"dash")
	player.finish_skill_feel()
	_GameplayInput.pause_open = false
	if player._dash_left > 0.0:
		_fail("pause started a dash")
		_drop(pair)
		player.free()
		return
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	var tick_at := body.find("func _tick_dash_move")
	var next_at := body.find("\nfunc ", tick_at + 10)
	var tick := body.substr(tick_at, next_at - tick_at)
	if not tick.contains("_try_move_delta"):
		_fail("dash must step through the walk probe")
		_drop(pair)
		player.free()
		return
	var svc := FileAccess.get_file_as_string("res://systems/skill_service.gd")
	if svc.contains("_try_move_delta") or svc.contains("_dash_invuln"):
		_fail("the dash burst must stay on the player")
		_drop(pair)
		player.free()
		return
	if skills.skill_activated.is_connected(player._on_skill_activated):
		skills.skill_activated.disconnect(player._on_skill_activated)
	if skills.skill_unlocked.is_connected(player._on_skill_unlocked):
		skills.skill_unlocked.disconnect(player._on_skill_unlocked)
	player.free()
	_drop(pair)
	print("OK dash burst")


func _check_ground_slam() -> void:
	var slam = preload("res://player/ground_slam_skill.gd")
	var edits = preload("res://world/terrain_edits.gd")
	var settings = preload("res://config/world_settings.gd")
	var spec: Dictionary = _Skills.CATALOG[&"ground_slam"]
	if float(spec.get("cooldown", -1.0)) != _Skills.DEFAULT_COOLDOWN:
		_fail("ground slam cooldown stays the catalog placeholder until Q-046")
		return
	var center := Vector2i(4, 4)
	var patch: Array = slam.footprint(center)
	if patch.size() != 9 or patch[0] != Vector2i(3, 3) or patch[8] != Vector2i(5, 5):
		_fail("ground slam footprint must be the 3x3 around the player, got %s" % patch)
		return
	var src := FileAccess.get_file_as_string("res://player/ground_slam_skill.gd")
	if not src.contains("dig_cells(") or src.contains(".dig("):
		_fail("ground slam must break through the batched dig")
		return
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	if not body.contains("cast_ground_slam") or not body.contains("_Slam.break_ground"):
		_fail("the player must cast ground slam through the batched break")
		return
	var svc := FileAccess.get_file_as_string("res://systems/skill_service.gd")
	if svc.contains("dig_cells("):
		_fail("the slam break must stay off the skill service")
		return
	edits.reset()
	var world := _SlamWorld.new()
	var editor := _SlamEditor.new()
	editor.world = world
	var layer: float = settings.get_active().layer_height()
	var batch: Dictionary = slam.break_ground(world, editor, center)
	if int(batch.get("dug_count", 0)) != 9 or editor.remesh_calls != 1 or int(batch.get("remesh_count", 0)) != 1:
		_fail("3x3 slam dug %s across %d remesh calls" % [str(batch.get("dug_count", 0)), editor.remesh_calls])
		edits.reset()
		return
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var drop: float = edits.get_height_delta(center.x + dx, center.y + dz)
			if absf(drop - (-layer)) > 0.001:
				_fail("column %s,%s dropped %s, want one layer" % [center.x + dx, center.y + dz, drop])
				edits.reset()
				return
	if absf(edits.get_height_delta(8, 4)) > 0.001:
		_fail("a column outside the 3x3 moved")
		edits.reset()
		return
	edits.reset()
	var outside: Dictionary = slam.break_ground(world, editor, Vector2i(3000, 0))
	if int(outside.get("dug_count", 0)) != 0:
		_fail("ground slam dug outside the border")
		edits.reset()
		return
	var scale: float = settings.get_active().voxel_scale
	var foe := _SlamFoe.new()
	foe.position = Vector3(5.5 * scale, 1.0, 5.5 * scale)
	var far := _SlamFoe.new()
	far.position = Vector3(8.5 * scale, 1.0, 4.5 * scale)
	var dead := _SlamFoe.new()
	dead.health = 0.0
	dead.position = Vector3(4.5 * scale, 1.0, 4.5 * scale)
	var bystander := _SlamFoe.new()
	bystander.add_to_group("player")
	bystander.position = Vector3(4.5 * scale, 1.0, 3.5 * scale)
	var pair = _pair(1)
	var skills = pair.skills
	var player := Player.new()
	player.world = world
	player.voxel_position = Vector3(4.2, 1.0, 4.1)
	root.add_child(foe)
	foe.add_to_group("crystal_enemy")
	skills.unlock(&"ground_slam")
	skills.equip(0, &"ground_slam")
	player._bind_dash()
	if not skills.skill_activated.is_connected(player._on_skill_activated):
		_fail("player did not listen for ground slam")
		_drop(pair)
		player.free()
		edits.reset()
		return
	player.cast_ground_slam([foe, far, dead, bystander, foe])
	if absf(foe.health - (30.0 - slam.DAMAGE)) > 0.01 or foe.last_source != slam.SKILL_ID:
		_fail("ground slam did not damage the enemy on the patch, health %s" % foe.health)
		_cleanup_slam(pair, player, skills, edits)
		return
	if absf(far.health - 30.0) > 0.01 or absf(dead.health) > 0.01 or absf(bystander.health - 30.0) > 0.01:
		_fail("ground slam hit someone outside the patch, a dead body, or the player")
		_cleanup_slam(pair, player, skills, edits)
		return
	root.remove_child(foe)
	foe.remove_from_group("crystal_enemy")
	if int(player.cast_ground_slam([]).get("hits", -1)) != 0:
		_fail("a second slam with nobody on the patch still counted a hit")
		_cleanup_slam(pair, player, skills, edits)
		return
	root.add_child(foe)
	foe.add_to_group("crystal_enemy")
	edits.reset()
	var before := edits.get_height_delta(4, 4)
	if not skills.try_activate(0):
		_fail("equipped ground slam did not activate into the break")
		_cleanup_slam(pair, player, skills, edits)
		return
	player.finish_skill_feel()
	if absf(edits.get_height_delta(4, 4) - (-layer)) > 0.001:
		_fail("activating ground slam did not break the player's column")
		_cleanup_slam(pair, player, skills, edits)
		return
	if absf(foe.health - (30.0 - slam.DAMAGE * 2.0)) > 0.01:
		_fail("activating ground slam did not hit the enemy again")
		_cleanup_slam(pair, player, skills, edits)
		return
	_GameplayInput.pause_open = true
	var paused: Dictionary = player.cast_ground_slam([foe])
	_GameplayInput.pause_open = false
	if not paused.is_empty() or absf(edits.get_height_delta(4, 4) - (-layer)) > 0.001:
		_fail("pause started a ground slam")
		_cleanup_slam(pair, player, skills, edits)
		return
	if absf(before) > 0.001:
		_fail("the slam check started from a dirty column")
		_cleanup_slam(pair, player, skills, edits)
		return
	_cleanup_slam(pair, player, skills, edits)
	print("OK ground slam")


func _check_crystal_pulse() -> void:
	var pulse = preload("res://player/crystal_pulse_skill.gd")
	var settings = preload("res://config/world_settings.gd")
	pulse.clear()
	var spec: Dictionary = _Skills.CATALOG[&"crystal_pulse"]
	if float(spec.get("cooldown", -1.0)) != pulse.COOLDOWN or pulse.COOLDOWN <= _Skills.DEFAULT_COOLDOWN:
		_fail("crystal pulse cooldown must be its own clock, got %s" % str(spec.get("cooldown", -1.0)))
		return
	if pulse.RADIUS < 2.0 or pulse.DURATION < 1.0 or pulse.SLOW <= 0.0 or pulse.SLOW >= 1.0 or pulse.DAMAGE <= 0.0:
		_fail("crystal pulse radius, duration, slow, or damage is not a short slow field")
		return
	var center := Vector2i(8, 8)
	if not pulse.covers(Vector2i(11, 8), center) or pulse.covers(Vector2i(13, 8), center):
		_fail("crystal pulse radius did not cover 3 columns and exclude 5")
		return
	if absf(pulse.spread_scale(Vector2i(8, 8), Vector2i(9, 8)) - 1.0) > 0.001:
		_fail("crystal spread slowed with no pulse armed")
		pulse.clear()
		return
	pulse.arm(center)
	if absf(pulse.spread_scale(Vector2i(8, 8), Vector2i(12, 8)) - pulse.SLOW) > 0.001:
		_fail("an edge inside the pulse did not slow")
		pulse.clear()
		return
	if absf(pulse.spread_scale(Vector2i(20, 20), Vector2i(21, 20)) - 1.0) > 0.001:
		_fail("an edge outside the pulse slowed")
		pulse.clear()
		return
	_GameplayInput.pause_open = true
	pulse.advance(pulse.DURATION)
	_GameplayInput.pause_open = false
	if not pulse.active():
		_fail("pause expired the crystal pulse")
		pulse.clear()
		return
	pulse.advance(pulse.DURATION)
	if pulse.active() or absf(pulse.spread_scale(center, center) - 1.0) > 0.001:
		_fail("the crystal pulse outlasted its duration")
		pulse.clear()
		return
	var fluid_src := FileAccess.get_file_as_string("res://crystal/crystal_fluid_sim.gd")
	var sim_src := FileAccess.get_file_as_string("res://crystal/crystal_simulation.gd")
	if not fluid_src.contains("_Pulse.spread_scale(") or not sim_src.contains("_Pulse.advance("):
		_fail("crystal flow does not read the pulse slow")
		return
	var open_depth: float = _pulse_downhill(pulse, false)
	var slow_depth: float = _pulse_downhill(pulse, true)
	pulse.clear()
	if open_depth <= 0.05 or slow_depth <= 0.02 or slow_depth > open_depth * 0.75:
		_fail("pulse downhill depth %s vs open %s" % [slow_depth, open_depth])
		return
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	if not body.contains("cast_crystal_pulse") or not body.contains("_Pulse.arm"):
		_fail("the player must cast crystal pulse")
		pulse.clear()
		return
	var svc := FileAccess.get_file_as_string("res://systems/skill_service.gd")
	if svc.contains("spread_scale(") or svc.contains(".arm("):
		_fail("the pulse effect must stay off the skill service")
		pulse.clear()
		return
	var scale: float = settings.get_active().voxel_scale
	var foe := _SlamFoe.new()
	foe.position = Vector3((8.5) * scale, 1.0, 8.5 * scale)
	var far := _SlamFoe.new()
	far.position = Vector3(14.5 * scale, 1.0, 8.5 * scale)
	var beast := _SlamFoe.new()
	beast.position = Vector3(8.5 * scale, 1.0, 9.5 * scale)
	var dead := _SlamFoe.new()
	dead.health = 0.0
	dead.position = Vector3(7.5 * scale, 1.0, 8.5 * scale)
	var pair = _pair(1)
	var skills = pair.skills
	var player := Player.new()
	player.voxel_position = Vector3(8.2, 1.0, 8.1)
	root.add_child(foe)
	foe.add_to_group("crystal_enemy")
	root.add_child(dead)
	dead.add_to_group("crystal_enemy")
	skills.unlock(&"crystal_pulse")
	skills.equip(0, &"crystal_pulse")
	player._bind_dash()
	if not skills.skill_activated.is_connected(player._on_skill_activated):
		_fail("player did not listen for crystal pulse")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	pulse.clear()
	player.cast_crystal_pulse([foe, far, beast, dead, foe])
	if absf(foe.health - (30.0 - pulse.DAMAGE)) > 0.01 or foe.last_source != pulse.SKILL_ID:
		_fail("crystal pulse did not damage the crystal enemy, health %s" % foe.health)
		_cleanup_pulse(pair, player, skills, pulse)
		return
	if absf(far.health - 30.0) > 0.01 or absf(beast.health - 30.0) > 0.01 or absf(dead.health) > 0.01:
		_fail("crystal pulse hit someone outside the radius, wildlife, or a dead body")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	if not pulse.covers(center, player.cast_crystal_pulse([]).get("center", Vector2i.ZERO)):
		_fail("crystal pulse did not arm on the player column")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	pulse.clear()
	foe.health = 30.0
	if not skills.try_activate(0):
		_fail("equipped crystal pulse did not activate")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	player.finish_skill_feel()
	if absf(skills.cooldown_left(0) - pulse.COOLDOWN) > 0.001:
		_fail("crystal pulse cooldown did not start at its own length")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	if absf(foe.health - (30.0 - pulse.DAMAGE)) > 0.01 or not pulse.active():
		_fail("activating crystal pulse did not hit or arm")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	_GameplayInput.pause_open = true
	var paused: Dictionary = player.cast_crystal_pulse([foe])
	_GameplayInput.pause_open = false
	if not paused.is_empty() or absf(foe.health - (30.0 - pulse.DAMAGE)) > 0.01 or not pulse.active():
		_fail("pause started a crystal pulse or cleared the one already running")
		_cleanup_pulse(pair, player, skills, pulse)
		return
	_cleanup_pulse(pair, player, skills, pulse)
	print("OK crystal pulse")


func _check_quick_wall() -> void:
	var wall = preload("res://player/quick_wall_skill.gd")
	var edits = preload("res://world/terrain_edits.gd")
	var features = preload("res://world/feature_registry.gd")
	var integrity = preload("res://helpers/structure_integrity.gd")
	var settings = preload("res://config/world_settings.gd")
	var inventory_script = preload("res://inventory/inventory.gd")
	var spec: Dictionary = _Skills.CATALOG[&"quick_wall"]
	if float(spec.get("cooldown", -1.0)) != _Skills.DEFAULT_COOLDOWN:
		_fail("quick wall cooldown stays the catalog placeholder until Q-046")
		return
	if wall.BLUEPRINT_ID != &"wall_segment" or wall.COST_SCALE <= 0.0 or wall.COST_SCALE >= 1.0:
		_fail("quick wall must place a wall segment at a reduced cost")
		return
	var full := wall.full_count()
	var half := wall.reduced_count(full)
	var wood_full := wall.wood_full()
	var wood_half := wall.reduced_count(wood_full)
	if full < 2 or half >= full or half != maxi(1, int(ceil(float(full) * wall.COST_SCALE))):
		_fail("quick wall stone cost %s did not reduce from %s" % [half, full])
		return
	if wood_half >= wood_full or wood_half < 1:
		_fail("quick wall wood fallback did not reduce")
		return
	if wall.anchor_column(Vector2i(4, 4), Vector2(0, -1)) != Vector2i(4, 3):
		_fail("quick wall did not sit one column in front of the player")
		return
	if wall.quarter_for_facing(Vector2(0, -1)) != 0 or wall.quarter_for_facing(Vector2(1, 0)) != 3 or wall.quarter_for_facing(Vector2(-1, 0)) != 1:
		_fail("quick wall did not turn the segment across the facing")
		return
	var src := FileAccess.get_file_as_string("res://player/quick_wall_skill.gd")
	if not src.contains("try_place_blueprint") or src.contains("get_build_delay"):
		_fail("quick wall must place the blueprint immediately")
		return
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	if not body.contains("cast_quick_wall") or not body.contains("_Wall.place"):
		_fail("the player must cast quick wall")
		return
	var svc := FileAccess.get_file_as_string("res://systems/skill_service.gd")
	if svc.contains("try_place_blueprint") or svc.contains("wall_segment"):
		_fail("the wall place must stay off the skill service")
		return
	edits.reset()
	features.reset()
	integrity.reset()
	var world := _SlamWorld.new()
	var editor := TerrainEditor.new()
	var chunks := ChunkManager.new()
	root.add_child(editor)
	editor.world = world
	editor.chunk_manager = chunks
	if absf(editor.get_build_delay() - 0.03) > 0.0001:
		_fail("quick wall changed the build delay")
		_cleanup_wall(null, null, null, editor, chunks, edits, features, integrity)
		return
	var pair = _pair(1)
	var skills = pair.skills
	var player := Player.new()
	player.world = world
	player.voxel_position = Vector3(4.2, 1.0, 4.1)
	player.locked_yaw_degrees = 0.0
	var bag = inventory_script.new()
	player.inventory = bag
	skills.unlock(&"quick_wall")
	skills.equip(0, &"quick_wall")
	player._bind_dash()
	if not skills.skill_activated.is_connected(player._on_skill_activated):
		_fail("player did not listen for quick wall")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	bag.add_item(wall.material_id(), half)
	_GameplayInput.pause_open = true
	var paused: Dictionary = player.cast_quick_wall()
	_GameplayInput.pause_open = false
	if not paused.is_empty() or bag.count_item(wall.material_id()) != half:
		_fail("pause placed a quick wall")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	if player.cast_quick_wall().get("placed", false) != true or bag.count_item(wall.material_id()) != 0:
		_fail("quick wall did not place at the reduced stone cost, reason %s" % editor.last_fail_reason)
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	var layer: float = settings.get_active().layer_height()
	for col in [Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3)]:
		if absf(edits.get_height_delta(col.x, col.y) - layer * 2.0) > 0.001:
			_fail("wall column %s is not two layers" % col)
			_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
			return
		if str(features.get_feature(col.x, col.y).get("build_id", "")) != "stone_wall":
			_fail("wall column %s is not a stone wall" % col)
			_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
			return
	if absf(edits.get_height_delta(4, 4)) > 0.001 or absf(edits.get_height_delta(7, 3)) > 0.001:
		_fail("quick wall raised a column outside the segment")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	edits.reset()
	features.reset()
	integrity.reset()
	bag.add_item("wall_segment", 1)
	bag.add_item(wall.material_id(), half)
	if player.cast_quick_wall().get("placed", false) != true or bag.count_item("wall_segment") != 1 or bag.count_item(wall.material_id()) != 0:
		_fail("quick wall spent the crafted piece or skipped the reduced stone cost")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	edits.reset()
	features.reset()
	integrity.reset()
	var priced = inventory_script.new()
	priced.add_item(wall.material_id(), full - 1)
	if editor.try_place_blueprint(Vector3(20, 0, 20), priced, wall.BLUEPRINT_ID, 0):
		_fail("a normal wall placed without the full stone cost")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	if priced.count_item(wall.material_id()) != full - 1:
		_fail("a refused full-price wall spent stone")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	priced.add_item(wall.material_id(), 1)
	if not editor.try_place_blueprint(Vector3(20, 0, 20), priced, wall.BLUEPRINT_ID, 0) or priced.count_item(wall.material_id()) != 0:
		_fail("a normal wall did not charge the full stone cost, reason %s" % editor.last_fail_reason)
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	edits.reset()
	features.reset()
	integrity.reset()
	var timber = inventory_script.new()
	timber.add_item("wood", wood_half)
	player.inventory = timber
	if player.cast_quick_wall().get("placed", false) != true or timber.count_item("wood") != 0:
		_fail("quick wall did not take the reduced wood fallback, reason %s" % editor.last_fail_reason)
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	edits.reset()
	features.reset()
	integrity.reset()
	var short = inventory_script.new()
	short.add_item(wall.material_id(), half - 1)
	player.inventory = short
	if not skills.try_activate(0):
		_fail("equipped quick wall did not activate")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	player.finish_skill_feel()
	if skills.cooldown_left(0) > 0.001 or short.count_item(wall.material_id()) != half - 1 or absf(edits.get_height_delta(4, 3)) > 0.001:
		_fail("a short stack still placed or kept the cooldown")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	short.add_item(wall.material_id(), 1)
	if not skills.try_activate(0):
		_fail("activating quick wall did not start")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	player.finish_skill_feel()
	if short.count_item(wall.material_id()) != 0:
		_fail("activating quick wall did not place the segment, reason %s" % editor.last_fail_reason)
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	if absf(skills.cooldown_left(0) - _Skills.DEFAULT_COOLDOWN) > 0.001:
		_fail("quick wall cooldown did not start")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	if skills.try_activate(0):
		_fail("quick wall activated again during its cooldown")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	_GameplayInput.pause_open = true
	var held: Dictionary = player.cast_quick_wall()
	_GameplayInput.pause_open = false
	if not held.is_empty():
		_fail("pause started a second quick wall")
		_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
		return
	_cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity)
	print("OK quick wall")


func _check_passives() -> void:
	var passives = preload("res://player/skill_passives.gd")
	var stats_script = preload("res://stats/stat_component.gd")
	var ids = preload("res://stats/stat_ids.gd")
	var integrity = preload("res://helpers/structure_integrity.gd")
	if passives.MINING_SPEED <= 0.0 or passives.MAX_HP <= 0.0 or passives.STRUCTURE_HP <= 0:
		_fail("passive bonuses must raise mining speed, max HP, and structure HP")
		return
	if integrity.HP_PER_CELL != 8:
		_fail("structure HP per cell drifted from 8")
		return
	var body := FileAccess.get_file_as_string("res://player/player.gd")
	if not body.contains("_Passives.apply") or not body.contains("_on_skill_unlocked"):
		_fail("the player does not apply passive stats")
		return
	var walls := FileAccess.get_file_as_string("res://helpers/structure_integrity.gd")
	if not walls.contains("HP_PER_CELL + _Passives.structure_cell_bonus()"):
		_fail("new structures do not add the builder passive")
		return
	var editor := FileAccess.get_file_as_string("res://world/terrain_editor.gd")
	if not editor.contains("base_delay / dig_speed"):
		_fail("dig delay no longer follows dig speed")
		return
	var pair = _pair(3)
	var skills = pair.skills
	var stats = stats_script.new()
	pair.host.add_child(stats)
	passives.apply(stats, skills)
	if absf(stats.get_stat(ids.DIG_SPEED) - 1.0) > 0.001 or absf(stats.get_stat(ids.MAX_HEALTH) - 100.0) > 0.001:
		_fail("passives changed stats before unlock")
		_drop(pair)
		return
	if passives.structure_cell_bonus() != 0:
		_fail("structure bonus applied before the builder passive")
		_drop(pair)
		return
	if not skills.unlock(passives.MINER) or not skills.unlock(passives.FIGHTER) or not skills.unlock(passives.BUILDER):
		_fail("passive unlocks failed")
		_drop(pair)
		return
	passives.apply(stats, skills)
	passives.apply(stats, skills)
	if absf(stats.get_stat(ids.DIG_SPEED) - (1.0 + passives.MINING_SPEED)) > 0.001:
		_fail("miner passive did not raise dig speed, got %s" % stats.get_stat(ids.DIG_SPEED))
		_drop(pair)
		return
	if absf(stats.get_stat(ids.MAX_HEALTH) - (100.0 + passives.MAX_HP)) > 0.001:
		_fail("fighter passive did not raise max health, got %s" % stats.get_stat(ids.MAX_HEALTH))
		_drop(pair)
		return
	if passives.structure_cell_bonus() != passives.STRUCTURE_HP:
		_fail("builder passive did not add structure HP")
		_drop(pair)
		return
	var blob: Dictionary = skills.export_state()
	var other = _pair(0)
	other.skills.import_state(blob)
	if not other.skills.is_unlocked(passives.MINER) or not other.skills.is_unlocked(passives.FIGHTER) or not other.skills.is_unlocked(passives.BUILDER):
		_fail("passive unlocks did not load")
		_drop(pair)
		_drop(other)
		return
	if passives.structure_cell_bonus() != passives.STRUCTURE_HP:
		_fail("loaded builder passive did not keep the structure bonus")
		_drop(pair)
		_drop(other)
		return
	var loaded = stats_script.new()
	other.host.add_child(loaded)
	passives.apply(loaded, other.skills)
	if absf(loaded.get_stat(ids.DIG_SPEED) - (1.0 + passives.MINING_SPEED)) > 0.001 or absf(loaded.get_stat(ids.MAX_HEALTH) - (100.0 + passives.MAX_HP)) > 0.001:
		_fail("loaded passives did not restore mining speed and max HP")
		_drop(pair)
		_drop(other)
		return
	_drop(other)
	_drop(pair)
	print("OK passives")


func _check_skill_tree() -> void:
	_GameplayInput.skill_tree_open = false
	_GameplayInput.pause_open = false
	_GameplayInput.map_open = false
	_GameplayInput.dev_chat_open = false
	_GameplayInput.world_loading = false
	var project := FileAccess.get_file_as_string("res://project.godot")
	if not project.contains("skill_tree=") or project.find("physical_keycode\":75") < 0:
		_fail("skill tree key must be K")
		return
	var main_src := FileAccess.get_file_as_string("res://main.gd")
	if not main_src.contains("res://ui/skill_tree_panel.gd"):
		_fail("main does not spawn the skill tree")
		return
	var pause_src := FileAccess.get_file_as_string("res://ui/pause_menu.gd")
	if not pause_src.contains("skill_tree"):
		_fail("pause does not close the skill tree")
		return
	var pair = _pair(2)
	var panel = load("res://ui/skill_tree_panel.gd").new()
	root.add_child(panel)
	for branch in ["fighter", "miner", "builder"]:
		var col: Node = panel.get_node_or_null("Root/Panel/Body/Branches/" + branch)
		if col == null:
			_fail("branch %s is missing" % branch)
			panel.free()
			_drop(pair)
			return
	var miner_btn: Button = panel.get_node("Root/Panel/Body/Branches/miner/miner_passive")
	var dash_btn: Button = panel.get_node("Root/Panel/Body/Branches/fighter/dash")
	var builder_btn: Button = panel.get_node("Root/Panel/Body/Branches/builder/builder_passive")
	panel.open()
	if not panel.visible or not _GameplayInput.skill_tree_open or not _GameplayInput.blocks_actions():
		_fail("skill tree did not open")
		panel.free()
		_drop(pair)
		return
	var points: Label = panel.get_node("Root/Panel/Body/Points")
	if points.text != "Points 2":
		_fail("skill tree points read %s" % points.text)
		panel.free()
		_drop(pair)
		return
	if not miner_btn.text.contains("(locked)") or not builder_btn.text.contains("(locked)"):
		_fail("a locked passive was marked open")
		panel.free()
		_drop(pair)
		return
	miner_btn.pressed.emit()
	dash_btn.pressed.emit()
	if not pair.skills.is_unlocked(&"miner_passive") or not pair.skills.is_unlocked(&"dash") or pair.prog.skill_points != 0:
		_fail("the tree did not spend points on quick mine and dash")
		panel.free()
		_drop(pair)
		return
	if not miner_btn.text.contains("(on)") or not dash_btn.text.contains("slot 1"):
		_fail("tree captions after unlock were %s / %s" % [miner_btn.text, dash_btn.text])
		panel.free()
		_drop(pair)
		return
	if pair.skills.slot_skill(0) != &"dash":
		_fail("the tree did not equip dash")
		panel.free()
		_drop(pair)
		return
	dash_btn.pressed.emit()
	if pair.skills.slot_skill(0) != &"" or dash_btn.text.contains("slot"):
		_fail("a second click did not clear dash")
		panel.free()
		_drop(pair)
		return
	var blob: Dictionary = pair.skills.export_state()
	panel.close()
	if panel.visible or _GameplayInput.skill_tree_open or _GameplayInput.blocks_actions() or paused:
		_fail("skill tree stayed open")
		panel.free()
		_drop(pair)
		return
	var saved = _pair(4)
	saved.skills.import_state(blob)
	if not saved.skills.is_unlocked(&"miner_passive") or not saved.skills.is_unlocked(&"dash") or saved.skills.is_unlocked(&"builder_passive"):
		_fail("the tree unlocks did not save")
		panel.free()
		_drop(saved)
		_drop(pair)
		return
	_drop(saved)
	var key := InputEventKey.new()
	key.physical_keycode = 75
	key.pressed = true
	_GameplayInput.map_open = true
	panel._unhandled_input(key)
	if panel.visible:
		_fail("the map let the skill tree open")
		_GameplayInput.map_open = false
		panel.free()
		_drop(pair)
		return
	_GameplayInput.map_open = false
	panel._unhandled_input(key)
	if not panel.visible or not _GameplayInput.blocks_actions():
		_fail("K did not open the skill tree")
		panel.free()
		_drop(pair)
		return
	var pause = load("res://ui/pause_menu.gd").new()
	root.add_child(pause)
	pause.open()
	if panel.visible or _GameplayInput.skill_tree_open or not _GameplayInput.pause_open:
		_fail("pause left the skill tree open")
		pause.free()
		panel.free()
		_drop(pair)
		return
	pause.close()
	if _GameplayInput.pause_open or paused or panel.visible:
		_fail("closing pause left the tree or the pause flag up")
		pause.free()
		panel.free()
		_drop(pair)
		return
	pause.free()
	panel.free()
	_drop(pair)
	_GameplayInput.skill_tree_open = false
	_GameplayInput.pause_open = false
	paused = false
	print("OK skill tree")


func _cleanup_wall(pair, player, skills, editor, chunks, edits, features, integrity) -> void:
	_GameplayInput.pause_open = false
	if player != null and skills != null and skills.skill_activated.is_connected(player._on_skill_activated):
		skills.skill_activated.disconnect(player._on_skill_activated)
	if player != null and skills != null and skills.skill_unlocked.is_connected(player._on_skill_unlocked):
		skills.skill_unlocked.disconnect(player._on_skill_unlocked)
	if player != null:
		player.free()
	if pair != null:
		_drop(pair)
	if editor != null:
		editor.free()
	if chunks != null:
		chunks.free()
	edits.reset()
	features.reset()
	integrity.reset()


func _pulse_downhill(pulse, slowed: bool) -> float:
	var fluid_sim = preload("res://crystal/crystal_fluid_sim.gd")
	var terrain_q = preload("res://crystal/crystal_terrain_query.gd")
	var sim_cfg = preload("res://config/crystal_sim_config.gd")
	pulse.clear()
	var cfg = sim_cfg.create_default()
	cfg.pressure_flow_rate = 1.4
	cfg.max_flow_per_cell = 8.0
	cfg.max_outflow_ratio = 0.95
	cfg.lateral_spread_bias = 0.0
	var heights: Dictionary = {}
	for x in 12:
		for z in 12:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(6, 5)] = 8.0
	var terrain = terrain_q.new()
	terrain.test_base_heights = heights
	var sim = fluid_sim.new(cfg, terrain)
	sim.empty_cell_inflow_cap = 3.0
	sim.set_depth(Vector2i(5, 5), 2.2, 0, false)
	if slowed:
		pulse.arm(Vector2i(5, 5))
	sim.tick_flow(0.25)
	var depth: float = sim.get_depth_at(6, 5)
	pulse.clear()
	return depth


func _cleanup_pulse(pair: Dictionary, player: Player, skills, pulse) -> void:
	pulse.clear()
	_GameplayInput.pause_open = false
	if skills.skill_activated.is_connected(player._on_skill_activated):
		skills.skill_activated.disconnect(player._on_skill_activated)
	if skills.skill_unlocked.is_connected(player._on_skill_unlocked):
		skills.skill_unlocked.disconnect(player._on_skill_unlocked)
	player.free()
	_drop(pair)


func _cleanup_slam(pair: Dictionary, player: Player, skills, edits) -> void:
	if skills.skill_activated.is_connected(player._on_skill_activated):
		skills.skill_activated.disconnect(player._on_skill_activated)
	if skills.skill_unlocked.is_connected(player._on_skill_unlocked):
		skills.skill_unlocked.disconnect(player._on_skill_unlocked)
	player.free()
	_drop(pair)
	edits.reset()


class _SlamWorld:
	extends "res://world/InfiniteNoiseWorld.gd"

	func get_surface_height(wx: float, wz: float) -> float:
		var edits = preload("res://world/terrain_edits.gd")
		return edits.get_height_delta(floori(wx), floori(wz))

	func get_tile_type(_wx: float, _wz: float) -> int:
		return 0

	func invalidate_column_cache(_wx: int, _wz: int) -> void:
		pass


class _SlamEditor:
	extends RefCounted
	var world
	var remesh_calls: int = 0

	func remesh_break_chunk(_chunk: Vector2i, _columns: Array) -> void:
		remesh_calls += 1

	func update_break_water(_chunk: Vector2i, _columns: Array) -> void:
		pass

	func update_break_crystal(_chunk: Vector2i, _columns: Array) -> void:
		pass

	func flush_break_chunks() -> void:
		pass


class _SlamFoe:
	extends Node3D
	var health := 30.0
	var last_source: StringName = &""

	func take_damage(amount: float, source: StringName = &"") -> void:
		health -= amount
		last_source = source
