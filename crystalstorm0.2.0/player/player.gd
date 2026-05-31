class_name Player
extends Node2D

@export var move_speed := 10.0

var voxel_position: Vector3i = Vector3i.ZERO

func _process(delta):

	var move := Vector2i.ZERO

	if Input.is_action_pressed("ui_right"):
		move.x += 1
	if Input.is_action_pressed("ui_left"):
		move.x -= 1
	if Input.is_action_pressed("ui_down"):
		move.y += 1
	if Input.is_action_pressed("ui_up"):
		move.y -= 1

	match IsoMath.rotation:
		0:
			pass

		1:
			move = Vector2i(move.y, -move.x)

		2:
			move = Vector2i(-move.x, -move.y)

		3:
			move = Vector2i(-move.y, move.x)

	if move != Vector2i.ZERO:
		voxel_position.x += move.x
		voxel_position.y += move.y
		# Immediately snap visual position
		position = IsoMath.voxel_to_screen(voxel_position.x, voxel_position.y, voxel_position.z)
		
