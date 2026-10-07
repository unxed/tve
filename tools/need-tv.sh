# Sourced by the scripts: sets TVSRC to the src/ directory of tv3. TV=/path/to/tv3 picks a checkout; else ./tv; else one is cloned into ./tv (the branch TV_REF, default main).
here=${here:-$(cd "$(dirname "$0")/.." && pwd)}
if [ -n "${TV:-}" ] && [ -f "$TV/src/tvgeom.pas" ]; then
    TVSRC=$TV/src
elif [ -f "$here/tv/src/tvgeom.pas" ]; then
    TVSRC=$here/tv/src
else
    echo "tv/ is not there: cloning tv3 (set TV=/path/to/tv3 to use a checkout)" >&2
    git clone -q --depth 1 --branch "${TV_REF:-main}" https://github.com/unxed/tv3 "$here/tv" || { echo "ERROR: no tv3" >&2; exit 1; }
    TVSRC=$here/tv/src
fi
export TVSRC
