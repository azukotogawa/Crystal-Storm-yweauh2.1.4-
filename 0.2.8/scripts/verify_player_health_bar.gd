extends SceneTree
## Headless: the HUD health bar sits above the hotbar and follows player health.
## Green above 55%, yellow above 28%, red at or below 28%. Mouse clicks pass through.


const _OverlayScene = preload("res://ui/game_overlay.tscn")
const _PlayerSettings = preload("res://systems/player_settings.gd")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	_failed = true


func _run() -> void:
	await process_frame
	_check_player_source()
	root.size = Vector2i(1280, 720)
	var player := _make_player(100.0, 100.0)
	root.add_child(player)
	var overlay: Control = _OverlayScene.instantiate()
	root.add_child(overlay)
	await process_frame
	await process_frame
	var panel := overlay.get_node_or_null("PlayerHealthBar") as PanelContainer
	if panel == null:
		_fail("PlayerHealthBar missing")
		_finish()
		return
	var bar := panel.find_child("HpFill", true, false) as ProgressBar
	var value_label := _value_label(panel)
	if bar == null or value_label == null:
		_fail("health bar fill or value label missing")
		_finish()
		return
	_check_layout(panel, bar)
	_expect_hp(bar, value_label, 100.0, 100.0, "100 / 100", _green(), "full")
	player.health = 55.0
	player.poke()
	_expect_hp(bar, value_label, 55.0, 100.0, "55 / 100", _yellow(), "55% boundary")
	player.health = 56.0
	player.poke()
	_expect_hp(bar, value_label, 56.0, 100.0, "56 / 100", _green(), "just above 55%")
	player.health = 28.0
	player.poke()
	_expect_hp(bar, value_label, 28.0, 100.0, "28 / 100", _red(), "28% boundary")
	player.health = 29.0
	player.poke()
	_expect_hp(bar, value_label, 29.0, 100.0, "29 / 100", _yellow(), "just above 28%")
	# A change that does not emit still shows up on the next HUD frame.
	player.health = 80.0
	player.max_health = 100.0
	await process_frame
	_expect_hp(bar, value_label, 80.0, 100.0, "80 / 100", _green(), "polled heal")
	player.health = 20.0
	player.max_health = 40.0
	player.poke()
	_expect_hp(bar, value_label, 20.0, 40.0, "20 / 40", _yellow(), "resized max")
	player.health = 40.0
	player.poke()
	_PlayerSettings.colorblind_palette = true
	overlay.apply_hud_palette(true)
	_expect_color(bar, Color(0.95, 0.82, 0.18), "colorblind high")
	player.health = 4.0
	player.poke()
	_expect_color(bar, Color(0.35, 0.72, 1.0), "colorblind low")
	_PlayerSettings.colorblind_palette = false
	overlay.apply_hud_palette(false)
	_expect_color(bar, _red(), "colorblind off restores red")
	player.queue_free()
	await process_frame
	await process_frame
	if panel.visible:
		_fail("bar stayed visible after the player was freed")
	_finish()


func _finish() -> void:
	_PlayerSettings.colorblind_palette = false
	if _failed:
		quit(1)
	else:
		print("All player health bar tests OK")
		quit(0)


func _check_player_source() -> void:
	var src := FileAccess.get_file_as_string("res://player/player.gd")
	if src.is_empty():
		_fail("player.gd unreadable")
		return
	if not src.contains("signal health_changed(current: float, maximum: float)"):
		_fail("player missing health_changed signal")
	if src.count("_publish_health()") < 6:
		_fail("player health publish sites changed (%s)" % src.count("_publish_health()"))
	var damage := _func_body(src, "func take_damage")
	if damage.find("health = maxf(health - amount, 0.0)") < 0 \
			or damage.find("_publish_health()") < damage.find("health = maxf"):
		_fail("take_damage does not publish after the hit")
	if damage.find("if burst and _hit_iframes > 0.0:") > damage.find("_publish_health()"):
		_fail("iframe return publishes a hit that did not land")
	var heal := _func_body(src, "func heal")
	if not heal.contains("_publish_health()"):
		_fail("heal does not publish")


func _func_body(src: String, header: String) -> String:
	var at := src.find(header)
	if at < 0:
		_fail("missing %s" % header)
		return ""
	var nxt := src.find("\nfunc ", at + header.length())
	if nxt < 0:
		return src.substr(at)
	return src.substr(at, nxt - at)


func _make_player(hp: float, mx: float) -> Node:
	var scr := GDScript.new()
	scr.source_code = """extends Node
signal health_changed(current: float, maximum: float)
var health: float = 100.0
var max_health: float = 100.0
func poke() -> void:
	health_changed.emit(health, max_health)
"""
	var err := scr.reload()
	if err != OK:
		_fail("player stub script %s" % err)
	var player := Node.new()
	player.set_script(scr)
	player.name = "Scout"
	player.add_to_group("player")
	player.health = hp
	player.max_health = mx
	return player


func _value_label(panel: PanelContainer) -> Label:
	for child in panel.find_children("*", "Label", true, false):
		var label := child as Label
		if label != null and label.text.contains("/"):
			return label
	return null


func _check_layout(panel: PanelContainer, bar: ProgressBar) -> void:
	if panel.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("health panel steals clicks")
	if bar.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("health fill steals clicks")
	if panel.anchor_left != 0.5 or panel.anchor_right != 0.5:
		_fail("health bar is not centered")
	if panel.anchor_top != 1.0 or panel.anchor_bottom != 1.0:
		_fail("health bar is not on the bottom edge")
	# Hotbar top is -76. The bar bottom must stay above that.
	if panel.offset_bottom > -80.0:
		_fail("health bar overlaps the hotbar (bottom %s)" % panel.offset_bottom)
	if panel.offset_top >= panel.offset_bottom:
		_fail("health bar has no height")
	if panel.offset_left >= 0.0 or panel.offset_right <= 0.0:
		_fail("health bar is not centered on the offsets")
	if bar.custom_minimum_size.x < 100.0 or bar.custom_minimum_size.y < 12.0:
		_fail("health fill is too small %s" % bar.custom_minimum_size)
	if bar.show_percentage:
		_fail("health bar shows a percent instead of the value label")


func _expect_hp(
	bar: ProgressBar,
	value_label: Label,
	hp: float,
	mx: float,
	text: String,
	fill: Color,
	tag: String
) -> void:
	if absf(bar.max_value - mx) > 0.01 or absf(bar.value - hp) > 0.01:
		_fail("%s bar %s/%s want %s/%s" % [tag, bar.value, bar.max_value, hp, mx])
	if value_label.text != text:
		_fail("%s label '%s' want '%s'" % [tag, value_label.text, text])
	_expect_color(bar, fill, tag)


func _expect_color(bar: ProgressBar, fill: Color, tag: String) -> void:
	var box := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if box == null:
		_fail("%s fill style missing" % tag)
		return
	if not _same_color(box.bg_color, fill):
		_fail("%s fill %s want %s" % [tag, box.bg_color, fill])


func _same_color(got: Color, want: Color) -> bool:
	return absf(got.r - want.r) < 0.02 and absf(got.g - want.g) < 0.02 and absf(got.b - want.b) < 0.02


func _green() -> Color:
	return Color(0.32, 0.78, 0.38)


func _yellow() -> Color:
	return Color(0.92, 0.7, 0.2)


func _red() -> Color:
	return Color(0.88, 0.24, 0.28)
