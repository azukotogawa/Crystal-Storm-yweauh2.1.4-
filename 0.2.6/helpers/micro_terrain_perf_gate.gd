class_name MicroTerrainPerfGate
extends RefCounted
## Frozen perf contract for micro-on vs macro-only localized edit comparison.


const MEASUREMENT_NOISE_MS := 0.15
const MEASUREMENT_NOISE_RATIO := 0.005


static func noise_budget_ms(baseline_median_ms: float) -> float:
	return maxf(MEASUREMENT_NOISE_MS, baseline_median_ms * MEASUREMENT_NOISE_RATIO)


static func passes(baseline_median_ms: float, micro_median_ms: float) -> bool:
	return micro_median_ms <= baseline_median_ms + noise_budget_ms(baseline_median_ms)


static func evaluate(metric_name: String, baseline_median_ms: float, micro_median_ms: float) -> Dictionary:
	var noise_ms: float = noise_budget_ms(baseline_median_ms)
	var delta_ms: float = micro_median_ms - baseline_median_ms
	return {
		"name": metric_name,
		"baseline": baseline_median_ms,
		"micro": micro_median_ms,
		"noise_ms": noise_ms,
		"delta_ms": delta_ms,
		"ratio": micro_median_ms / maxf(baseline_median_ms, 0.001),
		"ok": passes(baseline_median_ms, micro_median_ms),
	}