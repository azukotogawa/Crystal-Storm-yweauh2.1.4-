extends RefCounted

const _Build = preload("res://scripts/honest_bot/honest_build.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Combat = preload("res://scripts/honest_bot/honest_combat.gd")
const _Fight = preload("res://scripts/honest_bot/honest_fight.gd")
const _Cast = preload("res://scripts/honest_bot/honest_skill_cast.gd")
const _Hazard = preload("res://scripts/honest_bot/honest_hazard.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Move = preload("res://entities/entity_navigation.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Worlds = preload("res://systems/world_manager.gd")
const _Edits = preload("res://world/terrain_edits.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Corrupt = preload("res://crystal/crystal_corruption.gd")

const MAIN_SCENE := "res://scenes/main.tscn"
const SEED := 12349
const STEP := 1.0 / 60.0
const BOOT_FRAMES := 2400
const DIG_FRAMES := 4200
const BUILD_FRAMES := 7200

const OPENING_BANNER := "Watch the purple front — dig trenches & walls where it advances"
const WALL_BANNER := "Wall raised — crystal slows here; it will find another way"


func play(tree: SceneTree, scenario: String) -> int:
	var name := scenario.strip_edges()
	if name == "break":
		return _break(tree)
	if name == "crystals" or name == "corruption" or name == "combat":
		return await _play_feature(tree, name)
	if name == "mite_fight":
		return await _play_mite(tree)
	if name != "dig" and name != "build":
		print("FAIL harness unknown scenario %s" % name)
		return 1
	print("HARNESS seed %d" % SEED)
	print("HARNESS setup pending_launch harness-%s seed %d resume off" % [name, SEED])
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, name, seen)
	if player == null:
		return 1
	var bot = _Bot.new()
	bot.chapter = name
	bot.objective = "dig one column" if name == "dig" else "place one stone wall"
	var before := _snap(tree, player)
	var build = _Build.new()
	var hands = _Hands.new()
	build.reset("dig_tool" if name == "dig" else "structure_place")
	var cap := DIG_FRAMES if name == "dig" else BUILD_FRAMES
	var result := ""
	var frames := 0
	while frames < cap:
		var delta := _delta(tree)
		result = build.tick(delta, tree, player, hands, null)
		_note_banner(tree, seen)
		if result == "fail":
			return _give_up(bot, player, "play returned fail")
		if name == "dig" and result == "pass":
			break
		if name == "build" and build.beat >= 10:
			result = "pass"
			break
		await tree.process_frame
		frames += 1
	if result != "pass":
		return _give_up(bot, player, "scenario did not finish")
	var after := _snap(tree, player)
	_stamp_world(name, build, after)
	var reason := _expect(name, before, after, seen)
	if reason != "":
		print("FAIL harness assertion %s" % reason)
		return _give_up(bot, player, "assertion %s" % reason)
	_print_see(name, before, after, seen)
	var pos := _xz(player)
	var shot := bot.save_view(name, pos)
	if shot == "":
		return _give_up(bot, player, "screenshot was not saved")
	return 0


func _break(tree: SceneTree) -> int:
	var bot = _Bot.new()
	bot.chapter = "dig"
	bot.objective = "height drop"
	bot.set_target(Vector2(10.0, 0.0))
	var reason := "height drop expected 1 saw 0"
	print("FAIL harness assertion %s" % reason)
	bot.fail_closed(Vector2.ZERO, "assertion %s" % reason)
	if bot.fail_report == "" or bot.fail_shot == "":
		print("FAIL harness report missing")
		return 1
	if tree == null:
		return 1
	return 1


func _boot(tree: SceneTree, scenario: String, seen: PackedStringArray, seed_value: int = -1):
	var use_seed := seed_value if seed_value >= 0 else SEED
	_Worlds.pending_launch = {
		"id": "harness-%s" % scenario,
		"seed": use_seed,
		"name": "Harness",
	}
	_Worlds.pending_resume = false
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		print("FAIL harness no main scene")
		return null
	var game: Node = packed.instantiate()
	tree.root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < BOOT_FRAMES:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await tree.process_frame
		_note_banner(tree, seen)
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		print("FAIL harness start region not ready")
		return null
	for _w in 120:
		await tree.process_frame
		_note_banner(tree, seen)
		if not _GI.blocks_actions():
			break
	if _GI.blocks_actions():
		print("FAIL harness actions still blocked")
		return null
	var player = tree.get_first_node_in_group("player")
	if player == null or not bool(player.get("world_ready")):
		print("FAIL harness player not world_ready")
		return null
	var world = game.get_node_or_null("World")
	var seeded := int(world.world_seed) if world != null and "world_seed" in world else -1
	if seeded != use_seed:
		print("FAIL harness seed %d want %d" % [seeded, use_seed])
		return null
	print("HARNESS booted seed %d" % seeded)
	return player


func _expect(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray) -> String:
	if not bool(after.get("hp_panel", false)):
		return "hp bar hidden"
	var want_hp := "%d / %d" % [int(round(float(after.get("hp", 0.0)))), int(round(float(after.get("max", 0.0))))]
	if str(after.get("hp_label", "")) != want_hp:
		return "hp label %s want %s" % [str(after.get("hp_label", "")), want_hp]
	if absf(float(after.get("hp", -1.0)) - float(before.get("hp", -2.0))) > 0.01:
		return "hp changed"
	if not _saw(seen, OPENING_BANNER):
		return "opening banner missing"
	if name == "dig":
		if int(after.get("stone", 0)) <= int(before.get("stone", 0)):
			return "stone did not increase"
		if float(after.get("drop", 0.0)) < 0.01:
			return "height drop missing"
		return ""
	if int(after.get("walls", 0)) < 1:
		return "stone wall missing"
	if int(after.get("stone", 0)) >= int(before.get("stone", 0)):
		return "stone was not spent"
	for line in seen:
		if line == OPENING_BANNER or line == WALL_BANNER:
			continue
		if line.begins_with("Gate ") or line.begins_with("Bridge ") or line.begins_with("Trench "):
			continue
		if line.begins_with("First steps "):
			continue
		return "unexpected banner %s" % line
	return ""


func _print_see(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray) -> void:
	print("HARNESS see %s drop %.3f walls %d stone %d to %d hp %s banners %s" % [
		name,
		float(after.get("drop", 0.0)),
		int(after.get("walls", 0)),
		int(before.get("stone", 0)),
		int(after.get("stone", 0)),
		str(after.get("hp_label", "")),
		"|".join(seen),
	])


func _snap(tree: SceneTree, player) -> Dictionary:
	var hp := float(player.health) if "health" in player else -1.0
	var mx := float(player.max_health) if "max_health" in player else 100.0
	var stone := 0
	var inv = player.get("inventory")
	if inv != null and inv.has_method("count_item"):
		stone = int(inv.count_item("stone"))
	var label := ""
	var panel_on := false
	var panel = tree.root.find_child("PlayerHealthBar", true, false)
	if panel != null:
		panel_on = panel.visible
		label = _label_under(panel)
	return {
		"hp": hp,
		"max": mx,
		"hp_label": label,
		"hp_panel": panel_on,
		"stone": stone,
		"drop": 0.0,
		"walls": 0,
	}


func _stamp_world(name: String, build, after: Dictionary) -> void:
	if name == "dig":
		var cell: Vector2i = build._dropped()
		if cell.x >= 900000:
			return
		var was := float(build.heights.get(cell, _Edits.get_height_delta(cell.x, cell.y)))
		after["drop"] = was - _Edits.get_height_delta(cell.x, cell.y)
		return
	after["walls"] = int(build._new_tiles())


func _note_banner(tree: SceneTree, seen: PackedStringArray) -> void:
	var toast = tree.root.find_child("ToastLabel", true, false)
	if toast == null or not toast.visible:
		return
	var text := str(toast.text).strip_edges()
	if text == "" or _saw(seen, text):
		return
	seen.append(text)


func _saw(seen: PackedStringArray, text: String) -> bool:
	for line in seen:
		if line == text:
			return true
	return false


func _label_under(node: Node) -> String:
	var found := ""
	for child in node.get_children():
		if child is Label:
			var text := str(child.text)
			if "/" in text:
				return text
		var nested := _label_under(child)
		if nested != "":
			found = nested
	return found


func _give_up(bot, player, reason: String) -> int:
	var pos := _xz(player)
	bot.home = pos
	bot.fail_closed(pos, reason)
	return 1


func _xz(player) -> Vector2:
	if player == null or not ("voxel_position" in player):
		return Vector2.ZERO
	var feet: Vector3 = player.voxel_position
	return Vector2(feet.x, feet.z)


func _delta(tree: SceneTree) -> float:
	var delta := tree.root.get_process_delta_time()
	if delta <= 0.0:
		return STEP
	return minf(delta, 1.0 / 30.0)


const FEATURE_LIMIT := {
	"crystals": 90.0,
	"corruption": 240.0,
	"combat": 240.0,
}
const FIND_COLUMNS := 8.0
const FILM_DEPTH := 0.2
const SWING_GAP := 0.42


func _play_feature(tree: SceneTree, name: String) -> int:
	print("HARNESS seed %d" % SEED)
	print("HARNESS setup pending_launch harness-%s seed %d resume off" % [name, SEED])
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, name, seen)
	if player == null:
		return 1
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		print("FAIL harness no crystal")
		return 1
	var origin: Vector2i = crystal.get_origin_cell()
	var origin_xz := Vector2(float(origin.x) + 0.5, float(origin.y) + 0.5)
	var bot = _Bot.new()
	bot.chapter = name
	bot.objective = name
	bot.stuck_limit = 12
	var hands = _Hands.new()
	var fight = _Combat.new()
	fight.chip_skills = false
	var cast = _Cast.new()
	var before := _snap(tree, player)
	var heart0 := _heart_hp(crystal)
	var shards0 := _count(player, "crystal_shard")
	var corrupt0 := _corrupt_near(origin, 18)
	var scars0 := _Corrupt.scar_count()
	var job := {
		"found": false,
		"collected": false,
		"used": false,
		"spread": false,
		"cleansed": false,
		"burn_seen": false,
		"burned": false,
		"warned": false,
		"struck": false,
		"melee": false,
		"skilled": false,
		"cast_on": false,
		"heart_mark": heart0,
		"warn_hp": -1.0,
		"burn_hp": -1.0,
		"foe_hp": -1.0,
		"foe_id": "",
		"cell": Vector2i(999999, 999999),
		"swings": 0,
		"gap": 0.0,
		"pick": false,
		"sword": false,
	}
	job["corrupt_boot"] = corrupt0
	job["scars_boot"] = scars0
	var elapsed := 0.0
	var limit := float(FEATURE_LIMIT.get(name, 90.0))
	while elapsed < limit:
		var delta := _delta(tree)
		elapsed += delta
		_note_banner(tree, seen)
		if float(player.health) <= 0.0:
			return _give_up(bot, player, "player died")
		var done := _feature_tick(name, tree, player, crystal, origin, origin_xz, bot, hands, fight, cast, job, delta)
		if done != "":
			return _give_up(bot, player, done)
		if _feature_ready(name, job):
			break
		await tree.process_frame
	if not _feature_ready(name, job):
		return _give_up(bot, player, "scenario did not finish %s" % _feature_miss(name, job))
	var after := _snap(tree, player)
	after["shards"] = _count(player, "crystal_shard")
	after["heart"] = _heart_hp(crystal)
	after["corrupt"] = _corrupt_near(origin, 18)
	after["scars"] = _Corrupt.scar_count()
	before["shards"] = shards0
	before["heart"] = heart0
	before["corrupt"] = corrupt0
	before["scars"] = scars0
	var reason := _expect_feature(name, before, after, seen, job)
	if reason != "":
		print("FAIL harness assertion %s" % reason)
		return _give_up(bot, player, "assertion %s" % reason)
	_print_feature(name, before, after, seen, job)
	var shot := bot.save_view(name, _xz(player))
	if shot == "":
		return _give_up(bot, player, "screenshot was not saved")
	return 0


func _feature_ready(name: String, job: Dictionary) -> bool:
	if name == "crystals":
		return bool(job["found"]) and bool(job["collected"]) and bool(job["used"])
	if name == "corruption":
		return bool(job["spread"]) and bool(job["cleansed"]) and bool(job["burned"])
	return bool(job["struck"]) and bool(job["melee"]) and bool(job["skilled"])


func _feature_miss(name: String, job: Dictionary) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if name == "crystals":
		if not bool(job["found"]):
			bits.append("find")
		if not bool(job["collected"]):
			bits.append("collect")
		if not bool(job["used"]):
			bits.append("use")
	elif name == "corruption":
		if not bool(job["spread"]):
			bits.append("spread")
		if not bool(job["cleansed"]):
			bits.append("cleanse")
		if not bool(job["burned"]):
			bits.append("burn")
	else:
		if not bool(job["struck"]):
			bits.append("warning")
		if not bool(job["melee"]):
			bits.append("melee")
		if not bool(job["skilled"]):
			bits.append("skill")
	return ",".join(bits)


func _feature_tick(name: String, tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, fight, cast, job: Dictionary, delta: float) -> String:
	var pos := _xz(player)
	if name == "crystals":
		return _tick_crystals(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos)
	if name == "corruption":
		return _tick_corruption(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos)
	return _tick_combat(tree, player, crystal, origin, origin_xz, bot, hands, fight, cast, job, delta, pos)


func _tick_crystals(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, job: Dictionary, delta: float, pos: Vector2) -> String:
	if _attack_warn(tree):
		_step_away(tree, player, bot, origin_xz, delta, pos)
		return ""
	if not bool(job["found"]):
		if pos.distance_to(origin_xz) <= FIND_COLUMNS:
			job["found"] = true
			print("HARNESS found heart %.1f" % pos.distance_to(origin_xz))
			return ""
		_step_toward(bot, player, origin_xz, delta, pos)
		return ""
	if not bool(job["collected"]):
		if _count(player, "crystal_shard") > 0:
			job["collected"] = true
			job["cell"] = Vector2i(999999, 999999)
			job["swings"] = 0
			job["pick"] = false
			job["heart_mark"] = _heart_hp(crystal)
			print("HARNESS collected shards %d" % _count(player, "crystal_shard"))
			return ""
		_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
		return ""
	if not bool(job["used"]):
		var heart := _heart_hp(crystal)
		if heart >= 0.0 and heart < float(job["heart_mark"]) - 0.05:
			job["used"] = true
			print("HARNESS used heart %.1f to %.1f" % [float(job["heart_mark"]), heart])
			bot.release()
			return ""
		_swing_heart(tree, player, origin, bot, hands, job, delta, pos)
	return ""


func _tick_corruption(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, job: Dictionary, delta: float, pos: Vector2) -> String:
	var corrupt_now := _corrupt_near(origin, 18)
	if not bool(job["spread"]) and corrupt_now > int(job["corrupt_boot"]):
		job["spread"] = true
		job["corrupt_seen"] = corrupt_now
		print("HARNESS spread corrupt %d to %d" % [int(job["corrupt_boot"]), corrupt_now])
	if not bool(job["cleansed"]):
		if _attack_warn(tree) or _Hazard.ring_hot(tree, pos):
			_leave_attack(tree, player, bot, origin_xz, job, delta, pos)
			return ""
		if _Corrupt.scar_count() > int(job["scars_boot"]):
			job["cleansed"] = true
			job["scars_seen"] = _Corrupt.scar_count()
			job["cell"] = Vector2i(999999, 999999)
			print("HARNESS cleansed scars %d" % int(job["scars_seen"]))
		else:
			_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
			return ""
	if bool(job["burned"]):
		bot.release()
		return ""
	var tier := int(crystal.get("strength_tier"))
	var warned := _attack_warn(tree) or _Hazard.ring_hot(tree, pos)
	var deep_here := _Hazard.depth_at(tree, pos) >= _Hazard.BURN_DEPTH
	var burn := tree.root.find_child("BurnWarn", true, false)
	var burn_up: bool = burn != null and bool(burn.visible)
	if not burn_up and (warned or (tier < 1 and deep_here)):
		_leave_attack(tree, player, bot, origin_xz, job, delta, pos)
		return ""
	if tier < 1:
		job["dodge"] = Vector2.INF
		var foe := _nearest_foe_xz(tree, pos)
		if foe != Vector2.INF and pos.distance_to(foe) < 8.0:
			_leave_attack(tree, player, bot, origin_xz, job, delta, pos)
			return ""
		_step_toward(bot, player, _orbit_wait(origin_xz, pos), delta, pos, true)
		return ""
	var deep := _deep_stand(crystal, origin, pos)
	if not deep_here:
		job["dodge"] = Vector2.INF
		_step_toward(bot, player, deep, delta, pos, true)
		return ""
	if not bool(job.get("stand_logged", false)):
		job["stand_logged"] = true
		print("HARNESS burn stand tier %d hp %.1f" % [tier, float(player.health)])
	job["dodge"] = Vector2.INF
	bot.release()
	if burn_up:
		if not bool(job["burn_seen"]):
			job["burn_seen"] = true
			job["burn_hp"] = float(player.health)
			print("HARNESS burn warning hp %.1f" % float(player.health))
		elif float(player.health) < float(job["burn_hp"]) - 0.05:
			job["burned"] = true
			print("HARNESS burn hit %.1f to %.1f" % [float(job["burn_hp"]), float(player.health)])
			var away := _Hazard.leave_goal(tree, pos, origin_xz)
			_step_toward(bot, player, away, delta, pos)
	return ""


func _tick_combat(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, fight, cast, job: Dictionary, delta: float, pos: Vector2) -> String:
	_note_hit_feedback(tree, job)
	if not bool(job["struck"]):
		if _attack_warn(tree):
			bot.release()
			if float(job["warn_hp"]) < 0.0:
				job["warn_hp"] = float(player.health)
				job["warned"] = true
				print("HARNESS attack warning hp %.1f" % float(player.health))
			elif float(player.health) < float(job["warn_hp"]) - 0.05:
				job["struck"] = true
				print("HARNESS warning hit %.1f to %.1f" % [float(job["warn_hp"]), float(player.health)])
			return ""
		if pos.distance_to(origin_xz) > 12.0:
			_step_toward(bot, player, origin_xz, delta, pos)
			return ""
		_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
		return ""
	if not bool(job["melee"]):
		if _attack_warn(tree) or _Hazard.ring_hot(tree, pos):
			_step_away(tree, player, bot, origin_xz, delta, pos)
			return ""
		var rows := _near_foes(tree, pos)
		fight.set_vitals(float(player.health), float(player.max_health))
		fight.observe(rows)
		var foe_id := str(job["foe_id"])
		if foe_id != "":
			var now_hp := _foe_health(tree, foe_id)
			var was := float(job["foe_hp"])
			if was >= 0.0 and (now_hp < 0.0 or now_hp < was - 0.05):
				job["melee"] = true
				print("HARNESS melee %s %.1f to %.1f" % [foe_id, was, now_hp])
				fight.release()
				return ""
		if foe_id == "" or not _foe_alive(tree, foe_id):
			foe_id = fight.nearest_id(pos)
			job["foe_id"] = foe_id
			job["foe_hp"] = _foe_health(tree, foe_id)
		if foe_id == "":
			_step_toward(bot, player, origin_xz, delta, pos)
			return ""
		var aim_at := Vector2.INF
		for row in rows:
			if str(row.get("id", "")) == foe_id:
				aim_at = row["xz"]
				break
		bot.release()
		if aim_at != Vector2.INF:
			hands.begin_tick()
			hands.aim_column(player, aim_at.x, aim_at.y)
			fight.aim_ready = _foe_aimed(player, aim_at)
		fight.tick(pos, _yaw(player), delta)
		return ""
	if bool(job["skilled"]):
		bot.release()
		return ""
	if _points(tree) < 1 and not _unlocked(tree, "dash"):
		if not bool(job.get("farm_logged", false)):
			job["farm_logged"] = true
			print("HARNESS skill farm points %d" % _points(tree))
		if _attack_warn(tree):
			_step_away(tree, player, bot, origin_xz, delta, pos)
			return ""
		_swing_film(tree, player, crystal, origin, origin_xz, bot, hands, job, delta, pos, false)
		return ""
	if bool(job.get("dash_walk", false)):
		var mark: Vector2 = job.get("dash_from", pos)
		if pos.distance_to(mark) < 6.0:
			var goal: Vector2 = job.get("dash_goal", Vector2.INF)
			if goal == Vector2.INF:
				var side := pos - origin_xz
				if side.length() < 0.4:
					side = Vector2(1.0, 0.0)
				side = Vector2(-side.y, side.x).normalized()
				goal = _Hazard.skirt_goal(tree, pos, pos + side * 12.0)
				job["dash_goal"] = goal
			_step_toward(bot, player, goal, delta, pos, true)
			return ""
		job["dash_walk"] = false
		job["dash_goal"] = Vector2.INF
	if not bool(job["cast_on"]):
		cast.begin("skill_dash")
		job["cast_on"] = true
	var result: String = cast.tick(delta, tree, player, hands, bot, origin_xz, null)
	if result == "pass":
		job["skilled"] = true
		print("HARNESS skill dash")
		return ""
	if result == "fail":
		if int(job.get("dash_tries", 0)) >= 2:
			return "dash did not cast"
		job["dash_tries"] = int(job.get("dash_tries", 0)) + 1
		job["cast_on"] = false
		job["dash_walk"] = true
		job["dash_from"] = pos
		job["dash_goal"] = Vector2.INF
		bot.release()
		return ""
	return ""


func _swing_film(tree: SceneTree, player: Node, crystal: Node, origin: Vector2i, origin_xz: Vector2, bot, hands, job: Dictionary, delta: float, pos: Vector2, any_film: bool) -> void:
	if _attack_warn(tree):
		_step_away(tree, player, bot, origin_xz, delta, pos)
		return
	var cell: Vector2i = job["cell"]
	if cell.x > 900000 or int(job["swings"]) >= 10:
		cell = _film_cell(crystal, origin, pos, any_film)
		job["cell"] = cell
		job["swings"] = 0
		job["pick"] = false
	if cell.x > 900000:
		_step_toward(bot, player, origin_xz, delta, pos)
		return
	var stand := _stand_near(crystal, cell, pos)
	if pos.distance_to(stand) > 0.8:
		_step_toward(bot, player, stand, delta, pos)
		return
	if _GI.blocks_actions():
		bot.release()
		return
	bot.release()
	hands.begin_tick()
	hands.aim_column(player, float(cell.x) + 0.5, float(cell.y) + 0.5)
	if not bool(job["pick"]):
		if hands.pulse(&"hotbar_2"):
			job["pick"] = true
		return
	job["gap"] = float(job["gap"]) - delta
	if float(job["gap"]) > 0.0:
		return
	if hands.pulse(&"attack"):
		job["swings"] = int(job["swings"]) + 1
		job["gap"] = SWING_GAP


func _swing_heart(tree: SceneTree, player: Node, origin: Vector2i, bot, hands, job: Dictionary, delta: float, pos: Vector2) -> void:
	var cell_origin := Vector2(float(origin.x), float(origin.y))
	var aim := cell_origin + Vector2(0.5, 0.5)
	var pad := _Hazard.sword_pad(tree, cell_origin)
	if pad == Vector2.INF:
		pad = aim + Vector2(1.6, 0.2)
	if pos.distance_to(pad) > 0.8:
		job["aim_hold"] = 0.0
		_step_toward(bot, player, pad, delta, pos)
		return
	if _GI.blocks_actions():
		bot.release()
		return
	bot.release()
	hands.begin_tick()
	hands.aim_column(player, aim.x, aim.y)
	var facing := _Nav.face_action(pos, aim, _yaw(player))
	if facing != "":
		job["aim_hold"] = 0.0
		hands.set_held(PackedStringArray([facing]))
		return
	var locked := _heart_aimed(player, origin)
	if locked:
		job["aim_hold"] = 0.0
	else:
		job["aim_hold"] = float(job.get("aim_hold", 0.0)) + delta
	if not locked and float(job["aim_hold"]) < 0.35:
		return
	if not bool(job["sword"]):
		if hands.pulse(&"hotbar_1"):
			job["sword"] = true
		return
	job["gap"] = float(job["gap"]) - delta
	if float(job["gap"]) > 0.0:
		return
	if hands.pulse(&"attack"):
		if not bool(job.get("sword_logged", false)):
			job["sword_logged"] = true
			print("HARNESS sword at heart")
		job["gap"] = _Pace.strike_gap("sword_swing")


func _note_hit_feedback(tree: SceneTree, job: Dictionary) -> void:
	if bool(job.get("feedback", false)):
		return
	var vfx := tree.get_first_node_in_group("combat_visual_feedback")
	if vfx == null:
		return
	var marks = vfx.get_node_or_null("HitMarkers")
	if marks == null or not marks.has_method("has_live"):
		return
	if not bool(marks.has_live()):
		return
	job["feedback"] = true
	print("HARNESS hit feedback")


func _foe_aimed(player: Node, foe: Vector2) -> bool:
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return false
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return false
	var cell := Vector2(float(floori(shared.x)) + 0.5, float(floori(shared.z)) + 0.5)
	return cell.distance_to(foe) <= 1.15


func _heart_aimed(player: Node, origin: Vector2i) -> bool:
	var hl = player.get_node_or_null("TargetHighlight")
	if hl == null or not hl.has_method("get_action_column"):
		return false
	var shared: Vector3 = hl.get_action_column()
	if shared == Vector3.ZERO:
		return false
	var cell := Vector2(float(floori(shared.x)) + 0.5, float(floori(shared.z)) + 0.5)
	var want := Vector2(float(origin.x) + 0.5, float(origin.y) + 0.5)
	return cell.distance_to(want) <= 1.15


func _step_toward(bot, player: Node, goal: Vector2, delta: float, pos: Vector2, sprint_now: bool = false) -> void:
	if bot.gave_up:
		var spin := float(bot.stuck_reports + 1)
		bot.set_target(goal + Vector2(spin, -spin))
	elif not bot.has_target or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	var extras := PackedStringArray()
	if sprint_now or pos.distance_to(goal) > 6.0:
		extras.append("sprint")
	bot.extra_held = extras
	bot.tick(pos, _yaw(player), delta)


func _orbit_wait(origin_xz: Vector2, pos: Vector2) -> Vector2:
	var offset := pos - origin_xz
	if offset.length() < 8.0:
		if offset.length() < 0.2:
			offset = Vector2(1.0, 0.0)
		else:
			offset = offset.normalized()
		return origin_xz + offset * 12.0
	var side := Vector2(-offset.y, offset.x)
	if side.length_squared() < 0.01:
		side = Vector2(0.0, 1.0)
	return pos + side.normalized() * 4.0


func _leave_attack(tree: SceneTree, player: Node, bot, origin_xz: Vector2, job: Dictionary, delta: float, pos: Vector2) -> void:
	var foe := _nearest_foe_xz(tree, pos)
	var away := pos - foe if foe != Vector2.INF else pos - origin_xz
	var reach := 6.0
	for row in _Hazard.guardian_bubbles(tree):
		if typeof(row) != TYPE_DICTIONARY or not bool(row.get("hard", false)):
			continue
		reach = maxf(reach, float(row.get("radius", reach)))
		var at: Vector2 = row.get("xz", pos)
		var from_ring := pos - at
		if from_ring.length_squared() > 0.01:
			away = from_ring
	var proposed := _Hazard.slam_exit(pos, away, reach, origin_xz)
	if _Hazard.depth_at(tree, proposed) >= _Hazard.BURN_DEPTH:
		var clear := _Hazard.leave_goal(tree, pos, origin_xz)
		if clear != Vector2.INF:
			proposed = clear
	var previous: Vector2 = job.get("dodge", Vector2.INF)
	var goal := _Hazard.keep_dodge(pos, previous, proposed)
	job["dodge"] = goal
	_step_toward(bot, player, goal, delta, pos, true)


func _step_away(tree: SceneTree, player: Node, bot, origin_xz: Vector2, delta: float, pos: Vector2) -> void:
	var foe := _nearest_foe_xz(tree, pos)
	var action := "move_back"
	if foe != Vector2.INF:
		action = _Hazard.flee_action(pos, foe, _yaw(player))
	else:
		var away := _Hazard.leave_goal(tree, pos, origin_xz)
		_step_toward(bot, player, away, delta, pos)
		return
	bot.release()
	bot.input.begin_tick()
	var held := PackedStringArray()
	held.append(action)
	held.append("sprint")
	bot.input.set_held(held)


func _film_cell(crystal: Node, origin: Vector2i, pos: Vector2, any_film: bool) -> Vector2i:
	var best := Vector2i(999999, 999999)
	var best_d := 1.0e9
	for dz in range(-14, 15):
		for dx in range(-14, 15):
			var cell := Vector2i(origin.x + dx, origin.y + dz)
			if not any_film and cell == origin:
				continue
			var depth := float(crystal.get_depth_at(cell.x, cell.y))
			if depth < FILM_DEPTH:
				continue
			var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
			var dist := pos.distance_to(at)
			if dist < best_d:
				best_d = dist
				best = cell
	return best


func _stand_near(crystal: Node, cell: Vector2i, pos: Vector2) -> Vector2:
	var best := Vector2(float(cell.x) + 2.2, float(cell.y) + 0.5)
	var best_d := 1.0e9
	var center := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var at := Vector2(float(cell.x + dx) + 0.5, float(cell.y + dz) + 0.5)
			var span := at.distance_to(center)
			if span < 1.35 or span > 2.5:
				continue
			if float(crystal.get_depth_at(cell.x + dx, cell.y + dz)) >= _Hazard.BURN_DEPTH:
				continue
			var walk := at.distance_to(pos)
			if walk < best_d:
				best_d = walk
				best = at
	return best


func _deep_stand(crystal: Node, origin: Vector2i, pos: Vector2) -> Vector2:
	var best := Vector2(float(origin.x) + 0.5, float(origin.y) + 0.5)
	var best_d := 1.0e9
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var cell := Vector2i(origin.x + dx, origin.y + dz)
			if float(crystal.get_depth_at(cell.x, cell.y)) < _Hazard.BURN_DEPTH:
				continue
			var at := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
			var dist := pos.distance_to(at)
			if dist < best_d:
				best_d = dist
				best = at
	return best


func _corrupt_near(origin: Vector2i, radius: int) -> int:
	var count := 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var feat: Dictionary = _Features.get_feature(origin.x + dx, origin.y + dz)
			if bool(feat.get("corrupt", false)):
				count += 1
	return count


func _attack_warn(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node):
			continue
		var disc := node.get_node_or_null("StrikeTelegraph")
		if disc != null and disc.visible:
			return true
		var ring := node.get_node_or_null("TelegraphRing")
		if ring != null and ring.visible:
			return true
	return false


func _foe_rows(tree: SceneTree) -> Array:
	var rows: Array = []
	_collect_foes(rows, tree.get_nodes_in_group("crystal_enemy"), "enemy_id")
	_collect_foes(rows, tree.get_nodes_in_group("world_entity"), "entity_kind")
	return rows


func _collect_foes(rows: Array, nodes: Array, kind_field: String) -> void:
	for node in nodes:
		if not is_instance_valid(node) or float(node.get("health")) <= 0.0:
			continue
		var kind := str(node.get(kind_field))
		if kind == "town_villager" or kind == "town_militia":
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col: Vector2i = _Move.column_pos(body.global_position)
		rows.append({
			"id": str(node.get_instance_id()),
			"kind": kind,
			"xz": Vector2(float(col.x) + 0.5, float(col.y) + 0.5),
		})


func _near_foes(tree: SceneTree, pos: Vector2) -> Array:
	var close: Array = []
	for row in _foe_rows(tree):
		if str(row.get("kind", "")) == "origin_warden":
			continue
		var at: Vector2 = row["xz"]
		if pos.distance_to(at) > 28.0:
			continue
		close.append(row)
	return close


func _nearest_foe_xz(tree: SceneTree, pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := 1.0e9
	for row in _foe_rows(tree):
		var at: Vector2 = row["xz"]
		var dist := pos.distance_to(at)
		if dist < best_d:
			best_d = dist
			best = at
	return best


func _foe_alive(tree: SceneTree, foe_id: String) -> bool:
	return _foe_health(tree, foe_id) > 0.0


func _foe_health(tree: SceneTree, foe_id: String) -> float:
	if foe_id == "":
		return -1.0
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if str(node.get_instance_id()) != foe_id:
			continue
		if not is_instance_valid(node):
			return -1.0
		return float(node.get("health"))
	return -1.0


func _heart_hp(crystal: Node) -> float:
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return -1.0
	var prog: Dictionary = crystal.get_spawn_progress()
	return float(prog.get("crystal_health", -1.0))


func _count(player: Node, item_id: String) -> int:
	var inv = player.get("inventory")
	if inv == null or not inv.has_method("count_item"):
		return 0
	return int(inv.count_item(item_id))


func _points(tree: SceneTree) -> int:
	var svc := tree.get_first_node_in_group("progression_service")
	if svc == null:
		return 0
	return int(svc.get("skill_points"))


func _unlocked(tree: SceneTree, skill_id: String) -> bool:
	var skills := tree.get_first_node_in_group("skill_service")
	if skills == null or not skills.has_method("is_unlocked"):
		return false
	return bool(skills.is_unlocked(StringName(skill_id)))


func _expect_feature(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray, job: Dictionary) -> String:
	if not bool(after.get("hp_panel", false)):
		return "hp bar hidden"
	var want_hp := "%d / %d" % [int(round(float(after.get("hp", 0.0)))), int(round(float(after.get("max", 0.0))))]
	if str(after.get("hp_label", "")) != want_hp:
		return "hp label %s want %s" % [str(after.get("hp_label", "")), want_hp]
	if not _saw(seen, OPENING_BANNER):
		return "opening banner missing"
	for line in seen:
		if not _banner_allowed(line):
			return "unexpected banner %s" % line
	if name == "crystals":
		if absf(float(after.get("hp", -1.0)) - float(before.get("hp", -2.0))) > 0.01:
			return "hp changed"
		if int(after.get("shards", 0)) <= int(before.get("shards", 0)):
			return "shards did not increase"
		if float(after.get("heart", -1.0)) >= float(before.get("heart", -2.0)) - 0.05:
			return "crystal hp did not fall"
		return ""
	if float(after.get("hp", 1.0)) >= float(before.get("hp", 0.0)) - 0.05:
		return "hp did not fall"
	if name == "corruption":
		if not bool(job.get("spread", false)):
			return "corruption did not spread"
		if not bool(job.get("cleansed", false)):
			return "scar did not start"
		if not bool(job["burn_seen"]):
			return "burn warning missing"
		return ""
	if not bool(job["warned"]):
		return "attack warning missing"
	if not bool(job["melee"]):
		return "melee missed"
	if not bool(job.get("feedback", false)):
		return "hit feedback missing"
	if not bool(job["skilled"]):
		return "dash missing"
	return ""


func _banner_allowed(line: String) -> bool:
	if line == OPENING_BANNER or line == WALL_BANNER:
		return true
	var prefixes: PackedStringArray = PackedStringArray([
		"First steps ",
		"Trench ",
		"Gate ",
		"Bridge ",
		"Bank to water",
		"Enemy unlocked:",
		"Boss warning",
		"Crystal coverage",
		"Crystal pressure",
		"Crystal hostiles",
		"Crystal cracked",
		"ASSAULT ",
		"Maze again",
		"Level up ",
		"Skill unlocked",
		"Relic ",
		"Discovered ",
		"Landmark ",
		"You rallied ",
		"Origin Warden",
		"Shard Tyrant",
		"Used herb",
	])
	for prefix in prefixes:
		if line.begins_with(prefix):
			return true
	if " fell " in line or line.ends_with(" fell."):
		return true
	if " is under " in line or " calls " in line:
		return true
	return false


func _print_feature(name: String, before: Dictionary, after: Dictionary, seen: PackedStringArray, job: Dictionary) -> void:
	var corrupt_now := int(after.get("corrupt", 0))
	var scars_now := int(after.get("scars", 0))
	var corrupt_peak := maxi(corrupt_now, int(job.get("corrupt_seen", corrupt_now)))
	var scars_peak := maxi(scars_now, int(job.get("scars_seen", scars_now)))
	print("HARNESS see %s shards %d to %d heart %.1f to %.1f corrupt %d to %d now %d scars %d to %d now %d hp %s banners %s" % [
		name,
		int(before.get("shards", 0)),
		int(after.get("shards", 0)),
		float(before.get("heart", -1.0)),
		float(after.get("heart", -1.0)),
		int(before.get("corrupt", 0)),
		corrupt_peak,
		corrupt_now,
		int(before.get("scars", 0)),
		scars_peak,
		scars_now,
		str(after.get("hp_label", "")),
		"|".join(seen),
	])


const MITE_LIMIT := 150.0
const MITE_CLEAR := 16.0


func _play_mite(tree: SceneTree) -> int:
	var seeds: Array = _mite_seeds()
	var lived := 0
	var killed_runs := 0
	for seed_value in seeds:
		var seed := int(seed_value)
		var row: Dictionary = await _mite_attempt(tree, seed)
		var survived: bool = bool(row.get("survive", false))
		var kills := int(row.get("kills", 0))
		var sprints := int(row.get("burn_sprint", 0))
		if survived:
			lived += 1
		if kills > 0:
			killed_runs += 1
		print("HARNESS mite seed %d survive %s kill %d burn_sprint %d" % [
			seed, "yes" if survived else "no", kills, sprints,
		])
		if not survived or kills < 1 or sprints > 0:
			var why := str(row.get("why", "mite fight failed"))
			print("FAIL harness assertion %s" % why)
			var bot = row.get("bot", null)
			if bot != null:
				var at: Vector2 = row.get("pos", Vector2.ZERO)
				bot.home = at
				bot.fail_closed(at, why)
			return 1
	print("HARNESS mite %d/%d survive %d/%d kill" % [lived, seeds.size(), killed_runs, seeds.size()])
	return 0


func _mite_seeds() -> Array:
	var one := OS.get_environment("CRYSTALSTORM_HARNESS_SEED").strip_edges()
	if one != "":
		return [int(one)]
	var many := OS.get_environment("CRYSTALSTORM_HARNESS_SEEDS").strip_edges()
	if many != "":
		var picked: Array = []
		for part in many.split(","):
			var bit := part.strip_edges()
			if bit != "":
				picked.append(int(bit))
		if not picked.is_empty():
			return picked
	return [12349, 12350, 12351, 12352, 12353]


func _mite_attempt(tree: SceneTree, seed_value: int) -> Dictionary:
	print("HARNESS seed %d" % seed_value)
	print("HARNESS setup pending_launch harness-mite_fight seed %d resume off" % seed_value)
	var seen: PackedStringArray = PackedStringArray()
	var player = await _boot(tree, "mite_fight", seen, seed_value)
	if player == null:
		return {"survive": false, "kills": 0, "burn_sprint": 0, "why": "boot failed"}
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		await _drop_game(tree, player)
		return {"survive": false, "kills": 0, "burn_sprint": 0, "why": "no crystal"}
	var origin: Vector2i = crystal.get_origin_cell()
	var origin_xz := Vector2(float(origin.x), float(origin.y))
	var fight = _Fight.new()
	fight._phase = "hunt"
	fight._home_arrived = true
	fight._home_logged = true
	fight.finish_bow()
	fight.bot.chapter = "mite_fight"
	fight.bot.objective = "kill the crystal mites from the clear rim"
	fight.bot.stuck_limit = 24
	fight.bot.input.pace_presses = true
	var elapsed := 0.0
	var clear := 0.0
	var burn_sprint := 0
	var why := ""
	var last_pos := Vector2.ZERO
	while elapsed < MITE_LIMIT:
		var delta := _delta(tree)
		elapsed += delta
		fight.bot.input.advance_pace(delta)
		_note_banner(tree, seen)
		if float(player.health) <= 0.0:
			var died_at := _xz(player)
			why = "player died seed %d depth %.2f dist %.1f" % [
				seed_value, _Hazard.depth_at(tree, died_at), died_at.distance_to(origin_xz),
			]
			break
		var result := fight.tick(delta, tree, player, origin_xz)
		var pos := _xz(player)
		last_pos = pos
		if _burn_sprint(tree, fight, player, pos):
			burn_sprint += 1
		var mark := int(elapsed)
		if mark > 0 and mark % 5 == 0 and int(elapsed - delta) != mark:
			print("HARNESS mite trace t %d dist %.1f depth %.2f hp %.0f burn_sprint %d" % [
				mark, pos.distance_to(origin_xz), _Hazard.depth_at(tree, pos), float(player.health), burn_sprint,
			])
		if result == "fail":
			why = "fight returned fail seed %d" % seed_value
			break
		var kills := int(fight.killed.get("crystal_mite", 0))
		var near := _mites_near(tree, origin_xz, MITE_CLEAR)
		if kills >= 1 and near == 0 and not _Hazard.burning(tree, pos) and not _Hazard.must_leave(tree, pos):
			clear += delta
		else:
			clear = 0.0
		if clear >= 1.0:
			break
		await tree.process_frame
	var survived := player != null and float(player.health) > 0.0 and why == ""
	var total := int(fight.killed.get("crystal_mite", 0))
	if why == "" and not _saw(seen, OPENING_BANNER):
		why = "opening banner missing"
		survived = false
	if why == "" and total < 1:
		why = "no mite kill seed %d" % seed_value
	if why == "" and burn_sprint > 0:
		why = "burn sprint %d seed %d" % [burn_sprint, seed_value]
	var after := _snap(tree, player)
	if survived:
		var want_hp := "%d / %d" % [int(round(float(after.get("hp", 0.0)))), int(round(float(after.get("max", 0.0))))]
		if str(after.get("hp_label", "")) != want_hp:
			why = "hp label %s want %s" % [str(after.get("hp_label", "")), want_hp]
			survived = false
	print("HARNESS see mite_fight seed %d kills %d burn_sprint %d hp %s" % [
		seed_value, total, burn_sprint, str(after.get("hp_label", "")),
	])
	var shot := ""
	if survived and why == "":
		shot = fight.bot.save_view("mite_fight", _xz(player))
		if shot == "":
			why = "screenshot was not saved"
			survived = false
	fight.bot.release()
	var kept = fight.bot
	await _drop_game(tree, player)
	return {
		"survive": survived and why == "",
		"kills": total,
		"burn_sprint": burn_sprint,
		"why": why,
		"bot": kept,
		"pos": last_pos,
	}


func _burn_sprint(tree: SceneTree, fight, player: Node, pos: Vector2) -> bool:
	var names: PackedStringArray = fight.bot.input.held_names()
	var sprinting := false
	var dashing := false
	for action in names:
		if String(action) == "sprint":
			sprinting = true
		if String(action) == "skill_1" or String(action) == "dash":
			dashing = true
	var goal: Vector2 = fight.bot.home
	var through := _Hazard.burning(tree, pos) or _Hazard.burning(tree, goal) or _Hazard.crosses_burn(tree, pos, goal)
	if sprinting and through:
		return true
	return dashing and _Hazard.dash_lands_in_burn(tree, pos, _yaw(player))


func _mites_near(tree: SceneTree, origin: Vector2, radius: float) -> int:
	var count := 0
	if tree == null:
		return 0
	for node in tree.get_nodes_in_group("crystal_enemy"):
		if not is_instance_valid(node) or str(node.get("enemy_id")) != "crystal_mite":
			continue
		if float(node.get("health")) <= 0.0:
			continue
		var body := node as Node3D
		if body == null:
			continue
		var col := _Move.column_pos(body.global_position)
		var at := Vector2(float(col.x) + 0.5, float(col.y) + 0.5)
		if at.distance_to(origin) <= radius:
			count += 1
	return count


func _drop_game(tree: SceneTree, player: Node) -> void:
	var game := player
	while game != null and game.name != "Game":
		game = game.get_parent()
	if game != null and game != tree.root:
		game.queue_free()
	for _i in 30:
		await tree.process_frame
		if tree.get_first_node_in_group("player") == null:
			break


func _yaw(player: Node) -> float:
	var cam = player.get("camera")
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	return 0.0
