#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
ROOT="$REPO/0.2.8"
export PATH="/home/cwith/csmerge-bin:$PATH"; hash -r
export WSLENV="SMOKE_SESSION_SEC${WSLENV:+:$WSLENV}"
STATE=/tmp/cs-verify; mkdir -p "$STATE"
if [ "${1:-}" = quick ] && [ -z "${RUN_ID:-}" ]; then RUN_ID="quick-$(date +%Y%m%d-%H%M%S)"
else RUN_ID="${RUN_ID:-$(cat "$STATE/run_id" 2>/dev/null || date +%Y%m%d-%H%M%S)}"; echo "$RUN_ID" > "$STATE/run_id"; fi
EVID="/mnt/d/ARCHIVE/CrystalStorm/verify-evidence/$RUN_ID"
SCRATCH_W="/mnt/d/csmerge/verify-scratch/$RUN_ID"
export CRYSTALSTORM_SCRATCH="D:/csmerge/verify-scratch/$RUN_ID"
export CRYSTALSTORM_BAKE_RADIUS=2 CRYSTALSTORM_FULL_WORLD_BAKE=0 CRYSTALSTORM_BAKE_ON_NEW=0 CRYSTALSTORM_PERF_PRESET=medium
unset CRYSTALSTORM_PROBE_ABRUPT_EXIT
mkdir -p "$EVID" "$SCRATCH_W"

declare -A SUITE=( [full-map]=verify_full_map_toggle [water]=verify_water_body
  [save-continue]=verify_world_save_resume [dig]=verify_terrain_dig [frontend]=verify_world_frontend_flow )
declare -A MARK=( [full-map]="All full map toggle tests OK" [water]="All water body tests OK"
  [save-continue]="All world save resume tests OK" [dig]="All terrain dig tests OK" [frontend]="All world frontend flow tests OK" )
declare -A ABRUPT=( [frontend]=1 [save-continue]=1 [water]=1 )

run_godot(){ local name="$1"; shift
  { echo "\$ godot $*"; echo "# run_id=$RUN_ID start=$(date -Is)"; } > "$EVID/$name.log"
  godot "$@" >> "$EVID/$name.log" 2>&1 & local pid=$!
  echo "$pid" >> "$STATE/pids"; wait "$pid"; local rc=$?
  echo "# exit=$rc end=$(date -Is)" >> "$EVID/$name.log"; return $rc; }
bad(){ grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$1"; }

cmd="${1:-}"; shift || true
[ "$cmd" = quick ] && rmdir "$SCRATCH_W" 2>/dev/null
case "$cmd" in
doctor)
  ok=1
  [ "$(command -v godot)" = /home/cwith/csmerge-bin/godot ] && echo "OK godot wrapper" || { echo "FAIL godot wrapper missing"; ok=0; }
  v=$(godot --version 2>/dev/null | tr -d '\r' | tail -1); [[ "$v" == 4.7* ]] && echo "OK engine $v" || { echo "FAIL engine '$v'"; ok=0; }
  grep -q 'config/features=PackedStringArray("4.7"' "$ROOT/project.godot" && echo "OK project 4.7 at $ROOT" || { echo "FAIL project.godot"; ok=0; }
  echo "INFO branch $(git -C "$REPO" branch --show-current) head $(git -C "$REPO" rev-parse --short HEAD)"
  echo "INFO mem_available_mb $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)"
  n=$(pgrep -fc 'Godot|csmerge-bin/godot' 2>/dev/null || echo 0); echo "INFO godot_like_procs $n (only kill pids in $STATE/pids)"
  echo "INFO evidence $EVID"
  [ $ok = 1 ] && echo "DOCTOR OK" || { echo "DOCTOR FAILED"; exit 1; } ;;
quick)
  run_godot import --headless --path "$ROOT" --import; r=$?
  if [ $r -ne 0 ] || bad "$EVID/import.log"; then echo "QUICK FAIL import rc=$r"; tail -5 "$EVID/import.log"; exit 1; fi
  run_godot stability --headless --path "$ROOT" -s res://scripts/verify_stability_perf.gd; r=$?
  [ $r -eq 0 ] && grep -q 'All stability/perf tests OK' "$EVID/stability.log" || { echo "QUICK FAIL stability rc=$r"; tail -8 "$EVID/stability.log"; exit 1; }
  run_godot contracts --headless --path "$ROOT" -s res://scripts/verify_content_contracts.gd; r=$?
  [ $r -eq 0 ] && grep -q 'All content contract tests OK' "$EVID/contracts.log" || { echo "QUICK FAIL contracts rc=$r"; tail -8 "$EVID/contracts.log"; exit 1; }
  echo "QUICK OK (import, stability, contracts) evidence=$EVID" ;;
launch)
  sec="${1:-8}"
  ( cd "$ROOT" && SMOKE_SESSION_SEC="$sec" SMOKE_LOG="$EVID/smoke.log" bash scripts/run_smoke_gameplay.sh >/dev/null ) & p=$!
  echo "$p" >> "$STATE/pids"; wait $p; r=$?
  cp -f "$SCRATCH_W/scripted_smoke_evidence.md" "$EVID/" 2>/dev/null
  grep -E '^\- \*\*[A-Za-z ]+ (OK|FAIL)\*\*' "$EVID/scripted_smoke_evidence.md" 2>/dev/null
  if [ $r -eq 0 ]; then echo "LAUNCH OK (SMOKE GAMEPLAY OK)"; else echo "LAUNCH FAIL rc=$r"; grep -m3 -E 'FAIL' "$EVID/smoke.log"; exit 1; fi ;;
feature)
  f="${1:-}"; s="${SUITE[$f]:-}"; [ -n "$s" ] || { echo "unknown feature '$f' (${!SUITE[*]})"; exit 2; }
  if [ -n "${ABRUPT[$f]:-}" ]; then export CRYSTALSTORM_PROBE_ABRUPT_EXIT=1; fi
  run_godot "feature-$f" --headless --path "$ROOT" -s "res://scripts/$s.gd"; r=$?
  unset CRYSTALSTORM_PROBE_ABRUPT_EXIT
  grep -E '^(OK|FAIL)' "$EVID/feature-$f.log" | tr -d '\r'
  if grep -qF "${MARK[$f]}" "$EVID/feature-$f.log" && ! grep -q '^FAIL' "$EVID/feature-$f.log" && { [ $r -eq 0 ] || [ -n "${ABRUPT[$f]:-}" ]; }; then
    echo "FEATURE $f OK rc=$r marker='${MARK[$f]}'"; else echo "FEATURE $f FAIL rc=$r"; tail -8 "$EVID/feature-$f.log"; exit 1; fi ;;
cleanup)
  if [ -f "$STATE/pids" ]; then while read -r p; do kill -0 "$p" 2>/dev/null && { kill "$p"; echo "killed $p"; }; done < "$STATE/pids"; rm -f "$STATE/pids"; fi
  rm -rf "$SCRATCH_W"; rm -f "$STATE/run_id"
  echo "CLEANUP OK scratch removed; evidence kept at $EVID ($(ls "$EVID" | wc -l) files)" ;;
*) sed -n '2,8p' "$0"; exit 2 ;;
esac
