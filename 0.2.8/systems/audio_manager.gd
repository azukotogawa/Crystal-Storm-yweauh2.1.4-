extends Node

const _Manifest = preload("res://config/audio_manifest.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _GameManager = preload("res://game/game_manager.gd")

const POOL_3D := 6
const POOL_2D := 3
const SFX_GAP_MSEC := 45

var _logged: Dictionary = {}
var _streams: Dictionary = {}
var _gap_until: Dictionary = {}
var _sfx3d: Array[AudioStreamPlayer3D] = []
var _sfx2d: Array[AudioStreamPlayer] = []
var _ui: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_state: String = ""
var _bound: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_players()
	apply_saved_volumes()
	# Keybinds, UI scale, and display once, before gameplay input. Later volume loads do not reapply them.
	_PlayerSettings.apply_runtime(get_tree())
	set_process(true)


func _process(_delta: float) -> void:
	if _bound:
		set_process(false)
		return
	_bind_game()
	if _bound:
		set_process(false)


func play_sfx(id: String, pos: Variant = null) -> void:
	var now := Time.get_ticks_msec()
	if int(_gap_until.get(id, 0)) > now:
		return
	var stream := _stream_for(id)
	if stream == null:
		return
	_gap_until[id] = now + SFX_GAP_MSEC
	var bus := _Manifest.bus_of(id)
	if pos is Vector3:
		var player := _take_3d()
		player.stream = stream
		player.bus = bus if _bus_ok(bus) else "Master"
		player.global_position = pos
		player.play()
		return
	var flat := _take_2d()
	flat.stream = stream
	flat.bus = bus if _bus_ok(bus) else "Master"
	flat.play()


func play_ui(id: String) -> void:
	var stream := _stream_for(id)
	if stream == null:
		return
	if _ui == null:
		return
	_ui.stream = stream
	var bus := _Manifest.bus_of(id)
	_ui.bus = bus if _bus_ok(bus) else "Master"
	_ui.play()


func play_music(id: String) -> void:
	var stream := _stream_for(id)
	if _music == null:
		return
	if stream == null:
		return
	if _music.stream == stream and _music.playing:
		return
	_music.stream = stream
	_music.bus = "Music" if _bus_ok("Music") else "Master"
	_music.play()


func set_music_state(state: String) -> void:
	if state == _music_state:
		return
	_music_state = state
	if state == "assault":
		play_music("music_assault")
	elif state == "maze":
		play_music("music_maze")


func music_state() -> String:
	return _music_state


func missing_log_count(id: String) -> int:
	return 1 if _logged.has(id) else 0


func set_bus_linear(bus: String, linear: float, persist: bool = true) -> void:
	var v := clampf(linear, 0.0, 1.0)
	_apply_linear(bus, v)
	_PlayerSettings.set_bus_volume(bus, v, persist)


func get_bus_linear(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func set_bus_db(bus: String, db: float, persist: bool = true) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, db)
	set_bus_linear(bus, db_to_linear(db), persist)


func get_bus_db(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(idx)


func apply_saved_volumes() -> void:
	var data := _PlayerSettings.load_settings()
	_apply_linear("Master", float(data.get("volume_master", 1.0)))
	_apply_linear("Music", float(data.get("volume_music", 1.0)))
	_apply_linear("SFX", float(data.get("volume_sfx", 1.0)))
	_apply_linear("UI", float(data.get("volume_ui", 1.0)))


func _apply_linear(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.0001 else -80.0)


func _stream_for(id: String) -> AudioStream:
	if _streams.has(id):
		var cached = _streams[id]
		return cached if cached is AudioStream else null
	var path := _Manifest.path_of(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		_log_missing(id)
		_streams[id] = null
		return null
	var res = load(path)
	if res is AudioStream:
		_streams[id] = res
		return res
	_log_missing(id)
	_streams[id] = null
	return null


func _log_missing(id: String) -> void:
	if _logged.has(id):
		return
	_logged[id] = true
	print("AudioManager: missing sound '%s' (skipped)" % id)


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		if AudioServer.get_bus_index("Master") >= 0:
			AudioServer.set_bus_send(idx, "Master")


func _build_players() -> void:
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx3D%d" % i
		p.bus = "SFX"
		p.max_distance = 36.0
		p.unit_size = 8.0
		add_child(p)
		_sfx3d.append(p)
	for i in POOL_2D:
		var p2 := AudioStreamPlayer.new()
		p2.name = "Sfx2D%d" % i
		p2.bus = "SFX"
		add_child(p2)
		_sfx2d.append(p2)
	_ui = AudioStreamPlayer.new()
	_ui.name = "Ui"
	_ui.bus = "UI"
	add_child(_ui)
	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.bus = "Music"
	add_child(_music)


func _take_3d() -> AudioStreamPlayer3D:
	for p in _sfx3d:
		if not p.playing:
			return p
	return _sfx3d[0]


func _take_2d() -> AudioStreamPlayer:
	for p in _sfx2d:
		if not p.playing:
			return p
	return _sfx2d[0]


func _bus_ok(bus: String) -> bool:
	return AudioServer.get_bus_index(bus) >= 0


func _bind_game() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager") if is_inside_tree() else null
	if gm == null:
		return
	if gm.has_signal("phase_changed") and not gm.phase_changed.is_connected(_on_phase):
		gm.phase_changed.connect(_on_phase)
	if gm.has_signal("run_state_changed") and not gm.run_state_changed.is_connected(_on_run_state):
		gm.run_state_changed.connect(_on_run_state)
	_bound = true
	if "phase" in gm:
		_on_phase(int(gm.phase))
	if "run_state" in gm:
		_on_run_state(int(gm.run_state))


func _on_phase(phase: int) -> void:
	if phase == int(_GameManager.Phase.ASSAULT):
		set_music_state("assault")
	elif phase == int(_GameManager.Phase.MAZE):
		set_music_state("maze")


func _on_run_state(state: int) -> void:
	if state == int(_GameManager.RunState.WON):
		play_sfx("run_win")
	elif state == int(_GameManager.RunState.LOST):
		play_sfx("run_lose")
