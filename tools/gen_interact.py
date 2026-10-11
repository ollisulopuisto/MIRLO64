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
error), a name is at most 23 characters, a list has at most 16 options, and the names use only letters, digits, space and ( ) - . / :
(the characters the menus that loaded had). The controller layout is four lists -- Normal, Shift, Shift: D-pad, D-pad keys, each with Auto
first -- and Save / Forget for this game (lang/n64rt/n64rt_ctrl.h: the lists lay over the game's saved layout, else its family's, else
Standard). Bus words (0x1000_0100 + 4 x n): 16 Normal, 17 Shift, 18 Shift: D-pad, 19 D-pad keys, 21 the actions (a write of 2 Saves, 3 Forgets)."""
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

AUTO = (0, "Auto (from the game)")

def build():
  entries = [
 {"name":"Show FPS","id":238,"type":"check","enabled":True,"persist":True,"address":"0x1000013C","defaultval":0,"value":1,"value_off":0,"writeonly":True},
 lst("Crop Vertical", 235, "0x1000010C", [(0, "None"), (8, "8 lines"), (12, "12 lines")], 1),
 lst("Crop Right", 236, "0x10000114", [(0, "None"), (1, "1 column")], 1),
 lst("Controller 1 pak", 214, "0x10000108", [(0, "None"), (1, "Controller Pak"), (2, "Transfer Pak")]),
 lst("Shift key", 228, "0x10000110", [(0, "None"), (1, "L"), (2, "R"), (3, "ZL"), (4, "ZR"), (6, "Select")]),
 lst("Normal: A B X Y / L R", 240, "0x10000140", [AUTO, (1, "A B cR cL / Z R"), (2, "cR cD cU cL / Z R"), (3, "A B cR cL / R Z"),
                                                   (4, "A B cU Z / Z R")]),
 lst("Shift: A B X Y / L R", 241, "0x10000144", [AUTO, (1, "Same as normal"), (2, "cR cD cU cL"), (3, "A B cU cD"), (4, "/ L R (shoulders)")]),
 lst("Shift: D-pad", 242, "0x10000148", [AUTO, (1, "Same as normal"), (2, "C buttons"), (3, "Half stick"), (4, "N64 D-pad"),
                                        (5, "Stick and D-pad")]),
 lst("D-pad keys", 243, "0x1000014C", [(0, "N64 stick (default)"), (1, "N64 D-pad"), (2, "Stick and D-pad"), (3, "C buttons")]),
 lst("Analog sticks (dock)", 244, "0x10000150", [(1, "L stick / R C buttons"), (0, "L stick / R none"), (2, "L half / R C buttons"),
                                                 (3, "L D-pad / R C buttons"), (4, "L C buttons / R stick"), (5, "Both none")]),
 lst("Stick dead zone", 273, "0x10000118", [(0, "Default (12)"), (1, "None"), (2, "Small (6)"), (3, "Large (20)"), (4, "Huge (30)")]),
 lst("Stick range", 274, "0x1000011C", [(0, "Default (80)"), (1, "Wide (85)"), (2, "75"), (3, "70"), (4, "Small (60)")]),
 lst("D-pad ramp", 275, "0x10000120", [(0, "Off"), (1, "Fast"), (2, "Medium"), (3, "Slow")]),
 action("Save for this game", 271, 2),
 action("Forget this game", 272, 3),
  ]
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
        assert all(set(n) <= set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ()-./:") for n in [e["name"]] + [o["name"] for o in e.get("options", [])]), e["name"]
    out = '{"interact":{"magic":"APF_VER_1","variables":[\n' + ",\n".join(json.dumps(e, separators=(",", ":")) for e in entries) + '\n],"messages":[]}}\n'
    shipped = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pkg", "pocket", "Cores", "tortuga.Mirlo64", "interact.json")
    path = rest[0] if rest else shipped
    if READABLE and not rest and "--install" not in args:
        sys.exit("--readable needs a FILE (or --install to replace the shipped menu)")
    open(path, "w").write(out)
    print("%d entries (%s) -> %s" % (len(entries), "readable" if READABLE else "writeonly", path))

if __name__ == "__main__":
    main()
