#!/usr/bin/env python3
"""Writes pkg/pocket/Cores/tortuga.Mirlo64/interact.json: the core's settings menu.

Every entry is `writeonly` (the Pocket stores the value and writes it; it never reads it back): the configuration that loads and works on a
Pocket, and the original author's. `--readable` writes the variant the Pocket reads back every frame (Analogue's docs: read, modify, write
back), which would let its menu show the selected option: rtl/soc/mirlo_regs.sv answers the reads and sim/interact_bridge runs the Pocket's cycle
against that variant in CI, but it has not been tried on a Pocket, and a Pocket that read wrong values would write them back. Only the actions
stay writeonly in it.
   gen_interact.py                     the shipped pkg/pocket/Cores/tortuga.Mirlo64/interact.json
   gen_interact.py --readable [FILE]   the readable variant (to FILE, or the shipped path with --install)

The Pocket shows at most 16 entries of interact.json (Analogue's docs: "Up to 16 UI entries ... can be shown"; a longer file is a load
error), a name is at most 23 characters, a list has at most 16 options. So the controller remap table is not one entry per field: five
entries are an editor -- 1. which layer, 2. which button, 3. it sends, 3b. or (special) -- and Apply puts the choice in the table (lang/n64rt/n64rt_ctrl.h, n64rt_ctrl_edit); the
table lives in the runtime's RAM, and Save / Forget keep a game's own copy (the .ctl file). Bus words (0x1000_0100 + 4 x n): 16 layer, 17 key,
18 gives, 19 or, 20 "Controls", 21 the actions (a write of 1 Applies, 2 Saves, 3 Forgets)."""
import json, os, sys

READABLE = False

def lst(name, ident, address, options, dflt=0, persist=True):
    e = {"name": name, "id": ident, "type": "list", "enabled": True}
    if persist:
        e["persist"] = True
    e.update({"address": address, "defaultval": dflt, "options": [{"value": v, "name": n} for v, n in options]})
    e["writeonly"] = True                 # (build() drops it for the readable variant)
    return e

def action(name, ident, value):
    return {"name": name, "id": ident, "type": "action", "enabled": True, "address": "0x10000154", "value": value, "writeonly": True}

KEYS = ["A", "B", "X", "Y", "L", "R", "ZL", "ZR", "Select", "Start", "L3", "R3", "D-pad keys", "Left stick", "Right stick"]
OUTPUTS = [(1, "A"), (2, "B"), (3, "Z"), (4, "Start"), (5, "L"), (6, "R"), (7, "C-up"), (8, "C-down"), (9, "C-left"), (10, "C-right"),
           (11, "D-up"), (12, "D-down"), (13, "D-left"), (14, "D-right")]

def build():
  entries = [
 {"name":"Show FPS","id":238,"type":"check","enabled":True,"persist":True,"address":"0x1000013C","defaultval":0,"value":1,"value_off":0,"writeonly":True},
 {"name":"Crop Vertical","id":235,"type":"slider_u32","enabled":True,"persist":True,"address":"0x1000010C","defaultval":8,"graphical":{"signed":False,"min":0,"max":30,"adjust_small":1,"adjust_large":4},"writeonly":True},   # (fork only: a slider, lines blanked at the picture's top and bottom; 5 bits, the video code takes any 0-31)
 lst("Crop Right", 236, "0x10000114", [(0, "None"), (1, "1 column")], 1),
 lst("Controller 1 pak", 214, "0x10000108", [(0, "None"), (1, "Controller Pak"), (2, "Transfer Pak")]),
 lst("Controls", 270, "0x10000150", [(0, "Menu"), (1, "Auto"), (2, "Standard"), (3, "Platformer / adventure"), (4, "Shooter"),
                                     (5, "Skate / snowboard"), (6, "Racing"), (7, "Fighter")], 1),
 lst("Stick dead zone", 273, "0x10000118", [(0, "Default (12)"), (1, "None"), (2, "Small (6)"), (3, "Large (20)"), (4, "Huge (30)")]),
 lst("Stick range", 274, "0x1000011C", [(0, "Default (80)"), (1, "Wide (85)"), (2, "75"), (3, "70"), (4, "Small (60)")]),
 lst("D-pad ramp", 275, "0x10000120", [(0, "Off"), (1, "Fast"), (2, "Medium"), (3, "Slow")]),
 lst("Modifier", 228, "0x10000110", [(0, "None"), (1, "L"), (2, "R"), (3, "ZL"), (4, "ZR"), (6, "Select")]),
 lst("1. Remap: which layer", 240, "0x10000140", [(0, "Base (normal)"), (1, "Held (Modifier on)")], persist=False),
 lst("2. Remap: which button", 241, "0x10000144", list(enumerate(KEYS)), persist=False),
 lst("3. Remap: it sends", 242, "0x10000148", [(0, "Default"), (31, "None")] + OUTPUTS, persist=False),
 lst("3b. Or (special)", 243, "0x1000014C", [(0, "Use step 3"), (1, "Same as Base"), (2, "Stick"), (3, "Half stick"), (4, "N64 D-pad"), (5, "C buttons")], persist=False),
 action("4. Apply remap", 244, 1),
 action("Save for this game", 271, 2),
 action("Forget this game", 272, 3),
  ]
  if READABLE:
    for e in entries:
      if e['type'] != 'action':
        e.pop('writeonly', None)
  return entries

def main():
    global READABLE
    args = sys.argv[1:]
    READABLE = "--readable" in args
    rest = [a for a in args if not a.startswith("--")]
    entries = build()
    assert len(entries) <= 16, "the Pocket shows 16 entries of interact.json at most"
    assert len({e["id"] for e in entries}) == len(entries)
    for e in entries:
        assert len(e["name"]) <= 23, e["name"]
        assert len(e.get("options", [])) <= 16, e["name"]
        assert all(len(o["name"]) <= 23 for o in e.get("options", [])), e["name"]
        assert 0 <= e["id"] <= 65535
    out = '{"interact":{"magic":"APF_VER_1","variables":[\n' + ",\n".join(json.dumps(e, separators=(",", ":")) for e in entries) + '\n],"messages":[]}}\n'
    shipped = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pkg", "pocket", "Cores", "tortuga.Mirlo64", "interact.json")
    path = rest[0] if rest else shipped
    if READABLE and not rest and "--install" not in args:
        sys.exit("--readable needs a FILE (or --install to replace the shipped menu)")
    open(path, "w").write(out)
    print("%d entries (%s) -> %s" % (len(entries), "readable" if READABLE else "writeonly", path))

if __name__ == "__main__":
    main()
