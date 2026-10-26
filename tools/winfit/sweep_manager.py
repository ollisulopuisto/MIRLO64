#!/usr/bin/env python3
"""Long-running seed sweep manager for the Windows build box.
Sweeps a wide range of Quartus fitter seeds, logs progress, tracks closure,
and automatically updates fits.json and mirlo.qsf when a new best seed is found.
"""
import json
import os
import re
import subprocess
import sys
import time

R = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
QUARTUS = r"E:\altera\quartus\bin64"
BOOT = r"C:\Users\guest\boot.hex"
LOCKS = r"E:\locks"
JOBS = 4
STATUS_FILE = os.path.join(R, "sweep_status.txt")
RESULTS_FILE = os.path.join(R, "sweep_results.json")
LOG_FILE = os.path.join(R, "sweep_10h.log")

# Already tested for this commit:
# Closed: 1 (+0.080 ns), 27 (+0.028 ns)
# Failed/no fit: 2, 5, 6, 7, 10, 12, 13, 16, 30, 41
ALREADY_TESTED = {1, 2, 5, 6, 7, 10, 12, 13, 16, 27, 30, 41}

# Priority candidates first (previously known good seeds), then sequential up to 130
PRIORITY = [35, 14, 18, 20, 22, 23, 25, 28, 31, 32, 33, 34, 36, 37, 3, 4, 8, 9, 11, 15, 17, 19, 21, 24, 26, 29]
REST = [s for s in range(38, 131) if s not in ALREADY_TESTED and s not in PRIORITY]
SEED_LIST = [s for s in PRIORITY if s not in ALREADY_TESTED] + REST


