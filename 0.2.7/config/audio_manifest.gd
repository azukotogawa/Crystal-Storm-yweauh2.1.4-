class_name AudioManifest
extends RefCounted
## Id -> res:// path. Files are not shipped. AudioManager skips a missing file.

const _SFX := "res://assets/audio/sfx/"
const _UI := "res://assets/audio/ui/"
const _MUSIC := "res://assets/audio/music/"


static func get_entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})


static func path_of(id: String) -> String:
	var entry: Dictionary = get_entry(id)
	return str(entry.get("path", ""))


static func bus_of(id: String) -> String:
	var entry: Dictionary = get_entry(id)
	var bus := str(entry.get("bus", "SFX"))
	return bus if bus != "" else "SFX"


static func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for key in ENTRIES.keys():
		out.append(str(key))
	return out


const ENTRIES := {
	"swing_sword": {
		"path": _SFX + "swing_sword.ogg",
		"bus": "SFX",
		"event": "Player swings the wooden sword",
		"length": "0.12s",
		"character": "Short dry whoosh, light wood",
	},
	"swing_spear": {
		"path": _SFX + "swing_spear.ogg",
		"bus": "SFX",
		"event": "Player thrusts the spear",
		"length": "0.14s",
		"character": "Tight forward stab, little air",
	},
	"swing_hammer": {
		"path": _SFX + "swing_hammer.ogg",
		"bus": "SFX",
		"event": "Player slams the crystal hammer",
		"length": "0.28s",
		"character": "Heavy overhead whoosh into a low thud",
	},
	"swing_pick": {
		"path": _SFX + "swing_pick.ogg",
		"bus": "SFX",
		"event": "Player swings the stone pick",
		"length": "0.10s",
		"character": "Small metallic tick and grit",
	},
	"hit_light": {
		"path": _SFX + "hit_light.ogg",
		"bus": "SFX",
		"event": "A light or normal hit lands",
		"length": "0.08s",
		"character": "Soft crack, not a boom",
	},
	"hit_heavy": {
		"path": _SFX + "hit_heavy.ogg",
		"bus": "SFX",
		"event": "Hammer, bomb, or other heavy hit",
		"length": "0.20s",
		"character": "Thick impact with a short ring",
	},
	"fire_bow": {
		"path": _SFX + "fire_bow.ogg",
		"bus": "SFX",
		"event": "Shortbow fires an arrow",
		"length": "0.16s",
		"character": "String snap and a thin whistle",
	},
	"fire_sling": {
		"path": _SFX + "fire_sling.ogg",
		"bus": "SFX",
		"event": "Sling looses a stone",
		"length": "0.12s",
		"character": "Leather snap, low and short",
	},
	"impact_arrow": {
		"path": _SFX + "impact_arrow.ogg",
		"bus": "SFX",
		"event": "Arrow hits a body, crystal, or ground",
		"length": "0.10s",
		"character": "Thunk, muffled",
	},
	"impact_stone": {
		"path": _SFX + "impact_stone.ogg",
		"bus": "SFX",
		"event": "Sling stone hits",
		"length": "0.08s",
		"character": "Pebble clack",
	},
	"bomb_throw": {
		"path": _SFX + "bomb_throw.ogg",
		"bus": "SFX",
		"event": "Crystal bomb leaves the hand",
		"length": "0.14s",
		"character": "Soft toss and a crystal clink",
	},
	"bomb_explode": {
		"path": _SFX + "bomb_explode.ogg",
		"bus": "SFX",
		"event": "Crystal bomb detonates",
		"length": "0.45s",
		"character": "Bright crystal crack, then a low blast",
	},
	"dig": {
		"path": _SFX + "dig.ogg",
		"bus": "SFX",
		"event": "Pick removes a terrain layer",
		"length": "0.10s",
		"character": "Dry dirt scoop",
	},
	"build_place": {
		"path": _SFX + "build_place.ogg",
		"bus": "SFX",
		"event": "Wall, gate, bridge, or fill is placed",
		"length": "0.12s",
		"character": "Stone set down, solid",
	},
	"build_remove": {
		"path": _SFX + "build_remove.ogg",
		"bus": "SFX",
		"event": "A placed structure layer is removed",
		"length": "0.10s",
		"character": "Block lift and grit",
	},
	"crystal_crackle": {
		"path": _SFX + "crystal_crackle.ogg",
		"bus": "SFX",
		"event": "Crystal mass takes damage and stays",
		"length": "0.12s",
		"character": "Glass tickle, quiet",
	},
	"crystal_shatter": {
		"path": _SFX + "crystal_shatter.ogg",
		"bus": "SFX",
		"event": "A crystal cell breaks",
		"length": "0.28s",
		"character": "Shard burst, bright and short",
	},
	"spawn_destroyed": {
		"path": _SFX + "spawn_destroyed.ogg",
		"bus": "SFX",
		"event": "A crystal spawn heart is destroyed",
		"length": "0.70s",
		"character": "Large crystalline collapse",
	},
	"enemy_hurt": {
		"path": _SFX + "enemy_hurt.ogg",
		"bus": "SFX",
		"event": "An enemy or creature takes a non-lethal hit",
		"length": "0.10s",
		"character": "Soft organic hit",
	},
	"enemy_death": {
		"path": _SFX + "enemy_death.ogg",
		"bus": "SFX",
		"event": "An enemy or creature dies",
		"length": "0.35s",
		"character": "Drop and a short dissolve hiss",
	},
	"boss_telegraph": {
		"path": _SFX + "boss_telegraph.ogg",
		"bus": "SFX",
		"event": "Warden or tyrant starts a windup",
		"length": "0.40s",
		"character": "Rising crystal tone, warns the slam",
	},
	"boss_slam": {
		"path": _SFX + "boss_slam.ogg",
		"bus": "SFX",
		"event": "Boss slam, charge, or burst lands",
		"length": "0.35s",
		"character": "Ground hit, heavier than the hammer",
	},
	"boss_phase": {
		"path": _SFX + "boss_phase.ogg",
		"bus": "SFX",
		"event": "Origin Warden enters phase 2",
		"length": "0.80s",
		"character": "Chord shift, ominous, not a sting",
	},
	"boss_death": {
		"path": _SFX + "boss_death.ogg",
		"bus": "SFX",
		"event": "Origin Warden dies",
		"length": "1.20s",
		"character": "Large crystal break, then quiet",
	},
	"player_hurt": {
		"path": _SFX + "player_hurt.ogg",
		"bus": "SFX",
		"event": "Player takes a burst hit",
		"length": "0.16s",
		"character": "Close thud, no voice line",
	},
	"player_death": {
		"path": _SFX + "player_death.ogg",
		"bus": "SFX",
		"event": "Player dies",
		"length": "0.80s",
		"character": "Low falloff, ends the run",
	},
	"pickup": {
		"path": _SFX + "pickup.ogg",
		"bus": "SFX",
		"event": "Loot, herb use, or similar gain",
		"length": "0.10s",
		"character": "Small bright blip",
	},
	"water_splash": {
		"path": _SFX + "water_splash.ogg",
		"bus": "SFX",
		"event": "Player enters or leaves water, or a shot lands in it",
		"length": "0.22s",
		"character": "Light splash, not a wave",
	},
	"corruption_spread": {
		"path": _SFX + "corruption_spread.ogg",
		"bus": "SFX",
		"event": "A tile corrupts (rate-limited)",
		"length": "0.30s",
		"character": "Quiet crystal whisper",
	},
	"relic_open": {
		"path": _UI + "relic_open.ogg",
		"bus": "UI",
		"event": "Relic choice modal opens",
		"length": "0.35s",
		"character": "Soft chime, modal",
	},
	"relic_pick": {
		"path": _UI + "relic_pick.ogg",
		"bus": "UI",
		"event": "Player picks a relic",
		"length": "0.28s",
		"character": "Confirm chime, warmer than click",
	},
	"ui_click": {
		"path": _UI + "ui_click.ogg",
		"bus": "UI",
		"event": "Button press",
		"length": "0.05s",
		"character": "Dry click",
	},
	"ui_hover": {
		"path": _UI + "ui_hover.ogg",
		"bus": "UI",
		"event": "Pointer enters a button",
		"length": "0.04s",
		"character": "Very quiet tick",
	},
	"ui_open": {
		"path": _UI + "ui_open.ogg",
		"bus": "UI",
		"event": "Pause, inventory, or a menu screen opens",
		"length": "0.12s",
		"character": "Soft open",
	},
	"ui_close": {
		"path": _UI + "ui_close.ogg",
		"bus": "UI",
		"event": "Pause, inventory, or relic modal closes",
		"length": "0.10s",
		"character": "Soft close",
	},
	"run_win": {
		"path": _SFX + "run_win.ogg",
		"bus": "SFX",
		"event": "Run is won",
		"length": "1.40s",
		"character": "Short triumph, crystal and horn",
	},
	"run_lose": {
		"path": _SFX + "run_lose.ogg",
		"bus": "SFX",
		"event": "Run is lost",
		"length": "1.20s",
		"character": "Low descending tone",
	},
	"music_maze": {
		"path": _MUSIC + "music_maze.ogg",
		"bus": "Music",
		"event": "Maze phase loop",
		"length": "60–90s loop",
		"character": "Sparse, building, low pulse",
	},
	"music_assault": {
		"path": _MUSIC + "music_assault.ogg",
		"bus": "Music",
		"event": "Assault phase loop",
		"length": "45–75s loop",
		"character": "Tighter rhythm, same palette as the maze bed",
	},
}
