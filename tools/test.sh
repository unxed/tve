#!/bin/sh
# Unit tests of tve (tests/t_*.pas): tools/test.sh [t_name ...]. Needs fpc and tv3 (see need-tv.sh).
# The units of src (and the units of tv3 they use) are built once; then the tests are built and run side by side
# (TVE_TEST_JOBS, default nproc), each with a directory of its own for its objects, its TMPDIR and its HOME.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
w=${TVE_TEST_WORK:-$here/build/tests}; mkdir -p "$w"
w=$(cd "$w" && pwd)
fpc=${FPC:-fpc}
cd "$here/tests"

if [ "${1:-}" = "--one" ]; then                         # one test: build it, run it, write $w/$n.res
    n=$2; d="$w/$n"; rm -rf "$d"; mkdir -p "$d/tmp" "$d/home"
    out=$($fpc -Fu"$w/lib" -Fu"$here/src" -Fu"$TVSRC" -Fu. -Fi"$TVSRC" -Fi"$here/tests" -FU"$d" -FE"$d" "$n.pas" 2>&1) || true
    if echo "$out" | grep -qE "Error|Fatal"; then
        { echo "BUILD FAIL $n"; echo "$out" | grep -E "Error|Fatal" | head -3; } > "$w/$n.res"; exit 0
    fi
    TMPDIR="$d/tmp" HOME="$d/home" "$d/$n" > "$w/$n.txt" 2>&1 || true
    r=$(tail -1 "$w/$n.txt"); echo "$n: $r" > "$w/$n.res"
    case "$r" in "ALL OK"*) ;; *) grep -E '^FAIL' "$w/$n.txt" | head -10 >> "$w/$n.res" || true;; esac
    exit 0
fi

if [ $# -gt 0 ]; then tests=$(for n in "$@"; do basename "${n%.pas}"; done); else tests=$(ls t_*.pas | sed 's/\.pas$//'); fi

# the units of src, once, in one compiler run (every test then reads them from $w/lib, which comes first in its unit path)
mkdir -p "$w/lib"
{ echo "program allunits;"; echo "uses"
  ls "$here"/src/*.pas | xargs -n1 basename | sed 's/\.pas$//' | paste -sd, -
  echo "; begin end."; } > "$w/lib/allunits.pas"
out=$($fpc -Fu"$here/src" -Fu"$TVSRC" -Fi"$TVSRC" -FU"$w/lib" -FE"$w/lib" "$w/lib/allunits.pas" 2>&1) || true
if echo "$out" | grep -qE "Error|Fatal"; then echo "BUILD FAIL the units of src"; echo "$out" | grep -E "Error|Fatal" | head -5; exit 1; fi

for n in $tests; do rm -f "$w/$n.res"; done
echo "$tests" | xargs -P "${TVE_TEST_JOBS:-$(nproc)}" -n1 "$here/tools/test.sh" --one

fail=0
for n in $tests; do
    if [ -f "$w/$n.res" ]; then cat "$w/$n.res"; else echo "NO RESULT $n"; fail=1; continue; fi
    head -1 "$w/$n.res" | grep -q ": ALL OK" || fail=1
done
exit $fail
