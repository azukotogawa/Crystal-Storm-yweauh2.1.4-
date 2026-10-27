extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")

const OLD_ANIM := {"stone_pick": 0.26, "wall_segment": 0.28, "gate": 0.28, "stairs": 0.28}
const OLD_WIND := {"multi_block_break": 0.35, "building_placement": 0.16}
const OLD_RECOVERY := {"multi_block_break": 0.24, "building_placement": 0.12}

var _failed := 0


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _init() -> void:
	for id in OLD_ANIM:
		var an := float(_ItemTypes.get_def(id).get("anim_duration", 0.0))
		print("%s anim %.2f" % [id, an])
		if an <= 0.0 or an > OLD_ANIM[id] * 0.65:
			_fail("%s anim %.2f is not about 40 percent shorter" % [id, an])
	var cfg = _GameFeelConfig.active()
	for id in OLD_WIND:
		var row: Dictionary = cfg.action(id)
		var wind := float(row["telegraph_sec"])
		var rec := float(row["recovery_sec"])
		print("%s wind %.2f recovery %.2f" % [id, wind, rec])
		if wind <= 0.0 or wind > OLD_WIND[id] * 0.65 or wind < OLD_WIND[id] * 0.5:
			_fail("%s wind-up %.2f not about 40 percent shorter and above zero" % [id, wind])
		if rec <= 0.0 or rec > OLD_RECOVERY[id] * 0.65:
			_fail("%s recovery %.2f not about 40 percent shorter" % [id, rec])
	if not is_equal_approx(cfg.brush_reach, 4.5):
		_fail("break and place reach changed")
	if _failed == 0:
		print("All break and place speed checks OK")
		quit(0)
	else:
		quit(1)
