#!/usr/bin/env bash
# Post-optimization streaming profile — canonical traversal benchmark only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-10619a925a26/implementer}"
mkdir -p "$SCRATCH"
export CRYSTALSTORM_SCRATCH="$SCRATCH"
LOG="$SCRATCH/streaming_after_profile_run.log"
: >"$LOG"

bash "$ROOT/scripts/run_streaming_traversal_benchmark.sh" 2>&1 | tee -a "$LOG"

export CRYSTALSTORM_PERF_PRESET=medium
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1
godot --headless --path "$ROOT" -s scripts/profile_gameplay.gd 2>&1 \
  | tee "$SCRATCH/profile_gameplay_after_run.log" | tee -a "$LOG" || {
  if grep -q "PROFILE_REPORT_PATH=" "$SCRATCH/profile_gameplay_after_run.log"; then
    echo "WARN: profile_gameplay non-zero exit after report" | tee -a "$LOG"
  else
    exit 1
  fi
}

godot --headless --path "$ROOT" -s scripts/verify_chunk_incremental_patch.gd 2>&1 \
  | tee "$SCRATCH/verify_incremental_benchmark_gate.log" | tee -a "$LOG" || {
  if grep -q "All chunk incremental patch tests OK" "$SCRATCH/verify_incremental_benchmark_gate.log"; then
    echo "WARN: incremental verify abrupt exit" | tee -a "$LOG"
  else
    exit 1
  fi
}

echo "DONE streaming_after_profile in $SCRATCH"