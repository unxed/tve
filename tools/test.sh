#!/bin/sh
# Unit tests of tve (tests/t_*.pas): tools/test.sh [t_name ...]. Needs fpc and tv3 (see need-tv.sh).
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
w=${TVE_TEST_WORK:-$here/build/tests}; mkdir -p "$w"
cd "$here/tests"
if [ $# -gt 0 ]; then tests=$(for n in "$@"; do echo "${n%.pas}.pas"; done); else tests=$(ls t_*.pas); fi
fail=0
for t in $tests; do
    n=${t%.pas}
    out=$(${FPC:-fpc} -Fu"$here/src" -Fu"$TVSRC" -Fu. -Fi"$TVSRC" -Fi"$here/tests" -FU"$w" -FE"$w" "$t" 2>&1) || true
    if echo "$out" | grep -qE "Error|Fatal"; then echo "BUILD FAIL $n"; echo "$out" | grep -E "Error|Fatal" | head -3; fail=1; continue; fi
    "$w/$n" > "$w/$n.txt" 2>&1 || true
    r=$(tail -1 "$w/$n.txt"); echo "$n: $r"
    case "$r" in "ALL OK"*) ;; *) fail=1; grep -E '^FAIL' "$w/$n.txt" | head -10;; esac
done
exit $fail
