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
RECORD_FPS=30
SHOWCASE_CAPTURE=0
SHOWCASE_OVERRIDE=0
FFMPEG=""

record_fail() { echo "RECORD FAIL: $*" >&2; exit 1; }

arm_showcase_override() {
  [ "$SHOWCASE_CAPTURE" = 1 ] || return 0
  local cfg="$ROOT/override.cfg"
  if [ -e "$cfg" ]; then
    record_fail "refusing to replace existing 0.2.8/override.cfg"
  fi
  printf '%s\n' '[display]' '' \
    'window/size/viewport_width=1280' \
    'window/size/viewport_height=720' \
    'window/size/window_width_override=1280' \
    'window/size/window_height_override=720' > "$cfg"
  SHOWCASE_OVERRIDE=1
}

clear_showcase_override() {
  [ "$SHOWCASE_OVERRIDE" = 1 ] || return 0
  rm -f "$ROOT/override.cfg"
  SHOWCASE_OVERRIDE=0
}

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
  [ "$slug" = showcase ] && SHOWCASE_CAPTURE=1
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
  local part="$EVID/$name.encoding.mp4"
  local log="$EVID/$name-ffmpeg.log"
  local out_win in_win seq_win wav_win frames game vf part_win
  if [ -s "$out" ]; then
    if duration_ok "$out" "$name"; then
      echo "RECORD mp4=$out"
      return 0
    fi
    echo "RECORD FAIL: $out is already there and its duration is not game time" >&2
    return 1
  fi
  out_win=$(win_path "$out")
  part_win=$(win_path "$part")
  if [ -s "$avi" ]; then
    wait_avi_closed "$avi" || return 1
    in_win=$(win_path "$avi")
    frames=$(video_frame_count "$in_win") || { echo "RECORD FAIL: frame count of $name.avi" >&2; return 1; }
    game=$(game_seconds_for "$name" || true)
    vf=$(pace_vf "$frames" "$game")
    if ! "$FFMPEG" -nostdin -y -i "$in_win" -vf "$vf" -fps_mode passthrough -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$part_win" >"$log" 2>&1; then
      if ! "$FFMPEG" -nostdin -y -i "$in_win" -an -vf "$vf" -fps_mode passthrough -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$part_win" >"$log" 2>&1; then
        echo "RECORD FAIL: ffmpeg could not convert $name.avi (see $log)" >&2
        return 1
      fi
    fi
    if ! duration_ok "$part" "$name"; then
      echo "RECORD FAIL: $name video duration is not game time (see $log)" >&2
      return 1
    fi
    mv "$part" "$out" || return 1
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
    args=(-nostdin "${args[@]}" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$part_win")
    if ! "$FFMPEG" "${args[@]}" >"$log" 2>&1; then
      echo "RECORD FAIL: ffmpeg could not convert $name png sequence (see $log)" >&2
      return 1
    fi
    if ! duration_ok "$part" "$name"; then
      echo "RECORD FAIL: $name video duration is not game time (see $log)" >&2
      return 1
    fi
    mv "$part" "$out" || return 1
  fi
  echo "RECORD mp4=$out"
}

wait_avi_closed() {
  local avi="$1" win size prev=0 stable=0 i locked
  win=$(win_path "$avi")
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    [ -f "$avi" ] || { sleep 0.4; continue; }
    size=$(stat -c %s "$avi" 2>/dev/null || echo 0)
    locked=0
    if command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -Command "try { \$f=[System.IO.File]::Open('$win','Open','Read','None'); \$f.Dispose(); exit 0 } catch { exit 1 }" >/dev/null 2>&1 || locked=1
    fi
    if [ "$locked" -eq 0 ] && [ "$size" = "$prev" ] && [ "$size" -gt 32 ]; then
      stable=$((stable + 1))
      [ "$stable" -ge 2 ] && return 0
    else
      stable=0
    fi
    prev=$size
    sleep 0.4
  done
  echo "RECORD FAIL: $avi was still open or still growing" >&2
  return 1
}

