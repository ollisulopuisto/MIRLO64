#!/usr/bin/env python3
"""Writes pkg/pocket/Cores/tortuga.Mirlo64/interact.json: the core's settings menu.

The lists and the check are readable: the Pocket reads each entry's register every frame, applies the user's change and writes it back
(Analogue's docs), and shows the value it read as the selected option (rtl/soc/mirlo_regs.sv answers the reads; sim/interact_bridge runs
the Pocket's cycle against it). Only the actions are writeonly.

The Pocket shows at most 16 entries of interact.json (Analogue's docs: "Up to 16 UI entries ... can be shown"; a longer file is a load
error), a name is at most 23 characters, a list has at most 16 options. So the controller remap table is not one entry per field: five
entries are an editor -- Remap: layer, key, gives, or -- and Apply puts the choice in the table (lang/n64rt/n64rt_ctrl.h, n64rt_ctrl_edit); the
table lives in the runtime's RAM, and Save / Forget keep a game's own copy (the .ctl file). Bus words (0x1000_0100 + 4 x n): 16 layer, 17 key,
18 gives, 19 or, 20 "Controls", 21 the actions (a write of 1 Applies, 2 Saves, 3 Forgets)."""
import json, os

def lst(name, ident, address, options, dflt=0, persist=True):
    e = {"name": name, "id": ident, "type": "list", "enabled": True}
    if persist:
        e["persist"] = True
    e.update({"address": address, "defaultval": dflt, "options": [{"value": v, "name": n} for v, n in options]})
    return e

def action(name, ident, value):
    return {"name": name, "id": ident, "type": "action", "enabled": True, "address": "0x10000154", "value": value, "writeonly": True}

KEYS = ["A", "B", "X", "Y", "L", "R", "ZL", "ZR", "Select", "Start", "L3", "R3", "D-pad keys", "Left stick", "Right stick"]
OUTPUTS = [(1, "A"), (2, "B"), (3, "Z"), (4, "Start"), (5, "L"), (6, "R"), (7, "C-up"), (8, "C-down"), (9, "C-left"), (10, "C-right"),
           (11, "D-up"), (12, "D-down"), (13, "D-left"), (14, "D-right")]

ENTRIES = [
 {"name":"Show FPS","id":238,"type":"check","enabled":True,"persist":True,"address":"0x1000013C","defaultval":0,"value":1,"value_off":0},
 lst("Crop Vertical", 235, "0x1000010C", [(0, "None"), (8, "8 lines"), (12, "12 lines")], 1),
 lst("Crop Right", 236, "0x10000114", [(0, "None"), (1, "1 column")], 1),
 lst("Controller 1 pak", 214, "0x10000108", [(0, "None"), (1, "Controller Pak"), (2, "Transfer Pak")]),
 lst("Controls", 270, "0x10000150", [(0, "Menu"), (1, "Auto"), (2, "Standard"), (3, "Platformer / adventure"), (4, "Shooter"),
                                     (5, "Skate / snowboard"), (6, "Racing"), (7, "Fighter")], 1),
 lst("Stick", 225, "0x1000012C", [(0, "D-pad"), (1, "L stick"), (2, "R stick")]),
 lst("D-pad", 226, "0x10000134", [(0, "None"), (1, "D-pad"), (2, "L stick"), (3, "R stick")]),
 lst("C buttons", 223, "0x10000128", [(0, "None"), (1, "Right stick")]),
 lst("Modifier", 228, "0x10000110", [(0, "None"), (1, "L"), (2, "R"), (3, "ZL"), (4, "ZR"), (6, "Select")]),
 lst("Remap: layer", 240, "0x10000140", [(0, "Base"), (1, "Held (Modifier)")], persist=False),
 lst("Remap: key", 241, "0x10000144", list(enumerate(KEYS)), persist=False),
 lst("Remap: gives", 242, "0x10000148", [(0, "Default"), (31, "None")] + OUTPUTS, persist=False),
 lst("Remap: or", 243, "0x1000014C", [(0, "Use 'gives'"), (1, "Same as Base"), (2, "Stick"), (3, "Half stick"), (4, "N64 D-pad"), (5, "C buttons")], persist=False),
 action("Apply remap", 244, 1),
 action("Save for this game", 271, 2),
 action("Forget this game", 272, 3),
]

def main():
    assert len(ENTRIES) <= 16, "the Pocket shows 16 entries of interact.json at most"
    assert len({e["id"] for e in ENTRIES}) == len(ENTRIES)
    for e in ENTRIES:
        assert len(e["name"]) <= 23, e["name"]
        assert len(e.get("options", [])) <= 16, e["name"]
        assert all(len(o["name"]) <= 23 for o in e.get("options", [])), e["name"]
        assert 0 <= e["id"] <= 65535
    out = '{"interact":{"magic":"APF_VER_1","variables":[\n' + ",\n".join(json.dumps(e, separators=(",", ":")) for e in ENTRIES) + '\n],"messages":[]}}\n'
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pkg", "pocket", "Cores", "tortuga.Mirlo64", "interact.json")
    open(path, "w").write(out)
    print("%d entries" % len(ENTRIES))

if __name__ == "__main__":
    main()
