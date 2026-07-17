class_name MacroTerrainPerfGate
extends RefCounted
## Frozen perf contract for macro vs legacy median comparison (probe must not redefine).


const MEASUREMENT_NOISE_MS := 0.15
const MEASUREMENT_NOISE_RATIO := 0.005


static func noise_budget_ms(legacy_median_ms: float) -> float:
	return maxf(MEASUREMENT_NOISE_MS, legacy_median_ms * MEASUREMENT_NOISE_RATIO)


static func passes(legacy_median_ms: float, macro_median_ms: float) -> bool:
	return macro_median_ms <= legacy_median_ms + noise_budget_ms(legacy_median_ms)


static func evaluate(metric_name: String, legacy_median_ms: float, macro_median_ms: float) -> Dictionary:
	var noise_ms: float = noise_budget_ms(legacy_median_ms)
	var delta_ms: float = macro_median_ms - legacy_median_ms
	return {
		"name": metric_name,
		"legacy": legacy_median_ms,
		"macro": macro_median_ms,
		"noise_ms": noise_ms,
		"delta_ms": delta_ms,
		"ratio": macro_median_ms / maxf(legacy_median_ms, 0.001),
		"ok": passes(legacy_median_ms, macro_median_ms),
	}