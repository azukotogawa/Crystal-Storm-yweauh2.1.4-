extends SceneTree
## Headless: pixel-look settings parse, defaults OFF, size + snap math.

const _PixelLook = preload("res://helpers/pixel_look.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _run() -> void:
	# Isolate from ambient env for default checks.
	var saved_en := OS.get_environment(_PixelLook.ENV_ENABLE)
	var saved_h := OS.get_environment(_PixelLook.ENV_HEIGHT)
	var saved_b := OS.get_environment(_PixelLook.ENV_BANDING)
	var saved_o := OS.get_environment(_PixelLook.ENV_OUTLINE)
	OS.set_environment(_PixelLook.ENV_ENABLE, "")
	OS.set_environment(_PixelLook.ENV_HEIGHT, "")
	OS.set_environment(_PixelLook.ENV_BANDING, "")
	OS.set_environment(_PixelLook.ENV_OUTLINE, "")

	_expect(_PixelLook.parse_enabled() == false, "default enabled is false")
	_expect(_PixelLook.parse_enabled("") == false, "empty string enabled is false")
	_expect(_PixelLook.parse_enabled("0") == false, "0 is false")
	_expect(_PixelLook.parse_enabled("off") == false, "off is false")
	_expect(_PixelLook.parse_enabled("1") == true, "1 is true")
	_expect(_PixelLook.parse_enabled("true") == true, "true is true")
	_expect(_PixelLook.parse_enabled("ON") == true, "ON is true")

	_expect(_PixelLook.parse_height() == _PixelLook.DEFAULT_HEIGHT, "default height 270")
	_expect(_PixelLook.parse_height("216") == 216, "height 216")
	_expect(_PixelLook.parse_height("360") == 360, "height 360")
	_expect(_PixelLook.parse_height("12") == _PixelLook.MIN_HEIGHT, "height clamps low")
	_expect(_PixelLook.parse_height("9999") == _PixelLook.MAX_HEIGHT, "height clamps high")
	_expect(_PixelLook.parse_height("nope") == _PixelLook.DEFAULT_HEIGHT, "bad height falls back")

	_expect(_PixelLook.parse_banding() == false, "banding default off")
	_expect(_PixelLook.parse_outline() == false, "outline default off")
	_expect(_PixelLook.parse_banding("1") == true, "banding on")
	_expect(_PixelLook.parse_outline("yes") == true, "outline on")

	var sz := _PixelLook.internal_size(Vector2i(1280, 720), 270)
	_expect(sz.y == 270, "internal height 270")
	_expect(sz.x == 480, "1280x720 @270 -> width 480 got %d" % sz.x)

	var sz2 := _PixelLook.internal_size(Vector2i(1920, 1080), 216)
	_expect(sz2 == Vector2i(384, 216), "1920x1080 @216 -> 384x216 got %s" % str(sz2))

	var sz3 := _PixelLook.internal_size(Vector2i(1280, 720), 360)
	_expect(sz3 == Vector2i(640, 360), "1280x720 @360 -> 640x360 got %s" % str(sz3))

	var upp := _PixelLook.world_units_per_pixel(27.0, 270)
	_expect(is_equal_approx(upp, 0.1), "upp 27/270=0.1 got %s" % str(upp))

	# Identity basis: snap along X/Y.
	var basis := Basis.IDENTITY
	var snap := _PixelLook.snap_camera_position(Vector3(0.25, 0.07, 3.0), basis, 27.0, 270)
	var snapped: Vector3 = snap["snapped"]
	var sub: Vector2 = snap["subpixel"]
	_expect(is_equal_approx(snapped.x, 0.2), "snap x floor to 0.2 got %s" % str(snapped.x))
	_expect(is_equal_approx(snapped.y, 0.0), "snap y floor to 0.0 got %s" % str(snapped.y))
	_expect(is_equal_approx(snapped.z, 3.0), "forward z preserved got %s" % str(snapped.z))
	_expect(is_equal_approx(sub.x, 0.5), "subpixel x 0.5 got %s" % str(sub.x))
	_expect(is_equal_approx(sub.y, 0.7), "subpixel y 0.7 got %s" % str(sub.y))

	# Already on grid -> zero remainder (build from upp so floats stay exact).
	var upp_g := _PixelLook.world_units_per_pixel(27.0, 270)
	var on_grid := Vector3(4.0 * upp_g, -3.0 * upp_g, 1.0)
	var snap2 := _PixelLook.snap_camera_position(on_grid, basis, 27.0, 270)
	_expect(is_equal_approx(float((snap2["subpixel"] as Vector2).x), 0.0), "on-grid sub x 0 got %s" % str(snap2["subpixel"]))
	_expect(is_equal_approx(float((snap2["subpixel"] as Vector2).y), 0.0), "on-grid sub y 0 got %s" % str(snap2["subpixel"]))

	# resolve_settings: defaults off, env wins.
	var resolved := _PixelLook.resolve_settings({})
	_expect(resolved["enabled"] == false, "resolve default off")
	_expect(int(resolved["height"]) == 270, "resolve default height")
	OS.set_environment(_PixelLook.ENV_ENABLE, "1")
	OS.set_environment(_PixelLook.ENV_HEIGHT, "216")
	resolved = _PixelLook.resolve_settings({"pixel_render_enabled": false, "pixel_height": 360})
	_expect(resolved["enabled"] == true, "env overrides config enabled")
	_expect(int(resolved["height"]) == 216, "env overrides config height")

	# Restore ambient env.
	OS.set_environment(_PixelLook.ENV_ENABLE, saved_en)
	OS.set_environment(_PixelLook.ENV_HEIGHT, saved_h)
	OS.set_environment(_PixelLook.ENV_BANDING, saved_b)
	OS.set_environment(_PixelLook.ENV_OUTLINE, saved_o)

	if _failed == 0:
		print("PIXEL_LOOK_CONFIG OK")
		quit(0)
	else:
		print("PIXEL_LOOK_CONFIG FAIL count=%d" % _failed)
		quit(1)
