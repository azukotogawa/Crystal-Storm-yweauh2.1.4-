class_name LivingWorldDirector
extends Node
## Thin Living World content director: biome legibility, ruin discovery surprise,
## town defense feedback. Uses existing managers — no new engine cores.

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")

signal ruin_discovered(ruin_name: String, center: Vector2i, power_bonus: float)
## Full expedition result: loot, relic, guardians — production UI listens.
signal ruin_expedition_completed(result: Dictionary)
signal town_militia_called(town_name: String, count: int)
signal town_rallied(town_name: String, center: Vector2i, militia: int, health_restored: float)
signal town_threat_changed(town_name: String, state_label: String, center: Vector2i)
signal biome_changed(biome_name: String)
signal biome_first_visited(biome_name: String, gift_item: String, gift_count: int)

@export var ruin_discover_radius: float = 10.0
@export var ruin_power_bonus: float = 6.0
@export var biome_poll_sec: float = 0.45
@export var rally_health_restore: float = 35.0
@export var rally_militia_count: int = 2
## Extra columns beyond town radius for “you made it to the outskirts.”
@export var rally_radius_bonus: float = 4.0
@export var ruin_guardian_count: int = 2
@export var ruin_loot_stone: int = 4
@export var ruin_loot_herb: int = 2

var _player: Node3D
var _world: InfiniteNoiseWorld
var _crystal: CrystalManager
var _town_defense: Node
var _entity_manager: Node
var _discovered_ruins: Dictionary = {}  # Vector2i -> true
var _rallied_towns: Dictionary = {}  # Vector2i -> true (once per town per run)
var _visited_biomes: Dictionary = {}  # name -> true
var _last_biome: String = ""
var _biome_timer: float = 0.0
var _bound: bool = false
## Round-robin ruin scan under frame budget (Phase 3).
var _ruin_scan_cursor: int = 0
var _last_threat_key: String = ""
var _relics_found: int = 0


func _enter_tree() -> void:
	add_to_group("living_world_director")


func _ready() -> void:
	call_deferred("_bind")


func _bind() -> void:
	if _bound:
		return
	_player = get_tree().get_first_node_in_group("player")
	_world = get_tree().get_first_node_in_group("world")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_town_defense = get_tree().get_first_node_in_group("town_defense_manager")
	_entity_manager = get_tree().get_first_node_in_group("entity_manager")
	if _town_defense and _town_defense.has_signal("militia_requested"):
		if not _town_defense.militia_requested.is_connected(_on_militia_requested):
			_town_defense.militia_requested.connect(_on_militia_requested)
	if _town_defense and _town_defense.has_signal("town_state_changed"):
		if not _town_defense.town_state_changed.is_connected(_on_town_state_changed):
			_town_defense.town_state_changed.connect(_on_town_state_changed)
	_bound = _player != null and _world != null


