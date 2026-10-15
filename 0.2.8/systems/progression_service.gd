class_name ProgressionService
extends Node

const XP_ENABLED := true
const CURVE_BASE := 50.0
const CURVE_EXPONENT := 1.5

signal xp_gained(amount: int, xp: int)
signal level_up(level: int)

static var _active = null

var xp: int = 0
var level: int = 1


static func get_active():
	return _active


func _enter_tree() -> void:
	_active = self
	add_to_group("progression_service")


func _exit_tree() -> void:
	if _active == self:
		_active = null


static func xp_to_advance(from_level: int) -> int:
	var lv := maxi(from_level, 1)
	return int(round(CURVE_BASE * pow(float(lv), CURVE_EXPONENT)))


func add_xp(amount: int) -> void:
	if not XP_ENABLED or amount <= 0:
		return
	xp += amount
	_raise_levels()
	xp_gained.emit(amount, xp)


func _raise_levels() -> void:
	var guard := 0
	while guard < 64:
		var need := xp_to_advance(level)
		if need <= 0 or xp < need:
			return
		xp -= need
		level += 1
		level_up.emit(level)
		guard += 1
