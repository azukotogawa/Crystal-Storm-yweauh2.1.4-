#!/usr/bin/env bash
# Display-window corroboration → display_session_evidence.md (NOT manual_verification.md).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${DISPLAY_LOG:-/tmp/grok-goal-e8916ce4c6d5/implementer/display_session.log}"
timeout 90s env CRYSTALSTORM_PERF_PRESET=medium CRYSTALSTORM_PROBE_ABRUPT_EXIT=1 godot --path "$ROOT" -s "$ROOT/scripts/display_session_probe.gd" 2>&1 | tee "$LOG" || true
if grep -q "DISPLAY SESSION FAILED" "$LOG"; then
	exit 1
fi
if grep -q "DISPLAY SESSION OK" "$LOG"; then
	exit 0
fi
exit 1