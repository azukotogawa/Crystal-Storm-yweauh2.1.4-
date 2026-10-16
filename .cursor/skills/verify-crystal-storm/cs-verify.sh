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

export CRYSTALSTORM_RUN_ID="$RUN_ID"
export CRYSTALSTORM_EVIDENCE="$(win_path "$EVID")"

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

ffprobe_bin() {
  local d
  d=$(dirname "$FFMPEG")
  if [ -f "$d/ffprobe.exe" ]; then echo "$d/ffprobe.exe"; return 0; fi
  if [ -f "$d/ffprobe" ]; then echo "$d/ffprobe"; return 0; fi
  return 1
}

video_frame_count() {
  local in_win="$1" probe n
  probe=$(ffprobe_bin) || return 1
  n=$("$probe" -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$in_win" 2>/dev/null | tr -d '\r')
  case "$n" in
    ''|N/A|0)
      n=$("$probe" -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$in_win" 2>/dev/null | tr -d '\r')
      ;;
  esac
  case "$n" in
    ''|N/A|0) return 1 ;;
  esac
  echo "$n"
}

contact_layout() {
  local n=$1 cols rows cells
  if [ "$n" -ge 16 ]; then cols=4; rows=4; cells=16
  elif [ "$n" -ge 12 ]; then cols=4; rows=3; cells=12
  elif [ "$n" -ge 9 ]; then cols=3; rows=3; cells=9
  elif [ "$n" -ge 8 ]; then cols=4; rows=2; cells=8
  elif [ "$n" -ge 6 ]; then cols=3; rows=2; cells=6
  elif [ "$n" -ge 4 ]; then cols=2; rows=2; cells=4
  elif [ "$n" -ge 2 ]; then cols=$n; rows=1; cells=$n
  else cols=1; rows=1; cells=1
  fi
  echo "$cols $rows $cells"
}

samples_per_file() {
  local nfiles=$1 per target cols rows cells guard=0
  per=$((16 / nfiles))
  [ "$per" -lt 1 ] && per=1
  while [ "$guard" -lt 6 ]; do
    guard=$((guard + 1))
    target=$((per * nfiles))
    read -r cols rows cells < <(contact_layout "$target")
    [ "$cells" -eq "$target" ] && { echo "$per"; return 0; }
    per=$((cells / nfiles))
    [ "$per" -lt 1 ] && { echo 1; return 0; }
  done
  echo "$per"
}

frame_select_expr() {
  local total=$1 count=$2 i idx expr=""
  [ "$count" -gt "$total" ] && count=$total
  [ "$count" -lt 1 ] && count=1
  for ((i=0; i<count; i++)); do
    if [ "$count" -eq 1 ]; then idx=0
    else idx=$(( i * (total - 1) / (count - 1) ))
    fi
    [ -n "$expr" ] && expr="${expr}+"
    expr="${expr}eq(n\\,${idx})"
  done
  printf '%s' "$expr"
}

