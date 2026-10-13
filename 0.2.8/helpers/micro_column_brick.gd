class_name MicroColumnBrick
extends RefCounted
## Sparse per-column micro refinement payload (localized overlay on macro authority).


const REASON_NONE := 0
const REASON_EDIT := 1
const REASON_CLIFF := 2
const REASON_BUILD := 3

var surface_y: float = 0.0
var surface_tile: int = 0
var dug_layers: int = 0
var reason: int = REASON_NONE


func copy_from_macro(surface_y_value: float, surface_tile_value: int, reason_value: int, dug: int = 0) -> void:
	surface_y = surface_y_value
	surface_tile = surface_tile_value
	reason = reason_value
	dug_layers = dug


func matches_macro(surface_y_value: float, surface_tile_value: int) -> bool:
	return is_equal_approx(surface_y, surface_y_value) and surface_tile == surface_tile_value