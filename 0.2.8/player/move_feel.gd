class_name MoveFeel
extends RefCounted
## Sprint and jump-feel numbers for the player step.
## Pure math. No terrain probes, so the 60 Hz tick stays the same shape.
## Ramps, floor snap, and lighting do not read this.

## Hold sprint on dry ground. A column of water does not use this.
const SPRINT_MULT := 1.62
## A river tile is already slow. Sprint still helps, less than on grass.
const WADE_SPRINT_MULT := 1.28
## Air keeps momentum. Steering is softer than the ground.
const AIR_CONTROL := 0.42
## Releasing the keys on the ground stops sooner than the old glide.
const GROUND_STOP_MULT := 1.35
## Turning around uses a harder accel so the body does not ice-skate.
const REVERSE_MULT := 2.1
## Extra push for the first steps of a sprint, still on the ground only.
const SPRINT_ACCEL_MULT := 1.2
## Walk off a ledge and the jump still counts for this long.
const COYOTE_SEC := 0.12
## A jump pressed just before landing still fires.
const JUMP_BUFFER_SEC := 0.12
## Tap jump hops. Holding jump keeps the full rise.
const JUMP_RELEASE_MULT := 0.48
## Falling is heavier than the rise, so landings settle.
const FALL_GRAVITY_MULT := 1.32
## Landing keeps most of the run. The old 0.65 dump killed a sprint.
const LAND_SPEED_KEEP := 0.84
const SPRINT_BOB_RATE := 15.5
const WALK_BOB_RATE := 11.0


static func sprint_multiplier(wading: bool) -> float:
	return WADE_SPRINT_MULT if wading else SPRINT_MULT


## Submerged bodies ignore sprint. The caller already applied the swim slow.
static func apply_sprint(speed: float, sprinting: bool, submerged: bool, wading: bool) -> float:
	if not sprinting or submerged:
		return speed
	return speed * sprint_multiplier(wading)


static func accel_rate(
	move_accel: float,
	move_friction: float,
	has_input: bool,
	airborne: bool,
	reversing: bool,
	sprinting: bool = false
) -> float:
	var rate := move_friction
	if has_input:
		rate = move_accel
		if sprinting and not airborne:
			rate *= SPRINT_ACCEL_MULT
		if reversing and not airborne:
			rate *= REVERSE_MULT
	else:
		rate = move_friction * (GROUND_STOP_MULT if not airborne else AIR_CONTROL)
	if airborne and has_input:
		rate *= AIR_CONTROL
	return rate


static func coyote_after(left: float, supported: bool, delta: float) -> float:
	if supported:
		return COYOTE_SEC
	return maxf(left - delta, 0.0)


static func can_jump(supported: bool, coyote_left: float) -> bool:
	return supported or coyote_left > 0.0


static func gravity_scale(vertical_speed: float) -> float:
	if vertical_speed < 0.0:
		return FALL_GRAVITY_MULT
	return 1.0


static func release_jump(vertical_speed: float) -> float:
	if vertical_speed > 0.0:
		return vertical_speed * JUMP_RELEASE_MULT
	return vertical_speed


static func bob_rate(sprinting: bool) -> float:
	return SPRINT_BOB_RATE if sprinting else WALK_BOB_RATE
