#!/usr/bin/env bash
# Display-window corroboration → display_session_evidence.md (NOT manual_verification.md).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH_RAW="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-4d59198f47c0/implementer}"
if [[ "$SCRATCH_RAW" == *.md || "$SCRATCH_RAW" == *.log ]]; then
	SCRATCH_DIR="$(dirname "$SCRATCH_RAW")"
else
	SCRATCH_DIR="$SCRATCH_RAW"
fi
mkdir -p "$SCRATCH_DIR"
LOG="${DISPLAY_LOG:-$SCRATCH_DIR/display_session.log}"
timeout 180s env CRYSTALSTORM_PERF_PRESET=medium CRYSTALSTORM_PROBE_ABRUPT_EXIT=1 CRYSTALSTORM_SCRATCH="$SCRATCH_DIR/display_session_evidence.md" godot --path "$ROOT" -s "$ROOT/scripts/display_session_probe.gd" 2>&1 | tee "$LOG" || true
if grep -q "DISPLAY SESSION FAILED" "$LOG"; then
	exit 1
fi
if grep -q "DISPLAY SESSION OK" "$LOG"; then
	exit 0
fi
exit 1