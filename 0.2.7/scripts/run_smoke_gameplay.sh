#!/usr/bin/env bash
# Run smoke_gameplay; exit 0 when terminal marker is OK (tolerates Godot teardown abort 134).
# Optional: SMOKE_SESSION_SEC (default 30), SMOKE_LOG, SMOKE_FORCE_FAIL
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${SMOKE_LOG:-}"
ARGS=(--headless --path "$ROOT" -s "$ROOT/scripts/smoke_gameplay.gd")
export CRYSTALSTORM_PERF_PRESET=medium
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1
export SMOKE_SESSION_SEC="${SMOKE_SESSION_SEC:-30}"
if [[ -n "${SMOKE_FORCE_FAIL:-}" ]]; then
	export SMOKE_FORCE_FAIL
fi
if [[ -n "$LOG" ]]; then
	godot "${ARGS[@]}" 2>&1 | tee "$LOG" || true
	TEXT="$(cat "$LOG")"
else
	TEXT="$(godot "${ARGS[@]}" 2>&1 || true)"
	printf '%s\n' "$TEXT"
fi
if grep -q "SMOKE GAMEPLAY FAILED" <<<"$TEXT"; then
	exit 1
fi
if grep -q "SMOKE GAMEPLAY OK" <<<"$TEXT"; then
	exit 0
fi
exit 1