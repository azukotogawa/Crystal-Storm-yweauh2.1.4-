extends SceneTree

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")


func _init() -> void:
	var cfg = _GameFeelConfig.active()
	if absf(cfg.brush_reach - 4.5) > 0.001 or absf(_ActionTargeting.reach() - cfg.brush_reach) > 0.001:
		push_error("reach must be the brush_reach tunable, default 4.5, got %s" % _ActionTargeting.reach())
		quit(1)
		return
	var src := FileAccess.get_file_as_string("res://player/action_targeting.gd")
	if "INTERACTION_RANGE" in src:
		push_error("action_targeting still declares a second reach constant")
		quit(1)
		return
	print("All interaction-range tests OK")
	quit(0)
