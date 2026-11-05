class_name PixelLook
extends RefCounted
## Low-res nearest upscale helpers (t3ssel8r-style). Default OFF.

const ENV_ENABLE := "CS_PIXEL_RENDER"
const ENV_HEIGHT := "CS_PIXEL_HEIGHT"
const ENV_BANDING := "CS_PIXEL_BANDING"
const ENV_OUTLINE := "CS_PIXEL_OUTLINE"

const DEFAULT_HEIGHT := 270
const MIN_HEIGHT := 72
const MAX_HEIGHT := 720
const HEIGHT_CHOICES: PackedInt32Array = [216, 270, 360]


static func _truthy(raw: String) -> bool:
	var v := raw.strip_edges().to_lower()
	return v in ["1", "true", "on", "yes"]


static func _falsy(raw: String) -> bool:
	var v := raw.strip_edges().to_lower()
	return v in ["0", "false", "off", "no"]


## Env default is OFF when unset or empty.
static func parse_enabled(env_value: String = "") -> bool:
	var raw := env_value
	if raw.is_empty():
		raw = OS.get_environment(ENV_ENABLE)
	if raw.strip_edges().is_empty():
		return false
	if _falsy(raw):
		return false
	return _truthy(raw)


static func parse_height(env_value: String = "", fallback: int = DEFAULT_HEIGHT) -> int:
	var raw := env_value
	if raw.is_empty():
		raw = OS.get_environment(ENV_HEIGHT)
	raw = raw.strip_edges()
	if raw.is_empty():
		return clamp_height(fallback)
	if not raw.is_valid_int():
		return clamp_height(fallback)
	return clamp_height(int(raw))


static func parse_banding(env_value: String = "") -> bool:
	var raw := env_value
	if raw.is_empty():
		raw = OS.get_environment(ENV_BANDING)
	if raw.strip_edges().is_empty():
		return false
	return _truthy(raw)


static func parse_outline(env_value: String = "") -> bool:
	var raw := env_value
	if raw.is_empty():
		raw = OS.get_environment(ENV_OUTLINE)
	if raw.strip_edges().is_empty():
		return false
	return _truthy(raw)


static func clamp_height(height: int) -> int:
	return clampi(int(height), MIN_HEIGHT, MAX_HEIGHT)


## Preserve window aspect; height is the controllable axis.
static func internal_size(window_size: Vector2i, internal_height: int) -> Vector2i:
	var h: int = clamp_height(internal_height)
	var aspect: float
	if window_size.x > 0 and window_size.y > 0:
		aspect = float(window_size.x) / float(window_size.y)
	else:
		aspect = 16.0 / 9.0
	var w: int = maxi(1, int(round(float(h) * aspect)))
	return Vector2i(w, h)


## Godot ortho `size` is the full vertical world extent of the view.
static func world_units_per_pixel(ortho_size: float, internal_height: int) -> float:
	var h: int = maxi(1, clamp_height(internal_height))
	return float(ortho_size) / float(h)


## Snap camera position onto the screen-space pixel grid in the camera's right/up plane.
## Returns { "snapped": Vector3, "subpixel": Vector2 } where subpixel is the fractional
## pixel remainder in [0, 1) along right/up, applied to the upscale blit.
static func snap_camera_position(
	pos: Vector3,
	cam_basis: Basis,
	ortho_size: float,
	internal_height: int
) -> Dictionary:
	var upp: float = world_units_per_pixel(ortho_size, internal_height)
	if upp <= 0.000001:
		return {"snapped": pos, "subpixel": Vector2.ZERO}
	var right: Vector3 = cam_basis.x
	var up: Vector3 = cam_basis.y
	var forward: Vector3 = cam_basis.z
	if right.length_squared() < 0.000001 or up.length_squared() < 0.000001:
		return {"snapped": pos, "subpixel": Vector2.ZERO}
	right = right.normalized()
	up = up.normalized()
	forward = forward.normalized()
	var r: float = pos.dot(right)
	var u: float = pos.dot(up)
	var f: float = pos.dot(forward)
	var r_cell: float = floorf(r / upp)
	var u_cell: float = floorf(u / upp)
	var sub_r: float = (r / upp) - r_cell
	var sub_u: float = (u / upp) - u_cell
	# Absorb float dust that lands just below the next cell (esp. negative coords).
	if sub_r >= 0.999999:
		r_cell += 1.0
		sub_r = 0.0
	if sub_u >= 0.999999:
		u_cell += 1.0
		sub_u = 0.0
	if sub_r < 0.000001:
		sub_r = 0.0
	if sub_u < 0.000001:
		sub_u = 0.0
	var r_snap: float = r_cell * upp
	var u_snap: float = u_cell * upp
	var sub: Vector2 = Vector2(sub_r, sub_u)
	var snapped: Vector3 = right * r_snap + up * u_snap + forward * f
	return {"snapped": snapped, "subpixel": sub}


## Settings merge: config dict overrides defaults; env overrides config when set.
static func resolve_settings(config: Dictionary = {}) -> Dictionary:
	var enabled: bool = bool(config.get("pixel_render_enabled", false))
	var height: int = clamp_height(int(config.get("pixel_height", DEFAULT_HEIGHT)))
	var banding: bool = bool(config.get("pixel_banding", false))
	var outline: bool = bool(config.get("pixel_outline", false))

	var env_en := OS.get_environment(ENV_ENABLE).strip_edges()
	if not env_en.is_empty():
		enabled = parse_enabled(env_en)
	var env_h := OS.get_environment(ENV_HEIGHT).strip_edges()
	if not env_h.is_empty():
		height = parse_height(env_h, height)
	var env_b := OS.get_environment(ENV_BANDING).strip_edges()
	if not env_b.is_empty():
		banding = parse_banding(env_b)
	var env_o := OS.get_environment(ENV_OUTLINE).strip_edges()
	if not env_o.is_empty():
		outline = parse_outline(env_o)

	return {
		"enabled": enabled,
		"height": height,
		"banding": banding,
		"outline": outline,
	}
