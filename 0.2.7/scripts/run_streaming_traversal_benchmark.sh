#!/usr/bin/env bash
# Canonical churn-gated streaming traversal benchmark — medium×2 + low×2.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-10619a925a26/implementer}"
mkdir -p "$SCRATCH"
export CRYSTALSTORM_SCRATCH="$SCRATCH"
export CRYSTALSTORM_CHUNK_PROFILE=1
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1
export CRYSTALSTORM_STREAM_AFTER=1
LOG="$SCRATCH/streaming_traversal_benchmark_run.log"
: >"$LOG"

_run() {
  local preset="$1"
  local run="$2"
  echo "=== benchmark preset=$preset run=$run ===" | tee -a "$LOG"
  export CRYSTALSTORM_PERF_PRESET="$preset"
  export BENCHMARK_RUN="$run"
  godot --headless --path "$ROOT" -s scripts/streaming_traversal_benchmark.gd 2>&1 \
    | tee "$SCRATCH/streaming_traversal_benchmark_${preset}_run${run}.log" \
    | tee -a "$LOG" || {
    if grep -q "streaming traversal benchmark OK" "$SCRATCH/streaming_traversal_benchmark_${preset}_run${run}.log" \
       && grep -q "CHURN_GATE=PASS" "$SCRATCH/streaming_traversal_benchmark_${preset}_run${run}.log"; then
      echo "WARN: non-zero exit after churn PASS" | tee -a "$LOG"
    else
      return 1
    fi
  }
}

_run medium 1
_run medium 2
_run low 1
_run low 2
echo "DONE benchmark artifacts in $SCRATCH"