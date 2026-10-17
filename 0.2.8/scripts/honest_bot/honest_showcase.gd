extends RefCounted

const _Route = preload("res://scripts/honest_bot/honest_route.gd")
const _Walk = preload("res://scripts/honest_bot/honest_traversal.gd")
const _Nav = preload("res://scripts/honest_bot/honest_nav.gd")
const _Bot = preload("res://scripts/honest_bot/honest_play_bot.gd")
const _Hands = preload("res://scripts/honest_bot/honest_input.gd")
const _Sun = preload("res://helpers/terrain_lighting.gd")
const _Marks = preload("res://world/distant_landmarks.gd")
const _Coords = preload("res://helpers/world_visual_coords.gd")
const _Tutorial = preload("res://ui/tutorial_overlay.gd")
const _World = preload("res://world/world_state.gd")
const _GI = preload("res://helpers/gameplay_input.gd")
const _Water = preload("res://helpers/water_locomotion.gd")
const _Build = preload("res://scripts/honest_bot/honest_build.gd")
const _Fight = preload("res://scripts/honest_bot/honest_fight.gd")
const _Cast = preload("res://scripts/honest_bot/honest_skill_cast.gd")
const _Finale = preload("res://scripts/honest_bot/honest_showcase_finale.gd")
const _Pace = preload("res://scripts/honest_bot/honest_pace.gd")
const _Farm = preload("res://scripts/honest_bot/honest_farm.gd")
const _Hazard = preload("res://scripts/honest_bot/honest_hazard.gd")
const _Relic = preload("res://ui/relic_choice_panel.gd")

const ROUTE_PATH := "res://docs/showcase/ROUTE.md"
const MOVE_COLUMNS := 8.0
const MOVE_LIMIT := 22.0
const LIGHT_HOLD := 4.0
const BOOT_LIMIT := 8.0
const FACE_LIMIT := 2.5
const PICKUP_LIMIT := 8.0
const DETOUR_STUCK := 12
const DETOUR_RESUMES := 6
const TREASURE_TOUCH := 9.0
const TREASURE_SAFE := 24.0

const READY: Array[String] = [
	"boot_tutorial",
	"movement",
	"lighting",
	"day_night",
	"dig_tool",
	"structure_place",
	"density_poi",
	"density_treasure",
	"density_landmark",
	"combat_crystal_mite",
	"combat_farm_bomber",
	"combat_crystal_stag",
	"combat_thornling",
	"combat_corrupted_beast",
	"combat_crystal_wisp",
	"combat_shard_guard",
	"combat_spawn_elite",
	"xp_level",
	"skill_dash",
	"skill_ground_slam",
	"multiblock_break",
	"skill_crystal_pulse",
	"skill_quick_wall",
	"skill_passives",
	"crystal",
	"boss",
	"win_screen",
]

var bot = _Bot.new()
var hands = _Hands.new()
var route: Dictionary = {}
var ids: PackedStringArray = PackedStringArray()
var finished := false
var failed := false
var tree: SceneTree
var player: Node
var hud: Node
var chapters: RefCounted
var origin := Vector2.ZERO
var _sun_basis := Basis.IDENTITY
var _sun_basis_ready := false
var _cursor := 0
var _seg := ""
var _seg_age := 0.0
var _seg_status := ""
var _boot_step := 0
var _move_start := Vector2.ZERO
var _move_armed := false
var _jump_sent := false
var _left_ground := false
var _sprint_seen := false
var _swim_hold := false
var _swim_release := false
var _unstuck_sent := false
var _detour_face := Vector2.ZERO
var _detour_goal := Vector2.ZERO
var _detour_label := ""
var _detour_limit := 20.0
var _detour_resumes := 0
var _face_only := false
var _face_age := 0.0
var _pickup_wait := false
var _pickup_age := 0.0
var _ruins_before := 0
var _treasure_clear := false
var _chain: Dictionary = {}
var _chain_ready := false
var _lights_noted := false
var _bow_stamped := false
var _hold_status := ""
var _pose := ""
var _pose_age := 0.0
var build = _Build.new()
var fight = _Fight.new()
var caster = _Cast.new()
var finale = _Finale.new()
var _banner_left := 0.0
var _glow_leg := false
var _glow_done := false
var _glow_goal := Vector2.ZERO
var _glow_face := Vector2.ZERO
var _glow_limit := 20.0
var _glow_walk := false
var _paced_level := -1
var _relic_paced := false
var _stage_hit: Array[bool] = [false, false, false]


