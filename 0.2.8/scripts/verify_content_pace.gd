extends SceneTree

const _Spawner = preload("res://entities/crystal_enemy_spawner.gd")
const _SimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

var _failed := 0


func _init() -> void:
	var cfg = GameFeelConfig.active()
	if not "content_pace" in cfg:
		_fail("game_feel_config has no content_pace")
		_finish()
		return
	if absf(float(cfg.content_pace) - 0.45) > 0.0001:
		_fail("default content_pace %.2f want 0.45" % cfg.content_pace)
	var sim = _SimConfig.create_default()
	var want_old := {
		"interval": 8.0, "cap": 24, "grace": 28.0, "assault": 1.6, "pressure": 1.25,
		"origin": 1.6, "ruin": 1.1, "artifact": 0.7,
		"grass": 0.14, "bush": 0.09, "tree": 0.05, "farmland": 0.11,
		"ruin_bonus": 12.0, "burst": 2, "summon": 3,
	}
	var want_new := {
		"interval": 17.78, "cap": 11, "grace": 62.22, "assault": 1.27, "pressure": 0.5625,
		"origin": 0.72, "ruin": 0.495, "artifact": 0.315,
		"grass": 0.063, "bush": 0.0405, "tree": 0.0225, "farmland": 0.0495,
		"ruin_bonus": 5.4, "burst": 1, "summon": 1,
	}
	for pair in [[1.0, want_old], [0.45, want_new]]:
		var p: float = pair[0]
		GameFeelConfig.pace_override = p
		var sp = _Spawner.new()
		var got := {
			"interval": sp.paced_interval(), "cap": sp.paced_cap(), "grace": sp.paced_grace(),
			"assault": sp.paced_assault_mult(), "pressure": sp.pressure_coeff(),
			"origin": sim.origin_emit_rate * GameFeelConfig.pace(),
			"ruin": sim.ruin_emit_rate * GameFeelConfig.pace(),
			"artifact": sim.artifact_emit_rate * GameFeelConfig.pace(),
			"grass": sim.grass_absorb_rate * GameFeelConfig.pace(),
			"bush": sim.bush_absorb_rate * GameFeelConfig.pace(),
			"tree": sim.tree_absorb_rate * GameFeelConfig.pace(),
			"farmland": sim.farmland_absorb_rate * GameFeelConfig.pace(),
			"ruin_bonus": 12.0 * GameFeelConfig.pace(),
			"burst": GameFeelConfig.paced_count(2, GameFeelConfig.pace()),
			"summon": GameFeelConfig.paced_summon(3, GameFeelConfig.pace()),
		}
		sp.free()
		var want: Dictionary = pair[1]
		for k in want:
			var tol := 0.01 if typeof(want[k]) == TYPE_FLOAT else 0.0
			if absf(float(got[k]) - float(want[k])) > tol:
				_fail("pace %.2f %s=%s want %s" % [p, k, str(got[k]), str(want[k])])
			else:
				print("OK pace %.2f %s=%s" % [p, k, str(got[k])])
		var worst: float = float(got.interval) / (float(got.assault) * (1.0 + float(got.pressure)) * 1.55)
		print("INFO pace %.2f worst-case mite cadence %.2f s cap %d" % [p, worst, got.cap])
	GameFeelConfig.pace_override = -1.0
	var uses := {
		"res://entities/crystal_enemy_spawner.gd": ["paced_grace()", "paced_cap()", "paced_interval()", "paced_assault_mult()", "pressure_coeff()", "GameFeelConfig.paced_count(int(entry.spawn_burst)"],
		"res://entities/crystal_enemy.gd": ["GameFeelConfig.paced_summon(mini(count, 3)"],
		"res://crystal/crystal_evolution.gd": ["def.bonus_power * GameFeelConfig.pace()", "GameFeelConfig.paced_count(def.spawn_burst"],
		"res://crystal/crystal_manager.gd": ["sim_config.grass_absorb_rate * pace", "sim_config.farmland_absorb_rate * pace", "snap.content_pace = pace"],
		"res://crystal/crystal_simulation.gd": ["emit_rate * snapshot.content_pace"],
		"res://crystal/crystal_fluid_sim.gd": ["spawn.emit_rate * GameFeelConfig.pace()"],
	}
	for path in uses:
		var src := FileAccess.get_file_as_string(path)
		for needle in uses[path]:
			if src.find(needle) < 0:
				_fail("%s does not apply pace: %s" % [path, needle])
	var spawner_src := FileAccess.get_file_as_string("res://entities/crystal_enemy_spawner.gd")
	if spawner_src.find(">= max_active") >= 0:
		_fail("spawner still checks the raw max_active")
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("All content pace tests OK")
		quit(0)
	else:
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)