game_seconds_for() {
  local name="$1" log="$EVID/$name.log" end line
  if [ -s "$EVID/chapters.txt" ]; then
    end=$(awk 'NF >= 3 { v = $3 } END { if (v + 0 > 0) print v }' "$EVID/chapters.txt")
    if [ -n "$end" ]; then
      echo "$end"
      return 0
    fi
  fi
  if [ -f "$log" ]; then
    line=$(grep -E '^MOVIE_GAME_SEC ' "$log" | tail -1 | tr -d '\r')
    if [ -n "$line" ]; then
      echo "${line#MOVIE_GAME_SEC }"
      return 0
    fi
  fi
  return 1
}

pace_vf() {
  local frames="$1" game="$2" keep="$1" sel scale
  if [ "$frames" -gt 1 ]; then
    keep=$((frames - 1))
    sel="select='gte(n\\,1)'"
  else
    sel="select='gte(n\\,0)'"
  fi
  scale=""
  if [ -n "$game" ] && [ "$keep" -ge 1 ]; then
    scale=$(awk -v g="$game" -v k="$keep" -v fps="$RECORD_FPS" 'BEGIN { n = k / fps; tol = g * 0.08; if (tol < 0.45) tol = 0.45; if (n + tol < g) printf "%.6f", g / k }')
  fi
  if [ -n "$scale" ]; then
    echo "RECORD pace $keep frames across ${game}s" >&2
    printf '%s,setpts=N*%s/TB' "$sel" "$scale"
  else
    printf '%s,setpts=N/FRAME_RATE/TB' "$sel"
  fi
}

duration_ok() {
  local file="$1" name="$2" dur game
  dur=$(video_duration "$(win_path "$file")") || return 1
  game=$(game_seconds_for "$name" || true)
  if [ -n "$game" ]; then
    if ! awk -v d="$dur" -v g="$game" 'BEGIN { tol = g * 0.08; if (tol < 0.45) tol = 0.45; diff = d - g; if (diff < 0) diff = -diff; exit (diff <= tol ? 0 : 1) }'; then
      echo "RECORD FAIL: $name video ${dur}s vs game ${game}s" >&2
      return 1
    fi
    echo "RECORD time $name video=${dur}s game=${game}s"
  else
    echo "RECORD time $name video=${dur}s"
  fi
  return 0
}

ffprobe_bin() {
  local d
  d=$(dirname "$FFMPEG")
  if [ -f "$d/ffprobe.exe" ]; then echo "$d/ffprobe.exe"; return 0; fi
  if [ -f "$d/ffprobe" ]; then echo "$d/ffprobe"; return 0; fi
  return 1
}

