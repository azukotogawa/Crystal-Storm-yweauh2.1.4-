extends SceneTree

const _Nav = preload("res://entities/entity_navigation.gd")
const _Cfg = preload("res://config/entity_brain_config.gd")
const _Wildlife = preload("res://world/wildlife_density.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Types = preload("res://helpers/world_feature_types.gd")


func _init() -> void:
	call_deferred("_run")


func _plan_counts() -> String:
	var world = _World.new(12349)
	var plan: Array[Dictionary] = _Wildlife.plan(world, 160, 512)
	var by_biome := {}
	var kinds := {}
	for spot in plan:
		var b := str(spot.get("biome", ""))
		var k := str(_Types.ANIMAL_DISPLAY.get(int(spot.get("animal_kind", -1)), "?")).to_lower()
		var row: Dictionary = by_biome.get(b, {})
		row[k] = int(row.get(k, 0)) + 1
		by_biome[b] = row
		kinds[k] = true
	var parts := []
	var keys := by_biome.keys()
	keys.sort()
	for b in keys:
		parts.append("%s:%d" % [b, (by_biome[b] as Dictionary).size()])
	return "plan_spots=%d kinds=%d types_per_biome=%s detail=%s" % [plan.size(), kinds.size(), ",".join(parts), str(by_biome)]


func _is_animal(e) -> bool:
	if e == null or not is_instance_valid(e) or e.brain == null or e.config == null:
		return false
	if e.config.behavior_profile != _Cfg.BehaviorProfile.PASSIVE_HERBIVORE:
		return false
	return str(e.entity_kind) != "town_villager"


func _run() -> void:
	print("P7_G_PLAN %s" % _plan_counts())
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var player = null
	for _i in 2400:
		player = get_first_node_in_group("player")
		if player and bool(player.get("world_ready")):
			break
		await process_frame
	for _i in 120:
		await physics_frame
	var mgr = get_first_node_in_group("entity_manager")
	var reg = load("res://entities/entity_brain_registry.gd")
	var pc: Vector2i = _Nav.column_pos(player.global_position)
	var ids := ["rabbit", "deer", "boar", "bird", "fox", "goat", "duck"]
	var spawned := 0
	for i in 28:
		var cfg = reg.get_def(StringName(ids[i % ids.size()]))
		if cfg == null:
			cfg = reg.get_def(&"rabbit")
		var ang := TAU * float(i) / 28.0
		var r := 18.0 + float(i % 4) * 3.0
		var c := pc + Vector2i(int(round(cos(ang) * r)), int(round(sin(ang) * r)))
		mgr._spawn_world_entity(c.x, c.y, cfg, c, Color(0.7, 0.7, 0.7))
		spawned += 1
	print("P7_G_SPAWNED %d" % spawned)
	for _i in 60:
		await physics_frame
	var last := {}
	var last_dir := {}
	var win_start := {}
	var win_target := {}
	var turns := 0.0
	var turn_n := 0
	var sharp := 0
	var windows := 0
	var stuck := 0
	var seen := {}
	var halt := {}
	var stalls := 0
	var stall_frames := 0
	var want_frames := 0
	var kinds := {}
	for f in 1800:
		await physics_frame
		if player:
			player.health = 100.0
		for e in get_nodes_in_group("world_entity"):
			if not _is_animal(e):
				continue
			seen[e] = true
			kinds[str(e.entity_kind)] = true
			var p: Vector3 = e.global_position
			var flat := Vector2(p.x, p.z)
			if last.has(e):
				var mv: Vector2 = flat - last[e]
				var want: bool = e.brain.target_cell != _Nav.column_pos(p)
				if want:
					want_frames += 1
				if want and mv.length() <= 0.0005:
					stall_frames += 1
					halt[e] = int(halt.get(e, 0)) + 1
					if int(halt[e]) == 30:
						stalls += 1
						if OS.get_environment("P7_DIAG") == "1":
							print("P7_G_STALLDIAG kind=%s state=%d cell=%s tgt=%s st=%s knock=%s skip=%s y=%.2f" % [e.entity_kind, int(e.brain.state), _Nav.column_pos(p), e.brain.target_cell, str(e.get("_stall_time")), str(e.get("_knock_left")), str(mgr.get("physics_skip_frames")), p.y])
				else:
					halt[e] = 0
				if mv.length() > 0.004:
					var d := mv.normalized()
					if last_dir.has(e):
						var a := absf(rad_to_deg((last_dir[e] as Vector2).angle_to(d)))
						turns += a
						turn_n += 1
						if a >= 60.0:
							sharp += 1
					last_dir[e] = d
			last[e] = flat
			if f % 60 == 0:
				if win_start.has(e):
					var cell: Vector2i = _Nav.column_pos(p)
					var wants: bool = win_target[e] != cell
					if wants:
						windows += 1
						if (flat - (win_start[e] as Vector2)).length() < 0.15:
							stuck += 1
						if OS.get_environment("P7_DIAG") == "1":
							print("P7_G_STUCKDIAG kind=%s state=%d cell=%s tgt=%s now_tgt=%s y=%.2f stall=%s" % [e.entity_kind, int(e.brain.state), cell, win_target[e], e.brain.target_cell, p.y, str(e.get("_stall_time"))])
				win_start[e] = flat
				win_target[e] = e.brain.target_cell
	var rate := float(stuck) / maxf(1.0, float(windows))
	print("P7_G_WALK tag=%s animals=%d kinds=%s stalls_0p5s=%d stall_frame_rate=%.4f windows=%d net_low=%d net_low_rate=%.3f mean_turn_deg=%.2f sharp_turns=%d moving_samples=%d" % [OS.get_environment("P7_TAG"), seen.size(), str(kinds.keys()), stalls, float(stall_frames) / maxf(1.0, float(want_frames)), windows, stuck, rate, turns / maxf(1.0, float(turn_n)), sharp, turn_n])
	quit()