#!/usr/bin/env python3
"""Per-card thermal summary from monitor.csv for the burn-in windows in run.log.

Usage: summarize.py monitor.csv run.log
Only rows where the card is busy (>= 90 %) and drawing >= 200 W count as "under load".
Steady state = the last 60 % of each card's loaded samples in a window.
"""
import csv, re, sys
from collections import defaultdict
from datetime import datetime

mon, runlog = sys.argv[1], sys.argv[2]
ts = lambda s: datetime.strptime(s, "%Y-%m-%d %H:%M:%S")

# Windows: stage 1 per gpu (start..exit) and stage 2 (start..exit).
wins = []
starts = {}
for line in open(runlog):
    m = re.match(r"(\S+ \S+) stage 1 gpu(\d) (start|exit)", line)
    if m:
        key = f"stage1-gpu{m.group(2)}"
        if m.group(3) == "start":
            starts[key] = ts(m.group(1))
        elif key in starts:
            wins.append((key, starts[key], ts(m.group(1))))
    m = re.match(r"(\S+ \S+) stage 2: all", line)
    if m:
        starts["stage2"] = ts(m.group(1))
    m = re.match(r"(\S+ \S+) stage 2 exit", line)
    if m and "stage2" in starts:
        wins.append(("stage2", starts["stage2"], ts(m.group(1))))
if "stage2" in starts and not any(w[0] == "stage2" for w in wins):
    wins.append(("stage2 (running)", starts["stage2"], datetime.max))

rows = list(csv.DictReader(open(mon)))
num = lambda r, k: float(r[k]) if r.get(k) not in (None, "") else None

print(f"{'window':18} {'card':8} {'n':>4} {'edge':>9} {'hotspot':>9} {'vram':>9} {'hot-edge':>9} {'power':>7} {'fan':>6} {'sclk':>6}")
print(f"{'':18} {'':8} {'':>4} {'avg/max':>9} {'avg/max':>9} {'avg/max':>9} {'avg/max':>9} {'avg':>7} {'avg':>6} {'avg':>6}")
for name, a, b in wins:
    per = defaultdict(list)
    for r in rows:
        t = ts(r["time"])
        if a <= t <= b and (num(r, "busy_pct") or 0) >= 90 and (num(r, "power_w") or 0) >= 200:
            per[r["pci"]].append(r)
    for pci in sorted(per):
        rs = per[pci]
        rs = rs[int(len(rs) * 0.4):] or rs
        def am(k):
            v = [num(r, k) for r in rs if num(r, k) is not None]
            return (sum(v) / len(v), max(v)) if v else (0, 0)
        e, j, m_, p, f, s = am("edge_c"), am("junction_c"), am("mem_c"), am("power_w"), am("fan_rpm"), am("sclk_mhz")
        d = [num(r, "junction_c") - num(r, "edge_c") for r in rs]
        print(f"{name:18} {pci[5:]:8} {len(rs):>4} {e[0]:4.0f}/{e[1]:<4.0f} {j[0]:4.0f}/{j[1]:<4.0f} {m_[0]:4.0f}/{m_[1]:<4.0f} "
              f"{sum(d) / len(d):4.0f}/{max(d):<4.0f} {p[0]:7.0f} {f[0]:6.0f} {s[0]:6.0f}")
    links = {r["link"] for r in rows if a <= ts(r["time"]) <= b and r["pci"] in per}
    if links - {"32.0GT/s x16"}:
        print(f"{'':18} LINK CHANGES SEEN: {sorted(links)}")
