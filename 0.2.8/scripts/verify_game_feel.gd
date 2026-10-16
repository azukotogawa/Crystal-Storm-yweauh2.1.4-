extends SceneTree

const _Config = preload("res://config/game_feel_config.gd")
const _TRES := "res://config/default_game_feel.tres"

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


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
	if _failed == 0:
		print("All game feel tests OK")
		quit(0)
	else:
		push_error("verify_game_feel: %d failure(s)" % _failed)
		quit(1)


func _check_config(cfg: GameFeelConfig, label: String) -> void:
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
		elif telegraph < _Config.TELEGRAPH_MIN or telegraph > _Config.TELEGRAPH_MAX:
			_fail("%s %s telegraph %.3f outside 0.15-0.40" % [label, id, telegraph])
		if linger <= 0.0:
			_fail("%s %s linger is zero" % [label, id])
		elif linger < _Config.LINGER_MIN or linger > _Config.LINGER_MAX:
			_fail("%s %s linger %.3f outside 0.50-1.50" % [label, id, linger])
		var hit := float(row["hit_stop_sec"])
		if hit < _Config.HIT_STOP_MIN or hit > _Config.HIT_STOP_MAX:
			_fail("%s %s hit-stop %.3f outside 0.05-0.10" % [label, id, hit])
		if float(row["shake"]) <= 0.0 or float(row["flash"]) <= 0.0 or float(row["recovery_sec"]) <= 0.0:
			_fail("%s %s shake, flash, or recovery is zero" % [label, id])
	if cfg.action("missing").size() != 0:
		_fail("%s unknown action returned a row" % label)
	if cfg.banner_sec < _Config.BANNER_MIN or cfg.banner_sec > _Config.BANNER_MAX:
		_fail("%s banner %.2f outside 2-3s" % [label, cfg.banner_sec])
	for id in _Config.BEATS:
		var row: Dictionary = cfg.beat(id)
		if row.is_empty():
			_fail("%s missing beat %s" % [label, id])
			continue
		var banner := float(row["banner_sec"])
		if banner < _Config.BANNER_MIN or banner > _Config.BANNER_MAX:
			_fail("%s %s banner %.2f outside 2-3s" % [label, id, banner])
		var scale := float(row["slow_mo_scale"])
		if scale < _Config.SLOW_MO_FLOOR or scale > 1.0:
			_fail("%s %s slow-mo %.2f is a freeze or above 1" % [label, id, scale])
		if float(row["slow_mo_sec"]) <= 0.0 or float(row["camera_shake"]) <= 0.0:
			_fail("%s %s emphasis duration or shake is zero" % [label, id])
	for id in _Config.ENEMIES:
		var row: Dictionary = cfg.enemy(id)
		if row.is_empty() or float(row["telegraph_sec"]) <= 0.0:
			_fail("%s %s telegraph missing" % [label, id])
	print("OK game feel %s" % label)
