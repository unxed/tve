#!/usr/bin/env python3
"""Pty test of the tve program: the menu bar by the navigation guidelines of vtui (F9 and F10 open it, Esc closes the drop-down and keeps the bar,
the second Esc leaves it). usage: test_app.py PATH/TO/tve   (PtyTerm: tools/pty_screen.py; PTY_TOOLS=DIR names another directory)"""
import os
import sys

sys.path.insert(0, os.environ.get('PTY_TOOLS', os.path.join(os.path.dirname(__file__), '..', '..', 'tools')))
from pty_screen import PtyTerm

fails = 0
count = 0


def check(cond, name, info=''):
    global fails, count
    count += 1
    print(('PASS ' if cond else 'FAIL ') + name)
    if not cond:
        fails += 1
        if info:
            print(info)


t = PtyTerm([sys.argv[1]], 80, 25)
check(t.wait_for('File'), 'the program starts and draws the menu bar')
for name, key in (('F9', b'\x1b[20~'), ('F10', b'\x1b[21~')):
    t.send(key)
    t.send(b'\x1b[B')
    check('Save macro' in t.text(), name + ' + Down opens the File menu', t.text())
    t.send(b'\x1b')
    check('Save macro' not in t.text(), name + ': Esc closes the drop-down', t.text())
    t.send(b'\x1b[B')
    check('Save macro' in t.text(), name + ': the bar stays active, Down opens the menu again', t.text())
    t.send(b'\x1b')
    t.send(b'\x1b')
    t.send(b'\x1b[B')
    check('Save macro' not in t.text(), name + ': the second Esc leaves the bar', t.text())
t.send(b'\x1bx', settle=0.5)
check(t.close() == 0, 'Alt-X ends the program')


def jumps(args):
    """types foo.bar, goes Home and presses Ctrl+Right twice: how far the cursor went"""
    t = PtyTerm([sys.argv[1]] + args, 80, 25)
    t.wait_for('File')
    t.send(b'foo.bar')
    t.send(b'\x1b[H')
    x0 = t.screen.x
    t.send(b'\x1b[1;5C')
    t.send(b'\x1b[1;5C')
    d = t.screen.x - x0
    t.send(b'\x1bx', settle=0.5)
    t.close()
    return d


# E.7 of the guidelines: the word movement of the guidelines is optional (--words=nav); the default keeps the word rules of the editor
check(jumps([]) == 4, 'Ctrl+Right twice on foo.bar: the word rules of the editor stop at foo.|bar')
check(jumps(['--words=nav']) == 7, '--words=nav: the rules of the guidelines take foo.bar in two jumps')



def cursor_after(args, keys):
    """opens the program, sends the keys, quits: where the cursor was before Alt-X"""
    t = PtyTerm([sys.argv[1]] + args, 80, 25)
    t.wait_for('File')
    for k in keys:
        t.send(k)
    pos = (t.screen.x, t.screen.y)
    t.send(b'\x1bx', settle=0.5)
    t.close()
    return pos


# --state: the cursor of a file is remembered when the program quits and restored when it opens the file again
import tempfile
with tempfile.TemporaryDirectory(prefix='tve-state-') as d:
    f = os.path.join(d, 'a.txt')
    with open(f, 'w') as h:
        h.write(''.join('line %d\n' % i for i in range(20)))
    st = ['--state=' + os.path.join(d, 'state.ini'), f]
    first = cursor_after(st, [b'\x1b[B'] * 5 + [b'\x1b[C'] * 3)
    again = cursor_after(st, [])
    check(again == first and first[1] > 2, '--state: the cursor is where it was', '%r %r' % (first, again))
    check(cursor_after([f], []) != first, 'without --state the file opens at its start')

print('ALL OK (%d checks)' % count if not fails else '%d of %d checks FAILED' % (fails, count))
sys.exit(1 if fails else 0)
