extends Node
## Centralized per-frame work budget owner (Performance Phase 3).
## Systems enqueue/drain unit work; this node records budget consumption for PerfProfiler.
## Determinism: queues are FIFO; each system processes a fixed max unit count per frame
## (soft wall-clock only stops after min_units to prevent starvation without reordering).

const SYS_CRYSTAL_DISPATCH := &"crystal_dispatch"
const SYS_LIVING_WORLD := &"living_world"
const SYS_TOWN_DEFENSE := &"town_defense"
const SYS_CHUNK_APPLY := &"chunk_apply"
const SYS_CHUNK_UPLOAD := &"chunk_upload"
const SYS_ENTITY_SPAWN := &"entity_spawn"
const SYS_FEATURE_VISUAL := &"feature_visual"
const SYS_WORLD_REBUILD := &"world_rebuild"
const SYS_HUD := &"hud_rebuild"

## Lower priority number runs earlier when draining registered systems.
const DEFAULT_PRIORITY := {
	SYS_CRYSTAL_DISPATCH: 10,
	SYS_CHUNK_APPLY: 20,
	SYS_CHUNK_UPLOAD: 25,
	SYS_TOWN_DEFENSE: 40,
	SYS_LIVING_WORLD: 50,
	SYS_ENTITY_SPAWN: 60,
	SYS_FEATURE_VISUAL: 65,
	SYS_WORLD_REBUILD: 70,
	SYS_HUD: 90,
}

## Soft wall-clock budget (microseconds) per system per frame.
const DEFAULT_BUDGET_US := {
	SYS_CRYSTAL_DISPATCH: 2000,
	SYS_CHUNK_APPLY: 2500,
	SYS_CHUNK_UPLOAD: 2500,
	SYS_TOWN_DEFENSE: 1500,
	SYS_LIVING_WORLD: 1200,
	SYS_ENTITY_SPAWN: 1000,
	## One chunk of billboards per frame — populate can be multi-ms for dense veg.
	SYS_FEATURE_VISUAL: 2000,
	SYS_WORLD_REBUILD: 1500,
	SYS_HUD: 800,
}

## Hard unit caps (work items) per frame — primary determinism control.
const DEFAULT_MAX_UNITS := {
	## Absorption completes can cost tens of ms each (WorldState + chunk rebuild).
	## Cap units so a backlog of ABSORPTION_READY cannot monopolize a frame.
	SYS_CRYSTAL_DISPATCH: 8,
	## One apply/upload unit per frame: avoids stacking two multi-ms ChunkView.setup
	## costs into a single hitch while stream still progresses every frame (min_units=1).
	SYS_CHUNK_APPLY: 1,
	SYS_CHUNK_UPLOAD: 1,
	SYS_TOWN_DEFENSE: 2,
	SYS_LIVING_WORLD: 8,
	SYS_ENTITY_SPAWN: 2,
	SYS_FEATURE_VISUAL: 1,
	SYS_WORLD_REBUILD: 4,
	SYS_HUD: 1,
}

## Guaranteed progress even if soft budget is already spent.
const DEFAULT_MIN_UNITS := {
	## Was 8: forced eight absorption rebuilds even when soft wall was long exceeded.
	SYS_CRYSTAL_DISPATCH: 1,
	SYS_CHUNK_APPLY: 1,
	SYS_CHUNK_UPLOAD: 1,
	SYS_TOWN_DEFENSE: 1,
	SYS_LIVING_WORLD: 2,
	SYS_ENTITY_SPAWN: 0,
	SYS_FEATURE_VISUAL: 1,
	SYS_WORLD_REBUILD: 1,
	SYS_HUD: 0,
}


var _systems: Dictionary = {}  # id -> config dict
var _frame_id: int = 0
var _frame_started_us: int = 0
## Per-frame stats for profiler (reset each begin_frame).
var _consumed_us: Dictionary = {}
var _units_done: Dictionary = {}
var _deferred_units: Dictionary = {}  # queue depth reported by systems
var _oldest_age_frames: Dictionary = {}
var _latency_sum_us: Dictionary = {}
var _latency_count: Dictionary = {}
var _latency_max_us: Dictionary = {}
var _emergency_flushes: Dictionary = {}


func _enter_tree() -> void:
	add_to_group("frame_budget_scheduler")
	process_priority = -50000  # early: open the frame accounting window
	set_process(true)
	_register_defaults()


