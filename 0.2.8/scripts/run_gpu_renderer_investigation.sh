#!/usr/bin/env bash
# GPU/renderer investigation — display session for screenshots + headless JSONL fallback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-d700decdc9e9/implementer}"
mkdir -p "$SCRATCH"
export CRYSTALSTORM_SCRATCH="$SCRATCH"
export CRYSTALSTORM_PERF_PRESET="${CRYSTALSTORM_PERF_PRESET:-medium}"
LOG="$SCRATCH/gpu_renderer_investigation_run.log"
: >"$LOG"

unset CRYSTALSTORM_GPU_PROBE_HEADLESS || true

echo "=== GPU probe WITH display (screenshots + F3 capture) ===" | tee -a "$LOG"
godot --path "$ROOT" -s scripts/gpu_renderer_investigation.gd 2>&1 \
  | tee "$SCRATCH/gpu_renderer_display.log" | tee -a "$LOG" || {
  if grep -q "gpu renderer investigation OK" "$SCRATCH/gpu_renderer_display.log"; then
    echo "WARN: non-zero exit after OK" | tee -a "$LOG"
  else
    exit 1
  fi
}
cp -f "$SCRATCH/gpu_renderer_before_after_report.md" "$SCRATCH/gpu_renderer_display_report.md" 2>/dev/null || true
cp -f "$SCRATCH/gpu_renderer_samples.jsonl" "$SCRATCH/gpu_renderer_display_samples.jsonl" 2>/dev/null || true

echo "=== GPU probe headless (counter validation) ===" | tee -a "$LOG"
export CRYSTALSTORM_GPU_PROBE_HEADLESS=1
godot --headless --path "$ROOT" -s scripts/gpu_renderer_investigation.gd 2>&1 \
  | tee "$SCRATCH/gpu_renderer_headless.log" | tee -a "$LOG" || {
  if grep -q "gpu renderer investigation OK" "$SCRATCH/gpu_renderer_headless.log"; then
    echo "WARN: headless non-zero exit after OK" | tee -a "$LOG"
  else
    exit 1
  fi
}
cp -f "$SCRATCH/gpu_renderer_before_after_report.md" "$SCRATCH/gpu_renderer_headless_report.md" 2>/dev/null || true
cp -f "$SCRATCH/gpu_renderer_display_report.md" "$SCRATCH/gpu_renderer_before_after_report.md" 2>/dev/null || true
cp -f "$SCRATCH/gpu_renderer_display_samples.jsonl" "$SCRATCH/gpu_renderer_samples.jsonl" 2>/dev/null || true

echo "DONE GPU artifacts in $SCRATCH"