func load_route() -> bool:
	route = _Route.from_file(ROUTE_PATH)
	ids = _Route.ids(route)
	return not ids.is_empty()


func first_blocked() -> String:
	for id in ids:
		var name := String(id)
		if not _is_ready(name):
			return name
	return ""


func bind(host: SceneTree, body: Node, heart: Vector2, overlay: Node, log: RefCounted) -> void:
	tree = host
	player = body
	origin = heart
	hud = overlay
	chapters = log
	_remember_sun()


func tick(delta: float) -> bool:
	if finished:
		return true
	var step := delta
	if step <= 0.0:
		step = 1.0 / 60.0
	_advance_clock(step)
	_arm_pace(step)
	if _seg != "":
		_note_beats()
	if _banner_left > 0.0:
		_banner_left = maxf(_banner_left - step, 0.0)
		if not _unsafe():
			_idle_inputs()
			_paint()
			return finished
	if _seg == "":
		if not _pull_next():
			finished = true
			_paint()
			return true
	_seg_age += step
	if _hold_status == "":
		_sync_bow()
		_sync_farm()
		_run_segment(step)
		if _seg_status != "":
			_hold_status = _seg_status
			_seg_status = ""
	elif _chapter_ready():
		_seg_status = _hold_status
		_hold_status = ""
		_finish_segment()
	_paint()
	return finished


func _pull_next() -> bool:
	if player != null and float(player.get("health")) <= 0.0:
		print("FAIL showcase died")
		failed = true
		return false
	while _cursor < ids.size():
		var id := String(ids[_cursor])
		_cursor += 1
		if not _is_ready(id):
			print("SHOWCASE NEXT %s" % id)
			return false
		_open_segment(id)
		return true
	return false


func _is_ready(id: String) -> bool:
	for name in READY:
		if name == id:
			return true
	return false


func _open_segment(id: String) -> void:
	_seg = id
	_seg_age = 0.0
	_seg_status = ""
	_boot_step = 0
	_jump_sent = false
	_left_ground = false
	_sprint_seen = false
	_swim_hold = false
	_swim_release = false
	_unstuck_sent = false
	_face_only = false
	_face_age = 0.0
	_pickup_wait = false
	_pickup_age = 0.0
	_detour_label = ""
	_detour_resumes = 0
	_pose = ""
	_pose_age = 0.0
	_hold_status = ""
	_move_armed = false
	bot.stuck_limit = 0
	bot.extra_held = PackedStringArray()
	bot.release()
	hands.release_all()
	if id.begins_with("density_"):
		_arm_detour(id)
		return
	if chapters != null and chapters.has_method("open"):
		var feature := id
		if id == "structure_place":
			feature = "structure_stone_wall"
		elif id == "day_night":
			feature = "night"
		chapters.open(feature)
	if id == "movement":
		_arm_movement()
	elif id == "dig_tool" or id == "structure_place":
		build.reset(id)
	elif id == "combat_crystal_mite":
		fight.reset()
		var prior: Dictionary = _chain.get("density_treasure", {})
		if str(prior.get("status", "")) == "walk":
			fight.skip_site(prior.get("xz", Vector2.ZERO))
	elif id == "xp_level" or id.begins_with("skill_") or id == "multiblock_break":
		if caster == null:
			print("FAIL skill cast missing")
			_seg_status = "fail"
			return
		caster.begin(id)
	elif id == "crystal" or id == "boss" or id == "win_screen":
		if id == "crystal" and not _Farm.ready(fight.level_now(), fight.remainder_now()):
			print("FAIL crystal before level 3 earned %d" % _Farm.earned(fight.level_now(), fight.remainder_now()))
			_seg_status = "fail"
			return
		finale.begin(id)


func _finish_segment() -> void:
	var status := _seg_status
	var stop := status == "fail" and (_seg == "crystal" or _seg == "boss" or _seg == "win_screen")
	if status == "fail":
		failed = true
	if chapters != null and chapters.has_method("close"):
		chapters.close()
	print("SHOWCASE %s %s" % [_seg, status])
	for line in bot.stuck_lines:
		print(line)
	bot.stuck_lines = PackedStringArray()
	bot.extra_held = PackedStringArray()
	bot.stuck_limit = 0
	bot.release()
	hands.release_all()
	fight.release()
	if stop:
		finale.release()
		finished = true
	_seg = ""
	_seg_status = ""