def log(msg):
    ts = time.strftime("[%Y-%m-%d %H:%M:%S]")
    line = f"{ts} {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def update_status(current_best, completed, total, closed_seeds):
    lines = [
        f"MIRLO64 10-Hour Seed Sweep Status - {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"Completed: {completed}/{total} seeds ({completed * 100 // total}%)",
        f"Current best: Seed {current_best['seed']} (slack: {current_best['slack']:+.3f} ns, ALMs: {current_best.get('alms', 'n/a')})",
        "",
        "Closing seeds found:",
    ]
    for s in sorted(closed_seeds, key=lambda x: x["slack"], reverse=True):
        lines.append(f"  Seed {s['seed']:3d}: {s['slack']:+.3f} ns (ALMs: {s.get('alms', 'n/a')})")
    lines.append("")
    with open(STATUS_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def get_current_best():
    fits_path = os.path.join(R, "projects", "fits.json")
    best = {"seed": 1, "slack": 0.080, "alms": 18264}
    if os.path.exists(fits_path):
        try:
            data = json.load(open(fits_path))
            if data.get("fits"):
                top = max(data["fits"], key=lambda x: x["worst_slack_ns"])
                best = {"seed": top["seed"], "slack": top["worst_slack_ns"], "alms": top.get("alms", 18264)}
        except Exception:
            pass
    return best


def record_best_seed(seed, slack, alms):
    # Update mirlo.qsf
    qsf_path = os.path.join(R, "projects", "mirlo.qsf")
    if os.path.exists(qsf_path):
        qsf = open(qsf_path).read()
        qsf = re.sub(r"^set_global_assignment -name SEED .*$", f"set_global_assignment -name SEED {seed}", qsf, flags=re.M)
        open(qsf_path, "w").write(qsf)

    # Update fits.json
    try:
        proc = subprocess.run([sys.executable, os.path.join(R, "tools", "fits.py"), "fingerprint"], capture_output=True, text=True, cwd=R)
        fp = proc.stdout.strip()
    except Exception:
        fp = ""

    fits_path = os.path.join(R, "projects", "fits.json")
    fits_data = {"quartus": "25.1std.0 Build 1129 10/21/2025 SC Lite Edition", "sources": fp, "fits": []}
    if os.path.exists(fits_path):
        try:
            fits_data = json.load(open(fits_path))
            fits_data["sources"] = fp
        except Exception:
            pass

    fits = fits_data.get("fits", [])
    fits = [f for f in fits if f["seed"] != seed]
    fits.append({
        "seed": seed,
        "worst_slack_ns": round(slack, 3),
        "alms": alms,
        "date": time.strftime("%Y-%m-%d")
    })
    fits.sort(key=lambda x: x["worst_slack_ns"], reverse=True)
    fits_data["fits"] = fits
    with open(fits_path, "w", encoding="utf-8") as f:
        json.dump(fits_data, f, indent=2)

    # Git commit and push
    subprocess.run(["git", "commit", "-am", f"projects/fits.json: seed {seed} closed with {slack:+.3f} ns (best on Windows box)"], cwd=R)
    subprocess.run(["git", "push", "origin", "fork-patches"], cwd=R)


def main():
    log(f"Starting 10-hour seed sweep across {len(SEED_LIST)} seeds: {SEED_LIST[:10]} ...")
    best = get_current_best()
    closed_seeds = [
        {"seed": 1, "slack": 0.080, "alms": 18264},
        {"seed": 27, "slack": 0.028, "alms": 18296}
    ]
    all_results = {}
    if os.path.exists(RESULTS_FILE):
        try:
            all_results = json.load(open(RESULTS_FILE))
        except Exception:
            pass

    total = len(SEED_LIST)
    completed = 0
    update_status(best, completed, total, closed_seeds)

    # Run fit.py in batches of 4 seeds (one batch at a time for clean tracking)
    batch_size = 4
    for i in range(0, total, batch_size):
        batch = SEED_LIST[i:i + batch_size]
        log(f"--- Launching batch {i // batch_size + 1}/{(total + batch_size - 1) // batch_size}: seeds {batch} ---")
        cmd = [
            sys.executable, "-u",
            os.path.join(R, "tools", "winfit", "fit.py"),
            "--quartus", QUARTUS,
            "--boot", BOOT,
            "--locks", LOCKS,
            "--jobs", str(JOBS),
        ] + [str(s) for s in batch]

        t0 = time.time()
        p = subprocess.Popen(cmd, cwd=R, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in p.stdout:
            line_str = line.strip()
            if not line_str:
                continue
            log(f"  [fit.py] {line_str}")
            # Format: seed 1: exit 0, worst slack +0.080, CLOSED, 16 min
            m = re.search(r"seed\s+(\d+):\s+exit\s+(\d+),\s+worst slack\s+([-+][0-9.]+|n/a),\s+(CLOSED|not closed)", line_str)
            if m:
                s_id = int(m.group(1))
                rc = int(m.group(2))
                sl_str = m.group(3)
                is_closed = m.group(4) == "CLOSED"
                slack = float(sl_str) if sl_str != "n/a" else None
                all_results[str(s_id)] = {"exit": rc, "slack": slack, "closed": is_closed, "time": time.strftime("%Y-%m-%d %H:%M:%S")}
                completed += 1

                if is_closed and slack is not None:
                    # Check ALMs from fit.summary
                    alms = None
                    fit_dir = os.path.join(R, "winfit_out", f"fit-{s_id}-closed-true")
                    sum_file = os.path.join(fit_dir, "mirlo.fit.summary")
                    if os.path.exists(sum_file):
                        am = re.search(r"Logic utilization.*?([0-9,]+)\s+/\s+[0-9,]+", open(sum_file).read())
                        if am:
                            alms = int(am.group(1).replace(",", ""))

                    closed_entry = {"seed": s_id, "slack": slack, "alms": alms}
                    closed_seeds.append(closed_entry)
                    log(f"*** SEED {s_id} CLOSED! Slack: {slack:+.3f} ns, ALMs: {alms} ***")

                    if slack > best["slack"]:
                        log(f"*** NEW BEST SEED FOUND: {s_id} with {slack:+.3f} ns (beat {best['seed']} at {best['slack']:+.3f} ns)! Recording... ***")
                        best = {"seed": s_id, "slack": slack, "alms": alms}
                        try:
                            record_best_seed(s_id, slack, alms)
                        except Exception as e:
                            log(f"Error recording best seed: {e}")

                update_status(best, completed, total, closed_seeds)
                with open(RESULTS_FILE, "w", encoding="utf-8") as rf:
                    json.dump(all_results, rf, indent=2)

        p.wait()
        log(f"Batch completed in {(time.time() - t0) / 60:.1f} minutes.")
        time.sleep(5)

    log(f"All {total} seeds finished! Best seed: {best['seed']} with slack {best['slack']:+.3f} ns.")


if __name__ == "__main__":
    main()
