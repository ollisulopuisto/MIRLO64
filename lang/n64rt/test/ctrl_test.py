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
    # a family owns the Modifier and the table, nothing of the stick's feel (dead zone, range, ramp are the player's)
    for f, p in presets.items():
        if p['m1'] or p['s1']:
            fail('family %d owns set1 bits: %x / %x' % (f, p['m1'], p['s1']))
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
    s0, s1, m = 6 << 10 | 0x7FFF | 0x2AA << 20, 3 | 0x3FFF000, [0x12345678 & 0x3FFFFFFF, 1, 2, 3, 0x3FFFFFFF]
    args = ['%x' % s0, '%x' % s1, *('%x' % w for w in m)]
    want = '1 %x %x %s' % (s0 & (31 << 10 | 0x3FF << 20), s1 & 0x1F, ' '.join('%x' % w for w in m))
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
    for src_, saved, fam, want in ((0, 1, 1, 'menu'), (1, 1, 1, '1800 0 %x 1234' % 0x1F), (1, 0, 1, None), (1, 0, -1, 'menu'),
                                   (2, 1, 1, None), (3, 1, -1, None), (7, 0, 0, None), (8, 1, 1, 'menu'), (31, 1, 1, 'menu')):
        got = run(ctrl, 'select', str(src_), str(saved), str(fam), 'x').strip()
        if want is not None and got != want:
            fail('select %s: %s, expected %s' % ((src_, saved, fam), got, want))
        if want is None and (got == 'menu' or not got):
            fail('select %s: %s' % ((src_, saved, fam), got))
    if int(run(ctrl, 'select', '2', '1', '-1', 'x').split()[0], 16) != 0 or int(run(ctrl, 'select', '3', '1', '-1', 'x').split()[0], 16) != 6 << 10:
        fail('a family source gave the wrong Modifier')
    # the menu's editor: each (layer, key, gives, special) the menu can send puts the right code in the right field and nothing else, or
    # nothing (a choice that means nothing); then through the pad mapping the table does what was asked
    def field_of(words, f): return (words[f // 6] >> (5 * (f % 6))) & 31
    for layer in (0, 1):
        for key in range(15):
            for gives in [0, 31] + list(range(1, 15)):
                for special in range(6):
                    out = run(ctrl, 'edit', str(layer), str(key), str(gives), str(special)).split()
                    changed, words = int(out[0]), [int(w, 16) for w in out[1:]]
                    group = key >= 12
                    if group:
                        want = {0: {0: 0, 31: 5}.get(gives), 1: 6 if layer else None}.get(special, special - 1 if 2 <= special <= 5 else None)
                    else:
                        want = (gives if gives in [0, 31] + list(range(1, 15)) else None) if special == 0 else (15 if layer else None) if special == 1 else None
                    f = (15 if layer else 0) + key
                    if want is None:
                        if changed or any(words): fail('edit %s: changed something that means nothing: %s' % ((layer, key, gives, special), words))
                    elif not changed or field_of(words, f) != want or any(field_of(words, g) for g in range(30) if g != f):
                        fail('edit %s: field %d is %d, expected %d (changed %d)' % ((layer, key, gives, special), f, field_of(words, f), want, changed))
    for nonsense in ((2, 0, 1, 0), (0, 15, 1, 0), (0, 0, 15, 0), (0, 0, 20, 0), (0, 0, 1, 6)):
        if int(run(ctrl, 'edit', *map(str, nonsense)).split()[0]) != 0: fail('edit %s was accepted' % (nonsense,))
    # the menu file against the Pocket's limits (Analogue's docs: 16 entries shown, names 23 characters, a list 16 options, ids unique 16-bit):
    # a longer file is "Load error in interact" at the core's start
    import json
    menu = json.load(open(os.path.join(root, 'pkg', 'pocket', 'Cores', 'tortuga.Mirlo64', 'interact.json')))['interact']['variables']
    if len(menu) > 16: fail('interact.json has %d entries: the Pocket shows 16' % len(menu))
    if len({v['id'] for v in menu}) != len(menu): fail('interact.json has duplicate ids')
    for v in menu:
        if len(v['name']) > 23: fail('interact.json name %r is over 23 characters' % v['name'])
        if not 0 <= v['id'] <= 65535: fail('interact.json id %r' % v['id'])
        if v['type'] not in ('radio', 'check', 'slider_u32', 'list', 'number_u32', 'action'): fail('interact.json type %r' % v['type'])
        if len(v.get('options', [])) > 16: fail('interact.json list %r has over 16 options' % v['name'])
        for o in v.get('options', []):
            if len(o['name']) > 23: fail('interact.json option %r is over 23 characters' % o['name'])
        if v['type'] == 'list' and not 0 <= v['defaultval'] < len(v['options']): fail('interact.json %r defaultval' % v['name'])
    # a family's Modifier is a default: the menu's own (any key) wins; a game's saved layout has its own Modifier, which is the game's
    ap = lambda menu, src, saved, fam: int(run(ctrl, 'apply', '%x' % menu, str(src), str(saved), str(fam)).strip(), 16)
    sel6, l1 = 6 << 10, 1 << 10
    for menu, src, saved, fam, want in ((0, 3, 0, -1, sel6), (l1, 3, 0, -1, l1), (2 << 10, 5, 0, -1, 2 << 10), (0, 1, 0, 3, sel6),
                                        (l1, 1, 0, 3, l1), (l1, 1, 1, 3, 3 << 10), (0, 1, 1, 3, 3 << 10), (l1, 0, 0, 3, l1), (0, 0, 0, 3, 0),
                                        (0, 2, 0, -1, 0), (l1, 2, 0, -1, l1)):
        got = ap(menu, src, saved, fam)
        if got != want: fail('apply menu %x src %d saved %d family %d: %x, expected %x' % (menu, src, saved, fam, got, want))
    # the session: Apply edits the layout in use (a family's, a game's saved one, or the menu's table), the edit is what the pad mapping gets
    # until "Controls" changes, and Save keeps the layout in use
    def session(saved, fam, script):
        out = run(ctrl, 'session', str(saved), str(fam), stdin=script).splitlines()
        return [[int(x, 16) if x not in ('applied', 'eff', 'cap') else x for x in line.split()] for line in out]
    def fld(words, f): return (words[f // 6] >> (5 * (f % 6))) & 31
    # Auto in a Skate game (family 3, no saved layout): the family's Modifier (Select, code 6), Base A is C-right (10)
    r = session(0, 3, 'src 1\nmenu 0 0\neff\napply 0 0 1 0\neff\nmenu 400 0\neff\n')
    if r[0][1] != 6 << 10 or fld(r[0][3:], 0) != 10: fail('session: the family layout is not in use under Auto: %s' % (r[0],))
    if r[1] != ['applied', 1]: fail('session: the first Apply under Auto was refused: %s' % (r[1],))
    if r[2][1] != 6 << 10 or fld(r[2][3:], 0) != 1 or fld(r[2][3:], 1) != 8: fail('session: the edit did not take effect on a copy of the family: %s' % (r[2],))
    if r[3][1] != 0x400: fail('session: the menu Modifier (L, code 1) lost to the family copy: %s' % (r[3],))
    # the "Controls" setting moving ends the edit: the family decides again, and the edit is the Menu table
    r = session(0, 3, 'src 1\nmenu 0 0\napply 0 0 1 0\nsrc 0\neff\nsrc 1\neff\nsrc 4\neff\n')
    if fld(r[1][3:], 0) != 1 or r[1][1] != 0: fail('session: the edit was not kept in the Menu table after Controls moved: %s' % (r[1],))
    if fld(r[2][3:], 0) != 10 or r[2][1] != 6 << 10: fail('session: Auto did not return to the family after Controls moved back: %s' % (r[2],))
    # (Controls moved away and back: the first edit's session ended, the live table still holds the edit, but Auto uses the family)
    # under Menu: the live table, under the menu's own settings
    r = session(0, -1, 'src 0\nmenu 800 1c00\napply 1 3 1 0\neff\n')
    if r[1][1] != 0x800 or r[1][2] != 0x1c00 or fld(r[1][3:], 15 + 3) != 1: fail('session: a Menu edit changed the menu settings or missed: %s' % (r[1],))
    # a game's saved layout (Modifier code 3) is what Auto uses, and an edit starts from it
    r = session(1, 3, 'src 1\nmenu 0 0\neff\napply 0 5 31 0\neff\n')
    if r[0][1] != 3 << 10 or r[0][3] != 0x1234: fail('session: the saved layout is not in use under Auto: %s' % (r[0],))
    if r[2][1] != 3 << 10 or fld(r[2][3:], 5) != 31 or r[2][3] & ~(31 << 25) != 0x1234 & ~(31 << 25): fail('session: an edit of the saved layout lost its other fields: %s' % (r[2],))
    # Save keeps the layout in use: a family's, edited or not
    r = session(0, 3, 'src 1\nmenu 0 0\ncap\napply 0 2 4 0\ncap\n')
    if r[0][1] != 6 << 10 or fld(r[0][3:], 0) != 10: fail('session: Save of an unedited family layout: %s' % (r[0],))
    if fld(r[2][3:], 2) != 4 or r[2][1] != 6 << 10: fail('session: Save of an edited family layout: %s' % (r[2],))
    # and what was saved is what Auto then uses, with the edit session over
    r = session(0, 3, 'src 1\nmenu 0 0\napply 0 0 1 0\nsave\nsrc 4\neff\nsrc 1\neff\n')
    if fld(r[2][3:], 0) != 1: fail('session: a saved edit is not used by Auto afterwards: %s' % (r[2],))
    r = session(0, 3, 'src 1\nmenu 0 0\napply 0 0 1 0\nsave\nsrc 4\neff\nsrc 1\nforget\neff\n')
    if fld(r[2][3:], 0) != 10: fail('session: Forget did not return Auto to the family: %s' % (r[2],))
    # nonsense changes nothing and does not start an edit that hides the family
    r = session(0, 3, 'src 1\nmenu 0 0\napply 0 0 1 3\neff\n')
    if r[0] != ['applied', 0] or fld(r[1][3:], 0) != 10: fail('session: a choice that means nothing: %s' % (r,))
    # the stick's feel is kept by a family, a game's saved layout carries it; the menu's own Modifier still wins over a family's
    feel = 2 << 20 | 3 << 25                          # dead zone code 2, range code 3
    if ap(feel, 3, 0, -1) != feel | 6 << 10: fail('a family changed the stick\'s feel: %x' % ap(feel, 3, 0, -1))
    if ap(feel | 1 << 10, 3, 0, -1) != feel | 1 << 10: fail('a family overrode the menu Modifier with the feel set')
    if ap(feel, 1, 1, 3) != 3 << 10: fail('a game\'s saved layout kept the menu\'s feel: %x' % ap(feel, 1, 1, 3))
    # the D-pad ramp: grows by the step, never past the target; a release, a reversal or a smaller target is at once; off is the target
    ramp = lambda c, t, st: int(run(ctrl, 'ramp', str(c), str(t), str(st)).strip())
    for cur, tgt, step, want in ((0, 80, 20, 20), (20, 80, 20, 40), (70, 80, 20, 80), (0, -80, 40, -40), (-40, -80, 40, -80), (60, 0, 20, 0),
                                 (60, -80, 20, -80), (80, 40, 20, 40), (0, 80, 0, 80), (0, 40, 10, 10), (5, 3, 10, 3), (0, 80, -5, 80)):
        if ramp(cur, tgt, step) != want:
            fail('ramp %d -> %d by %d: %d, expected %d' % (cur, tgt, step, ramp(cur, tgt, step), want))
    for step in (10, 20, 40):                        # from rest to full: the polls the step implies, no overshoot, no stall
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