func _run_segment(step: float) -> void:
	if _seg_status != "":
		return
	match _seg:
		"boot_tutorial":
			_tick_boot()
		"movement":
			_tick_movement(step)
		"lighting":
			_tick_lighting()
		"day_night":
			_tick_day_night(step)
		"dig_tool", "structure_place":
			_tick_build(step)
		"density_poi", "density_treasure", "density_landmark":
			_tick_detour(step)
		"combat_crystal_mite":
			_tick_hunt(step)
		"combat_farm_bomber", "combat_crystal_stag", "combat_thornling", "combat_corrupted_beast", "combat_crystal_wisp", "combat_shard_guard", "combat_spawn_elite":
			_tick_kind()
		"xp_level", "skill_dash", "skill_ground_slam", "multiblock_break", "skill_crystal_pulse", "skill_quick_wall", "skill_passives":
			_tick_cast(step)
		"crystal", "boss", "win_screen":
			_tick_finale(step)
		_:
			_seg_status = "fail"


func _tick_boot() -> void:
	if _tutorial_open():
		_pulse_pause()
		if _seg_age >= BOOT_LIMIT:
			print("FAIL boot tutorial still open")
			_seg_status = "fail"
		return
	if player == null or not bool(player.get("world_ready")) or _GI.blocks_actions():
		if _seg_age >= BOOT_LIMIT:
			print("FAIL boot player cannot move")
			_seg_status = "fail"
		return
	_seg_status = "pass"


func _pulse_pause() -> void:
	if _boot_step == 0:
		if hands.pulse("pause"):
			_boot_step = 1
		return
	if _boot_step == 1:
		hands.begin_tick()
		_boot_step = 2
		return
	if _boot_step == 2:
		if hands.pulse("pause"):
			_boot_step = 3
		return
	if _boot_step == 3:
		hands.begin_tick()
		_boot_step = 4


func _arm_movement() -> void:
	_move_start = _xz()
	var goal := origin
	if _move_start.distance_to(origin) < MOVE_COLUMNS + 2.0:
		var dir := origin - _move_start
		if dir.length_squared() < 0.04:
			dir = Vector2(0.0, -1.0)
		goal = _move_start + dir.normalized() * (MOVE_COLUMNS + 4.0)
	bot.set_target(goal)
	_move_armed = true


func _tick_movement(step: float) -> void:
	if not _move_armed:
		_arm_movement()
	var pos := _xz()
	var extras := PackedStringArray()
	extras.append("sprint")
	var wet := _submerged()
	if wet:
		extras.append("jump")
		_swim_hold = true
	elif _swim_hold:
		_swim_hold = false
		_swim_release = true
	bot.extra_held = extras
	bot.tick(pos, _yaw(), step)
	if _swim_release:
		_swim_release = false
		return
	if bot.input.is_held("sprint") and bot.input.is_held("move_forward"):
		_sprint_seen = true
	var moved := pos.distance_to(_move_start)
	var state := int(player.current_state) if player != null else 0
	if state == Player.State.JUMPING or state == Player.State.FALLING:
		_left_ground = true
	if not _jump_sent and not wet and moved >= 1.0 and _grounded(state):
		if bot.input.pulse("jump"):
			_jump_sent = true
	if moved >= MOVE_COLUMNS and _left_ground and _sprint_seen:
		print("OK movement columns %.2f jump true sprint true" % moved)
		_seg_status = "pass"
		return
	if bot.gave_up or _seg_age >= MOVE_LIMIT:
		_pulse_unstuck()
		print("FAIL movement columns %.2f jump %s sprint %s" % [
			moved, _left_ground, _sprint_seen,
		])
		_seg_status = "fail"


func _tick_lighting() -> void:
	bot.release()
	if _seg_age < LIGHT_HOLD:
		return
	var reason := _lighting_reason()
	if reason == "":
		_seg_status = "pass"
		return
	print("FAIL lighting %s" % reason)
	_seg_status = "fail"


func _tick_build(step: float) -> void:
	var result := build.tick(step, tree, player, hands, chapters)
	if result != "":
		_seg_status = result


func _tick_hunt(step: float) -> void:
	var result := fight.tick(step, tree, player, origin)
	if result != "":
		_seg_status = result


func _tick_kind() -> void:
	var kind := _seg.trim_prefix("combat_")
	_seg_status = fight.outcome(kind)


func _tick_finale(step: float) -> void:
	if finale == null:
		print("FAIL finale missing")
		_seg_status = "fail"
		return
	var result := finale.tick(step, tree, player)
	if result != "":
		_seg_status = result


func _tick_cast(step: float) -> void:
	if caster == null:
		print("FAIL skill cast missing")
		_seg_status = "fail"
		return
	var result := caster.tick(step, tree, player, hands, bot, origin, chapters)
	if result != "":
		_seg_status = result


