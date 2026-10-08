#!/bin/sh
# The tve program in a pty (tests/pty/test_app.py): builds the program, then runs the groups of the test side by side (they wait for
# the program, not for the CPU), each with a HOME and XDG directories of its own. Needs fpc, python3 and tv3 (see need-tv.sh).
# usage: tools/pty-test.sh [--build]      --build only builds build/app/tve (CI runs the groups with tools/ci-par.sh)
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/tools/need-tv.sh"
cd "$here"
mkdir -p build/app
out=$(${FPC:-fpc} -Fusrc -Fu"$TVSRC" -Fi"$TVSRC" -FUbuild/app -FEbuild/app app/tve.pas 2>&1)
if echo "$out" | grep -qE 'Error|Fatal'; then echo "BUILD FAIL app/tve.pas"; echo "$out" | grep -E 'Error|Fatal' | head -5; exit 1; fi
[ "${1:-}" = --build ] && exit 0
w=$(mktemp -d "${TMPDIR:-/tmp}/tve-pty.XXXXXX")
groups="menu words state"
for g in $groups; do
    (
        HOME=$w/home-$g
        XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state XDG_DATA_HOME=$HOME/.local/share XDG_CACHE_HOME=$HOME/.cache
        export HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME
        mkdir -p "$HOME"
        python3 tests/pty/test_app.py build/app/tve "$g" > "$w/$g.txt" 2>&1; echo $? > "$w/$g.rc"
    ) &
done
wait
fail=0
for g in $groups; do
    if [ "$(cat "$w/$g.rc" 2>/dev/null)" = 0 ]; then echo "$g: $(tail -1 "$w/$g.txt")"; else echo "$g: FAILED"; grep -E '^FAIL' "$w/$g.txt" | head -10; fail=1; fi
done
if [ $fail = 0 ]; then rm -rf "$w"; else echo "the output of the tests: $w"; fi
exit $fail
