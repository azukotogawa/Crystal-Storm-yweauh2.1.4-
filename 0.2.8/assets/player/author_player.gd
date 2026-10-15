extends SceneTree

const ART_SIZE := Vector2i(32, 48)
const PARTS := [
	{"id": "torso", "bone": "Torso", "parent": "Root", "x": 12, "y": 12, "w": 8, "h": 12},
	{"id": "head", "bone": "Head", "parent": "Torso", "x": 12, "y": 2, "w": 8, "h": 8},
	{"id": "upper_arm_l", "bone": "UpperArm_L", "parent": "Torso", "x": 8, "y": 12, "w": 4, "h": 4},
	{"id": "lower_arm_l", "bone": "LowerArm_L", "parent": "UpperArm_L", "x": 8, "y": 16, "w": 4, "h": 4},
	{"id": "upper_arm_r", "bone": "UpperArm_R", "parent": "Torso", "x": 20, "y": 12, "w": 4, "h": 4},
	{"id": "lower_arm_r", "bone": "LowerArm_R", "parent": "UpperArm_R", "x": 20, "y": 16, "w": 4, "h": 4},
	{"id": "leg_l", "bone": "Leg_L", "parent": "Root", "x": 12, "y": 28, "w": 4, "h": 8},
	{"id": "leg_r", "bone": "Leg_R", "parent": "Root", "x": 16, "y": 28, "w": 4, "h": 8},
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := Color(0.12, 0.1, 0.08, 1)
	var hair := Color(0.28, 0.16, 0.1, 1)
	var skin := Color(0.86, 0.62, 0.42, 1)
	var tunic := Color(0.22, 0.42, 0.34, 1)
	var tunic_dark := Color(0.14, 0.28, 0.24, 1)
	var belt := Color(0.42, 0.28, 0.14, 1)
	var boot := Color(0.2, 0.14, 0.1, 1)
	var eye := Color(0.08, 0.08, 0.1, 1)
	_vox(img, 12, 2, hair, outline)
	_vox(img, 16, 2, hair, outline)
	_vox(img, 12, 6, skin, outline)
	_vox(img, 16, 6, skin, outline)
	_dot(img, 14, 8, eye)
	_dot(img, 18, 8, eye)
	_vox(img, 8, 12, tunic, outline)
	_vox(img, 12, 12, tunic, outline)
	_vox(img, 16, 12, tunic_dark, outline)
	_vox(img, 20, 12, tunic, outline)
	_vox(img, 12, 16, tunic, outline)
	_vox(img, 16, 16, belt, outline)
	_vox(img, 12, 20, tunic_dark, outline)
	_vox(img, 16, 20, tunic_dark, outline)
	_vox(img, 8, 16, skin, outline)
	_vox(img, 20, 16, skin, outline)
	_vox(img, 12, 28, boot, outline)
	_vox(img, 16, 28, boot, outline)
	_vox(img, 12, 32, boot, outline)
	_vox(img, 16, 32, boot, outline)
	var out := ProjectSettings.globalize_path("res://assets/player/player.png")
	img.save_png(out)
	print("WROTE %s" % out)
	quit(0)


func _vox(img: Image, x: int, y: int, fill: Color, outline: Color) -> void:
	for py in 4:
		for px in 4:
			var c := fill
			if px == 0 or py == 0:
				c = outline
			elif px == 3 or py == 3:
				c = fill.darkened(0.18)
			img.set_pixel(x + px, y + py, c)


func _dot(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(x, y, c)
	img.set_pixel(x + 1, y, c)
	img.set_pixel(x, y + 1, c)
	img.set_pixel(x + 1, y + 1, c)
