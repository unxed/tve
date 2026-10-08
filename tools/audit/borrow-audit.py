#!/usr/bin/env python3
"""Finds code of the reference corpora in the sources of this repository.

usage: borrow-audit.py [-k 24] --ref LIST [--report FILE] PATH...

LIST names one reference source per line (tools/audit/fetch-corpora.sh writes it). PATH is a file or a directory
(its .pas, .pp, .inc files). The text is compared as tokens: comments, layout and letter case do not count. Every
chain of K tokens or more of a source file that occurs in a reference file is printed with both places, and the exit
code is 1 when there is at least one.

The heading of a routine (procedure, function, constructor, destructor, operator: from the keyword to the semicolon
that ends it, with its directives such as override or virtual) is a token that matches nothing, so no chain goes over
it: an override has to repeat the signature of the API it overrides. Everything else (bodies, constants, types,
tables) counts token by token.
"""
import argparse, os, re, sys

TOK = re.compile(r"""
   (?P<str>(?:'(?:[^']|'')*'|\#\$?[0-9a-fA-F]+)+)
 | (?P<num>\$[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)
 | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
 | (?P<sym>:=|<=|>=|<>|\.\.|[^\sA-Za-z0-9_])
""", re.X)
HEADS = {'procedure', 'function', 'constructor', 'destructor', 'operator'}
DIRECTIVES = {'override', 'virtual', 'abstract', 'overload', 'reintroduce', 'static', 'inline', 'cdecl', 'stdcall',
              'register', 'pascal', 'safecall', 'forward', 'assembler', 'dynamic', 'message', 'deprecated', 'platform',
              'final', 'varargs', 'local', 'nostackframe', 'interrupt', 'far', 'near', 'export'}


def strip_comments(t):
    """The text without comments; the line breaks are kept, so the token lines stay right."""
    out, i, n = [], 0, len(t)
    while i < n:
        c = t[i]
        if c == "'":
            j = i + 1
            while j < n:
                if t[j] == "'":
                    if j + 1 < n and t[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            out.append(t[i:j + 1])
            i = j + 1
        elif c == '{' or t.startswith('(*', i) or t.startswith('//', i):
            end = {'{': '}', '(': '*)', '/': '\n'}[c]
            j = t.find(end, i + 1)
            j = n if j < 0 else (j if end == '\n' else j + len(end))
            out.append(' ' + '\n' * t.count('\n', i, j))
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def tokens(path):
    """[(token, line)]; every routine heading is one token that is equal to no other."""
    text = strip_comments(open(path, encoding='latin-1').read())
    raw = []
    for m in TOK.finditer(text):
        v = m.group(m.lastgroup)
        raw.append((v.lower() if m.lastgroup != 'sym' else v, text.count('\n', 0, m.start()) + 1))
    out, i, n = [], 0, len(raw)
    while i < n:
        v, line = raw[i]
        prev = raw[i - 1][0] if i else ''
        if v in HEADS and prev not in ('=', ':', '(', ','):      # a procedural type (T = procedure ...) stays as it is
            j, depth = i + 1, 0
            while j < n and not (raw[j][0] == ';' and depth == 0):
                depth += {'(': 1, ')': -1}.get(raw[j][0], 0)
                j += 1
            j += 1
            while j + 1 < n and raw[j][0] in DIRECTIVES:
                j += 1
                while j < n and raw[j][0] != ';':
                    j += 1
                j += 1
            out.append((('\x00head', path, len(out)), line))
            i = j
        else:
            out.append((v, line))
            i += 1
    return out


def files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, dirs, names in os.walk(p):
                dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
                for name in sorted(names):
                    if name.lower().endswith(('.pas', '.pp', '.inc')):
                        yield os.path.join(root, name)
        else:
            yield p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-k', type=int, default=24)
    ap.add_argument('--ref', required=True)
    ap.add_argument('--report')
    ap.add_argument('paths', nargs='+')
    a = ap.parse_args()
    k = a.k
    index = {}
    refs = [l.strip() for l in open(a.ref, encoding='utf-8') if l.strip()]
    for r in refs:
        toks = tokens(r)
        words = [t for t, _ in toks]
        for i in range(len(words) - k + 1):
            index.setdefault(hash(tuple(words[i:i + k])), (r, toks[i][1]))
    found = []
    count = 0
    for f in files(a.paths):
        count += 1
        toks = tokens(f)
        words = [t for t, _ in toks]
        i, n = 0, len(words) - k + 1
        while i < n:
            hit = index.get(hash(tuple(words[i:i + k])))
            if hit is None:
                i += 1
                continue
            j = i + 1
            while j < n and hash(tuple(words[j:j + k])) in index:
                j += 1
            length = j - 1 + k - i
            found.append('%5d tokens  %s:%d-%d  ==  %s:%d' % (length, f, toks[i][1], toks[j - 1 + k - 1][1], hit[0], hit[1]))
            i = j - 1 + k
    out = '\n'.join(found + ['%d files, %d reference files, k = %d: %d chains' % (count, len(refs), k, len(found))])
    print(out)
    if a.report:
        open(a.report, 'w', encoding='utf-8').write(out + '\n')
    sys.exit(1 if found else 0)


if __name__ == '__main__':
    main()
