class_name CrystalPalette
extends RefCounted

const _PlayerSettings = preload("res://systems/player_settings.gd")


static func is_active() -> bool:
	return _PlayerSettings.colorblind_palette


static func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func mass_albedo(colorblind: bool) -> Color:
	if colorblind:
		return Color(0.96, 0.78, 0.12, 0.92)
	return Color(0.72, 0.28, 1.0, 0.88)


static func mass_emission(colorblind: bool) -> Color:
	if colorblind:
		return Color(0.85, 0.62, 0.08)
	return Color(0.55, 0.18, 0.95)


static func marker_albedo(colorblind: bool) -> Color:
	if colorblind:
		return Color(0.12, 0.38, 0.92, 0.95)
	return Color(1.0, 0.35, 0.9, 0.85)


static func marker_emission(colorblind: bool) -> Color:
	if colorblind:
		return Color(0.08, 0.28, 0.85)
	return Color(1.0, 0.2, 0.8)


static func marker_modulate(colorblind: bool, boss: bool) -> Color:
	if colorblind:
		return Color(0.98, 0.90, 0.32, 0.95) if boss else Color(0.30, 0.58, 0.98, 0.95)
	return Color(1.0, 0.92, 1.0, 0.95) if boss else Color(0.88, 0.78, 1.0, 0.88)


static func spawn_fill(colorblind: bool, boss: bool, low: bool) -> Color:
	if low:
		return Color(0.06, 0.06, 0.08) if colorblind else Color(1.0, 0.28, 0.22)
	if colorblind:
		return Color(0.98, 0.92, 0.40) if boss else Color(0.20, 0.55, 0.98)
	return Color(1.0, 0.35, 0.55) if boss else Color(0.82, 0.28, 1.0)


static func hud_arrow(colorblind: bool) -> Color:
	if colorblind:
		return Color(0.98, 0.88, 0.20)
	return Color(0.95, 0.75, 1.0)


static func boss_label_color(colorblind: bool) -> Color:
	if colorblind:
		return Color(0.98, 0.92, 0.55)
	return Color(1.0, 0.82, 0.86)


static func paint_mass(mat: StandardMaterial3D, colorblind: bool) -> void:
	if mat == null:
		return
	mat.albedo_color = mass_albedo(colorblind)
	mat.emission = mass_emission(colorblind)


static func paint_marker(mat: StandardMaterial3D, colorblind: bool) -> void:
	if mat == null:
		return
	mat.albedo_color = marker_albedo(colorblind)
	mat.emission = marker_emission(colorblind)