func _tick_day_night(step: float) -> void:
	var order: PackedStringArray = ["night", "torch", "day_night"]
	if _pose == "" or not order.has(_pose):
		_pose = "night"
		_pose_age = 0.0
	if chapters == null or not chapters.has_method("open") or not chapters.has_method("span"):
		_note_lights()
		_seg_status = "absent"
		return
	if not bool(chapters.open(_pose)):
		return
	var waiting_night := _pose == "night" and _has_day_clock() and not _night_on()
	if waiting_night and chapters.span() < 90.0:
		hands.set_held(PackedStringArray())
		return
	var held := PackedStringArray()
	if not waiting_night and _pose_age >= _Pace.PRE_PAUSE and _pose_age < _Pace.PRE_PAUSE + 0.8:
		held.append("rotate_right")
	hands.set_held(held)
	_pose_age += step
	if chapters.span() < _Pace.PRE_PAUSE + _Pace.RESULT_HOLD + _Pace.SETTLE:
		return
	_log_light(_pose)
	var idx := order.find(_pose)
	if idx < 0 or idx + 1 >= order.size():
		_seg_status = "pass" if _has_day_clock() and _night_on() else "absent"
		return
	_pose = order[idx + 1]
	_pose_age = 0.0
	hands.set_held(PackedStringArray())


func _log_light(feature: String) -> void:
	if feature == "night":
		print("SHOWCASE night %s" % ("pass" if _night_on() else "absent"))
		return
	if feature == "torch":
		print("SHOWCASE torch %s" % ("pass" if _torch_on() else "absent"))
		return
	if _has_day_clock() and _night_on():
		print("SHOWCASE day_night pass")
		return
	print("SHOWCASE day_night absent")


func _arm_detour(id: String) -> void:
	_ensure_chain()
	var choice: Dictionary = _chain.get(id, {})
	var kind := str(choice.get("poi_kind", ""))
	_detour_label = id if kind == "" else "%s %s" % [id, kind]
	_open_chapter(_detour_label.replace(" ", "_"))
	if str(choice.get("status", "")) != "walk":
		print("OK %s too-far dist %.1f" % [id, float(choice.get("distance", -1.0))])
		_seg_status = "too-far"
		return
	var center: Vector2 = choice.get("xz", Vector2.ZERO)
	var gap := _detour_gap(id)
	var plan: Dictionary = _Walk.approach(_xz(), center, gap)
	_detour_face = center
	_detour_goal = plan.get("goal", center)
	_detour_limit = _Walk.leg_limit(float(choice.get("distance", 0.0)))
	_ruins_before = _ruin_count()
	_treasure_clear = false
	bot.stuck_limit = DETOUR_STUCK
	print("OK %s %s dist %.1f limit %.0f" % [id, kind if kind != "" else "site", float(choice.get("distance", 0.0)), _detour_limit])
	if not bool(plan.get("walk", false)):
		_begin_face()
		return
	bot.set_target(_detour_goal)


func _tick_detour(step: float) -> void:
	if _step_off_burn(step):
		return
	if _glow_leg:
		_tick_glow(step)
		return
	if _pickup_wait:
		_tick_pickup(step)
		return
	var pos := _xz()
	if _face_only:
		_face_age += step
		_tick_face(pos, step)
		return
	if _leave_ring(step):
		return
	var extras := PackedStringArray()
	if _submerged():
		extras.append("jump")
	else:
		extras.append("sprint")
	var dodge := _Hazard.dodge_point(pos, _detour_goal, _Hazard.guardian_bubbles(tree))
	if dodge != Vector2.INF and pos.distance_to(_detour_goal) > 8.0:
		var flee := _Hazard.flee_toward(pos, dodge, _yaw())
		extras.append(flee)
		if not bot.has_target or bot.gave_up or bot.target.distance_to(dodge) > 1.5:
			bot.set_target(dodge)
	bot.extra_held = extras
	bot.tick(pos, _yaw(), step)
	if bot.arrived:
		bot.release()
		_begin_face()
		return
	if bot.gave_up and _detour_resumes < DETOUR_RESUMES and _seg_age < _detour_limit:
		_detour_resumes += 1
		bot.set_target(_detour_goal)
		return
	if bot.gave_up or _seg_age >= _detour_limit:
		_pulse_unstuck()
		print("FAIL %s detour" % _seg)
		_seg_status = "fail"


