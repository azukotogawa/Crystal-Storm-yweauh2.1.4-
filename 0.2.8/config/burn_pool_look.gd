class_name BurnPoolLook
extends Resource

const RESOURCE_PATH := "res://config/default_burn_pool_look.tres"

@export var cover_radius_columns: float = 1.35
@export var tile_inset: float = 0.08
@export var tile_thickness: float = 0.16
@export var ground_gap: float = 0.04
@export var magma_hot: Color = Color(1.0, 0.78, 0.12, 1.0)
@export var magma_cool: Color = Color(0.62, 0.08, 0.02, 1.0)
@export var crack_color: Color = Color(0.05, 0.012, 0.008, 1.0)
@export var emission: Color = Color(1.0, 0.32, 0.05, 1.0)
@export var emission_low: float = 0.9
@export var emission_high: float = 2.5
@export var alpha_low: float = 0.82
@export var alpha_span: float = 0.18
@export var colorblind_hot: Color = Color(1.0, 0.95, 0.35, 1.0)
@export var colorblind_cool: Color = Color(0.95, 0.55, 0.05, 1.0)
@export var colorblind_crack: Color = Color(0.05, 0.04, 0.02, 1.0)
@export var colorblind_emission: Color = Color(1.0, 0.9, 0.2, 1.0)
@export var fire_per_tile: int = 3
@export var fire_size: float = 0.16
@export var fire_height: float = 0.55
@export var fire_spread: float = 0.34
@export var fire_speed: float = 1.7
@export var fire_hot: Color = Color(1.0, 0.92, 0.35, 0.95)
@export var fire_cool: Color = Color(0.95, 0.28, 0.04, 0.7)
@export var colorblind_fire_hot: Color = Color(1.0, 1.0, 0.85, 0.95)
@export var colorblind_fire_cool: Color = Color(1.0, 0.72, 0.1, 0.75)

var _crack: ImageTexture
var _crack_blind: bool = false


static func load_active() -> BurnPoolLook:
	var script: Script = load("res://config/burn_pool_look.gd")
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded: Resource = load(RESOURCE_PATH)
		if loaded is BurnPoolLook:
			return loaded as BurnPoolLook
	return (script.new() as BurnPoolLook)


func crack_texture(colorblind: bool) -> ImageTexture:
	if _crack != null and _crack_blind == colorblind:
		return _crack
	_crack_blind = colorblind
	_crack = ImageTexture.create_from_image(_cracks(colorblind))
	return _crack


func tile_emission(colorblind: bool) -> Color:
	return colorblind_emission if colorblind else emission


func fire_color(colorblind: bool, rise: float) -> Color:
	var hot := colorblind_fire_hot if colorblind else fire_hot
	var cool := colorblind_fire_cool if colorblind else fire_cool
	return cool.lerp(hot, clampf(rise, 0.0, 1.0))


func _cracks(colorblind: bool) -> Image:
	var hot := colorblind_hot if colorblind else magma_hot
	var cool := colorblind_cool if colorblind else magma_cool
	var crack := colorblind_crack if colorblind else crack_color
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := cool.lerp(hot, _heat(x, y))
			if _crack_at(x, y):
				c = crack
			img.set_pixel(x, y, c)
	return img


func _heat(x: int, y: int) -> float:
	if x >= 6 and x <= 9 and y >= 6 and y <= 9:
		return 1.0
	if x >= 11 and x <= 13 and y >= 2 and y <= 4:
		return 0.85
	if x >= 2 and x <= 4 and y >= 11 and y <= 13:
		return 0.7
	return 0.15


func _crack_at(x: int, y: int) -> bool:
	if x == 0 or y == 0 or x == 15 or y == 15:
		return true
	if y == 5 and x >= 2 and x <= 10:
		return true
	if x == 10 and y >= 5 and y <= 12:
		return true
	if y == 12 and x >= 6 and x <= 14:
		return true
	if x == 4 and y >= 2 and y <= 8:
		return true
	if y == 8 and x >= 4 and x <= 7:
		return true
	if x == 12 and y >= 7 and y <= 14:
		return true
	if y == 3 and x >= 7 and x <= 14:
		return true
	return false