func _register_defaults() -> void:
	for id in DEFAULT_BUDGET_US.keys():
		register_system(
			id,
			int(DEFAULT_BUDGET_US[id]),
			int(DEFAULT_MAX_UNITS.get(id, 4)),
			int(DEFAULT_MIN_UNITS.get(id, 1)),
			int(DEFAULT_PRIORITY.get(id, 100))
		)


func register_system(
	id: StringName,
	budget_us: int,
	max_units: int,
	min_units: int = 1,
	priority: int = 100
) -> void:
	_systems[id] = {
		"budget_us": maxi(budget_us, 100),
		"max_units": maxi(max_units, 0),
		"min_units": maxi(min_units, 0),
		"priority": priority,
	}
	if not _consumed_us.has(id):
		_consumed_us[id] = 0
		_units_done[id] = 0
		_deferred_units[id] = 0
		_oldest_age_frames[id] = 0
		_latency_sum_us[id] = 0
		_latency_count[id] = 0
		_latency_max_us[id] = 0
		_emergency_flushes[id] = 0


func _process(_delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("frame_budget")
	begin_frame()
	if profiler and profiler.has_method("end"):
		profiler.end("frame_budget")


func begin_frame() -> void:
	_frame_id += 1
	_frame_started_us = Time.get_ticks_usec()
	for id in _systems.keys():
		_consumed_us[id] = 0
		_units_done[id] = 0
	_publish_profiler_gauges()


## Token used by systems while draining work under budget.
func open_token(system_id: StringName) -> RefCounted:
	if not _systems.has(system_id):
		register_system(system_id, 1500, 4, 1, 100)
	return _BudgetToken.new(self, system_id)


## Run a drain callback with a budget token. Callback signature: (token) -> void
func run_budgeted(system_id: StringName, drain: Callable) -> Dictionary:
	var token: RefCounted = open_token(system_id)
	var t0 := Time.get_ticks_usec()
	if drain.is_valid():
		drain.call(token)
	var elapsed := Time.get_ticks_usec() - t0
	_consumed_us[system_id] = int(_consumed_us.get(system_id, 0)) + elapsed
	return {
		"system": system_id,
		"units": int(_units_done.get(system_id, 0)),
		"consumed_us": int(_consumed_us.get(system_id, 0)),
		"budget_us": int(_systems[system_id].budget_us),
		"remaining_us": maxi(int(_systems[system_id].budget_us) - int(_consumed_us.get(system_id, 0)), 0),
	}


func report_queue_depth(system_id: StringName, depth: int, oldest_age_frames: int = 0) -> void:
	_deferred_units[system_id] = maxi(depth, 0)
	_oldest_age_frames[system_id] = maxi(oldest_age_frames, 0)


func report_item_latency(system_id: StringName, wait_us: int) -> void:
	if wait_us <= 0:
		return
	_latency_sum_us[system_id] = int(_latency_sum_us.get(system_id, 0)) + wait_us
	_latency_count[system_id] = int(_latency_count.get(system_id, 0)) + 1
	_latency_max_us[system_id] = maxi(int(_latency_max_us.get(system_id, 0)), wait_us)


func note_emergency_flush(system_id: StringName) -> void:
	_emergency_flushes[system_id] = int(_emergency_flushes.get(system_id, 0)) + 1


func get_budget_us(system_id: StringName) -> int:
	return int(_systems.get(system_id, {}).get("budget_us", 0))


func get_max_units(system_id: StringName) -> int:
	return int(_systems.get(system_id, {}).get("max_units", 0))


func get_min_units(system_id: StringName) -> int:
	return int(_systems.get(system_id, {}).get("min_units", 0))


func get_frame_id() -> int:
	return _frame_id


func get_system_stats(system_id: StringName) -> Dictionary:
	var cfg: Dictionary = _systems.get(system_id, {})
	var budget := int(cfg.get("budget_us", 0))
	var consumed := int(_consumed_us.get(system_id, 0))
	var lat_n := int(_latency_count.get(system_id, 0))
	var lat_avg := 0.0
	if lat_n > 0:
		lat_avg = float(_latency_sum_us.get(system_id, 0)) / float(lat_n) / 1000.0
	return {
		"budget_us": budget,
		"budget_ms": float(budget) / 1000.0,
		"consumed_us": consumed,
		"consumed_ms": float(consumed) / 1000.0,
		"remaining_us": maxi(budget - consumed, 0),
		"remaining_ms": float(maxi(budget - consumed, 0)) / 1000.0,
		"units_done": int(_units_done.get(system_id, 0)),
		"max_units": int(cfg.get("max_units", 0)),
		"min_units": int(cfg.get("min_units", 0)),
		"queue_depth": int(_deferred_units.get(system_id, 0)),
		"oldest_age_frames": int(_oldest_age_frames.get(system_id, 0)),
		"avg_latency_ms": lat_avg,
		"max_latency_ms": float(_latency_max_us.get(system_id, 0)) / 1000.0,
		"emergency_flushes": int(_emergency_flushes.get(system_id, 0)),
		"priority": int(cfg.get("priority", 100)),
		"over_budget": consumed > budget,
	}


func get_all_stats() -> Dictionary:
	var out := {}
	var worst_q := &""
	var worst_depth := -1
	for id in _systems.keys():
		var st: Dictionary = get_system_stats(id)
		out[str(id)] = st
		var d: int = int(st.get("queue_depth", 0))
		if d > worst_depth:
			worst_depth = d
			worst_q = id
	return {
		"frame_id": _frame_id,
		"systems": out,
		"worst_queue": str(worst_q),
		"worst_queue_depth": worst_depth,
	}


func _publish_profiler_gauges() -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler == null or not profiler.has_method("set_gauge"):
		return
	var all: Dictionary = get_all_stats()
	profiler.set_gauge("budget_worst_queue_depth", float(all.get("worst_queue_depth", 0)))
	var systems: Dictionary = all.get("systems", {})
	for id_s in systems.keys():
		var st: Dictionary = systems[id_s]
		profiler.set_gauge("budget_%s_ms" % id_s, float(st.get("consumed_ms", 0.0)))
		profiler.set_gauge("budget_%s_queue" % id_s, float(st.get("queue_depth", 0)))
		profiler.set_gauge("budget_%s_remain_ms" % id_s, float(st.get("remaining_ms", 0.0)))


func format_budget_report() -> String:
	var all: Dictionary = get_all_stats()
	var lines: PackedStringArray = PackedStringArray()
	lines.append("FRAME BUDGETS (frame_id=%d)" % int(all.get("frame_id", 0)))
	lines.append("Worst queue: %s depth=%d" % [str(all.get("worst_queue", "")), int(all.get("worst_queue_depth", 0))])
	var systems: Dictionary = all.get("systems", {})
	var keys: Array = systems.keys()
	keys.sort()
	for id_s in keys:
		var st: Dictionary = systems[id_s]
		var flag := " OVER" if bool(st.get("over_budget", false)) else ""
		lines.append(
			"%s  budget %.2fms  used %.2fms  rem %.2fms  units %d/%d  q=%d age=%d lat_avg %.2f lat_max %.2f%s"
			% [
				id_s,
				float(st.get("budget_ms", 0.0)),
				float(st.get("consumed_ms", 0.0)),
				float(st.get("remaining_ms", 0.0)),
				int(st.get("units_done", 0)),
				int(st.get("max_units", 0)),
				int(st.get("queue_depth", 0)),
				int(st.get("oldest_age_frames", 0)),
				float(st.get("avg_latency_ms", 0.0)),
				float(st.get("max_latency_ms", 0.0)),
				flag,
			]
		)
	return "\n".join(lines)


## Internal: used by BudgetToken
func _token_can_continue(system_id: StringName, units_spent: int, started_us: int) -> bool:
	var cfg: Dictionary = _systems.get(system_id, {})
	var max_u: int = int(cfg.get("max_units", 0))
	var min_u: int = int(cfg.get("min_units", 0))
	if max_u > 0 and units_spent >= max_u:
		return false
	var budget: int = int(cfg.get("budget_us", 0))
	var elapsed: int = Time.get_ticks_usec() - started_us
	# Always allow min_units even if soft budget exceeded (starvation prevention).
	if units_spent < min_u:
		return true
	if budget > 0 and elapsed >= budget:
		return false
	return true


func _token_note_unit(system_id: StringName) -> void:
	_units_done[system_id] = int(_units_done.get(system_id, 0)) + 1


class _BudgetToken extends RefCounted:
	var _sched: Node
	var system_id: StringName
	var units_spent: int = 0
	var started_us: int = 0

	func _init(sched: Node, id: StringName) -> void:
		_sched = sched
		system_id = id
		started_us = Time.get_ticks_usec()

	func can_continue() -> bool:
		if _sched == null:
			return false
		return _sched._token_can_continue(system_id, units_spent, started_us)

	func spend_unit() -> void:
		units_spent += 1
		if _sched:
			_sched._token_note_unit(system_id)

	func remaining_units() -> int:
		if _sched == null:
			return 0
		var max_u: int = _sched.get_max_units(system_id)
		return maxi(max_u - units_spent, 0)

	func elapsed_us() -> int:
		return Time.get_ticks_usec() - started_us