func _tick_face(pos: Vector2, step: float) -> void:
	if _leave_ring(step):
		return
	if _treasure_exit_needed(pos):
		_walk_off_treasure(pos, step)
		return
	hands.begin_tick()
	if _pose == "":
		_pose = "pause"
		_pose_age = 0.0
	if _pose == "pause":
		hands.set_held(PackedStringArray())
		_pose_age += step
		if _pose_age < _Pace.PRE_PAUSE:
			return
		_pose = "turn"
		_face_age = 0.0
		return
	if _pose == "turn":
		var rotate := _Nav.face_action(pos, _detour_face, _yaw())
		if rotate != "" and _face_age < FACE_LIMIT:
			var held := PackedStringArray()
			held.append(rotate)
			hands.set_held(held)
			return
		hands.release_all()
		_pose = "result"
		_pose_age = 0.0
		_pickup_age = 0.0
		return
	if _pose == "result":
		_pose_age += step
		var found := true
		if _seg == "density_treasure":
			_pickup_age += step
			found = _ruin_count() > _ruins_before
			if not found and _pickup_age < PICKUP_LIMIT:
				return
		if _pose_age < _pose_hold():
			return
		if _seg == "density_treasure":
			print("SHOWCASE treasure pickup %s" % ("pass" if found else "miss"))
		_pose = "settle"
		_pose_age = 0.0
		return
	_pose_age += step
	if _pose_age < _Pace.SETTLE:
		return
	if _seg == "density_landmark" and not _glow_done:
		_start_glow()
		return
	_seg_status = "pass"


func _start_glow() -> void:
	_glow_done = true
	_glow_leg = true
	_face_only = false
	_pose = "walk"
	_pose_age = 0.0
	_glow_walk = false
	_glow_goal = Vector2.ZERO
	_glow_face = Vector2.ZERO
	bot.release()
	hands.release_all()
	var cells: Dictionary = _World.get_active().feature_cells
	var choice: Dictionary = _Walk.glow_choice(_xz(), cells)
	if str(choice.get("status", "")) != "walk":
		print("OK glow too-far dist %.1f" % float(choice.get("distance", -1.0)))
		_glow_limit = 0.0
		return
	_glow_face = choice.get("xz", Vector2.ZERO)
	var plan: Dictionary = _Walk.approach(_xz(), _glow_face, _Walk.LANDMARK_STAND)
	_glow_goal = plan.get("goal", _glow_face)
	_glow_limit = _Walk.leg_limit(float(choice.get("distance", 0.0)))
	_glow_walk = bool(plan.get("walk", false))
	print("OK glow crystal_glow dist %.1f limit %.0f" % [float(choice.get("distance", 0.0)), _glow_limit])
	if _glow_walk:
		bot.stuck_limit = DETOUR_STUCK
		bot.set_target(_glow_goal)


func _tick_glow(step: float) -> void:
	if _leave_ring(step):
		return
	if chapters != null and chapters.has_method("open") and not bool(chapters.open("glow")):
		return
	if _glow_walk and _pose == "walk":
		var extras := PackedStringArray()
		if _submerged():
			extras.append("jump")
		else:
			extras.append("sprint")
		bot.extra_held = extras
		bot.tick(_xz(), _yaw(), step)
		_pose_age += step
		if not bot.arrived and not bot.gave_up and _pose_age < _glow_limit:
			return
		bot.release()
		_glow_walk = false
		_pose = "hold"
		_pose_age = 0.0
		return
	if _pose != "hold":
		_pose = "hold"
		_pose_age = 0.0
		return
	var held := PackedStringArray()
	if _glow_face != Vector2.ZERO:
		var spin := _Nav.face_action(_xz(), _glow_face, _yaw())
		if spin != "" and _pose_age < _Pace.PRE_PAUSE + 0.8:
			held.append(spin)
	hands.set_held(held)
	_pose_age += step
	var hold := _Pace.PRE_PAUSE + _Pace.RESULT_HOLD + _Pace.SETTLE
	if _glow_face != Vector2.ZERO and not _glow_near() and _pose_age < hold + 3.0:
		return
	if _pose_age < hold:
		return
	_note_glow()
	_glow_leg = false
	hands.release_all()
	bot.release()
	_seg_status = "pass"


func _step_off_burn(step: float) -> bool:
	var pos := _xz()
	if not _Hazard.burning(tree, pos):
		return false
	var goal := _Hazard.leave_goal(tree, pos, pos)
	var flee := _Hazard.flee_toward(pos, goal, _yaw())
	bot.extra_held = PackedStringArray([flee, "sprint"])
	if not bot.has_target or bot.gave_up or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	bot.tick(pos, _yaw(), step)
	return true


