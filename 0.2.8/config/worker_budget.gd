extends RefCounted

## Worker counts that follow the machine. One core is kept for the main
## thread. CRYSTALSTORM_WORKER_SCALE=0 returns the old fixed numbers.


static func enabled() -> bool:
	return OS.get_environment("CRYSTALSTORM_WORKER_SCALE").strip_edges() != "0"


static func cores() -> int:
	var raw := OS.get_environment("CRYSTALSTORM_CORES").strip_edges()
	if raw.is_valid_int() and int(raw) > 0:
		return int(raw)
	return maxi(OS.get_processor_count(), 1)


static func pool_workers(c: int) -> int:
	return maxi(c - 1, 1)


static func stream_inflight(preset: int, c: int) -> int:
	if not enabled():
		return preset
	return clampi(maxi(preset, (c - 1) / 2), 1, 8)


static func bake_jobs_inflight(c: int) -> int:
	if not enabled():
		return 2
	return clampi((c - 1) / 2, 2, 6)

