class_name DashSkill
extends RefCounted

const SKILL_ID := &"dash"
const DISTANCE := 4.0
const DURATION := 0.12
const INVULN := 0.18
const COOLDOWN := 3.0


static func direction(wish: Vector2, facing: Vector2) -> Vector2:
	if wish.length_squared() > 0.0001:
		return wish.normalized()
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector2(0.0, -1.0)


static func step_columns(left: float, delta: float) -> float:
	if left <= 0.0 or delta <= 0.0:
		return 0.0
	return minf(left, (DISTANCE / DURATION) * delta)