contact_chain() {
  local expr="$1" prefix="$2" with_text="$3" chain escaped
  chain="select='${expr}',scale=320:-2"
  if [ "$with_text" = 1 ]; then
    escaped=${prefix//:/\\:}
    chain="${chain},drawtext=fontfile='C\\:/Windows/Fonts/arial.ttf':text='${escaped}%{pts\\:hms}':fontsize=18:fontcolor=white:box=1:boxcolor=black@0.65:x=8:y=h-th-8"
  fi
  printf '%s' "$chain"
}

contact_tile() { printf 'tile=%sx%s:padding=6:margin=6:color=black' "$1" "$2"; }

contact_frame_count() {
  local dir=$1 n=0
  shopt -s nullglob
  local files=("$dir"/frame-*.png)
  n=${#files[@]}
  shopt -u nullglob
  echo "$n"
}

drop_contact_frames_from() {
  local dir=$1 start=$2 f base num
  shopt -s nullglob
  for f in "$dir"/frame-*.png; do
    base=$(basename "$f" .png)
    num=${base#frame-}
    num=$((10#$num))
    [ "$num" -ge "$start" ] && rm -f "$f"
  done
  shopt -u nullglob
}

write_one_contact_sheet() {
  local file="$1" fc="$2" cols="$3" rows="$4" count="$5"
  local expr in_win out vf
  expr=$(frame_select_expr "$fc" "$count")
  in_win=$(win_path "$file")
  out=$(win_path "$EVID/contact-sheet.png")
  if [ -f /mnt/c/Windows/Fonts/arial.ttf ]; then
    vf="$(contact_chain "$expr" "" 1),$(contact_tile "$cols" "$rows")"
    if "$FFMPEG" -y -i "$in_win" -vf "$vf" -fps_mode vfr -frames:v 1 -update 1 "$out" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1 && [ -s "$EVID/contact-sheet.png" ]; then
      return 0
    fi
    rm -f "$EVID/contact-sheet.png"
  fi
  vf="$(contact_chain "$expr" "" 0),$(contact_tile "$cols" "$rows")"
  "$FFMPEG" -y -i "$in_win" -vf "$vf" -fps_mode vfr -frames:v 1 -update 1 "$out" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1 && [ -s "$EVID/contact-sheet.png" ]
}

dump_contact_frames() {
  local file="$1" dir="$2" fc="$3" count="$4" start="$5" prefix="$6"
  local expr in_win seq vf before
  expr=$(frame_select_expr "$fc" "$count")
  in_win=$(win_path "$file")
  seq=$(win_path "$dir/frame-%02d.png")
  before=$(contact_frame_count "$dir")
  if [ -f /mnt/c/Windows/Fonts/arial.ttf ]; then
    vf=$(contact_chain "$expr" "$prefix" 1)
    if "$FFMPEG" -y -i "$in_win" -vf "$vf" -fps_mode vfr -start_number "$start" "$seq" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1; then
      [ $(( $(contact_frame_count "$dir") - before )) -eq "$count" ] && return 0
    fi
    drop_contact_frames_from "$dir" "$start"
  fi
  vf=$(contact_chain "$expr" "$prefix" 0)
  "$FFMPEG" -y -i "$in_win" -vf "$vf" -fps_mode vfr -start_number "$start" "$seq" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1 || return 1
  [ $(( $(contact_frame_count "$dir") - before )) -eq "$count" ]
}

tile_frames() {
  local dir="$1" cols="$2" rows="$3" seq out
  seq=$(win_path "$dir/frame-%02d.png")
  out=$(win_path "$EVID/contact-sheet.png")
  "$FFMPEG" -y -framerate 1 -start_number 0 -i "$seq" \
    -vf "$(contact_tile "$cols" "$rows")" \
    -frames:v 1 -update 1 "$out" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1
}

write_contact_sheet() {
  local -a files=("$@")
  local nfiles=${#files[@]}
  local tmp cols rows cells per i fc take start=0 prefix in_win f base num
  [ "$nfiles" -ge 1 ] || return 1
  : >"$EVID/contact-sheet-ffmpeg.log"
  if [ "$nfiles" -eq 1 ]; then
    in_win=$(win_path "${files[0]}")
    fc=$(video_frame_count "$in_win") || return 1
    take=$(samples_per_file 1)
    [ "$take" -gt "$fc" ] && take=$fc
    read -r cols rows cells < <(contact_layout "$take")
    [ "$cells" -gt "$fc" ] && cells=$fc
    read -r cols rows cells < <(contact_layout "$cells")
    write_one_contact_sheet "${files[0]}" "$fc" "$cols" "$rows" "$cells"
    return $?
  fi
  tmp="$EVID/.contact-frames"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  per=$(samples_per_file "$nfiles")
  for ((i=0; i<nfiles; i++)); do
    in_win=$(win_path "${files[$i]}")
    fc=$(video_frame_count "$in_win") || fc=1
    take=$per
    [ "$take" -gt "$fc" ] && take=$fc
    [ "$take" -lt 1 ] && take=1
    prefix="$(basename "${files[$i]}" .mp4) "
    dump_contact_frames "${files[$i]}" "$tmp" "$fc" "$take" "$start" "$prefix" || { rm -rf "$tmp"; return 1; }
    start=$((start + take))
  done
  read -r cols rows cells < <(contact_layout "$start")
  for f in "$tmp"/frame-*.png; do
    base=$(basename "$f" .png)
    num=${base#frame-}
    num=$((10#$num))
    [ "$num" -ge "$cells" ] && rm -f "$f"
  done
  tile_frames "$tmp" "$cols" "$rows" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  [ -s "$EVID/contact-sheet.png" ]
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
  if ! write_contact_sheet "${mp4s[@]}"; then
    echo "RECORD FAIL: contact sheet (see $EVID/contact-sheet-ffmpeg.log)" >&2
    return 1
  fi
  echo "RECORD OK evidence=$EVID"
  printf '%s\n' "${mp4s[@]}"
  echo "$EVID/contact-sheet.png"
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
bot)
  run_godot honest-bot --headless --path "$ROOT" -s res://scripts/verify_honest_bot_nav.gd; r=$?
  grep -E '^(OK|FAIL|STUCK|HONEST)' "$EVID/honest-bot.log" | tr -d '\r'
  if bad "$EVID/honest-bot.log"; then echo "BOT FAIL script rc=$r"; tail -8 "$EVID/honest-bot.log"; exit 1; fi
  if grep -qF "HONEST BOT NAV OK" "$EVID/honest-bot.log" && ! grep -q '^FAIL' "$EVID/honest-bot.log"; then
    echo "BOT OK rc=$r marker='HONEST BOT NAV OK'"; else echo "BOT FAIL rc=$r"; tail -12 "$EVID/honest-bot.log"; exit 1; fi ;;
bot-combat)
  run_godot honest-bot-combat --headless --path "$ROOT" -s res://scripts/verify_honest_bot_combat.gd; r=$?
  grep -E '^(OK|FAIL|KILL|DEATH|KILLS|HONEST)' "$EVID/honest-bot-combat.log" | tr -d '\r'
  if bad "$EVID/honest-bot-combat.log"; then echo "BOT COMBAT FAIL script rc=$r"; tail -8 "$EVID/honest-bot-combat.log"; exit 1; fi
  if grep -qF "HONEST BOT COMBAT OK" "$EVID/honest-bot-combat.log" && grep -q '^KILL ' "$EVID/honest-bot-combat.log" && grep -q '^DEATH ' "$EVID/honest-bot-combat.log" && ! grep -q '^FAIL' "$EVID/honest-bot-combat.log"; then
    echo "BOT COMBAT OK rc=$r marker='HONEST BOT COMBAT OK'"; else echo "BOT COMBAT FAIL rc=$r"; tail -12 "$EVID/honest-bot-combat.log"; exit 1; fi ;;
bot-progress)
  run_godot honest-bot-progress --headless --path "$ROOT" -s res://scripts/verify_honest_bot_progress.gd; r=$?
  grep -E '^(OK|FAIL|LEVEL|SKILL|XP_RATE|SKIP|KILL|HONEST)' "$EVID/honest-bot-progress.log" | tr -d '\r'
  if bad "$EVID/honest-bot-progress.log"; then echo "BOT PROGRESS FAIL script rc=$r"; tail -8 "$EVID/honest-bot-progress.log"; exit 1; fi
  if grep -qF "HONEST BOT PROGRESS OK" "$EVID/honest-bot-progress.log" && grep -q '^LEVEL ' "$EVID/honest-bot-progress.log" && grep -q '^SKILL ' "$EVID/honest-bot-progress.log" && grep -q '^XP_RATE ' "$EVID/honest-bot-progress.log" && ! grep -q '^FAIL' "$EVID/honest-bot-progress.log"; then
    echo "BOT PROGRESS OK rc=$r marker='HONEST BOT PROGRESS OK'"; else echo "BOT PROGRESS FAIL rc=$r"; tail -20 "$EVID/honest-bot-progress.log"; exit 1; fi ;;
bot-crystal)
  run_godot honest-bot-crystal --headless --path "$ROOT" -s res://scripts/verify_honest_bot_crystal.gd; r=$?
  grep -E '^(OK|FAIL|STOP|ORIGIN|START|CRYSTAL|BOSS|KILL|STUCK|HONEST)' "$EVID/honest-bot-crystal.log" | tr -d '\r'
  if bad "$EVID/honest-bot-crystal.log"; then echo "BOT CRYSTAL FAIL script rc=$r"; tail -8 "$EVID/honest-bot-crystal.log"; exit 1; fi
  if grep -qF "HONEST BOT CRYSTAL OK" "$EVID/honest-bot-crystal.log" && grep -q '^CRYSTAL DESTROYED' "$EVID/honest-bot-crystal.log" && grep -q '^BOSS SPAWN ' "$EVID/honest-bot-crystal.log" && grep -q '^BOSS KILL' "$EVID/honest-bot-crystal.log" && ! grep -q '^FAIL' "$EVID/honest-bot-crystal.log"; then
    echo "BOT CRYSTAL OK rc=$r marker='HONEST BOT CRYSTAL OK'"; else echo "BOT CRYSTAL FAIL rc=$r"; tail -20 "$EVID/honest-bot-crystal.log"; exit 1; fi ;;
bot-run)
  run_godot honest-bot-run --headless --path "$ROOT" -s res://scripts/verify_honest_bot_run.gd; r=$?
  grep -E '^(PHASE|STOP|REPORT|HONEST|SCRIPT ERROR|Parse Error)' "$EVID/honest-bot-run.log" | tr -d '\r'
  if bad "$EVID/honest-bot-run.log"; then echo "BOT RUN FAIL script rc=$r"; tail -8 "$EVID/honest-bot-run.log"; exit 1; fi
  if ! grep -qF "HONEST BOT RUN DONE" "$EVID/honest-bot-run.log" || grep -q '^FAIL' "$EVID/honest-bot-run.log"; then
    echo "BOT RUN FAIL rc=$r"; tail -20 "$EVID/honest-bot-run.log"; exit 1
  fi
  if [ ! -s "$EVID/bot-report.md" ]; then echo "BOT RUN FAIL missing bot-report.md"; exit 1; fi
  shopt -s nullglob
  jsons=("$EVID"/telemetry/*.json)
  shopt -u nullglob
  if [ ${#jsons[@]} -eq 0 ]; then echo "BOT RUN FAIL no telemetry json in $EVID/telemetry"; exit 1; fi
  echo "BOT RUN OK rc=$r report=$EVID/bot-report.md telemetry=${jsons[0]}"
  grep -m1 '^Result:' "$EVID/bot-report.md" | tr -d '\r' ;;
bot-showcase)
  run_godot honest-bot-showcase --headless --path "$ROOT" -s res://scripts/verify_honest_bot_showcase.gd; r=$?
  grep -E '^(OK|FAIL|SHOWCASE|CHAPTERS|STUCK|HONEST)' "$EVID/honest-bot-showcase.log" | tr -d '\r'
  if bad "$EVID/honest-bot-showcase.log"; then echo "BOT SHOWCASE FAIL script rc=$r"; tail -8 "$EVID/honest-bot-showcase.log"; exit 1; fi
  if ! grep -qF "HONEST BOT SHOWCASE OK" "$EVID/honest-bot-showcase.log" || grep -q '^FAIL' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL rc=$r"; tail -24 "$EVID/honest-bot-showcase.log"; exit 1
  fi
  if ! grep -q '^SHOWCASE movement pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE day_night absent' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE NEXT dig_tool' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL markers rc=$r"; exit 1
  fi
  if [ ! -s "$EVID/chapters.json" ] || [ ! -s "$EVID/chapters.txt" ]; then
    echo "BOT SHOWCASE FAIL missing chapters sidecar"; exit 1
  fi
  if ! grep -q '^movement ' "$EVID/chapters.txt" || ! grep -q '^day_night ' "$EVID/chapters.txt"; then
    echo "BOT SHOWCASE FAIL chapters.txt"; exit 1
  fi
  echo "BOT SHOWCASE OK rc=$r chapters=$EVID/chapters.json" ;;
telemetry-summary)
  py=""
  if command -v python3 >/dev/null 2>&1; then py=python3
  elif command -v python >/dev/null 2>&1; then py=python
  else echo "TELEMETRY SUMMARY FAIL: python missing"; exit 1; fi
  [ $# -ge 1 ] || { echo "usage: cs-verify.sh telemetry-summary <session.json|dir> [more...]"; exit 2; }
  "$py" "$ROOT/tools/telemetry_summary.py" "$@"; r=$?
  [ $r -eq 0 ] || exit "$r" ;;
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
*) echo "usage: cs-verify.sh doctor|quick|launch [SEC]|bot|bot-combat|bot-progress|bot-crystal|bot-run|bot-showcase|feature <name>|telemetry-summary <json...>|cleanup|record <mode...>"; exit 2 ;;
esac
