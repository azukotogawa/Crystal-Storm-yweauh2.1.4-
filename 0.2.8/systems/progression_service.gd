class_name ProgressionService
extends Node

const XP_ENABLED := true
const CURVE_BASE := 50.0
const CURVE_EXPONENT := 1.5
const XP_KILL_BASE := 8
const XP_KILL_PER_TIER := 6
const XP_CRYSTAL_HIT := 4
const XP_CRYSTAL_CELL := 10
const XP_BLOCK_MINED := 1
const XP_STRUCTURE_PLACED := 12
const XP_RUIN_DISCOVERED := 25
const XP_POI_DISCOVERED := 20
const KILL_TIERS := {
	&"rabbit": 0,
	&"deer": 0,
	&"bird": 0,
	&"boar": 0,
	&"crystal_mite": 0,
	&"thornling": 0,
	&"crystal_stag": 1,
	&"corrupted_beast": 1,
	&"farm_bomber": 1,
	&"crystal_wisp": 1,
	&"crystal_enemy": 1,
	&"shard_guard": 2,
	&"spawn_elite": 3,
	&"origin_warden": 4,
	&"town_militia": -1,
	&"town_villager": -1,
}

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


static func kill_tier(kind: StringName) -> int:
	if KILL_TIERS.has(kind):
		return int(KILL_TIERS[kind])
	return 0


static func xp_for_kill(tier: int) -> int:
	if tier < 0:
		return 0
	return XP_KILL_BASE + tier * XP_KILL_PER_TIER


static func xp_for_crystal_hit(amount: float, broken: bool) -> int:
	if amount <= 0.0 and not broken:
		return 0
	var total := 0
	if amount > 0.0:
		total += XP_CRYSTAL_HIT
	if broken:
		total += XP_CRYSTAL_CELL
	return total


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
