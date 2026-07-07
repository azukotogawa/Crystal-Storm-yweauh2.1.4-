class_name CrystalTexturePalette
extends Resource

## Color palette for a single texture category variant (crystal, biome, ore, ground).
## Assign in CrystalTextureGenConfig or load from JSON via TexturePaletteJsonIO.

@export var id: StringName = &"default"
@export var display_name: String = "Default"

@export_group("Base Colors")
@export var primary: Color = Color(0.62, 0.18, 0.98)
@export var secondary: Color = Color(0.35, 0.08, 0.72)
@export var accent: Color = Color(0.85, 0.55, 1.0)
@export var shadow: Color = Color(0.12, 0.04, 0.22)

@export_group("Effects")
@export var glow_color: Color = Color(0.72, 0.28, 1.0, 1.0)
@export var glow_strength: float = 0.65
@export var iridescence_strength: float = 0.45
@export var iridescence_hue_shift: float = 0.18
@export var roughness_hint: float = 0.15
@export var metallic_hint: float = 0.35

@export_group("Variation")
@export var noise_tint_strength: float = 0.22
@export var contrast: float = 1.0
@export var saturation: float = 1.0


func duplicate_palette():
	var copy = duplicate()
	copy.id = id
	return copy


func to_dict() -> Dictionary:
	return {
		"id": str(id),
		"display_name": display_name,
		"primary": primary.to_html(false),
		"secondary": secondary.to_html(false),
		"accent": accent.to_html(false),
		"shadow": shadow.to_html(false),
		"glow_color": glow_color.to_html(false),
		"glow_strength": glow_strength,
		"iridescence_strength": iridescence_strength,
		"iridescence_hue_shift": iridescence_hue_shift,
		"roughness_hint": roughness_hint,
		"metallic_hint": metallic_hint,
		"noise_tint_strength": noise_tint_strength,
		"contrast": contrast,
		"saturation": saturation,
	}


static func from_dict(data: Dictionary):
	var script: GDScript = load("res://config/crystal_texture_palette.gd") as GDScript
	var p = script.new()
	p.id = StringName(str(data.get("id", "default")))
	p.display_name = str(data.get("display_name", "Default"))
	p.primary = _color_from(data.get("primary"), p.primary)
	p.secondary = _color_from(data.get("secondary"), p.secondary)
	p.accent = _color_from(data.get("accent"), p.accent)
	p.shadow = _color_from(data.get("shadow"), p.shadow)
	p.glow_color = _color_from(data.get("glow_color"), p.glow_color)
	p.glow_strength = float(data.get("glow_strength", p.glow_strength))
	p.iridescence_strength = float(data.get("iridescence_strength", p.iridescence_strength))
	p.iridescence_hue_shift = float(data.get("iridescence_hue_shift", p.iridescence_hue_shift))
	p.roughness_hint = float(data.get("roughness_hint", p.roughness_hint))
	p.metallic_hint = float(data.get("metallic_hint", p.metallic_hint))
	p.noise_tint_strength = float(data.get("noise_tint_strength", p.noise_tint_strength))
	p.contrast = float(data.get("contrast", p.contrast))
	p.saturation = float(data.get("saturation", p.saturation))
	return p


static func _color_from(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.html(str(value))
	return fallback