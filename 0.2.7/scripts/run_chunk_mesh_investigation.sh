#!/usr/bin/env bash
# Chunk mesh investigation — per-rebuild telemetry + ROI report (no optimizations).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CRYSTALSTORM_SCRATCH="${CRYSTALSTORM_SCRATCH:-/tmp/grok-goal-209a36c30e46/implementer}"
export CRYSTALSTORM_CHUNK_PROFILE=1
export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1
mkdir -p "$CRYSTALSTORM_SCRATCH"
LOG="$CRYSTALSTORM_SCRATCH/chunk_mesh_investigation_run.log"
: >"$LOG"
for run in 1 2; do
  echo "=== investigation run $run ===" | tee -a "$LOG"
  godot --headless --path "$ROOT" -s scripts/chunk_mesh_investigation.gd 2>&1 | tee -a "$LOG" || {
    if grep -q "Chunk mesh investigation OK" "$LOG" && \
       [[ -f "$CRYSTALSTORM_SCRATCH/chunk_rebuild_telemetry.jsonl" ]] && \
       [[ -f "$CRYSTALSTORM_SCRATCH/chunk_mesh_investigation_report.md" ]]; then
      echo "WARN: non-zero exit after artifacts written (known teardown)" | tee -a "$LOG"
    else
      exit 1
    fi
  }
done
echo "Telemetry: $CRYSTALSTORM_SCRATCH/chunk_rebuild_telemetry.jsonl"
echo "Report: $CRYSTALSTORM_SCRATCH/chunk_mesh_investigation_report.md"