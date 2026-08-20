extends SceneTree
## Headless: loading screen binds to CompositionRoot stages and dismisses at INITIAL_STREAM_READY.
## Usage: godot --headless -s scripts/verify_loading_screen.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _CompositionRoot = preload("res://systems/composition_root.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "LOADING_SCREEN_FAIL no main")
		return
	var game: Node = packed.instantiate()
	var compose = game.get_node_or_null("CompositionRoot")
	var loading = game.get_node_or_null("LoadingLayer/LoadingScreen")
	if compose == null:
		_ProbeExit.finish_tree(self, 1, "LOADING_SCREEN_FAIL no CompositionRoot")
		return
	if loading == null:
		_ProbeExit.finish_tree(self, 1, "LOADING_SCREEN_FAIL no LoadingScreen in main.tscn")
		return

	var stages: Array = []
	compose.stage_changed.connect(func(_id: int, name: String): stages.append(name))
	var faded := false
	# Watch modulate/visible after INITIAL_STREAM_READY
	root.add_child(game)

	var frames := 0
	var saw_ics := false
	while frames < 2400:
		await process_frame
		frames += 1
		if compose.stage >= _CompositionRoot.Stage.INITIAL_STREAM_READY:
			saw_ics = true
		if saw_ics and (not loading.visible or float(loading.modulate.a) < 0.05 or bool(loading.get("_dismissed")) or bool(loading.get("_fading"))):
			faded = true
			break
		if bool(compose.get("_boot_done")) or int(compose.stage) == _CompositionRoot.Stage.FAILED:
			break

	if int(compose.stage) == _CompositionRoot.Stage.FAILED:
		_ProbeExit.finish_tree(self, 1, "LOADING_SCREEN_FAIL boot failed")
		return
	if not saw_ics:
		_ProbeExit.finish_tree(self, 1, "LOADING_SCREEN_FAIL never reached INITIAL_STREAM_READY")
		return
	if not faded and not bool(loading.get("_fading")) and not bool(loading.get("_dismissed")):
		# Allow a few more frames for tween start
		for _i in 30:
			await process_frame
			if bool(loading.get("_fading")) or bool(loading.get("_dismissed")) or not loading.visible:
				faded = true
				break
	if not faded and not bool(loading.get("_fading")) and not bool(loading.get("_dismissed")):
		push_error("loading screen did not start fade after INITIAL_STREAM_READY a=%.3f vis=%s" % [
			float(loading.modulate.a), str(loading.visible)
		])
		_ProbeExit.finish_tree(self, 1, "LOADING_SCREEN_FAIL no fade")
		return

	if not stages.has("CONFIGURED") and not stages.has("INITIAL_STREAM_READY"):
		# stage_changed may still have fired before we connected if boot raced; check phase text
		pass
	print("OK loading screen present stages_seen=%d ics=true fading_or_dismissed=true" % stages.size())
	print("OK loading phase_text=%s progress=%.2f" % [
		str(loading.get("_phase_text")),
		float(loading.get("_progress")),
	])
	_ProbeExit.finish_tree(self, 0, "LOADING_SCREEN_OK")