func _leave_ring(step: float) -> bool:
	var pos := _xz()
	var threats: Array = []
	for row in _Hazard.guardian_bubbles(tree):
		if typeof(row) == TYPE_DICTIONARY and bool(row.get("hard", false)):
			threats.append(row)
	var dodge := _Hazard.dodge_point(pos, pos, threats)
	if dodge == Vector2.INF:
		return false
	var flee := _Hazard.flee_toward(pos, dodge, _yaw())
	bot.extra_held = PackedStringArray([flee, "sprint"])
	if not bot.has_target or bot.gave_up or bot.target.distance_to(dodge) > 1.5:
		bot.set_target(dodge)
	bot.tick(pos, _yaw(), step)
	return true


func _begin_face() -> void:
	_face_only = true
	_face_age = 0.0


func _detour_gap(id: String) -> float:
	if id == "density_poi":
		return _Hazard.TRAVEL_SKIRT
	if id == "density_treasure":
		return TREASURE_TOUCH
	if id == "density_landmark":
		return _Walk.LANDMARK_STAND
	return 0.0


func _tick_pickup(step: float) -> void:
	_pickup_age += step
	var found := _ruin_count() > _ruins_before
	if not found and _pickup_age < PICKUP_LIMIT:
		return
	print("SHOWCASE treasure pickup %s" % ("pass" if found else "miss"))
	_seg_status = "pass"


func _ensure_chain() -> void:
	if _chain_ready:
		return
	_chain_ready = true
	var cells: Dictionary = _World.get_active().feature_cells
	for leg_v in _Walk.exploration_chain(_xz(), cells):
		var leg: Dictionary = leg_v
		var id := _density_id(str(leg.get("tag", "")))
		if id == "":
			continue
		_chain[id] = leg


func _density_id(tag: String) -> String:
	match tag:
		"poi":
			return "density_poi"
		"treasure":
			return "density_treasure"
		"landmark":
			return "density_landmark"
	return ""


func _open_chapter(feature: String) -> void:
	if chapters != null and chapters.has_method("open"):
		chapters.open(feature)


func _pose_hold() -> float:
	if _seg == "density_landmark":
		return _Pace.beat_hold("landmark_discovery")
	if _seg == "density_treasure":
		return _Pace.beat_hold("treasure")
	return _Pace.RESULT_HOLD


func _note_beats() -> void:
	_note_level()
	_note_relic()
	_note_stages()


func _note_level() -> void:
	if tree == null:
		return
	var node := tree.get_first_node_in_group("progression_service")
	if node == null:
		return
	var level := int(node.level)
	if _paced_level < 0:
		_paced_level = level
		return
	if level <= _paced_level:
		return
	_paced_level = level
	_arm_banner("level_up")


func _note_relic() -> void:
	var panel = _Relic._open
	var open := panel != null and is_instance_valid(panel)
	if not open:
		_relic_paced = false
		return
	if _relic_paced:
		return
	_relic_paced = true
	_arm_banner("relic")


func _note_stages() -> void:
	if tree == null or finale == null:
		return
	if not finale._bosses(tree).is_empty():
		return
	var crystal := tree.get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_spawn_progress"):
		return
	var prog: Dictionary = crystal.get_spawn_progress()
	var mx := float(prog.get("crystal_max_health", 0.0))
	var hp := float(prog.get("crystal_health", mx))
	if mx <= 0.0 or hp <= 0.0:
		return
	var ratio := hp / mx
	var lines: Array[float] = [0.75, 0.50, 0.25]
	var crossed := false
	for i in lines.size():
		if _stage_hit[i] or ratio > lines[i]:
			continue
		_stage_hit[i] = true
		crossed = true
	if crossed:
		_arm_banner("crystal_damage_stage")


func _arm_banner(id: String) -> void:
	var span := _Pace.banner_span(id)
	if span <= _banner_left:
		return
	_banner_left = span
	print("SHOWCASE pace %s %.2f" % [id, span])


func _unsafe() -> bool:
	if player == null:
		return false
	var mx := float(player.max_health)
	if mx > 0.0 and float(player.health) / mx <= 0.35:
		return true
	if tree == null:
		return false
	if _Hazard.burning(tree, _xz()) or _Hazard.ring_hot(tree, _xz()):
		return true
	var ahead := _xz() + Vector2(40.0, 0.0)
	return _Hazard.dodge_point(_xz(), ahead, _Hazard.guardian_bubbles(tree)) != Vector2.INF


