#!/usr/bin/env python3
"""Pty test of the tve program: the menu bar by the navigation guidelines of vtui (F9 and F10 open it, Esc closes the drop-down and keeps the bar,
the second Esc leaves it). usage: test_app.py PATH/TO/tve   (PtyTerm: tools/pty_screen.py; PTY_TOOLS=DIR names the directory)"""
import os
import sys

sys.path.insert(0, os.environ.get('PTY_TOOLS', os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tools')))
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
print('ALL OK (%d checks)' % count if not fails else '%d of %d checks FAILED' % (fails, count))
sys.exit(1 if fails else 0)
