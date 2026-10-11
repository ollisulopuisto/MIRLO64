#!/usr/bin/env python3
"""Writes pkg/pocket/Cores/tortuga.Mirlo64/interact.json: the core's settings menu.

The first entries are written out as they are; the controller remap table (docs/mips.md, "The core's settings for the controller")
is 30 lists made here: for each of the twelve keys a Base and a Held entry, and for the three groups (the D-pad keys, the left and the
right analog stick) a Base and a Held entry. The table's field f is the interact bus word 16 + f, at 0x1000_0100 + 4 x (16 + f);
lang/n64rt/n64rt_pad.h reads them. "Controls" (word 46) picks where the layout comes from and two actions (word 47) save and forget a
game's own (lang/n64rt/n64rt_ctrl.h)."""
import json, os

FIRST = [
 {"name":"Show FPS","id":238,"type":"check","enabled":True,"persist":True,"address":"0x1000013C","defaultval":0,"value":1,"value_off":0,"writeonly":True},
 {"name":"Crop Vertical","id":235,"type":"list","enabled":True,"persist":True,"address":"0x1000010C","defaultval":1,"options":[{"value":0,"name":"None"},{"value":8,"name":"8 lines"},{"value":12,"name":"12 lines"}],"writeonly":True},
 {"name":"Crop Right","id":236,"type":"list","enabled":True,"address":"0x10000114","persist":True,"defaultval":1,"options":[{"value":0,"name":"None"},{"value":1,"name":"1 column"}],"writeonly":True},
 {"name":"Controller 1 pak","id":214,"type":"list","enabled":True,"persist":True,"address":"0x10000108","defaultval":0,"options":[{"value":0,"name":"None"},{"value":1,"name":"Controller Pak"},{"value":2,"name":"Transfer Pak"}],"writeonly":True},
 {"name":"Controls","id":270,"type":"list","enabled":True,"persist":True,"address":"0x100001B8","defaultval":1,"options":[{"value":0,"name":"Menu"},{"value":1,"name":"Auto (game, preset, menu)"},{"value":2,"name":"Standard"},{"value":3,"name":"Platformer / adventure"},{"value":4,"name":"Shooter"},{"value":5,"name":"Skate / snowboard"},{"value":6,"name":"Racing"},{"value":7,"name":"Fighter"}],"writeonly":True},
 {"name":"Save controls for this game","id":271,"type":"action","enabled":True,"address":"0x100001BC","value":1,"writeonly":True},
 {"name":"Forget this game's controls","id":272,"type":"action","enabled":True,"address":"0x100001BC","value":2,"writeonly":True},
 {"name":"Stick","id":225,"type":"list","enabled":True,"persist":True,"address":"0x1000012C","defaultval":0,"options":[{"value":0,"name":"D-pad"},{"value":1,"name":"L stick"},{"value":2,"name":"R stick"}],"writeonly":True},
 {"name":"D-pad","id":226,"type":"list","enabled":True,"persist":True,"address":"0x10000134","defaultval":0,"options":[{"value":0,"name":"None"},{"value":1,"name":"D-pad"},{"value":2,"name":"L stick"},{"value":3,"name":"R stick"}],"writeonly":True},
 {"name":"C buttons","id":223,"type":"list","enabled":True,"persist":True,"address":"0x10000128","defaultval":0,"options":[{"value":0,"name":"None"},{"value":1,"name":"Right stick"}],"writeonly":True},
 {"name":"Modifier","id":228,"type":"list","enabled":True,"persist":True,"address":"0x10000110","defaultval":0,"options":[{"value":0,"name":"None"},{"value":1,"name":"L"},{"value":2,"name":"R"},{"value":3,"name":"ZL"},{"value":4,"name":"ZR"},{"value":6,"name":"Select"}],"writeonly":True},
]
KEYS = ["A", "B", "X", "Y", "L", "R", "ZL", "ZR", "Select", "Start", "L3", "R3"]
GROUPS = ["D-pad keys", "Left stick", "Right stick"]
HELD = 15                                     # the Held layer's first field
OUTPUTS = [(1, "A"), (2, "B"), (3, "Z"), (4, "Start"), (5, "L"), (6, "R"), (7, "C-up"), (8, "C-down"), (9, "C-left"), (10, "C-right"),
           (11, "D-up"), (12, "D-down"), (13, "D-left"), (14, "D-right")]
SAME, NONE = 15, 31
BASE_DEFAULT = [1, 2, 10, 9, 3, 6, NONE, NONE, 8, 4, NONE, NONE]
HELD_DEFAULT = [10, 8, 7, 9] + [SAME] * 8
DPAD = ["Stick/D-pad settings", "Stick", "Half stick", "N64 D-pad", "C buttons", "None"]     # codes 0-5; 6: same as Base (Held)


def entry(name, ident, field, options, dflt_index):
    return {"name": name, "id": ident, "type": "list", "enabled": True, "persist": True,
            "address": "0x%08X" % (0x10000140 + 4 * field), "defaultval": dflt_index, "options": options, "writeonly": True}


def key_entry(i, held):
    dflt = (HELD_DEFAULT if held else BASE_DEFAULT)[i]
    opts = [{"value": 0 if dflt == NONE else NONE, "name": "None"}] + [{"value": 0 if c == dflt else c, "name": n} for c, n in OUTPUTS]
    if held:
        opts.append({"value": 0 if dflt == SAME else SAME, "name": "Same as Base"})
    index = next(n for n, o in enumerate(opts) if o["value"] == 0)
    f = (HELD if held else 0) + i
    return entry("%s (%s)" % (KEYS[i], "held" if held else "base"), 240 + f, f, opts, index)


def group_entry(g, held):
    first = "Stick/D-pad settings" if g == 0 else "Stick/D-pad/C settings"
    opts = [{"value": v, "name": n} for v, n in enumerate([first] + DPAD[1:])]
    if held:
        opts.append({"value": 6, "name": "Same as Base"})
    f = (HELD if held else 0) + 12 + g
    return entry("%s (%s)" % (GROUPS[g], "held" if held else "base"), 240 + f, f, opts, 0)


def main():
    entries = FIRST
    for held in (False, True):
        entries = entries + [key_entry(i, held) for i in range(12)] + [group_entry(g, held) for g in range(3)]
    assert len({e["id"] for e in entries}) == len(entries) and all(len(e.get("options", [])) <= 16 for e in entries)
    lines = [json.dumps(e, separators=(",", ":")) for e in entries]
    out = '{"interact":{"magic":"APF_VER_1","variables":[\n' + ",\n".join(lines) + '\n],"messages":[]}}\n'
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pkg", "pocket", "Cores", "tortuga.Mirlo64", "interact.json")
    open(path, "w").write(out)
    print("%d entries" % len(entries))


if __name__ == "__main__":
    main()
