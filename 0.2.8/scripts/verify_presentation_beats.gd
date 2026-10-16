extends SceneTree

const _Config = preload("res://config/game_feel_config.gd")
const _OverlayScene = preload("res://ui/game_overlay.tscn")
const _Progression = preload("res://systems/progression_service.gd")
const _Skills = preload("res://systems/skill_service.gd")
const _Relics = preload("res://relics/relic_manager.gd")
const _Game = preload("res://game/game_manager.gd")
const _Living = preload("res://world/living_world_director.gd")
const _Hud = preload("res://scripts/honest_bot/honest_showcase_hud.gd")
const _Features = preload("res://world/feature_registry.gd")
const _FeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldState = preload("res://world/world_state.gd")
const _Spawn = preload("res://crystal/crystal_spawn_point.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

const _BEATS: Array[String] = [
	"level_up",
	"skill_unlock",
	"treasure",
	"relic",
	"landmark_discovery",
	"crystal_damage_stage",
	"boss_spawn",
	"win",
]

var _failed: int = 0
var _heard: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	if _Progression.XP_POI_DISCOVERED != 20 or _Progression.XP_RUIN_DISCOVERED != 25:
		_fail("discovery XP changed")
	var feel := root.get_node_or_null("GameFeel")
	if feel == null:
		_fail("GameFeel autoload missing")
		quit(1)
		return
	feel.sound_hook.connect(func(cue: String) -> void:
		_heard.append(cue)
	)
	_WorldState.replace_active()
	var heart := _Heart.new()
	var spawner := _Spawner.new()
	var progress := _Progression.new()
	var skills := _Skills.new()
	var relics := _Relics.new()
	var game := _Game.new()
	var living := _Living.new()
	var walker := _Walker.new()
	root.add_child(heart)
	root.add_child(spawner)
	root.add_child(progress)
	root.add_child(skills)
	root.add_child(relics)
	root.add_child(game)
	root.add_child(living)
	root.add_child(walker)
	living._player = walker
	var overlay: Node = _OverlayScene.instantiate()
	root.add_child(overlay)
	var hud := _Hud.new()
	root.add_child(hud)
	hud.set_readout("0:01.00", "movement")
	for _i in 4:
		await process_frame
	progress.skill_points = 1
	if not skills.unlock(&"dash"):
		_fail("dash unlock did not spend the point")
	else:
		_expect(overlay, feel, "skill_unlock", "Dash")
	progress.add_xp(_Progression.xp_to_advance(1))
	_expect(overlay, feel, "level_up", "Level up — 2")
	if not relics.equip(&"mason_glove"):
		_fail("relic equip failed")
	else:
		_expect(overlay, feel, "relic", "Relic equipped:")
	walker.voxel_position = Vector3(40, 0, 0)
	_Features.register_feature(0, 0, _FeatureTypes.FeatureKind.POI, {
		"center": Vector2i(0, 0),
		"name": "Rock Spire",
		"landmark": true,
		"poi_kind": "rock_spire",
	})
	if living.try_discover_landmarks() != "":
		_fail("landmark discovered from 40 columns")
	if game.pois_discovered != 0:
		_fail("landmark granted POI xp")
	walker.voxel_position = Vector3(12, 0, 0)
	if living.try_discover_landmarks() != "Rock Spire":
		_fail("landmark at 12 columns did not fire")
	else:
		_expect(overlay, feel, "landmark_discovery", "Rock Spire")
	if living.try_discover_landmarks() != "":
		_fail("landmark fired twice")
	_Features.register_feature(30, 30, _FeatureTypes.FeatureKind.RUIN, {
		"center": Vector2i(30, 30),
		"name": "Treasure Site 1",
		"treasure_site": true,
		"chest": {"resources": {"stone": 2, "herb": 1}, "relics": []},
	})
	var found: Dictionary = living.discover_ruin_at(Vector2i(30, 30))
	if not bool(found.get("treasure_site", false)):
		_fail("treasure pickup lost its site flag")
	else:
		_expect(overlay, feel, "treasure", "Treasure Site")
	var spawn := _Spawn.new(1, Vector2i.ZERO, _CrystalTypes.SpawnKind.ORIGIN, 100.0, true)
	spawn.health = 70.0
	heart.spawn_damaged.emit(spawn, 20.0)
	_expect(overlay, feel, "crystal_damage_stage", "75%")
	spawner.enemy_spawned.emit(&"origin_warden", Vector2i.ZERO)
	_expect(overlay, feel, "boss_spawn", "Boss warning")
	game.victory_reason = "crystal"
	game._set_won()
	_expect(overlay, feel, "win", "crystal was destroyed")
	if paused:
		_fail("a beat paused the tree")
		paused = false
	if absf(Engine.time_scale - 1.0) > 0.001:
		_fail("headless beat changed time_scale")
		Engine.time_scale = 1.0
	var toast := overlay.get_node_or_null("ToastLabel") as Label
	if toast == null or toast.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("banner accepts mouse clicks")
	else:
		_check_clearance(overlay, hud, toast)
	for id in _BEATS:
		if id not in _heard:
			_fail("beat %s never fired" % id)
		var row: Dictionary = feel.config.beat(id)
		var scale := float(row.get("slow_mo_scale", 0.0))
		if scale < _Config.SLOW_MO_FLOOR - 0.001:
			_fail("%s slow-mo %.2f can freeze the player" % [id, scale])
	_WorldState.replace_active()
	if _failed == 0:
		print("All presentation beat tests OK")
		quit(0)
	else:
		push_error("verify_presentation_beats: %d failure(s)" % _failed)
		quit(1)


func _expect(overlay: Node, feel: Node, beat_id: String, snippet: String) -> void:
	var seconds := float(feel.banner_seconds(beat_id))
	if _outside(seconds, _Config.BANNER_MIN, _Config.BANNER_MAX):
		_fail("%s banner %.2f is outside 2-3s" % [beat_id, seconds])
	if str(overlay._toast_beat) != beat_id:
		_fail("%s banner is %s" % [beat_id, str(overlay._toast_beat)])
	if absf(float(overlay._toast_timer) - seconds) > 0.001:
		_fail("%s timer %.3f is not the config %.3f" % [beat_id, float(overlay._toast_timer), seconds])
	var toast := overlay.get_node_or_null("ToastLabel") as Label
	if toast == null or not toast.visible or snippet not in toast.text:
		_fail("%s text missing %s" % [beat_id, snippet])
	if _heard.is_empty() or _heard[_heard.size() - 1] != beat_id:
		_fail("%s hook is %s" % [beat_id, str(_heard)])
	else:
		print("OK beat %s %.2fs" % [beat_id, seconds])


func _outside(value: float, lo: float, hi: float) -> bool:
	return value < lo - 0.001 or value > hi + 0.001


func _check_clearance(overlay: Node, hud: Node, toast: Label) -> void:
	overlay._ensure_objective_hud()
	var panel: Control = overlay._objective_panel
	var chapter := hud.get_child(1) as Control
	if panel == null or chapter == null:
		_fail("crystal panel or chapter label missing")
		return
	for view in [Vector2(1280, 720), Vector2(1024, 600), Vector2(1920, 1080)]:
		var banner := _anchored(view, toast)
		var crystal := _anchored(view, panel)
		var label := _anchored(view, chapter)
		if banner.intersects(crystal):
			_fail("banner covers crystal HP at %s" % str(view))
		elif banner.intersects(label):
			_fail("banner covers chapter label at %s" % str(view))
		else:
			print("OK banner clear %s" % str(view))


func _anchored(view: Vector2, node: Control) -> Rect2:
	var origin := Vector2(view.x * node.anchor_left, view.y * node.anchor_top)
	var far := Vector2(view.x * node.anchor_right, view.y * node.anchor_bottom)
	var pos := origin + Vector2(node.offset_left, node.offset_top)
	var size := (far + Vector2(node.offset_right, node.offset_bottom)) - pos
	return Rect2(pos, size)


class _Heart extends Node:
	signal spawn_damaged(spawn, amount: float)
	signal spawn_destroyed
	signal all_spawns_destroyed
	signal crystal_touched_player
	var covered_cells: int = 0
	var expansion_enabled: bool = true
	var strength_tier: int = 0

	func _enter_tree() -> void:
		add_to_group("crystal_manager")

	func get_coverage_ratio() -> float:
		return 0.0

	func get_spawn_progress() -> Dictionary:
		return {}


class _Spawner extends Node:
	signal enemy_spawned(enemy_id: StringName, world_pos: Vector2i)

	func _enter_tree() -> void:
		add_to_group("crystal_enemy_spawner")


class _Walker extends Node3D:
	var voxel_position := Vector3(40, 0, 0)

	func _enter_tree() -> void:
		add_to_group("player")

	func get_voxel_position() -> Vector3:
		return voxel_position
