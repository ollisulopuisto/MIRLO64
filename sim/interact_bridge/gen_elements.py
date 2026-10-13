#!/usr/bin/env python3
"""interact.json -> elements.svh for interact_bridge_test.sv: each entry's bus word, whether the Pocket reads it back (not writeonly),
and its legal values (a list's option values, a check's value_off / value; an action's one value)."""
import json, sys
d = json.load(open(sys.argv[1]))['interact']['variables']
word = lambda e: (int(e['address'], 16) - 0x10000100) >> 2
d = [e for e in d if word(e) < 22]      # (words 22 and up -- Screen Size -- are the Pocket's own: core_top keeps them from the SoC)
n = len(d)
def vals(e):
    if e['type'] == 'list': return [o['value'] for o in e['options']]
    if e['type'] == 'check': return [e.get('value_off', 0), e['value']]
    if e['type'] == 'slider_u32': g = e['graphical']; return [g['min'], e['defaultval'], g['max']]
    return [e['value']]
def default(e):
    if e['type'] == 'list': return vals(e)[e['defaultval']]
    if e['type'] == 'check': return e['value'] if e['defaultval'] else e.get('value_off', 0)
    if e['type'] == 'slider_u32': return e['defaultval']
    return 0
read = lambda e: 0 if (e.get('writeonly') or e['type'] == 'action') else 1
out = ["localparam int NE = %d;" % n]
def fn(name, expr, ret="int"):
    cases = "\n".join("        %d: %s = %s;" % (i, name, expr(e, i)) for i, e in enumerate(d))
    out.append("function automatic %s %s(input int e);\n    case (e)\n%s\n    default: %s = 0;\n    endcase\nendfunction" % (ret, name, cases, name))
fn("EWORD", lambda e, i: word(e))
fn("EREAD", lambda e, i: read(e))
fn("EACT", lambda e, i: 1 if e['type'] == 'action' else 0)
fn("ENV", lambda e, i: len(vals(e)))
fn("EDEF", lambda e, i: default(e))
out.append("function automatic int EVAL(input int e, input int k);\n    case (e)")
for i, e in enumerate(d):
    out.append("    %d: case (k)\n%s\n        default: EVAL = 0; endcase" % (i, "\n".join("        %d: EVAL = %d;" % (k, v) for k, v in enumerate(vals(e)))))
out.append("    default: EVAL = 0;\n    endcase\nendfunction")
print("\n".join(out))
