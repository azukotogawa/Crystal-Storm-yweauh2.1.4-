# Inside player.gd
extends Node2D

var z_height: float = 0.0
var z_velocity: float = 0.0
var is_jumping: bool = false
const GRAVITY_CONSTANT: float = 230.0

func _physics_process(delta: float):
	if is_jumping:
		# Apply downward acceleration to velocity
		z_velocity -= GRAVITY_CONSTANT * delta
		# Add velocity to your height offset tracking variable
		z_height += z_velocity * delta
		
		# FIX: The landing check must look at velocity direction.
		# If z_height returns to 0 (or goes positive) while moving downward, the player has landed.
		if z_velocity <= 0.0 and z_height >= 0.0:
			z_height = 0.0
			z_velocity = 0.0
			is_jumping = false
