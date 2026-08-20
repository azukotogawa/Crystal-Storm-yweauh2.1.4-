#!/usr/bin/env bash
# LOW-preset movement traversal probe — run twice for variance (Epic 2 criterion 2).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-10619a925a26/implementer}"
mkdir -p "$SCRATCH"
export CRYSTALSTORM_SCRATCH="$SCRATCH"
export CRYSTALSTORM_PERF_PRESET=low
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1
LOG="$SCRATCH/streaming_low_traversal_run.log"
: >"$LOG"

for run in 1 2; do
  echo "=== low traversal run $run ===" | tee -a "$LOG"
  export LOW_PROBE_RUN="run${run}"
  godot --headless --path "$ROOT" -s scripts/streaming_low_traversal_probe.gd 2>&1 | tee "$SCRATCH/streaming_low_traversal_${run}.log" | tee -a "$LOG" || {
    if grep -q "streaming low traversal probe OK" "$SCRATCH/streaming_low_traversal_${run}.log"; then
      echo "WARN: non-zero exit after OK marker" | tee -a "$LOG"
    else
      exit 1
    fi
  }
done
echo "DONE low traversal summaries in $SCRATCH"