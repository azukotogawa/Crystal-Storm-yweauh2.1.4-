#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../../.." && pwd)/0.2.8}"
LEDGER="$ROOT/studio/DECISIONS.md"
[ -f "$LEDGER" ] || { echo "LEDGER MISSING: $LEDGER"; exit 2; }
ok=0; bad=0; skip=0
while IFS= read -r line; do
  id="${line#- }"; id="${id%% *}"
  ref="$(sed -n 's/.*| ref: `\([^`]*\)`.*/\1/p' <<<"$line")"
  sym="$(sed -n 's/.*| sym: `\([^`]*\)`.*/\1/p' <<<"$line")"
  if [ -z "$ref" ]; then skip=$((skip+1)); continue; fi
  file="${ref%:*}"; ln="${ref##*:}"
  if [ ! -f "$ROOT/$file" ]; then echo "MISSING-FILE $id $file"; bad=$((bad+1)); continue; fi
  total=$(wc -l < "$ROOT/$file")
  if [ "$ln" -gt "$((total+1))" ]; then echo "MISSING-LINE $id $ref (file has $total lines)"; bad=$((bad+1)); continue; fi
  if [ -n "$sym" ] && ! grep -qF -- "$sym" "$ROOT/$file"; then echo "MISSING-SYMBOL $id $file '$sym'"; bad=$((bad+1)); continue; fi
  if [ -n "$sym" ]; then
    near=$(grep -nF -- "$sym" "$ROOT/$file" | cut -d: -f1 | awk -v n="$ln" '{d=$1-n; if(d<0)d=-d; if(b==""||d<b)b=d} END{print b}')
    if [ "$near" -gt 15 ]; then echo "MOVED $id $ref '$sym' now ${near} lines away"; fi
  fi
  ok=$((ok+1))
done < <(grep -E '^- D-[0-9]+ .*\| status: built \|' "$LEDGER")
echo "ledger-verify: built refs ok=$ok missing=$bad no-ref=$skip"
[ "$bad" -eq 0 ]
