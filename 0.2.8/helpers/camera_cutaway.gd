class_name CameraCutaway
extends RefCounted

const RADIUS_AT_PLAYER := 1.3
const RADIUS_AT_CAMERA := 1.25
const FEET_CLEAR := 0.3
const PAST_DISTANCE := 1.0
const T_MIN := 0.05
const BODY_LIFT := 1.4

static var submitted_enabled: float = 1.0
static var submitted_player: Vector3 = Vector3.ZERO
static var submitted_camera: Vector3 = Vector3.ZERO
static var submitted_radius: float = RADIUS_AT_PLAYER
static var submitted_radius_near: float = RADIUS_AT_CAMERA
static var submitted_feet_clear: float = FEET_CLEAR
static var submitted_past: float = PAST_DISTANCE
static var submit_count: int = 0


static func contains(
	world_pos: Vector3,
	player_pos: Vector3,
	camera_pos: Vector3,
	radius_at_player: float = RADIUS_AT_PLAYER,
	feet_clear: float = FEET_CLEAR,
	past_distance: float = PAST_DISTANCE
) -> bool:
	if world_pos.y <= player_pos.y + feet_clear:
		return false
	var ab: Vector3 = player_pos + Vector3(0.0, BODY_LIFT, 0.0) - camera_pos
	var ab_len2: float = ab.length_squared()
	if ab_len2 <= 0.01:
		return false
	var t: float = ab.dot(world_pos - camera_pos) / ab_len2
	if t <= T_MIN:
		return false
	var ab_len: float = sqrt(ab_len2)
	var ahead: float = (1.0 - t) * ab_len
	if ahead <= past_distance:
		return false
	var tc: float = clampf(t, 0.0, 1.0)
	var closest: Vector3 = camera_pos + ab * tc
	var dist: float = world_pos.distance_to(closest)
	var rad: float = lerpf(RADIUS_AT_CAMERA, radius_at_player, tc)
	return dist < rad
