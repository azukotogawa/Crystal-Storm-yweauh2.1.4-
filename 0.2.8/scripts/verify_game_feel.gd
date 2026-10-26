extends SceneTree

const _Config = preload("res://config/game_feel_config.gd")
const _TRES := "res://config/default_game_feel.tres"

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _outside(value: float, lo: float, hi: float) -> bool:
	return value < lo - 0.001 or value > hi + 0.001


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	_check_config(_Config.create_default(), "default")
	var loaded = load(_TRES)
	if not (loaded is _Config):
		_fail("default_game_feel.tres did not load")
	else:
		_check_config(loaded, "tres")
	_check_hooks()
	if _failed == 0:
		print("All game feel tests OK")
		quit(0)
	else:
		push_error("verify_game_feel: %d failure(s)" % _failed)
		quit(1)


func _check_config(cfg, label: String) -> void:
	if cfg.action_ids.size() != _Config.ACTIONS.size():
		_fail("%s action count %d" % [label, cfg.action_ids.size()])
	for id in _Config.ACTIONS:
		var row: Dictionary = cfg.action(id)
		if row.is_empty():
			_fail("%s missing action %s" % [label, id])
			continue
		var telegraph := float(row["telegraph_sec"])
		var linger := float(row["linger_sec"])
		if telegraph <= 0.0:
			_fail("%s %s telegraph is zero" % [label, id])
		elif _outside(telegraph, _Config.TELEGRAPH_MIN, _Config.TELEGRAPH_MAX):
			_fail("%s %s telegraph %.3f outside 0.09-0.40" % [label, id, telegraph])
		if linger <= 0.0:
			_fail("%s %s linger is zero" % [label, id])
		elif _outside(linger, _Config.LINGER_MIN, _Config.LINGER_MAX):
			_fail("%s %s linger %.3f outside 0.50-1.50" % [label, id, linger])
		var hit := float(row["hit_stop_sec"])
		if _outside(hit, _Config.HIT_STOP_MIN, _Config.HIT_STOP_MAX):
			_fail("%s %s hit-stop %.3f outside 0.05-0.10" % [label, id, hit])
		if float(row["shake"]) <= 0.0 or float(row["flash"]) <= 0.0 or float(row["recovery_sec"]) <= 0.0:
			_fail("%s %s shake, flash, or recovery is zero" % [label, id])
	if cfg.action("missing").size() != 0:
		_fail("%s unknown action returned a row" % label)
	if _outside(cfg.banner_sec, _Config.BANNER_MIN, _Config.BANNER_MAX):
		_fail("%s banner %.2f outside 2-3s" % [label, cfg.banner_sec])
	for id in _Config.BEATS:
		var row: Dictionary = cfg.beat(id)
		if row.is_empty():
			_fail("%s missing beat %s" % [label, id])
			continue
		var banner := float(row["banner_sec"])
		if _outside(banner, _Config.BANNER_MIN, _Config.BANNER_MAX):
			_fail("%s %s banner %.2f outside 2-3s" % [label, id, banner])
		var scale := float(row["slow_mo_scale"])
		if scale < _Config.SLOW_MO_FLOOR - 0.001 or scale > 1.001:
			_fail("%s %s slow-mo %.2f is a freeze or above 1" % [label, id, scale])
		if float(row["slow_mo_sec"]) <= 0.0 or float(row["camera_shake"]) <= 0.0:
			_fail("%s %s emphasis duration or shake is zero" % [label, id])
	for id in _Config.ENEMIES:
		var row: Dictionary = cfg.enemy(id)
		if row.is_empty() or float(row["telegraph_sec"]) <= 0.0:
			_fail("%s %s telegraph missing" % [label, id])
	print("OK game feel %s" % label)


func _check_hooks() -> void:
	var feel := root.get_node_or_null("GameFeel")
	if feel == null:
		_fail("GameFeel autoload missing")
		return
	if absf(float(feel.banner_seconds()) - 2.5) > 0.001:
		_fail("shared banner is %.2f" % float(feel.banner_seconds()))
	if absf(float(feel.banner_seconds("win")) - 3.0) > 0.001:
		_fail("win banner is not 3s")
	if absf(float(feel.safe_slow_scale(0.0)) - _Config.SLOW_MO_FLOOR) > 0.001:
		_fail("slow-mo floor did not hold")
	if absf(float(feel.safe_slow_scale(0.55)) - 0.55) > 0.001:
		_fail("slow-mo scale was rewritten")
	if feel.enemy_telegraph("mite") <= 0.0 or feel.enemy_telegraph("boss") <= 0.0 or feel.enemy_telegraph("burn_pool") <= 0.0:
		_fail("enemy telegraph hook is zero")
	var heard: Array[String] = []
	feel.sound_hook.connect(func(cue: String) -> void:
		heard.append(cue)
	)
	var scale_before := Engine.time_scale
	var paused_before := paused
	feel.play_action("sword_swing")
	feel.play_beat("level_up")
	feel.play_action("missing")
	feel.play_beat("missing")
	if heard.size() != 2 or heard[0] != "sword_swing" or heard[1] != "level_up":
		_fail("sound hook got %s" % str(heard))
	if absf(Engine.time_scale - scale_before) > 0.001:
		_fail("headless feel changed time_scale to %.3f" % Engine.time_scale)
		Engine.time_scale = 1.0
	if paused != paused_before:
		_fail("feel paused the tree")
		paused = paused_before
	else:
		print("OK game feel hooks")
