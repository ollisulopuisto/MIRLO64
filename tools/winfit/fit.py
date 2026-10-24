#!/usr/bin/env python3
"""A fit of the bitstream on a machine that has Quartus but no MIPS compiler (the CI's fit job, per seed; Windows or Linux).

   python tools/winfit/fit.py [--quartus DIR] [--jobs N] [--out DIR] [--boot boot.hex] SEED...

The one image only a MIPS compiler makes is the boot ROM: lang/mips/boot/build/boot.hex (the CI uploads it as the artifact "boot-rom";
give it with --boot, or put it there). The rest -- the RSP's divide ROM and the init files -- is made here (tools/mips_inits.py,
sim/rsp/make_div_rom.py). Each seed fits in its own copy of rtl/ platform/ target/ projects/ under OUT/s_<seed>, as the CI does (the SEED line of
projects/mirlo.qsf), and the result goes to OUT/fit-<seed>-closed-<true|false>/ (closure.txt, the summaries, and for a closed seed mirlo.rbf and the
packaged mirlo.rev). Several seeds run side by side (--jobs, default 4: a fit takes about 3-4 GB). The timing check is the CI's
(tools/area2/closure.py: the worst slack of all the corners, closed when it is >= 0)."""
import argparse, concurrent.futures, ctypes, os, re, shutil, subprocess, sys, time

R = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))   # (the tree to fit: --tree)
PY = sys.executable


def run(cmd, cwd=None, log=None):
    f = open(log, "w") if log else None
    try:
        return subprocess.run(cmd, cwd=cwd, stdout=f or subprocess.PIPE, stderr=subprocess.STDOUT, text=True).returncode
    finally:
        if f:
            f.close()


