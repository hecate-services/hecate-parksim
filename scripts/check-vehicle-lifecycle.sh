#!/usr/bin/env bash
# check-vehicle-lifecycle.sh — syntax/parse-check the guide_vehicle_lifecycle
# app's modules with the project's Erlang 27.2 toolchain (the asdf `erlc` shim
# resolves to a bogus path, so we call the real binary).
#
# Judges on erlc's EXIT CODE, not text matching — warnings (e.g. the benign
# `apply/2 already defined`, undefined cross-module calls that resolve at
# runtime, unused helpers) are non-fatal and must not fail the check. Modules
# are compiled into one shared outdir so each can see the others' beams,
# avoiding spurious "missing beam" from per-file ordering.
set -uo pipefail

ERL_BIN="$HOME/.asdf/installs/erlang/27.2/bin"
ROOT="$HOME/work/github.com/hecate-services/hecate-parksim"
APP="$ROOT/apps/guide_vehicle_lifecycle"
OUT=/tmp/vehc-check
RESULT=/tmp/vehc-check-result.txt

rm -rf "$OUT"; mkdir -p "$OUT"
: > "$RESULT"

mapfile -t SRCS < <(ls "$APP"/src/*.erl "$APP"/src/*/*.erl 2>/dev/null)
ERRS=0

for f in "${SRCS[@]}"; do
    # +nowarn_unused_record etc. left on; we only care about hard errors.
    if ! out=$("$ERL_BIN/erlc" -I "$APP/include" -o "$OUT" "$f" 2>&1); then
        echo "FAIL: $(basename "$f")" >> "$RESULT"
        echo "$out" | grep -vi "warning:" >> "$RESULT"
        ERRS=$((ERRS+1))
    fi
done

beams=$(ls "$OUT"/*.beam 2>/dev/null | wc -l)
{
    echo "----------------------------------------"
    echo "sources: ${#SRCS[@]}   beams: $beams   modules-with-errors: $ERRS"
    if [ "$ERRS" -eq 0 ]; then echo "VERDICT: PASS"; else echo "VERDICT: FAIL"; fi
} >> "$RESULT"

cat "$RESULT"
