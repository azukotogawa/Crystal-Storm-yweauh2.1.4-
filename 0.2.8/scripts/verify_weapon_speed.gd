extends SceneTree

const _ItemTypes = preload("res://helpers/item_types.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")

const OLD := {
	"wooden_sword": [0.45, 0.45],
	"spear": [0.78, 0.78],
	"shortbow": [0.8, 0.8],
	"sling": [0.5, 0.5],
}

var _failed := 0


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _init() -> void:
	var reach: float = _GameFeelConfig.active().brush_reach
	for id in ["wooden_sword", "spear", "crystal_hammer"]:
		var def := _ItemTypes.get_def(id)
		var r := float(def.get("range", 0.0))
		print("%s range %.1f" % [id, r])
		if r <= reach or r < 5.0:
			_fail("%s melee range %.1f must exceed brush reach %.1f and be at least 5" % [id, r, reach])
	for id in OLD:
		var def := _ItemTypes.get_def(id)
		var cd := float(def.get("cooldown", 0.0))
		var an := float(def.get("anim_duration", 0.0))
		print("%s cooldown %.2f anim %.2f" % [id, cd, an])
		if cd > OLD[id][0] * 0.72 or an > OLD[id][1] * 0.72:
			_fail("%s is not about 30 percent faster" % id)
		if cd <= 0.0 or an <= 0.0:
			_fail("%s lost its wind-up" % id)
	var hammer := _ItemTypes.get_def("crystal_hammer")
	if not is_equal_approx(float(hammer.anim_duration), 1.1) or not is_equal_approx(float(hammer.impact_ratio), 0.62) or not is_equal_approx(float(hammer.cooldown), 1.1):
		_fail("hammer timings are locked")
	if _failed == 0:
		print("All weapon speed checks OK")
		quit(0)
	else:
		quit(1)