video_size() {
  local in_win="$1" probe line
  probe=$(ffprobe_bin) || return 1
  line=$("$probe" -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$in_win" 2>/dev/null | tr -d '\r')
  case "$line" in
    ''|N/A|x) return 1 ;;
  esac
  echo "$line"
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

video_duration() {
  local in_win="$1" probe d
  probe=$(ffprobe_bin) || return 1
  d=$("$probe" -v error -show_entries format=duration -of default=nw=1:nk=1 "$in_win" 2>/dev/null | tr -d '\r')
  case "$d" in
    ''|N/A|nan) return 1 ;;
  esac
  echo "$d"
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

stamp_font_w() {
  local bundled="$HERE/fonts/DejaVuSans.ttf" win
  if [ -f "$bundled" ]; then
    win=$(win_path "$bundled")
  elif [ -f /mnt/c/Windows/Fonts/arial.ttf ]; then
    win="C:/Windows/Fonts/arial.ttf"
  else
    return 1
  fi
  win=${win//\\/\\\\}
  win=${win//:/\\:}
  printf '%s' "$win"
}

contact_chain() {
  local expr="$1" prefix="$2" font="$3" chain escaped
  chain="select='${expr}',scale=320:-2"
  escaped=${prefix//:/\\:}
  chain="${chain},drawtext=fontfile='${font}':text='${escaped}%{pts\\:hms}':fontsize=18:fontcolor=white:box=1:boxcolor=black@0.65:x=8:y=h-th-8"
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
  local expr in_win out vf font
  font=$(stamp_font_w) || { echo "RECORD FAIL: no stamp font" >&2; return 1; }
  expr=$(frame_select_expr "$fc" "$count")
  in_win=$(win_path "$file")
  out=$(win_path "$EVID/contact-sheet.png")
  vf="$(contact_chain "$expr" "" "$font"),$(contact_tile "$cols" "$rows")"
  "$FFMPEG" -nostdin -y -i "$in_win" -vf "$vf" -fps_mode vfr -frames:v 1 -update 1 "$out" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1 && [ -s "$EVID/contact-sheet.png" ]
}

dump_contact_frames() {
  local file="$1" dir="$2" fc="$3" count="$4" start="$5" prefix="$6"
  local expr in_win seq vf before font
  font=$(stamp_font_w) || { echo "RECORD FAIL: no stamp font" >&2; return 1; }
  expr=$(frame_select_expr "$fc" "$count")
  in_win=$(win_path "$file")
  seq=$(win_path "$dir/frame-%02d.png")
  before=$(contact_frame_count "$dir")
  vf=$(contact_chain "$expr" "$prefix" "$font")
  "$FFMPEG" -nostdin -y -i "$in_win" -vf "$vf" -fps_mode vfr -start_number "$start" "$seq" >>"$EVID/contact-sheet-ffmpeg.log" 2>&1 || return 1
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
    extra=(--fixed-fps "$RECORD_FPS" --disable-vsync --write-movie "$(movie_file_w "$name")")
    if [ "$SHOWCASE_CAPTURE" = 1 ]; then
      extra+=(--windowed --resolution 1280x720)
      arm_showcase_override
    fi
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
  clear_showcase_override
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
  if ! write_contact_sheet "${mp4s[@]}"; then
    echo "RECORD FAIL: contact sheet (see $EVID/contact-sheet-ffmpeg.log)" >&2
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    echo "RECORD FAIL rc=$rc evidence=$EVID"
    return "$rc"
  fi
  local primary="" dims w h published
  if [ "$SHOWCASE_CAPTURE" = 1 ]; then
    primary=$(showcase_mp4 "${mp4s[@]}")
    dims=$(video_size "$(win_path "$primary")") || { echo "RECORD FAIL: ffprobe size of $primary" >&2; return 1; }
    w=${dims%x*}
    h=${dims#*x}
    if [ "$w" -lt 1280 ] || [ "$h" -lt 720 ]; then
      echo "RECORD FAIL: capture ${w}x${h} is below 1280x720" >&2
      return 1
    fi
    echo "SHOWCASE capture ${w}x${h}"
  fi
  if [ -n "${CRYSTALSTORM_SHOWCASE_MAX_SEC:-}" ]; then
    echo "RECORD SMOKE evidence=$EVID"
    printf '%s\n' "${mp4s[@]}"
    echo "$EVID/contact-sheet.png"
    return 0
  fi
  if [ "$SHOWCASE_CAPTURE" = 1 ]; then
    published=$(attach_showcase_chapters "$primary" "$EVID/chapters.txt")
    publish_showcase "$published" || return 1
  fi
  echo "RECORD OK evidence=$EVID"
  printf '%s\n' "${mp4s[@]}"
  echo "$EVID/contact-sheet.png"
  return 0
}

showcase_mp4() {
  local f
  for f in "$@"; do
    [ "$(basename "$f")" = honest-bot-showcase.mp4 ] && { echo "$f"; return 0; }
  done
  echo "$1"
}

attach_showcase_chapters() {
  local mp4="$1" txt="$2" meta="$EVID/chapters.ffmeta" tmp="$EVID/showcase-chaptered.mp4"
  if [ ! -s "$txt" ]; then
    echo "$mp4"
    return 0
  fi
  awk 'NF >= 3 {
    s = int($2 * 1000 + 0.5)
    e = int($3 * 1000 + 0.5)
    if (e <= s) e = s + 1
    printf "[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=%s\n\n", s, e, $1
  }' "$txt" > "$EVID/chapters.ffmeta.body"
  if [ ! -s "$EVID/chapters.ffmeta.body" ]; then
    echo "$mp4"
    return 0
  fi
  { echo ";FFMETADATA1"; cat "$EVID/chapters.ffmeta.body"; } > "$meta"
  if "$FFMPEG" -y -i "$(win_path "$mp4")" -i "$(win_path "$meta")" -map 0 -map_metadata 1 -c copy -movflags +faststart "$(win_path "$tmp")" >>"$EVID/chapters-ffmpeg.log" 2>&1 && [ -s "$tmp" ]; then
    echo "$tmp"
    return 0
  fi
  echo "SHOWCASE chapters metadata skipped (see $EVID/chapters-ffmpeg.log)" >&2
  echo "$mp4"
}

copy_fresh() {
  local src="$1" dest="$2" dir base stem ext n candidate
  [ -s "$src" ] || return 1
  dir=$(dirname "$dest")
  base=$(basename "$dest")
  stem="$base"
  ext=""
  case "$base" in
    *.*) ext=".${base##*.}"; stem="${base%.*}" ;;
  esac
  candidate="$dest"
  n=2
  while [ -e "$candidate" ]; do
    candidate="$dir/${stem}-v${n}${ext}"
    n=$((n + 1))
    [ "$n" -le 40 ] || return 1
  done
  cp "$src" "$candidate" || return 1
  echo "$candidate"
}

publish_showcase() {
  local mp4="$1"
  local dest="$EVID_ROOT/showcase"
  local latest="/mnt/d/LATEST/CrystalStorm"
  local copied sheet chapters_json chapters_txt latest_mp4
  mkdir -p "$dest" "$latest" || return 1
  copied=$(copy_fresh "$mp4" "$dest/showcase-speedrun.mp4") || return 1
  sheet=$(copy_fresh "$EVID/contact-sheet.png" "$dest/contact-sheet.png") || return 1
  chapters_json=""
  chapters_txt=""
  if [ -s "$EVID/chapters.json" ]; then
    chapters_json=$(copy_fresh "$EVID/chapters.json" "$dest/chapters.json") || return 1
  fi
  if [ -s "$EVID/chapters.txt" ]; then
    chapters_txt=$(copy_fresh "$EVID/chapters.txt" "$dest/chapters.txt") || return 1
  fi
  if [ -z "$chapters_json" ] || [ -z "$chapters_txt" ]; then
    echo "RECORD FAIL: showcase chapters sidecar missing" >&2
    return 1
  fi
  latest_mp4=$(copy_fresh "$copied" "$latest/showcase-speedrun.mp4") || return 1
  echo "SHOWCASE mp4=$copied"
  echo "SHOWCASE sheet=$sheet"
  echo "SHOWCASE chapters=$chapters_json"
  echo "SHOWCASE latest=$latest_mp4"
}

record_trap() {
  local rc=$?
  trap - EXIT
  clear_showcase_override
  finish_record "$rc"
  exit $?
}

declare -A SUITE=( [full-map]=verify_full_map_toggle [water]=verify_water_body
  [save-continue]=verify_world_save_resume [dig]=verify_terrain_dig [frontend]=verify_world_frontend_flow [water-remesh]=verify_water_flow_remesh [highlight]=verify_highlight_block_under_cursor [swim-visual]=verify_swim_visual_depth [content-pace]=verify_content_pace [save-messages]=verify_save_load_messages [dev-error-log]=verify_dev_error_log )
declare -A MARK=( [full-map]="All full map toggle tests OK" [water]="All water body tests OK"
  [save-continue]="All world save resume tests OK" [dig]="All terrain dig tests OK" [frontend]="All world frontend flow tests OK" [water-remesh]="All water flow remesh tests OK" [highlight]="All highlight block under cursor tests OK" [swim-visual]="All swim visual depth tests OK" [content-pace]="All content pace tests OK" [save-messages]="All save load message tests OK" [dev-error-log]="All dev error log tests OK" )
declare -A ABRUPT=( [frontend]=1 [save-continue]=1 [water]=1 )

bad(){ grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$1"; }

[ "$cmd" = quick ] && rmdir "$SCRATCH_W" 2>/dev/null
[ "$SHOWCASE_CAPTURE" = 1 ] && export CRYSTALSTORM_SHOWCASE_CAPTURE=1
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
showcase|bot-showcase)
  run_godot honest-bot-showcase --headless --path "$ROOT" -s res://scripts/verify_honest_bot_showcase.gd; r=$?
  if [ -n "${CRYSTALSTORM_SHOWCASE_MAX_SEC:-}" ]; then
    if grep -q 'RECORD FAIL input driver did not load' "$EVID/honest-bot-showcase.log" || grep -q 'RECORD FAIL boot_tutorial has not advanced after 30s' "$EVID/honest-bot-showcase.log"; then
      grep -E '^RECORD FAIL' "$EVID/honest-bot-showcase.log" | tr -d '\r'
      echo "SHOWCASE SMOKE FAIL rc=$r evidence=$EVID"
      exit 1
    fi
    if bad "$EVID/honest-bot-showcase.log"; then echo "SHOWCASE SMOKE FAIL script rc=$r"; tail -8 "$EVID/honest-bot-showcase.log"; exit 1; fi
    if ! grep -q '^SHOWCASE boot_tutorial pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE boot_tutorial left ' "$EVID/honest-bot-showcase.log"; then
      echo "RECORD FAIL boot_tutorial did not pass"
      tail -24 "$EVID/honest-bot-showcase.log"
      exit 1
    fi
    grep -E '^(SHOWCASE boot_tutorial|RECORD FAIL|MOVIE_GAME_SEC|SHOWCASE smoke)' "$EVID/honest-bot-showcase.log" | tr -d '\r'
    echo "SHOWCASE SMOKE boot left rc=$r evidence=$EVID"
    exit 0
  fi
  if [ -s "$EVID/chapters.txt" ]; then
    short=$(awk 'NF >= 3 { d = $3 - $2; if (d + 0.001 < 4) { print $1; exit } }' "$EVID/chapters.txt" | tr -d '\r')
    if [ -n "$short" ]; then
      echo "BOT SHOWCASE FAIL chapter $short under 4s"
      exit 1
    fi
  fi
  grep -E '^(OK|FAIL|SHOWCASE|CHAPTERS|STUCK|HONEST|KILL|LEVEL|SKILL|DEATH|BOSS|CRYSTAL)' "$EVID/honest-bot-showcase.log" | tr -d '\r'
  if bad "$EVID/honest-bot-showcase.log"; then echo "BOT SHOWCASE FAIL script rc=$r"; tail -8 "$EVID/honest-bot-showcase.log"; exit 1; fi
  if ! grep -qF "HONEST BOT SHOWCASE OK" "$EVID/honest-bot-showcase.log" || grep -q '^FAIL' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL rc=$r"; tail -24 "$EVID/honest-bot-showcase.log"; exit 1
  fi
  if ! grep -q '^SHOWCASE movement pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE day_night absent' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE night absent\|^SHOWCASE night pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE torch absent\|^SHOWCASE torch pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE dig_tool pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE structure_place pass' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL markers rc=$r"; exit 1
  fi
  if ! grep -q '^SHOWCASE density_poi pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE density_treasure pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE density_landmark pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE treasure pickup pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE glow ' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL exploration rc=$r"; exit 1
  fi
  if ! grep -q '^SHOWCASE combat_crystal_mite pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^KILL crystal_mite' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE bow attack' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL combat rc=$r"; exit 1
  fi
  if ! grep -q '^SHOWCASE xp_level pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^LEVEL ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE xp ready level ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SKILL dash' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE skill_dash pass' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL progress rc=$r"; exit 1
  fi
  if ! grep -q '^SKILL ground_slam' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE skill_ground_slam pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE multiblock_break pass' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL slam rc=$r"; exit 1
  fi
  if ! grep -q '^SHOWCASE STAMP bow_shot ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE STAMP skill_ground_slam ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE STAMP multiblock_break ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE STAMP skill_crystal_pulse ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE STAMP skill_quick_wall ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE STAMP skill_passives ' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL stamps rc=$r"; exit 1
  fi
  if ! grep -q '^SKILL crystal_pulse' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE skill_crystal_pulse pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SKILL quick_wall' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE skill_quick_wall pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^SKILL miner_passive' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE skill_passives pass' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL skill show rc=$r"; exit 1
  fi
  if ! grep -q '^SHOWCASE crystal hp ' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE crystal pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^BOSS SPAWN ' "$EVID/honest-bot-showcase.log" || ! grep -q '^BOSS KILL' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE boss pass' "$EVID/honest-bot-showcase.log" || ! grep -q '^CRYSTAL DESTROYED' "$EVID/honest-bot-showcase.log" || ! grep -q '^SHOWCASE win_screen pass' "$EVID/honest-bot-showcase.log"; then
    echo "BOT SHOWCASE FAIL crystal rc=$r"; exit 1
  fi
  for kind in wall_segment wall_corner gate stairs small_tower; do
    if ! grep -q "^SHOWCASE structure ${kind} shown" "$EVID/honest-bot-showcase.log"; then
      echo "BOT SHOWCASE FAIL missing structure ${kind}"; exit 1
    fi
  done
  if [ ! -s "$EVID/chapters.json" ] || [ ! -s "$EVID/chapters.txt" ]; then
    echo "BOT SHOWCASE FAIL missing chapters sidecar"; exit 1
  fi
  if ! grep -q '^movement ' "$EVID/chapters.txt" || ! grep -q '^day_night ' "$EVID/chapters.txt" || ! grep -q '^dig_tool ' "$EVID/chapters.txt" || ! grep -q '^structure_place ' "$EVID/chapters.txt" || ! grep -q '^structure_small_tower ' "$EVID/chapters.txt"; then
    echo "BOT SHOWCASE FAIL chapters.txt"; exit 1
  fi
  if ! grep -q '^density_poi' "$EVID/chapters.txt" || ! grep -q '^density_treasure' "$EVID/chapters.txt" || ! grep -q '^density_landmark' "$EVID/chapters.txt"; then
    echo "BOT SHOWCASE FAIL density chapters"; exit 1
  fi
  if ! grep -q '^combat_crystal_mite ' "$EVID/chapters.txt" || ! grep -q '^combat_spawn_elite ' "$EVID/chapters.txt" || ! grep -q '^skill_dash ' "$EVID/chapters.txt" || ! grep -q '^skill_ground_slam ' "$EVID/chapters.txt"; then
    echo "BOT SHOWCASE FAIL combat chapters"; exit 1
  fi
  if ! grep -q '^crystal ' "$EVID/chapters.txt" || ! grep -q '^boss ' "$EVID/chapters.txt" || ! grep -q '^win_screen ' "$EVID/chapters.txt"; then
    echo "BOT SHOWCASE FAIL finale chapters"; exit 1
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
scenario)
  name="${1:-}"
  case "$name" in
    dig|build|multi_dig|multi_build|mouse_build|water_dig|water_trench|dev_keys|swim|camera|hotbar|controls_tour|break|crystals|corruption|combat|mite_fight|relic_esc|boss_tyrant|boss_warden|boss_heart|level_up|unlock|kite) ;;
    *) echo "usage: cs-verify.sh scenario <dig|build|multi_dig|multi_build|mouse_build|water_dig|water_trench|dev_keys|swim|camera|hotbar|controls_tour|break|crystals|corruption|combat|mite_fight|relic_esc|boss_tyrant|boss_warden|boss_heart|level_up|unlock|kite>"; exit 2 ;;
  esac
  export CRYSTALSTORM_SCENARIO="$name"
  run_godot "scenario-$name" --headless --fixed-fps 60 --path "$ROOT" -s res://scripts/verify_honest_bot_scenario.gd; r=$?
  unset CRYSTALSTORM_SCENARIO
  log="$EVID/scenario-$name.log"
  grep -E '^(OK|FAIL|HARNESS|STUCK|PROBE|SHOWCASE)' "$log" | tr -d '\r'
  if bad "$log"; then echo "SCENARIO $name FAIL script rc=$r"; tail -8 "$log"; exit 1; fi
  if [ "$name" = break ]; then
    if grep -q '^FAIL harness assertion ' "$log" && grep -q '^STUCK REPORT ' "$log" && grep -q '^STUCK SHOT ' "$log" && grep -q '^HARNESS SCENARIO FAIL break' "$log"; then
      echo "SCENARIO BREAK OK rc=$r evidence=$EVID"
      exit 0
    fi
    echo "SCENARIO BREAK FAIL rc=$r"; tail -20 "$log"; exit 1
  fi
  if ! grep -q "^HARNESS SCENARIO OK $name" "$log" || grep -q '^FAIL' "$log"; then
    echo "SCENARIO $name FAIL rc=$r"; tail -24 "$log"; exit 1
  fi
  if ! grep -q '^HARNESS SHOT ' "$log" || ! grep -q '^PROBE CAPTURE ' "$log"; then
    echo "SCENARIO $name FAIL no screenshot"; exit 1
  fi
  shopt -s nullglob
  shots=("$EVID"/steps/*_"$name".png)
  shopt -u nullglob
  if [ ${#shots[@]} -eq 0 ] || [ ! -s "${shots[0]}" ]; then
    echo "SCENARIO $name FAIL missing steps png under $EVID/steps"; exit 1
  fi
  echo "SCENARIO $name OK rc=$r shot=${shots[0]} evidence=$EVID" ;;
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
clip)
  run_godot movie-pace --headless --path "$ROOT" -s res://scripts/verify_movie_pace.gd; r=$?
  grep -E '^(OK|FAIL|MOVIE_)' "$EVID/movie-pace.log" | tr -d '\r'
  if bad "$EVID/movie-pace.log"; then echo "CLIP FAIL script rc=$r"; tail -8 "$EVID/movie-pace.log"; exit 1; fi
  if ! grep -q '^OK chapter label clear' "$EVID/movie-pace.log" || ! grep -q '^MOVIE_GAME_SEC ' "$EVID/movie-pace.log"; then
    echo "CLIP FAIL rc=$r"; tail -20 "$EVID/movie-pace.log"; exit 1
  fi
  echo "CLIP OK rc=$r" ;;
*) echo "usage: cs-verify.sh doctor|quick|launch [SEC]|bot|bot-combat|bot-progress|bot-crystal|bot-run|bot-showcase|showcase|scenario <dig|build|multi_dig|multi_build|mouse_build|water_dig|water_trench|dev_keys|swim|camera|hotbar|controls_tour|break|crystals|corruption|combat|mite_fight|relic_esc|boss_tyrant|boss_warden|boss_heart|level_up|unlock|kite>|feature <name>|clip|telemetry-summary <json...>|cleanup|record <mode...>"; exit 2 ;;
esac