func _process(delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("living_world")
	if not _bound:
		_bind()
		if not _bound:
			if profiler and profiler.has_method("end"):
				profiler.end("living_world")
			return
	_biome_timer += delta
	if _biome_timer >= biome_poll_sec:
		_biome_timer = 0.0
		_poll_biome()
	# Rally is cheap and player-facing; always try once.
	try_rally_at_player_column()
	# Ruin discovery scans under budget (round-robin centers).
	_budgeted_ruin_scan()
	if profiler and profiler.has_method("end"):
		profiler.end("living_world")


func _budgeted_ruin_scan() -> void:
	var centers: Array = _FeatureRegistry.get_ruin_centers()
	if centers.is_empty():
		return
	var sched = get_node_or_null("/root/FrameBudgetScheduler")
	var remaining := centers.size()  # worst-case pending scan work
	if sched and sched.has_method("report_queue_depth"):
		# Report how many centers left in this round-robin cycle.
		var left := maxi(centers.size() - (_ruin_scan_cursor % maxi(centers.size(), 1)), 0)
		sched.report_queue_depth(&"living_world", left, 0)
	if sched and sched.has_method("run_budgeted"):
		sched.run_budgeted(&"living_world", func(token):
			var col := _player_column()
			while token.can_continue() and centers.size() > 0:
				if _ruin_scan_cursor >= centers.size():
					_ruin_scan_cursor = 0
					break  # one full pass per drain wave; resume next frame
				var center: Vector2i = centers[_ruin_scan_cursor]
				_ruin_scan_cursor += 1
				if _discovered_ruins.has(center):
					token.spend_unit()
					continue
				var d := Vector2(col).distance_to(Vector2(center))
				if d <= ruin_discover_radius:
					discover_ruin_at(center)
				token.spend_unit()
		)
	else:
		# Fallback: limited scan without scheduler.
		try_discover_at_player_column()


func get_player_biome_name() -> String:
	return _last_biome


func get_discovered_ruin_count() -> int:
	return _discovered_ruins.size()


func _player_column() -> Vector2i:
	if _player == null:
		return Vector2i.ZERO
	if _player.has_method("get_voxel_position"):
		var v: Vector3 = _player.get_voxel_position()
		return Vector2i(floori(v.x), floori(v.z))
	var ws = _WorldSettings.get_active()
	return Vector2i(
		floori(ws.world_to_column(_player.global_position.x)),
		floori(ws.world_to_column(_player.global_position.z))
	)


func _poll_biome() -> void:
	if _world == null:
		return
	var col := _player_column()
	var b: Dictionary = _world.get_biome(float(col.x), 0.0, float(col.y))
	var name: String = str(b.get("name", "unknown"))
	if name != _last_biome:
		_last_biome = name
		biome_changed.emit(name)
	_try_first_biome_visit(name)


func _try_first_biome_visit(biome_name: String) -> void:
	if biome_name == "" or biome_name == "unknown":
		return
	if _visited_biomes.has(biome_name):
		return
	_visited_biomes[biome_name] = true
	# Small exploration gift — keeps walking the map rewarding.
	var gift := "herb"
	var count := 2
	match biome_name:
		"steppe":
			gift = "herb"
			count = 3
		"forest", "dense forest", "pine forest":
			gift = "wood"
			count = 4
		"mountain", "border_mountain":
			gift = "stone"
			count = 5
		"marsh":
			gift = "herb"
			count = 4
		_:
			gift = "stone"
			count = 2
	if _player and "inventory" in _player and _player.inventory and _player.inventory.has_method("add_item"):
		_player.inventory.add_item(gift, count)
	biome_first_visited.emit(biome_name, gift, count)
	print("[LivingWorld] First visit %s — +%d %s" % [biome_name, count, gift])


func _check_ruin_discovery() -> void:
	try_discover_at_player_column()


## Shared proximity path used by _process and harnesses.
func try_discover_at_player_column() -> Dictionary:
	var col := _player_column()
	for center in _FeatureRegistry.get_ruin_centers():
		if _discovered_ruins.has(center):
			continue
		var d := Vector2(col).distance_to(Vector2(center))
		if d > ruin_discover_radius:
			continue
		return discover_ruin_at(center)
	return {}


## Pure discover once: full expedition loop. Idempotent per center.
func discover_ruin_at(center: Vector2i) -> Dictionary:
	if _discovered_ruins.has(center):
		return {}
	_discovered_ruins[center] = true
	var ruin_name := "Forgotten Ruin"
	var feat: Dictionary = _FeatureRegistry.get_feature(center.x, center.y)
	if feat.has("name"):
		ruin_name = str(feat.name)
	# 1) Crystal still stirs — double-edged exploration.
	if _crystal and _crystal.has_method("grant_feed_power"):
		_crystal.grant_feed_power(ruin_power_bonus)
	elif _crystal and _crystal.has_method("_add_power"):
		_crystal._add_power(ruin_power_bonus)
	# 2) Plunder materials into inventory.
	var loot: Dictionary = _grant_ruin_loot(center)
	# 3) Chance at a ruin relic (progression reward).
	var relic_id: StringName = _try_grant_ruin_relic(center)
	# 4) Guardians wake — combat beat.
	var guardians: int = _spawn_ruin_guardians(center)
	var result := {
		"center": center,
		"power": ruin_power_bonus,
		"name": ruin_name,
		"loot": loot,
		"relic_id": str(relic_id),
		"guardians": guardians,
		"discovered_count": _discovered_ruins.size(),
	}
	ruin_discovered.emit(ruin_name, center, ruin_power_bonus)
	ruin_expedition_completed.emit(result)
	print(
		"[LivingWorld] Expedition %s at %s — crystal +%.0f · loot %s · relic=%s · guardians=%d"
		% [ruin_name, center, ruin_power_bonus, loot, str(relic_id), guardians]
	)
	return result


func get_relics_found_count() -> int:
	return _relics_found


func get_ruins_hud_line() -> String:
	var total: int = _FeatureRegistry.get_ruin_centers().size()
	var n: int = _discovered_ruins.size()
	if total <= 0:
		return ""
	return "Ruins %d/%d" % [n, total]


func _grant_ruin_loot(center: Vector2i) -> Dictionary:
	var stone_n := ruin_loot_stone
	var herb_n := ruin_loot_herb
	# Deterministic variety from center hash.
	var h: int = absi(hash(center))
	if h % 3 == 0:
		stone_n += 2
	if h % 5 == 0:
		herb_n += 1
	if _player and "inventory" in _player and _player.inventory:
		var inv = _player.inventory
		if inv.has_method("add_item"):
			inv.add_item("stone", stone_n)
			inv.add_item("herb", herb_n)
	return {"stone": stone_n, "herb": herb_n}


func _try_grant_ruin_relic(center: Vector2i) -> StringName:
	_RelicRegistry.ensure_builtins()
	if _player == null:
		return &""
	var relic_mgr = _player.get_node_or_null("RelicManager")
	if relic_mgr == null:
		relic_mgr = get_tree().get_first_node_in_group("relic_manager") if is_inside_tree() else null
	if relic_mgr == null or not relic_mgr.has_method("equip"):
		return &""
	var equipped: Array = relic_mgr.equipped if "equipped" in relic_mgr else []
	var pool: Array[StringName] = _RelicRegistry.ruin_loot_pool()
	if pool.is_empty():
		return &""
	# Deterministic pick among unequipped pool entries.
	var start: int = absi(hash(center)) % pool.size()
	for i in pool.size():
		var rid: StringName = pool[(start + i) % pool.size()]
		if rid in equipped:
			continue
		if relic_mgr.equip(rid):
			_relics_found += 1
			return rid
	return &""


func _spawn_ruin_guardians(center: Vector2i) -> int:
	var spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner") if is_inside_tree() else null
	if spawner == null or not spawner.has_method("spawn_enemy_at_column"):
		return 0
	var n := maxi(ruin_guardian_count, 1)
	var spawned := 0
	for i in n:
		var ox := (i % 2) * 2 - 1
		var oz := (i / 2) * 2 - 1
		if spawner.spawn_enemy_at_column(&"crystal_mite", center.x + ox, center.y + oz, center):
			spawned += 1
	return spawned


func _on_militia_requested(town: Dictionary, count: int) -> void:
	var town_name: String = str(town.get("name", "Settlement"))
	town_militia_called.emit(town_name, count)


func _on_town_state_changed(town_name: String, state: int, center: Vector2i) -> void:
	var label := _state_label(state)
	print("[LivingWorld] Town %s → %s" % [town_name, label])
	town_threat_changed.emit(town_name, label, center)
	_last_threat_key = "%s:%s" % [town_name, label]


func _state_label(state: int) -> String:
	match state:
		1:
			return "ALERT"
		2:
			return "BESIEGED"
		3:
			return "FALLEN"
		_:
			return "SAFE"


## HUD: nearest / highest-priority town threat for the player.
func get_priority_town_report() -> Dictionary:
	_bind()
	if _town_defense == null or not _town_defense.has_method("get_status_summary"):
		return {}
	var col := _player_column()
	var best: Dictionary = {}
	var best_score := -1.0e9
	for row in _town_defense.get_status_summary():
		var center: Vector2i = row.get("center", Vector2i.ZERO)
		var state: int = int(row.get("state", 0))
		var dist: float = Vector2(col).distance_to(Vector2(center))
		# Prefer threatened towns; among same threat tier, nearer wins.
		var threat_w := 0.0
		match state:
			3:
				threat_w = 4000.0
			2:
				threat_w = 3000.0
			1:
				threat_w = 2000.0
			_:
				threat_w = 100.0
		var score: float = threat_w - dist
		if score > best_score:
			best_score = score
			best = {
				"name": str(row.get("name", "Town")),
				"center": center,
				"state": state,
				"state_label": _state_label(state),
				"health": float(row.get("health", 100.0)),
				"health_pct": float(row.get("health", 100.0)),
				"distance": dist,
				"radius": int(row.get("radius", 12)),
			}
	if not best.is_empty() and "town_health_max" in _town_defense:
		var mx: float = float(_town_defense.town_health_max)
		if mx > 0.0:
			best["health_pct"] = clampf(float(best.get("health", 0.0)) / mx * 100.0, 0.0, 100.0)
	return best


func get_town_hud_line() -> String:
	var rep := get_priority_town_report()
	if rep.is_empty():
		return ""
	var label: String = str(rep.get("state_label", "SAFE"))
	var name: String = str(rep.get("name", "Town"))
	var dist: float = float(rep.get("distance", 0.0))
	var hp: float = float(rep.get("health_pct", 100.0))
	if label == "SAFE":
		return "Town %s safe · %.0fc away" % [name, dist]
	return "Town %s %s · HP %.0f%% · %.0fc" % [name, label, hp, dist]


func get_rallied_town_count() -> int:
	return _rallied_towns.size()


## Shared rally path: player enters threatened town → restore + militia once.
func try_rally_at_player_column() -> Dictionary:
	_bind()
	if _town_defense == null:
		return {}
	var col := _player_column()
	for town in _FeatureRegistry.get_towns():
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		if _rallied_towns.has(center):
			continue
		var radius: float = float(town.get("radius", 12)) + rally_radius_bonus
		var dist := Vector2(col).distance_to(Vector2(center))
		if dist > radius:
			continue
		var state: int = 0
		if _town_defense.has_method("get_town_state"):
			state = int(_town_defense.get_town_state(center))
		# Only rally under pressure (ALERT=1, BESIEGED=2).
		if state != 1 and state != 2:
			continue
		return rally_town_at(center)
	return {}


## Pure rally once for a town center (used by process + harness).
func rally_town_at(center: Vector2i) -> Dictionary:
	_bind()
	if _rallied_towns.has(center):
		return {}
	if _town_defense == null:
		return {}
	var state: int = int(_town_defense.get_town_state(center)) if _town_defense.has_method("get_town_state") else 0
	if state != 1 and state != 2:
		return {}
	var town: Dictionary = {}
	for t in _FeatureRegistry.get_towns():
		if t.get("center", Vector2i.ZERO) == center:
			town = t
			break
	if town.is_empty():
		return {}
	var town_name: String = str(town.get("name", "Settlement"))
	var restored := 0.0
	if _town_defense.has_method("restore_health"):
		restored = float(_town_defense.restore_health(center, rally_health_restore))
	var militia := rally_militia_count
	if _entity_manager and _entity_manager.has_method("spawn_town_defenders"):
		_entity_manager.spawn_town_defenders(town, militia)
	_rallied_towns[center] = true
	town_rallied.emit(town_name, center, militia, restored)
	print("[LivingWorld] Rallied %s — +%.0f HP, +%d militia" % [town_name, restored, militia])
	return {
		"name": town_name,
		"center": center,
		"militia": militia,
		"health_restored": restored,
		"state": state,
	}


## Harness: force ALERT + place player at town → real try_rally path.
func harness_rally_nearest_threatened_town() -> Dictionary:
	_bind()
	var towns: Array = _FeatureRegistry.get_towns()
	if towns.is_empty() or _town_defense == null:
		return {}
	var town: Dictionary = towns[0]
	var center: Vector2i = town.get("center", Vector2i.ZERO)
	_rallied_towns.erase(center)
	# Damaged + ALERT so rally is consequential and allowed.
	if _town_defense.has_method("force_threat_state"):
		_town_defense.force_threat_state(center, 1, 40.0)
	_place_player_at_column(center.x, center.y)
	return try_rally_at_player_column()


## Headless harness: warp player to nearest ruin and drive real proximity discovery.
func harness_force_discover_nearest_ruin() -> Dictionary:
	_bind()
	var centers: Array = _FeatureRegistry.get_ruin_centers()
	if centers.is_empty():
		return {}
	var center: Vector2i = centers[0]
	# Allow re-test of the path if already flagged this session.
	_discovered_ruins.erase(center)
	_place_player_at_column(center.x, center.y)
	# Real path: player column proximity → discover_ruin_at.
	return try_discover_at_player_column()


func _place_player_at_column(wx: int, wz: int) -> void:
	if _player == null:
		return
	var y := 8.0
	if _world and _world.has_method("get_surface_height"):
		y = float(_world.get_surface_height(float(wx), float(wz))) + 1.0
	if "voxel_position" in _player:
		_player.set("voxel_position", Vector3(float(wx) + 0.5, y, float(wz) + 0.5))
	if _player.has_method("_sync_global_from_voxel"):
		_player.call("_sync_global_from_voxel")
	elif _player is Node3D:
		(_player as Node3D).global_position = Vector3(float(wx) + 0.5, y, float(wz) + 0.5)
	if _player.has_method("_snap_to_ground"):
		_player.call("_snap_to_ground")
