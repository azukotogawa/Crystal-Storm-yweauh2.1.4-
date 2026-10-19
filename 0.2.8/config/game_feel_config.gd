class_name GameFeelConfig
extends Resource

const ACTIONS: Array[String] = [
	"dash",
	"ground_slam",
	"crystal_pulse",
	"quick_wall",
	"multi_block_break",
	"bow_shot",
	"sword_swing",
	"building_placement",
]
const BEATS: Array[String] = [
	"level_up",
	"skill_unlock",
	"treasure",
	"relic",
	"landmark_discovery",
	"crystal_damage_stage",
	"boss_spawn",
	"win",
]
const ENEMIES: Array[String] = ["mite", "boss", "burn_pool"]

const TELEGRAPH_MIN := 0.15
const TELEGRAPH_MAX := 0.40
const HIT_STOP_MIN := 0.05
const HIT_STOP_MAX := 0.10
const LINGER_MIN := 0.50
const LINGER_MAX := 1.50
const BANNER_MIN := 2.0
const BANNER_MAX := 3.0
const SLOW_MO_FLOOR := 0.35

@export var action_ids: PackedStringArray = PackedStringArray()
@export var telegraph_sec: PackedFloat32Array = PackedFloat32Array()
@export var hit_stop_sec: PackedFloat32Array = PackedFloat32Array()
@export var shake: PackedFloat32Array = PackedFloat32Array()
@export var flash: PackedFloat32Array = PackedFloat32Array()
@export var linger_sec: PackedFloat32Array = PackedFloat32Array()
@export var recovery_sec: PackedFloat32Array = PackedFloat32Array()

@export var beat_ids: PackedStringArray = PackedStringArray()
@export var banner_beats: PackedFloat32Array = PackedFloat32Array()
@export var slow_mo_scale: PackedFloat32Array = PackedFloat32Array()
@export var slow_mo_sec: PackedFloat32Array = PackedFloat32Array()
@export var camera_shake: PackedFloat32Array = PackedFloat32Array()
@export var camera_zoom: PackedFloat32Array = PackedFloat32Array()
@export var beat_flash: PackedFloat32Array = PackedFloat32Array()

@export var enemy_ids: PackedStringArray = PackedStringArray()
@export var enemy_telegraph_sec: PackedFloat32Array = PackedFloat32Array()

@export_range(2.0, 3.0, 0.05) var banner_sec: float = 2.5
@export var showcase_phase_frames: int = 180000
@export var showcase_phase_wall_sec: float = 150.0
@export var showcase_progress_sec: float = 2.0


static func create_default():
	var cfg = load("res://config/game_feel_config.gd").new()
	cfg.action_ids = PackedStringArray(ACTIONS)
	cfg.telegraph_sec = PackedFloat32Array([0.18, 0.32, 0.28, 0.20, 0.35, 0.40, 0.22, 0.16])
	cfg.hit_stop_sec = PackedFloat32Array([0.05, 0.09, 0.07, 0.05, 0.08, 0.05, 0.06, 0.05])
	cfg.shake = PackedFloat32Array([0.22, 0.70, 0.40, 0.18, 0.48, 0.12, 0.28, 0.16])
	cfg.flash = PackedFloat32Array([0.15, 0.55, 0.65, 0.25, 0.40, 0.10, 0.35, 0.30])
	cfg.linger_sec = PackedFloat32Array([0.55, 0.90, 1.10, 0.80, 0.70, 0.60, 0.50, 0.85])
	cfg.recovery_sec = PackedFloat32Array([0.12, 0.28, 0.22, 0.16, 0.24, 0.20, 0.14, 0.12])
	cfg.beat_ids = PackedStringArray(BEATS)
	cfg.banner_beats = PackedFloat32Array([2.4, 2.6, 2.2, 2.8, 2.5, 2.2, 3.0, 3.0])
	cfg.slow_mo_scale = PackedFloat32Array([0.55, 0.60, 0.70, 0.50, 0.75, 0.45, 0.40, 0.35])
	cfg.slow_mo_sec = PackedFloat32Array([0.35, 0.40, 0.25, 0.45, 0.30, 0.30, 0.55, 0.70])
	cfg.camera_shake = PackedFloat32Array([0.20, 0.24, 0.16, 0.30, 0.14, 0.45, 0.80, 0.55])
	cfg.camera_zoom = PackedFloat32Array([1.0, 1.2, 0.6, 1.4, 2.0, 0.8, 1.6, 2.2])
	cfg.beat_flash = PackedFloat32Array([0.25, 0.30, 0.20, 0.40, 0.15, 0.55, 0.70, 0.45])
	cfg.enemy_ids = PackedStringArray(ENEMIES)
	cfg.enemy_telegraph_sec = PackedFloat32Array([0.45, 0.85, 0.60])
	cfg.banner_sec = 2.5
	cfg.showcase_phase_frames = 180000
	cfg.showcase_phase_wall_sec = 150.0
	cfg.showcase_progress_sec = 2.0
	return cfg


func action(id: String) -> Dictionary:
	var index := action_ids.find(id)
	if index < 0:
		return {}
	if not _aligned(index, [telegraph_sec, hit_stop_sec, shake, flash, linger_sec, recovery_sec]):
		return {}
	return {
		"id": id,
		"telegraph_sec": telegraph_sec[index],
		"hit_stop_sec": hit_stop_sec[index],
		"shake": shake[index],
		"flash": flash[index],
		"linger_sec": linger_sec[index],
		"recovery_sec": recovery_sec[index],
	}


func beat(id: String) -> Dictionary:
	var index := beat_ids.find(id)
	if index < 0:
		return {}
	if not _aligned(index, [banner_beats, slow_mo_scale, slow_mo_sec, camera_shake, camera_zoom, beat_flash]):
		return {}
	return {
		"id": id,
		"banner_sec": banner_beats[index],
		"slow_mo_scale": slow_mo_scale[index],
		"slow_mo_sec": slow_mo_sec[index],
		"camera_shake": camera_shake[index],
		"camera_zoom": camera_zoom[index],
		"flash": beat_flash[index],
	}


func enemy(id: String) -> Dictionary:
	var index := enemy_ids.find(id)
	if index < 0:
		return {}
	if index >= enemy_telegraph_sec.size():
		return {}
	return {
		"id": id,
		"telegraph_sec": enemy_telegraph_sec[index],
	}


func _aligned(index: int, rows: Array) -> bool:
	for row in rows:
		if index >= (row as PackedFloat32Array).size():
			return false
	return true
