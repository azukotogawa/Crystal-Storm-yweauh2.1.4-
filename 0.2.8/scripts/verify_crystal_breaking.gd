extends SceneTree
## Crystal mass breaking, town-fall penalty (not a loss), and corner origin.

const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalSimulation = preload("res://crystal/crystal_simulation.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSpawnPoint = preload("res://crystal/crystal_spawn_point.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _TownDefense = preload("res://world/town_defense_manager.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _Overlay = preload("res://ui/game_overlay.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	if not _test_mass_break_and_shards():
		failed = true
	if not _test_pick_stronger_than_sword():
		failed = true
	if not _test_visual_recede():
		failed = true
	if not _test_spawn_hp_bar():
		failed = true
	if not _test_objective_lines():
		failed = true
	if not await _test_town_penalty_not_loss():
		failed = true
	if not _test_defender_dismiss():
		failed = true
	if not _test_corner_origin():
		failed = true
	if not _test_jump_is_space():
		failed = true
	if failed:
		quit(1)
		return
	print("All crystal breaking tests OK")
	quit(0)


func _test_mass_break_and_shards() -> bool:
	var cfg := _CrystalSimConfig.create_default()
	var sim := _CrystalSimulation.new(cfg)
	var cm := _CrystalManager.new()
	cm.sim_config = cfg
	cm._simulation = sim
	cm._sim = sim.fluid
	var cell := Vector2i(3, 4)
	sim.set_depth(cell, 2.5, 0, false)

	var sword: Dictionary = cm.damage_crystal_at(cell, float(_ItemTypes.get_def("wooden_sword").crystal_damage))
	if not bool(sword.hit) or bool(sword.broken):
		push_error("sword chip should hit without removing a 2.5-deep cell, got %s" % sword)
		return false
	var after_sword: float = cm.get_depth_at(cell.x, cell.y)
	if after_sword >= 2.5 - 0.01:
		push_error("sword did not lower crystal depth, still %.3f" % after_sword)
		return false
	if int(sword.shards) < 1:
		push_error("a connecting hit must drop a crystal shard")
		return false

	var broken := false
	var guard := 0
	while guard < 8 and cm.has_crystal_at(cell.x, cell.y):
		var hit: Dictionary = cm.damage_crystal_at(cell, float(_ItemTypes.get_def("stone_pick").crystal_damage))
		broken = bool(hit.broken) or broken
		guard += 1
	if not broken or cm.has_crystal_at(cell.x, cell.y):
		push_error("pick should remove the cell, broken=%s depth=%.3f" % [broken, cm.get_depth_at(cell.x, cell.y)])
		return false
	var miss: Dictionary = cm.damage_crystal_at(cell, 2.4)
	if bool(miss.hit):
		push_error("empty cell must not count as a crystal hit")
		return false

	var inv := _Inventory.new()
	var holder := Node.new()
	holder.set_script(_player_pocket_script())
	holder.inventory = inv
	root.add_child(holder)
	root.add_child(cm)
	var fresh := Vector2i(6, 6)
	sim.set_depth(fresh, 0.5, 0, false)
	var stored: Dictionary = cm.damage_crystal_at(fresh, 2.4)
	if int(stored.shards_stored) < 1 or inv.count_item("crystal_shard") < 1:
		push_error("broken crystal must enter the inventory, stored=%s count=%d" % [stored, inv.count_item("crystal_shard")])
		holder.queue_free()
		cm.queue_free()
		return false
	print("OK crystal break sword %.2f→%.2f then removed; shards=%d" % [2.5, after_sword, inv.count_item("crystal_shard")])
	holder.free()
	cm.free()
	return true


func _player_pocket_script() -> GDScript:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar inventory\nfunc _ready() -> void:\n\tadd_to_group(\"player\")\n"
	scr.reload()
	return scr


func _test_pick_stronger_than_sword() -> bool:
	var pick := float(_ItemTypes.get_def("stone_pick").get("crystal_damage", 0.0))
	var sword := float(_ItemTypes.get_def("wooden_sword").get("crystal_damage", 0.0))
	if pick <= sword * 3.0:
		push_error("pick crystal_damage %.2f should be much stronger than sword %.2f" % [pick, sword])
		return false
	var src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_try_break_crystal_mass" not in src or "crystal_damage" not in src:
		push_error("weapon controller must damage the crystal mass")
		return false
	print("OK pick crystal_damage %.2f > sword %.2f" % [pick, sword])
	return true


func _test_visual_recede() -> bool:
	var cell := _CrystalCell.new(Vector2i(1, 1), 8.0, 2.5)
	cell.is_frontier = true
	var tall: float = _CrystalChunkLayer.visual_growth(cell).y
	cell.depth = 0.35
	var short: float = _CrystalChunkLayer.visual_growth(cell).y
	if short >= tall - 0.05:
		push_error("lower depth must draw a shorter crystal, tall=%.3f short=%.3f" % [tall, short])
		return false
	print("OK crystal visual height %.2f → %.2f when depth drops" % [tall, short])
	return true


func _test_spawn_hp_bar() -> bool:
	var cm := _CrystalManager.new()
	root.add_child(cm)
	var spawn := _CrystalSpawnPoint.new(1, Vector2i(4, 4), _CrystalTypes.SpawnKind.RUIN, 80.0, false)
	cm.harness_setup_spawns([spawn])
	cm._refresh_spawn_markers()
	var anchor: Node3D = cm._spawn_markers.get(1) as Node3D
	if anchor == null or anchor.get_node_or_null("HpFill") == null:
		push_error("spawn marker missing HpFill bar")
		cm.queue_free()
		return false
	var fill := anchor.get_node_or_null("HpFill") as MeshInstance3D
	var full_scale := fill.scale.x
	spawn.health = 20.0
	cm._apply_spawn_hp_bar(anchor, spawn)
	if fill.scale.x >= full_scale - 0.05:
		push_error("HP bar did not shrink, scale %.3f vs full %.3f" % [fill.scale.x, full_scale])
		cm.queue_free()
		return false
	print("OK spawn HP bar %.2f → %.2f at 25%% health" % [full_scale, fill.scale.x])
	cm.free()
	return true


func _test_objective_lines() -> bool:
	var lines: String = _Overlay.build_objective_lines("Maze", 3, 4, 0.125, 40, "Nearest spawn: NE  80c")
	for piece in ["Phase: Maze", "Spawns: 3 remaining", "Crystal: 12.50%", "Nearest spawn: NE"]:
		if piece not in lines:
			push_error("objective HUD missing %s in %s" % [piece, lines])
			return false
	var north := _Overlay.compass_from_delta(0.0, -40.0)
	if not north.begins_with("Nearest spawn: N"):
		push_error("compass should read north, got %s" % north)
		return false
	var right := _Overlay.arrow_rotation(Vector2(10.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0))
	if right < 0.4:
		push_error("arrow should rotate toward screen-right, got %.3f" % right)
		return false
	var ahead := _Overlay.arrow_rotation(Vector2(0.0, 10.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0))
	if absf(ahead) > 0.05:
		push_error("arrow straight ahead should be unrotated, got %.3f" % ahead)
		return false
	var src := (_Overlay as GDScript).source_code
	if "ObjectiveHud" not in src or "_update_objective_hud" not in src:
		push_error("game overlay must keep an objective HUD")
		return false
	print("OK objective HUD lines and spawn arrow")
	return true


func _test_town_penalty_not_loss() -> bool:
	var gm := _GameManager.new()
	root.add_child(gm)
	var crystal := _CrystalManager.new()
	crystal.power = 5.0
	gm._crystal = crystal
	var stub := Node.new()
	stub.set_script(_dismiss_stub_script())
	root.add_child(stub)
	gm._on_town_fallen("Harbor", Vector2i(12, -4))
	if gm.run_state != _GameManager.RunState.PLAYING:
		push_error("fallen town must not end the run, state=%s reason=%s" % [gm.run_state, gm.last_loss_reason])
		return false
	if gm.fallen_towns != 1 or crystal.power < 40.0:
		push_error("town penalty missing surge or count power=%.1f towns=%d" % [crystal.power, gm.fallen_towns])
		return false
	if "defenders" not in gm.last_town_penalty:
		push_error("penalty line should mention defenders, got %s" % gm.last_town_penalty)
		return false
	if int(stub.get("calls")) != 1:
		push_error("town fall should dismiss defenders once, calls=%s" % stub.get("calls"))
		return false
	stub.free()
	var td := _TownDefense.new()
	td.add_to_group("town_defense_manager")
	root.add_child(td)
	td.force_threat_state(Vector2i(3, 3), _TownDefense.TownState.FALLEN, 0.0)
	gm._town_penalty_bound = true
	for _i in 3:
		await process_frame
	if gm.run_state != _GameManager.RunState.PLAYING:
		push_error("a fallen town flag must not lose the run during _process")
		return false
	if not td.is_town_fallen(Vector2i(3, 3)):
		push_error("town defense should report the fallen town")
		return false
	print("OK town fall penalty power=%.1f line=%s" % [crystal.power, gm.last_town_penalty])
	td.free()
	gm.free()
	crystal.free()
	return true


func _dismiss_stub_script() -> GDScript:
	var scr := GDScript.new()
	scr.source_code = "extends Node\nvar calls: int = 0\nfunc _ready() -> void:\n\tadd_to_group(\"entity_manager\")\nfunc dismiss_town_defenders(center: Vector2i) -> int:\n\tcalls += 1\n\treturn 3\n"
	scr.reload()
	return scr


func _test_defender_dismiss() -> bool:
	var em := _EntityManager.new()
	var militia := _WorldEntity.new()
	militia.entity_kind = &"town_militia"
	militia.home_cell = Vector2i(8, 9)
	em._entities.append(militia)
	var removed := em.dismiss_town_defenders(Vector2i(8, 9))
	if removed != 1 or not em._town_defenders_lost(Vector2i(8, 9)):
		push_error("dismiss should remove the town militia, removed=%d" % removed)
		return false
	var before := em._entities.size()
	em.spawn_town_defenders({"center": Vector2i(8, 9), "radius": 12}, 2)
	if em._entities.size() != before:
		push_error("fallen town must not recruit new defenders")
		return false
	print("OK dismissed town defenders stay gone")
	return true


func _test_corner_origin() -> bool:
	var cm_seed := _CrystalManager.new()
	var c1: Vector2i = cm_seed.origin_corner_for_seed(1)
	var c2: Vector2i = cm_seed.origin_corner_for_seed(2)
	var c1_again: Vector2i = cm_seed.origin_corner_for_seed(1)
	if c1 != c1_again or c1 == c2:
		push_error("corner choice must be deterministic and vary with seed, %s vs %s" % [c1, c2])
		return false
	for seed_value in [1, 2, 12349]:
		var world = load("res://world/InfiniteNoiseWorld.gd").new()
		world.world_seed = seed_value
		var cm := _CrystalManager.new()
		cm.world = world
		var origin: Vector2i = cm.pick_origin_spawn_cell()
		var again: Vector2i = cm.pick_origin_spawn_cell()
		if origin != again:
			push_error("seed %d origin not stable %s vs %s" % [seed_value, origin, again])
			return false
		var min_abs := int(float(_WorldBorder.PLAYABLE_HALF_X) * 0.55)
		if absi(origin.x) < min_abs or absi(origin.y) < min_abs:
			push_error("seed %d origin %s is not in a corner" % [seed_value, origin])
			return false
		if not _WorldBorder.allows_crystal(float(origin.x), float(origin.y)):
			push_error("seed %d origin %s is outside the playable map" % [seed_value, origin])
			return false
		var tile: int = world.get_tile_type(float(origin.x), float(origin.y))
		if _CrystalTypes.is_water_tile(tile):
			push_error("seed %d origin %s is water tile %d" % [seed_value, origin, tile])
			return false
		var surface: float = world.get_surface_height(float(origin.x), float(origin.y))
		if surface < 4.0 or surface > 138.0:
			push_error("seed %d origin %s surface %.2f is not land" % [seed_value, origin, surface])
			return false
		var preferred: Vector2i = cm.origin_corner_for_seed(seed_value)
		if _sgn(origin.x) != _sgn(preferred.x) or _sgn(origin.y) != _sgn(preferred.y):
			push_error("seed %d origin %s left its corner %s" % [seed_value, origin, preferred])
			return false
		print("OK corner origin seed=%d at %s tile=%d surface=%.1f" % [seed_value, origin, tile, surface])
	return true


func _sgn(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0


func _test_jump_is_space() -> bool:
	var text := FileAccess.get_file_as_string("res://project.godot")
	var jump_at := text.find("jump={")
	var next_at := text.find("\n}", jump_at)
	var jump_block := text.substr(jump_at, next_at - jump_at)
	if "physical_keycode\":32" not in jump_block and "physical_keycode\":32" not in jump_block.replace(":", "\":"):
		# File stores `"physical_keycode":32`.
		if "physical_keycode\":32" not in jump_block and not jump_block.contains("physical_keycode\":32"):
			pass
	if not jump_block.contains("physical_keycode\":32") and not jump_block.contains("physical_keycode\":32"):
		if not jump_block.contains("32"):
			push_error("jump action must be bound to Space (physical key 32)")
			return false
	if jump_block.contains("physical_keycode\":77") or jump_block.contains(":77"):
		push_error("jump must no longer be M")
		return false
	var accept_at := text.find("ui_accept={")
	if accept_at < 0:
		push_error("ui_accept must keep Enter after Space moves to jump")
		return false
	var accept_end := text.find("\n}", accept_at)
	var accept_block := text.substr(accept_at, accept_end - accept_at)
	if accept_block.contains(":32,") or accept_block.contains(":32\n"):
		push_error("ui_accept must not keep Space; Enter still confirms")
		return false
	if not accept_block.contains("4194309"):
		push_error("ui_accept must still include Enter")
		return false
	var viewer := (load("res://world/world_viewer.gd") as GDScript).source_code
	if "event.keycode == KEY_SPACE" in viewer:
		push_error("world viewer random-seed binding must move off Space")
		return false
	if "KEY_N" not in viewer:
		push_error("world viewer random seed should move to N")
		return false
	print("OK jump is Space; Enter still accepts UI")
	return true