func _treasure_exit_needed(pos: Vector2) -> bool:
	if _seg != "density_treasure" or _treasure_clear:
		return false
	if _ruin_count() <= _ruins_before:
		return false
	return pos.distance_to(_detour_face) < TREASURE_SAFE - 1.2


func _walk_off_treasure(pos: Vector2, step: float) -> void:
	var away := pos - _detour_face
	if away.length() < 0.2:
		away = Vector2(1.0, 0.0)
	var goal := _detour_face + away.normalized() * TREASURE_SAFE
	var extras := PackedStringArray(["sprint"])
	var dodge := _Hazard.dodge_point(pos, goal, _Hazard.guardian_bubbles(tree))
	if dodge != Vector2.INF:
		var flee := _Hazard.flee_toward(pos, dodge, _yaw())
		extras.append(flee)
		goal = dodge
	if not bot.has_target or bot.gave_up or bot.target.distance_to(goal) > 1.5:
		bot.set_target(goal)
	bot.extra_held = extras
	bot.tick(pos, _yaw(), step)
	if _xz().distance_to(_detour_face) < TREASURE_SAFE - 1.2:
		return
	_treasure_clear = true
	_pose = ""
	_pose_age = 0.0
	bot.release()


func _idle_inputs() -> void:
	hands.begin_tick()
	hands.release_all()
	bot.release()
	if fight != null:
		fight.bot.release()
	if finale != null and finale.heart != null and finale.heart.fight != null:
		finale.heart.fight.bot.release()


func _arm_pace(step: float) -> void:
	_pace_one(hands, step)
	_pace_one(bot.input, step)
	if fight != null:
		_pace_one(fight.bot.input, step)
	if finale != null and finale.heart != null and finale.heart.fight != null:
		_pace_one(finale.heart.fight.bot.input, step)


func _pace_one(pad: RefCounted, step: float) -> void:
	if pad == null:
		return
	pad.pace_presses = true
	if pad.has_method("advance_pace"):
		pad.advance_pace(step)


func _chapter_ready() -> bool:
	if chapters != null and chapters.has_method("can_advance"):
		return bool(chapters.can_advance())
	return _seg_age + 0.001 >= _Pace.MIN_CHAPTER


func _sync_bow() -> void:
	if fight == null or chapters == null or _seg != "combat_crystal_mite":
		return
	if fight.bow_phase == "wait":
		if chapters.open("bow_shot"):
			fight.arm_bow()
		return
	if fight.bow_logged and not _bow_stamped:
		_bow_stamped = true
		print("SHOWCASE STAMP bow_shot %s" % chapters.format_clock())
	if fight.bow_phase == "done":
		if chapters.open("combat_crystal_mite"):
			fight.finish_bow()


func _sync_farm() -> void:
	if chapters == null or fight == null or _seg != "combat_crystal_mite":
		return
	if fight.bow_phase == "wait" or fight.bow_phase == "run":
		return
	var want := str(fight.chapter_feature())
	if want == "":
		want = "combat_crystal_mite"
	chapters.open(want)


func _note_lights() -> void:
	if _lights_noted:
		return
	_lights_noted = true
	print("SHOWCASE night %s" % ("pass" if _night_on() else "absent"))
	print("SHOWCASE torch %s" % ("pass" if _torch_on() else "absent"))


func _note_glow() -> void:
	print("SHOWCASE glow %s" % ("pass" if _glow_near() else "absent"))


func _night_on() -> bool:
	if not _has_day_clock():
		return false
	var light := _sun_light()
	return light != null and light.light_energy < 0.35


func _torch_on() -> bool:
	if tree == null:
		return false
	for node in tree.root.find_children("*", "OmniLight3D", true, false):
		var omni := node as OmniLight3D
		if omni.visible and omni.light_energy > 0.05:
			return true
	for node in tree.root.find_children("*", "SpotLight3D", true, false):
		var spot := node as SpotLight3D
		if spot.visible and spot.light_energy > 0.05:
			return true
	return false


func _glow_near() -> bool:
	if tree == null:
		return false
	var layer := tree.get_first_node_in_group("feature_visual_layer")
	if layer == null:
		return false
	var pending: Array = [layer]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is Node3D and str(node.get_meta("landmark_kind", "")) == "crystal_glow":
			var at := (node as Node3D).global_position
			var scale := maxf(_Coords.voxel_scale(), 0.001)
			var col := Vector2(at.x, at.z) / scale
			if col.distance_to(_xz()) <= 24.0 and _Marks.glow_energy(node as Node3D) > 0.5:
				return true
		for child in node.get_children():
			pending.append(child)
	return false


