#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
ROOT="$REPO/0.2.8"
export PATH="/home/cwith/csmerge-bin:$PATH"; hash -r
export WSLENV="SMOKE_SESSION_SEC${WSLENV:+:$WSLENV}"
STATE=/tmp/cs-verify; mkdir -p "$STATE"
EVID_ROOT="${CS_VERIFY_EVID_ROOT:-/mnt/d/ARCHIVE/CrystalStorm/verify-evidence}"
FFMPEG_PORTABLE="/mnt/c/Users/cwith/pivot/ffmpeg/ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe"
RECORD=0
FFMPEG=""

record_fail() { echo "RECORD FAIL: $*" >&2; exit 1; }

find_ffmpeg() {
  if [ -n "${CS_VERIFY_FFMPEG:-}" ]; then
    [ -f "$CS_VERIFY_FFMPEG" ] && { echo "$CS_VERIFY_FFMPEG"; return 0; }
    return 1
  fi
  local c
  for c in "$FFMPEG_PORTABLE" \
    /mnt/c/Users/cwith/pivot/ffmpeg/bin/ffmpeg.exe \
    /mnt/c/Users/cwith/pivot/ffmpeg/ffmpeg.exe; do
    [ -f "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

cmd="${1:-}"; shift || true
if [ "$cmd" = record ]; then
  RECORD=1
  [ -d "$EVID_ROOT" ] || record_fail "evidence dir missing: D:\\ARCHIVE\\CrystalStorm\\verify-evidence\\ ($EVID_ROOT)"
  FFMPEG=$(find_ffmpeg) || record_fail "portable ffmpeg not found under C:\\Users\\cwith\\pivot\\ffmpeg\\ (expected ffmpeg-9.0.2-essentials_build\\bin\\ffmpeg.exe)"
  [ $# -ge 1 ] || record_fail "usage: record <mode...>  (example: record feature dig)"
  slug=$(printf '%s' "$*" | tr -s '[:space:]' '-' | tr -cd 'A-Za-z0-9._-')
  [ -n "$slug" ] || record_fail "empty mode"
  RUN_ID="$(date +%Y%m%d-%H%M%S)-$slug"
  echo "$RUN_ID" > "$STATE/run_id"
  cmd="${1:-}"; shift || true
elif [ "$cmd" = quick ] && [ -z "${RUN_ID:-}" ]; then
  RUN_ID="quick-$(date +%Y%m%d-%H%M%S)"
else
  RUN_ID="${RUN_ID:-$(cat "$STATE/run_id" 2>/dev/null || date +%Y%m%d-%H%M%S)}"; echo "$RUN_ID" > "$STATE/run_id"
fi
EVID="$EVID_ROOT/$RUN_ID"
SCRATCH_W="/mnt/d/csmerge/verify-scratch/$RUN_ID"
export CRYSTALSTORM_SCRATCH="D:/csmerge/verify-scratch/$RUN_ID"
export CRYSTALSTORM_BAKE_RADIUS=2 CRYSTALSTORM_FULL_WORLD_BAKE=0 CRYSTALSTORM_BAKE_ON_NEW=0 CRYSTALSTORM_PERF_PRESET=medium
unset CRYSTALSTORM_PROBE_ABRUPT_EXIT
mkdir -p "$EVID" "$SCRATCH_W"

win_path() { wslpath -w "$1" | tr '\\' '/'; }

movie_file_w() { win_path "$EVID/$1.avi"; }

wants_movie_frames() {
  local a
  for a in "$@"; do
    [ "$a" = --import ] && return 1
  done
  return 0
}

convert_movie() {
  local name="$1"
  local avi="$EVID/$name.avi"
  local wav="$EVID/$name.wav"
  local out="$EVID/$name.mp4"
  local log="$EVID/$name-ffmpeg.log"
  local out_win in_win seq_win wav_win
  out_win=$(win_path "$out")
  if [ -s "$avi" ]; then
    in_win=$(win_path "$avi")
    if ! "$FFMPEG" -y -i "$in_win" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$out_win" >"$log" 2>&1; then
      echo "RECORD FAIL: ffmpeg could not convert $name.avi (see $log)" >&2
      return 1
    fi
  else
    local pngs=()
    shopt -s nullglob
    pngs=("$EVID/${name}"*.png)
    shopt -u nullglob
    if [ ${#pngs[@]} -eq 0 ]; then
      echo "RECORD FAIL: no movie output for $name under $EVID" >&2
      return 1
    fi
    seq_win=$(win_path "$EVID/${name}%08d.png")
    local args=(-y -framerate 30 -start_number 0 -i "$seq_win")
    if [ -f "$wav" ]; then
      wav_win=$(win_path "$wav")
      args+=(-i "$wav_win" -c:a aac -shortest)
    fi
    args+=(-c:v libx264 -pix_fmt yuv420p -movflags +faststart "$out_win")
    if ! "$FFMPEG" "${args[@]}" >"$log" 2>&1; then
      echo "RECORD FAIL: ffmpeg could not convert $name png sequence (see $log)" >&2
      return 1
    fi
  fi
  echo "RECORD mp4=$out"
}

run_godot(){ local name="$1"; shift
  local extra=() args=("$@")
  if [ "$RECORD" = 1 ] && wants_movie_frames "$@"; then
    extra=(--write-movie "$(movie_file_w "$name")" --fixed-fps 30 --disable-vsync)
    args=()
    local a
    for a in "$@"; do
      [ "$a" = --headless ] && continue
      args+=("$a")
    done
  fi
  { echo "\$ godot ${extra[*]-} ${args[*]}"; echo "# run_id=$RUN_ID start=$(date -Is)"; } > "$EVID/$name.log"
  godot "${extra[@]}" "${args[@]}" >> "$EVID/$name.log" 2>&1 & local pid=$!
  echo "$pid" >> "$STATE/pids"; wait "$pid"; local rc=$?
  echo "# exit=$rc end=$(date -Is)" >> "$EVID/$name.log"; return $rc; }

finish_record() {
  local rc=$1
  [ "$RECORD" = 1 ] || return "$rc"
  local avi name
  local mp4s=()
  shopt -s nullglob
  for avi in "$EVID"/*.avi; do
    name=$(basename "$avi" .avi)
    [ -f "$EVID/$name.mp4" ] || convert_movie "$name" || rc=1
  done
  if [ "$rc" -eq 0 ]; then
    local png_base png
    for png in "$EVID"/*00000000.png; do
      png_base=$(basename "$png" 00000000.png)
      [ -f "$EVID/$png_base.mp4" ] || convert_movie "$png_base" || rc=1
    done
  fi
  mp4s=("$EVID"/*.mp4)
  shopt -u nullglob
  if [ ${#mp4s[@]} -eq 0 ]; then
    echo "RECORD FAIL: no mp4 written under $EVID"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    echo "RECORD FAIL rc=$rc evidence=$EVID"
    return "$rc"
  fi
  echo "RECORD OK evidence=$EVID"
  printf '%s\n' "${mp4s[@]}"
  return 0
}

record_trap() {
  local rc=$?
  trap - EXIT
  finish_record "$rc"
  exit $?
}

declare -A SUITE=( [full-map]=verify_full_map_toggle [water]=verify_water_body
  [save-continue]=verify_world_save_resume [dig]=verify_terrain_dig [frontend]=verify_world_frontend_flow )
declare -A MARK=( [full-map]="All full map toggle tests OK" [water]="All water body tests OK"
  [save-continue]="All world save resume tests OK" [dig]="All terrain dig tests OK" [frontend]="All world frontend flow tests OK" )
declare -A ABRUPT=( [frontend]=1 [save-continue]=1 [water]=1 )

bad(){ grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$1"; }

[ "$cmd" = quick ] && rmdir "$SCRATCH_W" 2>/dev/null
[ "$RECORD" = 1 ] && trap record_trap EXIT
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
  if [ "$RECORD" = 1 ]; then export CS_VERIFY_MOVIE_FILE="$(movie_file_w launch)"; fi
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
*) echo "usage: cs-verify.sh doctor|quick|launch [SEC]|feature <name>|cleanup|record <mode...>"; exit 2 ;;
esac
