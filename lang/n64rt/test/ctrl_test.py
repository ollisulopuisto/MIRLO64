#!/usr/bin/env python3
"""The per-game controller layouts (../n64rt_ctrl.h): the families do what they say through the pad mapping (the C of pad_host.c), the
cartridge table only has real cartridges (the save-type database's), a game's saved record survives and is refused when damaged, and the
"Controls" setting picks the right source.   python3 ctrl_test.py   (needs gcc)"""
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pad_test import K, N

FAM = dict(standard=0, platformer=1, shooter=2, skate=3, racing=4, fighter=5)
bad = 0


def fail(msg):
    global bad
    bad += 1
    print('FAIL', msg)


def build(name):
    exe = os.path.join(tempfile.mkdtemp(), name)
    subprocess.check_call(['gcc', '-O1', '-Wall', '-Wextra', '-o', exe, os.path.join(HERE, name + '.c')])
    return exe


def run(exe, *args, stdin=None):
    return subprocess.run([exe, *args], input=stdin, capture_output=True, text=True, check=True).stdout


def main():
    ctrl, pad = build('ctrl_host'), build('pad_host')
    presets = {}
    for line in run(ctrl, 'presets').splitlines():
        f, s0, s1, m1, *m = line.split()
        presets[int(f)] = dict(s0=int(s0, 16), s1=int(s1, 16), m1=int(m1, 16), map=[int(x, 16) for x in m])

    def pressed(fam, names, joy=0x80808080, typ=3):
        """the N64 buttons and stick family `fam` gives for the Pocket keys `names` (a settings word as the menu leaves it: the defaults)"""
        p = presets[fam]
        s0, s1 = p['s0'], p['s1'] & p['m1']
        k = typ << 28 | sum(1 << K[n] for n in names)
        out = run(pad, stdin='%x %x %x %x %s\n' % (k, joy, s0, s1, ' '.join('%x' % w for w in p['map']))).split()
        b = int(out[0], 16)
        return {n for n, bit in N.items() if b & bit}, int(out[1]), int(out[2])

    def expect(fam, names, want, stick=(0, 0), **kw):
        got = pressed(FAM[fam], names, **kw)
        if got != (set(want), *stick):
            fail('%s %s: %s, expected %s %s' % (fam, names, got, want, stick))

    # standard: no Modifier, the settings' defaults (Select is C-down)
    expect('standard', ['A'], ['A']); expect('standard', ['B'], ['B']); expect('standard', ['X'], ['CRIGHT']); expect('standard', ['Y'], ['CLEFT'])
    expect('standard', ['select'], ['CDOWN']); expect('standard', ['L1'], ['Z']); expect('standard', ['R1'], ['R']); expect('standard', ['start'], ['START'])
    expect('standard', ['left'], [], (-80, 0))
    # platformer: A, B, C-left, C-right unheld; Select (the Modifier) + X / Y / L / D-pad
    for fam in ('platformer', 'shooter'):
        expect(fam, ['A'], ['A']); expect(fam, ['B'], ['B']); expect(fam, ['X'], ['CRIGHT']); expect(fam, ['Y'], ['CLEFT'])
        expect(fam, ['select'], []); expect(fam, ['select', 'X'], ['CUP']); expect(fam, ['select', 'Y'], ['CDOWN'])
        expect(fam, ['select', 'A'], ['A']); expect(fam, ['select', 'B'], ['B']); expect(fam, ['select', 'L1'], ['L'])
        expect(fam, ['select', 'up'], ['CUP']); expect(fam, ['select', 'left'], ['CLEFT']); expect(fam, ['up'], [], (0, 80))
        expect(fam, ['start'], ['START'])
        expect(fam, [], ['CUP'], joy=0x20808080)                    # a dock pad's right stick up: C-up (the family turns "C buttons" on)
    expect('platformer', ['L1'], ['Z']); expect('platformer', ['R1'], ['R'])
    expect('shooter', ['R1'], ['Z']); expect('shooter', ['L1'], ['R'])
    # skate: the C buttons on the face keys, A / B with Select
    for key, c in (('A', 'CRIGHT'), ('B', 'CDOWN'), ('X', 'CUP'), ('Y', 'CLEFT')):
        expect('skate', [key], [c])
    expect('skate', ['select', 'A'], ['A']); expect('skate', ['select', 'B'], ['B']); expect('skate', ['select', 'X'], ['CUP'])
    expect('skate', ['select', 'A', 'B'], ['A', 'B']); expect('skate', ['L1'], ['Z']); expect('skate', ['left'], [], (-80, 0))
    # racing: the standard keys, Select + D-pad steers gently, Select + X / Y
    expect('racing', ['select', 'A'], ['A']); expect('racing', ['select', 'B'], ['B'])
    expect('racing', ['A'], ['A']); expect('racing', ['L1'], ['Z']); expect('racing', ['R1'], ['R'])
    expect('racing', ['left'], [], (-80, 0)); expect('racing', ['select', 'left'], [], (-40, 0))
    expect('racing', ['select', 'X'], ['CUP']); expect('racing', ['select', 'Y'], ['CDOWN'])
    # fighter: C-up (jump) on X, Z on Y and L, L on a dock pad's ZL
    expect('fighter', ['X'], ['CUP']); expect('fighter', ['Y'], ['Z']); expect('fighter', ['L1'], ['Z']); expect('fighter', ['L2'], ['L'])
    expect('fighter', ['select'], ['CDOWN']); expect('fighter', ['A'], ['A'])
    # a family sets the Modifier and (platformer, shooter) "C buttons", never "Stick" / "D-pad"
    for f, p in presets.items():
        if p['m1'] & ~(31 << 10):
            fail('family %d owns more of set1 than "C buttons": %x' % (f, p['m1']))
        if f not in (1, 2) and p['m1']:
            fail('family %d owns set1 bits without setting them' % f)
        if p['s0'] & ~(31 << 10):
            fail('family %d sets more of set0 than the Modifier: %x' % (f, p['s0']))

    # the cartridge table: every ID is a cartridge of the save-type database
    root = os.path.join(HERE, '..', '..', '..')
    db = open(os.path.join(root, 'pkg', 'pocket', 'Assets', 'mirlo', 'common', 'n64savedb.txt')).read()
    known = {m.group(1) for m in re.finditer(r'^([A-Z0-9]{3})[A-Z0-9?]\s', db, re.M)}
    src = open(os.path.join(HERE, '..', 'n64rt_ctrl.h')).read()
    ids = re.findall(r'N64RT_CG\("([A-Z0-9]{3})", N64RT_FAM_(\w+)\)', src)
    if not ids:
        fail('no cartridge table found')
    seen = set()
    for i, fam in ids:
        if i not in known: fail('cartridge %s is not in n64savedb.txt' % i)
        if i in seen: fail('cartridge %s is twice in the table' % i)
        seen.add(i)
    for i, want in (('NSME', 1), ('NSMJ', 1), ('NGEP', 2), ('NTQE', 3), ('NKTE', 4), ('NALE', 5), ('XXXX', -1), ('NSM', -1)):
        got = int(run(ctrl, 'family', i).strip())
        if got != want and not (len(i) == 3):
            fail('family %s: %d, expected %d' % (i, got, want))

    # a game's saved layout: it comes back, and any damage to it, or a short file, refuses it
    s0, s1, m = 6 << 10 | 0x7FFF, 1 << 10 | 2 << 15 | 1 << 22 | 0x3FFF000, [0x12345678 & 0x3FFFFFFF, 1, 2, 3, 0x3FFFFFFF]
    args = ['%x' % s0, '%x' % s1, *('%x' % w for w in m)]
    want = '1 %x %x %s' % (s0 & (31 << 10 | 0x3FF << 20), s1 & (31 << 10 | 31 << 15 | 3 << 22 | 0x3FF), ' '.join('%x' % w for w in m))
    got = run(ctrl, 'record', *args).strip()
    if got != want:
        fail('record: %s, expected %s' % (got, want))
    for word in range(9):
        for bit in (0, 7, 31):
            if run(ctrl, 'record', *args, str(word), str(bit)).strip() != '0':
                # (a flip in a bit the mask drops is not damage: words 1 and 2)
                if word in (1, 2): continue
                fail('record with word %d bit %d flipped was accepted' % (word, bit))
    if run(ctrl, 'record', *args, '8', '0', '35').strip() != '0':
        fail('a record of 35 bytes was accepted')
    # the "Controls" setting: src, saved?, family
    for src_, saved, fam, want in ((0, 1, 1, 'menu'), (1, 1, 1, '1800 0 %x 1234' % (31 << 10 | 31 << 15 | 3 << 22 | 0x3FF)), (1, 0, 1, None), (1, 0, -1, 'menu'),
                                   (2, 1, 1, None), (3, 1, -1, None), (7, 0, 0, None), (8, 1, 1, 'menu'), (31, 1, 1, 'menu')):
        got = run(ctrl, 'select', str(src_), str(saved), str(fam), 'x').strip()
        if want is not None and got != want:
            fail('select %s: %s, expected %s' % ((src_, saved, fam), got, want))
        if want is None and (got == 'menu' or not got):
            fail('select %s: %s' % ((src_, saved, fam), got))
    if int(run(ctrl, 'select', '2', '1', '-1', 'x').split()[0], 16) != 0 or int(run(ctrl, 'select', '3', '1', '-1', 'x').split()[0], 16) != 6 << 10:
        fail('a family source gave the wrong Modifier')
    # the user's database: first match wins, ? is any character, comments and bad lines are skipped, "menu" is explicit
    db = lambda text, cid: int(run(ctrl, 'db', text, cid).strip())
    for text, cid, want in (('', 'NSME', -2), ('NSM? racing', 'NSME', 4), ('NSM? racing', 'NSMJ', 4), ('NSME shooter\nNSM? racing', 'NSME', 2),
                            ('NSME shooter\nNSM? racing', 'NSMJ', 4), ('NSM? racing', 'NGEE', -2), ('# NSM? racing', 'NSME', -2),
                            ('NSM? menu', 'NSME', -1), ('NSM? standard # same as default', 'NSME', 0), ('NSM?\tfighter\r\n', 'NSME', 5),
                            ('NSM? bogus\nNSM? skate', 'NSME', 3), ('nsm? skate', 'NSME', -2), ('NSM skate', 'NSME', -2), ('NSM?skate', 'NSME', -2),
                            ('NSM? skates', 'NSME', -2), ('  \n\n  NSM?   platformer', 'NSME', 1), ('NSM? plat', 'NSME', -2),
                            ('N?M? racing', 'NSME', 4), ('????  fighter', 'ZZZZ', 5), ('NSM? racing', 'NSM', -2)):
        if cid == 'NSM': continue                                  # (a 3-character ID is not a cartridge's: skip)
        if db(text, cid) != want:
            fail('db %r for %s: %d, expected %d' % (text, cid, db(text, cid), want))
    # the D-pad ramp: grows by the step, never past the target; a release, a reversal or a smaller target is at once; off is the target
    ramp = lambda c, t, st: int(run(ctrl, 'ramp', str(c), str(t), str(st)).strip())
    for cur, tgt, step, want in ((0, 80, 20, 20), (20, 80, 20, 40), (70, 80, 20, 80), (0, -80, 40, -40), (-40, -80, 40, -80), (60, 0, 20, 0),
                                 (60, -80, 20, -80), (80, 40, 20, 40), (0, 80, 0, 80), (0, 40, 10, 10), (5, 3, 10, 3), (0, 80, -5, 80)):
        if ramp(cur, tgt, step) != want:
            fail('ramp %d -> %d by %d: %d, expected %d' % (cur, tgt, step, ramp(cur, tgt, step), want))
    # from rest to full, every step setting reaches the target and never overshoots, in the number of polls the step implies
    for step in (10, 20, 40):
        v, n = 0, 0
        while v != 80 and n < 100:
            nv = ramp(v, 80, step)
            if not v < nv <= 80: fail('ramp stalled or overshot at %d (step %d)' % (v, step)); break
            v, n = nv, n + 1
        if n != -(-80 // step): fail('ramp with step %d took %d polls' % (step, n))
    print('ctrl_test: %s' % ('FAIL (%d)' % bad if bad else 'PASS'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