func _ruin_count() -> int:
	if tree == null:
		return 0
	var director := tree.get_first_node_in_group("living_world_director")
	if director != null and director.has_method("get_discovered_ruin_count"):
		return int(director.get_discovered_ruin_count())
	return 0


func _lighting_reason() -> String:
	if not _Sun.SUN.is_equal_approx(Vector3(0.55, 0.82, 0.38)):
		return "locked sun %s" % _Sun.SUN
	var sun_v: Variant = _sun_vector()
	if typeof(sun_v) != TYPE_VECTOR3:
		return "sun missing"
	if not (sun_v as Vector3).is_equal_approx(_Sun.SUN):
		return "sun %s" % sun_v
	var light := _sun_light()
	if light == null:
		return "no directional light"
	if not light.shadow_enabled:
		return "shadow off"
	if _sun_basis_ready and not light.transform.basis.is_equal_approx(_sun_basis):
		return "sun rotated"
	var display := DisplayServer.get_name()
	if display == "headless":
		return ""
	if _body_casts():
		return ""
	return "body does not cast (%s)" % display


func _remember_sun() -> void:
	var light := _sun_light()
	if light == null:
		return
	_sun_basis = light.transform.basis
	_sun_basis_ready = true


func _sun_light() -> DirectionalLight3D:
	if tree == null:
		return null
	return tree.root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D


func _sun_vector() -> Variant:
	var live: Variant = RenderingServer.global_shader_parameter_get("terrain_sun_dir")
	if typeof(live) == TYPE_VECTOR3:
		return live
	var setting: Variant = ProjectSettings.get_setting("shader_globals/terrain_sun_dir", {})
	if setting is Dictionary:
		var value: Variant = (setting as Dictionary).get("value", null)
		if typeof(value) == TYPE_VECTOR3:
			return value
	return null


func _body_casts() -> bool:
	if player == null:
		return false
	var pending: Array = [player]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is GeometryInstance3D:
			var mesh := node as GeometryInstance3D
			if mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				return true
		for child in node.get_children():
			pending.append(child)
	return false


func _has_day_clock() -> bool:
	if tree == null:
		return false
	if not tree.get_nodes_in_group("day_night").is_empty():
		return true
	return tree.root.find_child("DayNight", true, false) != null


func _tutorial_open() -> bool:
	if tree == null:
		return false
	for node in tree.root.get_children():
		if node.get_script() != _Tutorial:
			continue
		if bool(node.get("visible")):
			return true
	return false


func _pulse_unstuck() -> void:
	if _unstuck_sent:
		return
	if not bot.input.pulse("unstuck"):
		return
	_unstuck_sent = true


func _submerged() -> bool:
	if player == null:
		return false
	var world = player.get("world")
	var feet: Vector3 = player.voxel_position
	if world == null:
		return false
	var col_x := floori(feet.x)
	var col_z := floori(feet.z)
	if not _Water.column_has_water(world, col_x, col_z):
		return false
	var info: Dictionary = _Water.sample(world, col_x, col_z, feet.y, feet.y, 1.6)
	return bool(info.get("submerged", false))


func _grounded(state: int) -> bool:
	return state == Player.State.IDLE or state == Player.State.RUNNING


func _advance_clock(step: float) -> void:
	if chapters != null and chapters.has_method("advance"):
		chapters.advance(step)


func _paint() -> void:
	if hud == null or chapters == null:
		return
	if hud.has_method("set_readout") and chapters.has_method("format_clock"):
		var chapter := _seg
		if build != null and (_seg == "dig_tool" or _seg == "structure_place") and build.chapter_label != "":
			chapter = build.chapter_label
		elif _detour_label != "":
			chapter = _detour_label
		elif finale != null and (_seg == "crystal" or _seg == "boss" or _seg == "win_screen") and finale.caption != "":
			chapter = finale.caption
		if chapters.has_method("feature"):
			var feat := str(chapters.feature())
			if feat == "bow_shot" or feat == "night" or feat == "torch" or feat == "day_night" or feat == "glow" or feat.begins_with("treasure_open") or (feat.begins_with("combat_") and feat != _seg):
				chapter = feat
		hud.set_readout(chapters.format_clock(), chapter)


func _xz() -> Vector2:
	if player == null:
		return Vector2.ZERO
	var feet: Vector3 = player.voxel_position
	return Vector2(feet.x, feet.z)


func _yaw() -> float:
	if player == null:
		return 0.0
	var cam = player.get("camera")
	if cam != null and "yaw_target_degrees" in cam:
		return float(cam.yaw_target_degrees)
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	return 0.0
