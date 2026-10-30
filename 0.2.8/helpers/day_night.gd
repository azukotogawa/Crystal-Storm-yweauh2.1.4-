class_name DayNight
extends RefCounted

const DAY_LENGTH_SEC := 480.0
const NOON_PHASE := 0.25
const MIDNIGHT_PHASE := 0.75
const DAY_AMBIENT := 1.0
const NIGHT_AMBIENT := 0.36
const DAY_SUN := 1.0
const NIGHT_SUN := 0.28
const DAY_TERRAIN := 1.0
const NIGHT_TERRAIN := 0.48
const RECORDED_NIGHT_DAY_RATIO := 0.36


static func phase_of(elapsed_sec: float) -> float:
	if DAY_LENGTH_SEC <= 0.0:
		return NOON_PHASE
	return fposmod(elapsed_sec, DAY_LENGTH_SEC) / DAY_LENGTH_SEC


static func daylight(phase: float) -> float:
	var s := sin(phase * TAU)
	return clampf(smoothstep(-0.2, 0.45, s), 0.0, 1.0)


static func ambient_factor(phase: float) -> float:
	return lerpf(NIGHT_AMBIENT, DAY_AMBIENT, daylight(phase))


static func sun_factor(phase: float) -> float:
	return lerpf(NIGHT_SUN, DAY_SUN, daylight(phase))


static func terrain_gain(phase: float) -> float:
	return lerpf(NIGHT_TERRAIN, DAY_TERRAIN, daylight(phase))


static func night_day_ambient_ratio() -> float:
	var day_v := ambient_factor(NOON_PHASE)
	var night_v := ambient_factor(MIDNIGHT_PHASE)
	if day_v <= 0.0001:
		return 0.0
	return night_v / day_v
