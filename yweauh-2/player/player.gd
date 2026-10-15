extends Node2D

var z_height: float = 0.0
var z_velocity: float = 0.0
var is_jumping: bool = false
const GRAVITY_CONSTANT: float = 230.0

func _physics_process(delta: float):
	if is_jumping:
		z_velocity -= GRAVITY_CONSTANT * delta
		z_height += z_velocity * delta
		
		if z_velocity <= 0.0 and z_height >= 0.0:
			z_height = 0.0
			z_velocity = 0.0
			is_jumping = false
