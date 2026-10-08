#!/bin/sh
# Fetches the reference corpora of tools/audit/borrow-audit.py into $CORPORA (default build/corpora, never committed)
# and writes $CORPORA/list.txt, one source file per line.
#   fpc      Free Pascal 3.2.2: packages fv, ide, fcl-base, rtl-objpas, fcl-passrc (GPL / LGPL with exception)
#   fpide    the Free Pascal IDE on tv3 (unxed/sp, GPL)
#   dn214    DOS Navigator OSP 2.14 sources (licence of RIT Research Labs / DN OSP)
#   dn151    DOS Navigator 1.51 sources (RIT Research Labs)
#   bp7tv    Borland Pascal 7.0 / 7.01 Turbo Vision sources (proprietary)
# usage: tools/audit/fetch-corpora.sh        needs: git, curl, sha256sum, unrar, unzip
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
C=${CORPORA:-$here/build/corpora}
mkdir -p "$C"
cd "$C"

get() {   # get FILE SHA256 URL: download once, check the sha256
    if [ ! -s "$1" ]; then
        curl -fsSL --retry 4 --max-time 900 -o "$1.part" "$3" \
            || curl -fsSL --retry 4 --max-time 900 -o "$1.part" "$(echo "$3" | sed 's|web.archive.org/web/[0-9]*if_/||')"
        mv "$1.part" "$1"
    fi
    echo "$2  $1" | sha256sum -c - >/dev/null || { echo "fetch-corpora: $1: wrong sha256" >&2; exit 1; }
}

if [ ! -d fpc ]; then
    rm -rf fpc.tmp
    git clone -q -c advice.detachedHead=false --depth 1 --branch release_3_2_2 --filter=blob:none --sparse https://github.com/fpc/FPCSource fpc.tmp
    git -C fpc.tmp sparse-checkout set packages/fv packages/ide packages/fcl-base packages/rtl-objpas packages/fcl-passrc
    mv fpc.tmp fpc
fi
if [ ! -d sp ]; then
    rm -rf sp.tmp && git clone -q --depth 1 https://github.com/unxed/sp sp.tmp && mv sp.tmp sp
fi
if [ ! -d dn214 ]; then
    get dn2s214.rar 4b8feadac86780f615d4b2a7847d81ad41f551c1962c9dd58b721806f36608c3 \
        https://web.archive.org/web/20220202202636if_/http://www.dnosp.com/files/dn2/dn2s214.rar
    rm -rf dn214.tmp && mkdir dn214.tmp && unrar x -y -idq dn2s214.rar dn214.tmp/ && mv dn214.tmp dn214
fi
if [ ! -d dn151 ]; then
    get dn151src.zip d2d12bad4a040e751d5a6f4186a8caabd5ba8b3540e3dc7cab69a58a4f210440 \
        https://web.archive.org/web/20250406173244if_/https://download.ritlabs.com/dn/dn151src.zip
    rm -rf dn151.tmp && unzip -q -o dn151src.zip -d dn151.tmp && mv dn151.tmp dn151
fi
if [ ! -d bp7tv ]; then
    get bp7.rar 1ba6251209ae4a56a4f6ce5926bff0eca815ea53a3dd5f57f779d52d1e1dc2fc \
        'https://web.archive.org/web/20231211134715if_/http://old-dos.ru/dl.php?id=9670'
    rm -rf bp7x bp7tv.tmp && mkdir -p bp7x bp7tv.tmp && unrar x -y -idq bp7.rar bp7x/
    for z in BPASCAL.700/D11/TVSRC.ZIP BPASCAL.700/D11/TVDEMO.ZIP BPASCAL.700/D8/TVFM.ZIP BPASCAL.700/D12/TVDEBUG.ZIP; do
        unzip -q -o -C -j "bp7x/$z" '*.pas' -d bp7tv.tmp
    done
    unzip -q -o -C -j bp7x/_UPDATE_/BP_OBJEC.701/2/BP7ETC.ZIP 'rtl/tv/*.pas' 'rtl/common/objects.pas' -d bp7tv.tmp
    rm -rf bp7x && mv bp7tv.tmp bp7tv
fi

{
    find fpc/packages -type f \( -iname '*.pas' -o -iname '*.pp' -o -iname '*.inc' \)
    find sp/fpide -type f \( -iname '*.pas' -o -iname '*.pp' -o -iname '*.inc' \)
    find dn214 dn151 bp7tv -type f \( -iname '*.pas' -o -iname '*.pp' -o -iname '*.inc' \)
} | LC_ALL=C sort | sed "s|^|$C/|" > list.txt
echo "reference corpora: $(wc -l < list.txt) files in $C"
