class_name RangedAim
extends RefCounted

const _GameFeelConfig = preload("res://config/game_feel_config.gd")

const REFERENCE_SPEED := 32.0


static func charge_of(held_sec: float) -> float:
	return clampf(held_sec / maxf(_GameFeelConfig.active().draw_sec, 0.01), 0.0, 1.0)


static func cancels(charge: float) -> bool:
	return charge < _GameFeelConfig.active().draw_min_charge


static func speed_for(charge: float, item_speed: float) -> float:
	var cfg = _GameFeelConfig.active()
	var t := pow(clampf(charge, 0.0, 1.0), cfg.draw_curve)
	return lerpf(cfg.draw_min_speed, cfg.draw_max_speed, t) * item_speed / REFERENCE_SPEED


static func cursor_point(ray_origin: Vector3, ray_dir: Vector3, plane_y: float) -> Vector3:
	if absf(ray_dir.y) < 0.00001:
		return ray_origin
	return ray_origin + ray_dir * ((plane_y - ray_origin.y) / ray_dir.y)


static func launch_direction(muzzle: Vector3, ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var point := cursor_point(ray_origin, ray_dir, muzzle.y)
	var dir := point - muzzle
	if dir.length_squared() < 0.0001:
		return Vector3(ray_dir.x, 0.0, ray_dir.z).normalized()
	return dir.normalized()


static func simulate_range(speed: float, dir: Vector3, gravity: float) -> float:
	var vel := dir * speed
	var pos := Vector3.ZERO
	var dt := 0.005
	for _i in 4000:
		vel.y -= gravity * dt
		pos += vel * dt
		if pos.y < 0.0 and vel.y < 0.0:
			break
	return Vector2(pos.x, pos.z).length()
