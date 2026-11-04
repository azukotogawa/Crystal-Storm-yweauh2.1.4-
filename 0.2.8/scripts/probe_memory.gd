extends Node
## Item 12 memory probe (autoload next to ColdProbe via override.cfg).
## Prints MEM monitor lines every CS_MEM_EVERY s (default 2) and an owner census
## (MEMOWN lines) every CS_MEM_CENSUS_EVERY s (default 10). Census walks every
## chunk view, so use separate runs for frame timings.

const _Census = preload("res://scripts/mem_census.gd")

var _t := 0.0
var _tc := 0.0
var _n := 0
var _every := 2.0
var _census_every := 10.0


func _ready() -> void:
	var e := OS.get_environment("CS_MEM_EVERY")
	if e.is_valid_float():
		_every = float(e)
	var c := OS.get_environment("CS_MEM_CENSUS_EVERY")
	if c.is_valid_float():
		_census_every = float(c)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	_tc += delta
	if _t >= _every:
		_t = 0.0
		print(_Census.monitors_line("t_ms=%d" % Time.get_ticks_msec()))
	if _tc >= _census_every:
		_tc = 0.0
		_n += 1
		var t0 := Time.get_ticks_usec()
		var acc: Dictionary = _Census.new().census_tree(get_tree())
		for ln in _Census.table_lines("c%d" % _n, acc):
			print(ln)
		print("MEMOWN c%d census_ms=%.1f" % [_n, (Time.get_ticks_usec() - t0) / 1000.0])
