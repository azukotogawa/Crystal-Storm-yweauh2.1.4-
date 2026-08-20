extends SceneTree
## Frame Budget Scheduler: registration, unit caps, crystal dispatch queue drain.
## Usage: godot --headless -s scripts/verify_frame_budget.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _CrystalSimEvents = preload("res://crystal/crystal_sim_events.gd")

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	var sched = root.get_node_or_null("/root/FrameBudgetScheduler")
	if sched == null:
		_fail("FrameBudgetScheduler autoload missing")
		_ProbeExit.finish_tree(self, 1, "Frame budget FAILED")
		return
	print("OK FrameBudgetScheduler present")

	# Structural budget table
	for id in [&"crystal_dispatch", &"living_world", &"town_defense", &"chunk_apply"]:
		var st: Dictionary = sched.get_system_stats(id)
		if int(st.get("budget_us", 0)) <= 0 or int(st.get("max_units", 0)) <= 0:
			_fail("system %s missing budget/max_units" % str(id))
		else:
			print("OK budget %s us=%d units=%d" % [str(id), int(st.budget_us), int(st.max_units)])

	# Unit cap: spend max then can_continue false
	var units := {"n": 0}
	sched.run_budgeted(&"crystal_dispatch", func(token):
		while token.can_continue():
			token.spend_unit()
			units.n = int(units.n) + 1
			if int(units.n) > 200:
				break
	)
	var max_u: int = int(sched.get_max_units(&"crystal_dispatch"))
	if int(units.n) != max_u:
		_fail("crystal_dispatch should process exactly max_units=%d got=%d" % [max_u, int(units.n)])
	else:
		print("OK unit cap enforced n=%d" % int(units.n))

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("main missing")
		_ProbeExit.finish_tree(self, 1, "Frame budget FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while compose and not bool(compose.get("_boot_done")) and frames < 2400:
		await process_frame
		frames += 1

	var crystal = get_first_node_in_group("crystal_manager")
	if crystal == null:
		_fail("crystal_manager missing")
	elif not crystal.has_method("get_dispatch_queue_depth"):
		_fail("crystal missing get_dispatch_queue_depth")
	else:
		# Flood deferred events and ensure one frame does not drain all if > max_units.
		var flood: Array = []
		for i in 200:
			flood.append(_CrystalSimEvents.depth_changed(Vector2i(i, 0)))
		if crystal.has_method("_dispatch_sim_events"):
			crystal._dispatch_sim_events(flood)
		var q0: int = int(crystal.get_dispatch_queue_depth())
		print("queue after flood=%d" % q0)
		if q0 < 100:
			_fail("expected deferred depth events queued (>=100) got %d" % q0)
		# Single process wave (crystal drains once per its _process).
		await process_frame
		var q1: int = int(crystal.get_dispatch_queue_depth())
		var drained: int = q0 - q1
		print("drained_one_wave=%d remaining=%d max_u=%d" % [drained, q1, max_u])
		# Allow +min_units slack only; hard unit cap is max_units.
		if drained > max_u:
			_fail("dispatch drained too many in one wave %d > max %d" % [drained, max_u])
		elif drained < 1 and q0 > 0:
			_fail("dispatch drained nothing with pending work")
		else:
			print("OK budgeted drain drained=%d remaining=%d" % [drained, q1])
		# Critical events still immediate
		var power_before: float = float(crystal.power)
		crystal._dispatch_sim_events([_CrystalSimEvents.power_delta(3.0)])
		if float(crystal.power) <= power_before:
			_fail("critical POWER_DELTA must apply immediately")
		else:
			print("OK critical power immediate %.1f→%.1f" % [power_before, float(crystal.power)])
		# Flush drains rest
		if crystal.has_method("flush_dispatch_queue"):
			crystal.flush_dispatch_queue()
		if int(crystal.get_dispatch_queue_depth()) != 0:
			_fail("flush_dispatch_queue left residual")
		else:
			print("OK emergency flush emptied queue")

	# Profiler surfaces budget report
	var profiler = root.get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("format_runtime_report"):
		var text: String = profiler.format_runtime_report()
		if "FRAME BUDGETS" not in text and "crystal_dispatch" not in text:
			# format includes budget only if scheduler present during format
			var br: String = sched.format_budget_report()
			if "crystal_dispatch" not in br:
				_fail("budget report missing crystal_dispatch")
			else:
				print("OK format_budget_report")
		else:
			print("OK profiler includes budget block")

	if _failed == 0:
		print("All frame budget tests OK")
		_ProbeExit.finish_tree(self, 0, "All frame budget tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Frame budget FAILED")
