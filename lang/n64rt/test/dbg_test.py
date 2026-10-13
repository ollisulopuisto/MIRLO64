#!/usr/bin/env python3
"""n64rt_dbg.h (the fork's debug graph) on the host: the windows of samples and the drawing.   python3 dbg_test.py   (needs gcc)"""
import os, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
with tempfile.TemporaryDirectory() as t:
    exe = os.path.join(t, 'dbg_host')
    subprocess.check_call(['gcc', '-O1', '-Wall', '-Wextra', '-o', exe, os.path.join(HERE, 'dbg_host.c')])
    r = subprocess.run([exe], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    sys.exit(r.returncode)