# The box is shared with other sessions: a registry file per running compile in LOCKS (E:\locks), "<session>-<n>.txt" -- session, project,
# working dir, start time, PID --; a file whose PID is gone, or older than 3 hours, is stale. A compile starts only with at least 6 GB of
# free RAM and fewer than 4 registry files; nothing here ever kills a process by name (the Pocket projects' agreed rules).
def pid_alive(pid):
    if os.name == "nt":
        out = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH"], capture_output=True, text=True).stdout
        return str(pid) in out
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def free_ram_gb():
    if os.name != "nt":
        return 99.0
    class MS(ctypes.Structure):
        _fields_ = [("l", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [(n, ctypes.c_ulonglong) for n in ("tp", "ap", "tpf", "apf", "tv", "av", "ae")]
    m = MS(); m.l = ctypes.sizeof(m)
    ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
    return m.ap / 2.0 ** 30


def live_locks(locks):
    n = 0
    for fn in os.listdir(locks):
        f = os.path.join(locks, fn)
        if not fn.endswith(".txt"):
            continue
        try:
            pid = int(re.search(r"^pid: *(\d+)", open(f).read(), re.M).group(1))
            stale = time.time() - os.path.getmtime(f) > 3 * 3600 or not pid_alive(pid)
        except Exception:
            stale = time.time() - os.path.getmtime(f) > 3 * 3600
        if stale:
            try:
                os.remove(f)
            except OSError:
                pass
        else:
            n += 1
    return n


def acquire(locks, tag, work):
    if not locks:
        return None
    os.makedirs(locks, exist_ok=True)
    while True:
        if free_ram_gb() >= 6.0 and live_locks(locks) < 4:
            f = os.path.join(locks, "pocket-n64-%s.txt" % tag)
            open(f, "w").write("session: pocket-n64\nproject: mirlo (tools/winfit/fit.py)\nworkdir: %s\nstart: %s\npid: %d\n" %
                               (work, time.strftime("%Y-%m-%d %H:%M:%S"), os.getpid()))
            return f
        time.sleep(30)


def prep(boot):
    dest = os.path.join(R, "lang", "mips", "boot", "build", "boot.hex")
    if boot:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(boot, dest)
    if not os.path.exists(dest):
        sys.exit("no boot ROM image: %s (the CI's artifact boot-rom, --boot)" % dest)
    for cmd in ([PY, os.path.join(R, "sim", "rsp", "make_div_rom.py"), os.path.join(R, "rtl", "rsp", "rsp_div_rom.hex")],
                [PY, os.path.join(R, "tools", "mips_inits.py")]):
        if run(cmd, cwd=R) != 0:
            sys.exit("failed: " + " ".join(cmd))
    svh = os.path.join(R, "rtl", "soc", "mirlo_mips_init.svh")      # (a tree's mips_inits.py may write the paths with backslashes: not in a Verilog string)
    t = open(svh).read()
    open(svh, "w").write(re.sub(r'(`define MIPS_INIT_\w+ ")([^"]*)"', lambda m: m.group(1) + m.group(2).replace("\\", "/") + '"', t))


FITSH = False


def one(seed, out, quartus, locks=None):
    t0 = time.time()
    work = os.path.join(out, "s_%d" % seed)
    lockfile = acquire(locks, str(seed), work)
    shutil.rmtree(work, ignore_errors=True)
    for d in ("rtl", "platform", "target", "projects"):
        shutil.copytree(os.path.join(R, d), os.path.join(work, d), ignore=shutil.ignore_patterns("db", "incremental_db", "output_files"))
    qsf = os.path.join(work, "projects", "mirlo.qsf")
    s = open(qsf).read()
    s, n = re.subn(r"^set_global_assignment -name SEED .*$", "set_global_assignment -name SEED %d" % seed, s, flags=re.M)
    assert n == 1, "no SEED line in mirlo.qsf"
    if FITSH:       # the macros tools/area2/fit.sh adds (what a recorded fit of projects/fits.json was made with)
        m = re.search(r"for m in (.*?); do", open(os.path.join(R, "tools", "area2", "fit.sh")).read())
        for mac in m.group(1).split():
            mac = mac.replace("${CPUCLK:-32}", "32")
            if not mac.startswith("$"):
                s += 'set_global_assignment -name VERILOG_MACRO "MIRLO_%s"\n' % mac
    open(qsf, "w").write(s)
    proj = os.path.join(work, "projects")
    rc = run([os.path.join(quartus, "quartus_sh"), "--flow", "compile", "mirlo"], cwd=proj, log=os.path.join(out, "compile_%d.log" % seed))
    outf = os.path.join(proj, "output_files")
    res = subprocess.run([PY, os.path.join(R, "tools", "area2", "closure.py"), outf], capture_output=True, text=True).stdout
    m = re.search(r"worst ([-+][0-9.]+)", res)
    worst = float(m.group(1)) if m else None
    closed = rc == 0 and worst is not None and worst >= 0
    dst = os.path.join(out, "fit-%d-closed-%s" % (seed, str(closed).lower()))
    shutil.rmtree(dst, ignore_errors=True)
    os.makedirs(dst)
    open(os.path.join(dst, "closure.txt"), "w").write(res)
    open(os.path.join(dst, "seed.txt"), "w").write("%d\n" % seed)
    shutil.copy(qsf, dst)
    if os.path.isdir(outf):
        for fn in os.listdir(outf):
            if fn.endswith((".summary", ".fit.rpt", ".sta.rpt")):
                shutil.copy(os.path.join(outf, fn), dst)
    rbf = os.path.join(outf, "mirlo.rbf")
    if closed and os.path.exists(rbf):
        shutil.copy(rbf, dst)
        run([PY, os.path.join(R, "tools", "package_bitstream.py"), os.path.join(dst, "mirlo.rbf"), os.path.join(dst, "mirlo.rev")], cwd=R)
    shutil.rmtree(work, ignore_errors=True) if closed is False and not os.environ.get("KEEP") else None
    if lockfile and os.path.exists(lockfile):
        os.remove(lockfile)
    return seed, rc, worst, closed, time.time() - t0


def main():
    global R, FITSH
    ap = argparse.ArgumentParser()
    ap.add_argument("seeds", nargs="+", type=int)
    ap.add_argument("--quartus", default=os.environ.get("QUARTUS_BIN", ""))
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--out", default=os.path.join(R, "winfit_out"))
    ap.add_argument("--boot")
    ap.add_argument("--fitsh", action="store_true", help="add the macros of the tree's tools/area2/fit.sh, as the recorded fits of projects/fits.json have")
    ap.add_argument("--tree", help="fit this tree (a checkout of another branch) instead of the one this script is in")
    ap.add_argument("--locks", default=os.environ.get("QUARTUS_LOCKS", ""), help="the registry directory shared with the other sessions (E:\\locks)")
    a = ap.parse_args()
    if not a.quartus:
        sys.exit("--quartus DIR (the quartus_sh's directory) or QUARTUS_BIN")
    FITSH = a.fitsh
    if a.tree:
        R = os.path.abspath(a.tree)
    os.makedirs(a.out, exist_ok=True)
    prep(a.boot)
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = [ex.submit(one, s, a.out, a.quartus, a.locks) for s in a.seeds]
        for f in concurrent.futures.as_completed(futs):
            seed, rc, worst, closed, secs = f.result()
            print("seed %d: exit %d, worst slack %s, %s, %.0f min" % (seed, rc, "n/a" if worst is None else "%+.3f" % worst,
                  "CLOSED" if closed else "not closed", secs / 60), flush=True)


if __name__ == "__main__":
    main()
