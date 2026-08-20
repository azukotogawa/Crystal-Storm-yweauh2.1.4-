#!/usr/bin/env bash
# Streaming lifecycle investigation — Phase 1 telemetry + stall timeline (no optimizations).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRATCH_DEFAULT="/tmp/grok-goal-10619a925a26/implementer"
export CRYSTALSTORM_SCRATCH="${CRYSTALSTORM_SCRATCH:-$SCRATCH_DEFAULT}"
export CRYSTALSTORM_CHUNK_PROFILE=1
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1
mkdir -p "$CRYSTALSTORM_SCRATCH"
LOG="$CRYSTALSTORM_SCRATCH/streaming_lifecycle_investigation_run.log"
: >"$LOG"
for run in 1 2; do
  echo "=== streaming investigation run $run ===" | tee -a "$LOG"
  godot --headless --path "$ROOT" -s scripts/streaming_lifecycle_investigation.gd 2>&1 | tee -a "$LOG" || {
    if grep -q "Streaming lifecycle investigation OK" "$LOG" && \
       [[ -f "$CRYSTALSTORM_SCRATCH/streaming_lifecycle_telemetry.jsonl" ]] && \
       [[ -f "$CRYSTALSTORM_SCRATCH/streaming_lifecycle_report.md" ]] && \
       [[ -f "$CRYSTALSTORM_SCRATCH/streaming_baseline_summary.md" ]]; then
      echo "WARN: non-zero exit after artifacts written (known teardown)" | tee -a "$LOG"
    else
      exit 1
    fi
  }
done
echo "Telemetry: $CRYSTALSTORM_SCRATCH/streaming_lifecycle_telemetry.jsonl"
echo "Report: $CRYSTALSTORM_SCRATCH/streaming_lifecycle_report.md"
echo "Baseline: $CRYSTALSTORM_SCRATCH/streaming_baseline_summary.md"