#!/usr/bin/env python3
"""The ROM's tail in PSRAM die 1: the numbers the runtime, the layout, the data.json and the core's RTL
(rtl/soc/mirlo_mips.sv, psram_rom_tail.sv, mirlo_regs.sv) each hold on their own, and the address maps' arithmetic
(the bridge's word -> the PSRAM's word, the PI engine's ROM offset -> the SDRAM's word or the PSRAM's) checked against each
other for every MiB. A change in one place that the others do not follow fails here.

    rom_tail_test.py        (run from anywhere)"""
import json
import os
import re
import sys

R = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def read(p):
    with open(os.path.join(R, p)) as f:
        return f.read()


def define(text, name):
    m = re.search(r"#define\s+%s\s+(0x[0-9A-Fa-f]+)u?" % name, text)
    assert m, name
    return int(m.group(1), 16)


MIB = 1 << 20
layout = read("lang/mips/include/layout.h")
rt = read("lang/n64rt/n64rt.h")
regs = read("rtl/soc/mirlo_regs.sv")
mips = read("rtl/soc/mirlo_mips.sv")

file_sdram = define(layout, "LAYOUT_FILE_SDRAM")
file_max = define(layout, "LAYOUT_FILE_MAX")
rom_off = define(rt, "N64RT_ROM_FILE_OFF")
rom_max = define(rt, "N64RT_ROM_MAX")
id_bit = define(rt, "N64RT_ID_ROM_TAIL")

# the layout: the ROM at 1 MiB, 48 MiB of it in the SDRAM, 16 MiB in the PSRAM, 64 MiB at most
assert rom_off == 1 * MIB
assert file_sdram == rom_off + 48 * MIB, hex(file_sdram)
assert rom_max == 64 * MIB
assert file_max == rom_off + rom_max, hex(file_max)
tail_bytes = rom_max - (file_sdram - rom_off)
assert tail_bytes == 16 * MIB                                  # die 1: two 16-bit chips of 4 M words = 16 MiB
assert tail_bytes // 4 == 1 << 22                              # the controller's 22-bit word address

# the core's ID bit and the data.json's file size
assert id_bit == 1 << 7
assert "32'(ROM_TAIL) << 7" in regs
data = json.load(open(os.path.join(R, "pkg/pocket/Cores/tortuga.Mirlo64/data.json")))
slot0 = [s for s in data["data"]["data_slots"] if s["id"] == 0][0]
assert int(slot0["size_maximum"], 16) >= rom_max, slot0["size_maximum"]

# the core's maps, as mirlo_mips.sv has them (words): the bridge's SDRAM-space word -> the PSRAM's word,
# the engine's (ROM offset word) -> the PSRAM's word or the SDRAM's
assert "wishbone_master_adr[21:18] - 4'd1" in mips            # the bridge: low 22 bits, megabyte - 1
assert "pd_adr[24] && pd_adr[23:22] == 2'b11" in mips        # the engine: a ROM word from 48 MiB up
assert "{pd_adr[23:18] + 6'd1, pd_adr[17:0]}" in mips        # below it: the SDRAM's word, 1 MiB up


def bridge_word_to_psram(adr):                                  # mirlo_mips.sv: the bridge's write of 49 to 65 MiB
    return ((((adr >> 18) & 15) - 1) & 15) << 18 | (adr & ((1 << 18) - 1))


def engine_word(rom_word):                                      # mirlo_mips.sv: the engine's read with bit 24 set
    if (rom_word >> 22) == 3:
        return ("psram", rom_word & ((1 << 22) - 1))
    return ("sdram", ((((rom_word >> 18) & 63) + 1) << 18) | (rom_word & ((1 << 18) - 1)))


n = 0
for rom_byte in list(range(0, 64 * MIB, MIB // 2)) + [64 * MIB - 4, 48 * MIB - 4, 48 * MIB, 63 * MIB, 48 * MIB + 4]:
    w = rom_byte // 4                                           # the ROM's word
    sdram_space = w + rom_off // 4                              # where the Pocket's bridge writes it (SDRAM word)
    kind, a = engine_word(w)
    if rom_byte < 48 * MIB:
        assert kind == "sdram" and a == sdram_space, (hex(rom_byte), kind, a)
    else:
        assert kind == "psram", hex(rom_byte)
        assert a == (rom_byte - 48 * MIB) // 4
        assert 49 * MIB // 4 <= sdram_space < 65 * MIB // 4    # the bridge's range for the PSRAM (br_ps)
        assert bridge_word_to_psram(sdram_space) == a, (hex(rom_byte), bridge_word_to_psram(sdram_space), a)
    n += 1
print("rom_tail_test: PASS (%d ROM offsets, the layout, the ID bit, data.json)" % n)
sys.exit(0)
