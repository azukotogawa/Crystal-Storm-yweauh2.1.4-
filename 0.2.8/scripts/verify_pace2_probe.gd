extends SceneTree

const _Run = preload("res://scripts/honest_bot/honest_scenario.gd")
const _Exit = preload("res://scripts/probe_exit.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const PICK_DAMAGE := 2.4
const PICK_SWING := 0.16
const SWORD_DAMAGE := 12.0
const SWORD_KNOCK := 1.0


func _init() -> void:
	Engine.physics_jitter_fix = 0.0
	Engine.physics_ticks_per_second = 60
	call_deferred("_go")


func _go() -> void:
	var run = _Run.new()
	var seen := PackedStringArray()
	var player = await run._boot(self, "crystals", seen)
	if player == null:
		_Exit.finish_tree(self, 1, "PROBE FAIL boot")
		return
	print("PROBE pace %.2f" % GameFeelConfig.pace())
	_tough(player)
	await _knock(player)
	await _crystal(player)
	_Exit.finish_tree(self, 0, "PROBE DONE")


func _tough(player) -> void:
	if "max_health" in player:
		player.max_health = 1000000.0
	if "health" in player:
		player.health = 1000000.0


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await physics_frame
		t += 1.0 / 60.0


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _knock(player) -> void:
	var spawner = get_first_node_in_group("crystal_enemy_spawner")
	if spawner == null:
		print("PROBE FAIL no spawner")
		return
	var vs: float = _WorldSettings.get_active().voxel_scale
	var col: Vector3 = player.voxel_position
	var offsets := [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3), Vector2i(2, 2)]
	var sums := {}
	var trials := 0
	for off in offsets:
		_tough(player)
		var before := get_nodes_in_group("crystal_enemy")
		if not spawner.spawn_enemy_at_column(&"crystal_mite", int(col.x) + off.x, int(col.z) + off.y, Vector2i.ZERO, true):
			print("PROBE knock spawn failed %s" % str(off))
			continue
		var mite: Node3D = null
		for e in get_nodes_in_group("crystal_enemy"):
			if not before.has(e):
				mite = e
		if mite == null:
			continue
		var waited := 0.0
		while waited < 3.0 and is_instance_valid(mite) and _flat(mite.global_position - player.global_position).length() > 2.8 * vs:
			await physics_frame
			waited += 1.0 / 60.0
		if not is_instance_valid(mite):
			continue
		mite.max_health = 1000.0
		mite.health = 1000.0
		var dir := _flat(mite.global_position - player.global_position).normalized()
		var p0: Vector3 = mite.global_position
		mite.take_damage(SWORD_DAMAGE, &"wooden_sword")
		mite.apply_knockback(dir, SWORD_KNOCK * vs)
		var row := []
		var t := 0.0
		var marks := [0.1, 0.25, 0.5, 0.75, 1.0]
		var peak := 0.0
		var mi := 0
		while mi < marks.size() and is_instance_valid(mite):
			await physics_frame
			t += 1.0 / 60.0
			var d := (mite.global_position - p0).dot(dir)
			peak = maxf(peak, d)
			if t + 0.0001 >= float(marks[mi]):
				row.append(d)
				sums[mi] = float(sums.get(mi, 0.0)) + d
				mi += 1
		sums["peak"] = float(sums.get("peak", 0.0)) + peak
		trials += 1
		print("PROBE knock trial %s peak %.2f at %s" % [str(off), peak, str(row)])
		if is_instance_valid(mite):
			mite.queue_free()
		await _wait(0.2)
	if trials == 0:
		print("PROBE FAIL knock no trials")
		return
	print("PROBE knock trials %d world units per voxel %.2f" % [trials, vs])
	print("PROBE knock mean peak %.2f" % (float(sums["peak"]) / trials))
	var labels := ["0.10", "0.25", "0.50", "0.75", "1.00"]
	for i in labels.size():
		print("PROBE knock mean disp t=%s %.2f" % [labels[i], float(sums.get(i, 0.0)) / trials])


func _crystal(player) -> void:
	var crystal = get_first_node_in_group("crystal_manager")
	if crystal == null:
		print("PROBE FAIL no crystal")
		return
	var cfg = crystal.get("sim_config")
	var min_d: float = cfg.min_depth if cfg else 0.04
	var origin: Vector2i = crystal.get_origin_cell()
	print("PROBE crystal origin %s depth %.2f" % [str(origin), crystal.get_depth_at(origin.x, origin.y)])
	var best := Vector2i.ZERO
	var best_sum := -1.0
	for r in range(0, 40):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				var c := origin + Vector2i(dx, dz)
				var s := _patch_sum(crystal, c, min_d)
				if s > best_sum:
					best_sum = s
					best = c
		if best_sum > 0.0:
			break
	if best_sum <= 0.0:
		print("PROBE FAIL no full crystal patch")
		return
	var cells := []
	for x in range(3):
		for z in range(3):
			cells.append(best + Vector2i(x, z))
	print("PROBE crystal patch %s (9 cells) depth %.2f" % [str(best), best_sum])
	var t := 0.0
	var swings := 0
	var broken := 0
	var cleared_at := -1.0
	var swing_t := 0.0
	while t < 30.0:
		await physics_frame
		t += 1.0 / 60.0
		swing_t += 1.0 / 60.0
		if swing_t >= PICK_SWING:
			swing_t -= PICK_SWING
			var target := _deepest(crystal, cells, min_d)
			if target.x != 2147483647:
				var hit: Dictionary = crystal.damage_crystal_at(target, PICK_DAMAGE)
				swings += 1
				if bool(hit.get("broken", false)):
					broken += 1
		if cleared_at < 0.0 and _filled(crystal, cells, min_d) == 0:
			cleared_at = t
			break
	print("PROBE crystal swings %d breaks %d break_rate %.2f/s clear_time %s" % [swings, broken, broken / maxf(t, 0.01), ("%.2f s" % cleared_at) if cleared_at >= 0.0 else "not cleared in 30 s"])
	var marks := [1.0, 2.0, 5.0, 10.0, 20.0, 30.0, 45.0]
	var mi := 0
	var w := 0.0
	while mi < marks.size():
		await physics_frame
		w += 1.0 / 60.0
		if w + 0.0001 >= float(marks[mi]):
			print("PROBE crystal regrow t=%.0f filled %d/9 depth %.2f" % [float(marks[mi]), _filled(crystal, cells, min_d), _sum(crystal, cells)])
			mi += 1


func _patch_sum(crystal, c: Vector2i, min_d: float) -> float:
	var s := 0.0
	for x in range(3):
		for z in range(3):
			var d: float = crystal.get_depth_at(c.x + x, c.y + z)
			if d < maxf(min_d * 2.0, 0.12):
				return -1.0
			s += d
	return s


func _deepest(crystal, cells: Array, min_d: float) -> Vector2i:
	var best := Vector2i(2147483647, 0)
	var bd := -1.0
	for c in cells:
		var d: float = crystal.get_depth_at(c.x, c.y)
		if d >= min_d and d > bd:
			bd = d
			best = c
	return best


func _filled(crystal, cells: Array, min_d: float) -> int:
	var n := 0
	for c in cells:
		if crystal.get_depth_at(c.x, c.y) >= min_d:
			n += 1
	return n


func _sum(crystal, cells: Array) -> float:
	var s := 0.0
	for c in cells:
		s += crystal.get_depth_at(c.x, c.y)
	return s