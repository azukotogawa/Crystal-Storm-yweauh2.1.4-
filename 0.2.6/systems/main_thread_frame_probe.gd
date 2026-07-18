extends Node
## Early main-thread frame probe (measurement only).
##
## Named phase bookends (real begin/end call sites — objective: physics/process callbacks):
##   physics_callbacks — open at first physics_process; closed when process band starts
##   process_callbacks — open at first process; closed by late PerfProfiler close_process_envelope
##
## Nested systems (entity_physics, chunk_*, living_world, …) begin/end under these parents;
## parent exclusive is only inter-callback gaps (hierarchical exclusive, not residual rename).
##
## Frame work wall (gate denominator):
##   mark_frame_work_start at first physics/process
##   → finalize at end of process (after all node _process)
##
## Does not change gameplay, scheduling budgets, or work amount.

const SECTION_PHYSICS := "physics_callbacks"
const SECTION_PROCESS := "process_callbacks"

var _physics_open: bool = false
var _process_open: bool = false
var _idle_start_us: int = 0


func _enter_tree() -> void:
	add_to_group("main_thread_frame_probe")
	process_priority = -100000
	set_process(true)
	set_physics_process(true)


func _profiler():
	return get_node_or_null("/root/PerfProfiler")


func _close_inter_frame_gap_and_start_work() -> void:
	var p = _profiler()
	if _idle_start_us > 0:
		var gap: int = Time.get_ticks_usec() - _idle_start_us
		_idle_start_us = 0
		if p and p.enabled and gap > 0 and p.has_method("note_inter_frame_gap_us"):
			p.note_inter_frame_gap_us(gap)
	if p and p.enabled and p.has_method("mark_frame_work_start"):
		p.mark_frame_work_start()


func _physics_process(_delta: float) -> void:
	var p = _profiler()
	if p == null or not p.enabled:
		return
	_close_inter_frame_gap_and_start_work()
	if _process_open:
		return
	if not _physics_open:
		if p.has_method("begin"):
			p.begin(SECTION_PHYSICS)
		_physics_open = true


func _process(_delta: float) -> void:
	var p = _profiler()
	if p == null or not p.enabled:
		return
	_close_inter_frame_gap_and_start_work()
	if _physics_open:
		if p.has_method("end"):
			p.end(SECTION_PHYSICS)
		_physics_open = false
	if not _process_open:
		if p.has_method("begin"):
			p.begin(SECTION_PROCESS)
		_process_open = true


## Called by PerfProfiler (late, process_priority 100000) at end of process phase.
func close_process_envelope() -> void:
	var p = _profiler()
	if p == null or not p.enabled:
		_process_open = false
		_physics_open = false
		_idle_start_us = Time.get_ticks_usec()
		if p and p.has_method("finalize_frame"):
			p.finalize_frame()
		return
	if _physics_open:
		if p.has_method("end"):
			p.end(SECTION_PHYSICS)
		_physics_open = false
	if _process_open:
		if p.has_method("end"):
			p.end(SECTION_PROCESS)
		_process_open = false
	if p.has_method("finalize_frame"):
		p.finalize_frame()
	# Gap until next physics/process (engine post-process + MQ + wait). Not in wall.
	_idle_start_us = Time.get_ticks_usec()
