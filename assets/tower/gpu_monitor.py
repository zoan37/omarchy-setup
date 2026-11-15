#!/usr/bin/env python3
"""Log every amdgpu card's temps (edge/junction/mem), power, fan, clocks, busy % and PCIe link to CSV.

Usage: gpu_monitor.py OUT.csv [interval_s]. Runs until killed. Reads sysfs only (no ROCm needed).
Wakes runtime-suspended cards first (power/control=on) so the sensors answer; restores on exit.
"""
import glob, os, signal, sys, time

out = sys.argv[1]
interval = float(sys.argv[2]) if len(sys.argv) > 2 else 5


def rd(p, default=""):
    try:
        with open(p) as f:
            return f.read().strip()
    except OSError:
        return default


cards = []
for dev in sorted(glob.glob("/sys/class/drm/card*/device")):
    if os.path.basename(os.path.realpath(os.path.join(dev, "driver"))) != "amdgpu":
        continue
    h = (glob.glob(os.path.join(dev, "hwmon/hwmon*")) or [None])[0]
    if not h:
        continue
    pci = os.path.basename(os.path.realpath(dev))
    if any(c["pci"] == pci for c in cards):
        continue
    temps = {}
    for t in glob.glob(os.path.join(h, "temp*_input")):
        lab = rd(t.replace("_input", "_label"), os.path.basename(t))
        temps[lab] = t
    cards.append({"pci": pci, "dev": dev, "h": h, "temps": temps, "ctl": rd(os.path.join(dev, "power/control"))})

for c in cards:
    try:
        with open(os.path.join(c["dev"], "power/control"), "w") as f:
            f.write("on")
    except OSError:
        pass


def restore(*_):
    for c in cards:
        try:
            with open(os.path.join(c["dev"], "power/control"), "w") as f:
                f.write(c["ctl"] or "auto")
        except OSError:
            pass
    sys.exit(0)


signal.signal(signal.SIGTERM, restore)
signal.signal(signal.SIGINT, restore)

cpu_h = next((os.path.dirname(p) for p in glob.glob("/sys/class/hwmon/hwmon*/name") if rd(p) == "k10temp"), None)

cols = ["time", "pci", "edge_c", "junction_c", "mem_c", "power_w", "cap_w", "fan_rpm", "busy_pct",
        "sclk_mhz", "mclk_mhz", "link", "vram_used_gib", "cpu_tctl_c"]
new = not os.path.exists(out)
f = open(out, "a", buffering=1)
if new:
    f.write(",".join(cols) + "\n")


def cur_clk(path):
    for line in rd(path).splitlines():
        if line.endswith("*"):
            return line.split(":")[1].strip().rstrip("*").strip().lower().replace("mhz", "")
    return ""


while True:
    ts = time.strftime("%F %T")
    tctl = rd(os.path.join(cpu_h, "temp1_input"), "") if cpu_h else ""
    for c in cards:
        h, d = c["h"], c["dev"]
        t = lambda k: (str(int(rd(c["temps"][k], "0")) // 1000) if k in c["temps"] else "")
        pw = rd(os.path.join(h, "power1_average")) or rd(os.path.join(h, "power1_input"))
        row = [ts, c["pci"], t("edge"), t("junction"), t("mem"),
               f"{int(pw) / 1e6:.0f}" if pw else "",
               f"{int(rd(os.path.join(h, 'power1_cap'), '0')) / 1e6:.0f}",
               rd(os.path.join(h, "fan1_input")), rd(os.path.join(d, "gpu_busy_percent")),
               cur_clk(os.path.join(d, "pp_dpm_sclk")), cur_clk(os.path.join(d, "pp_dpm_mclk")),
               rd(os.path.join(d, "current_link_speed")).split(" ")[0] + "GT/s x" + rd(os.path.join(d, "current_link_width")),
               f"{int(rd(os.path.join(d, 'mem_info_vram_used'), '0')) / 2**30:.1f}",
               f"{int(tctl) / 1000:.0f}" if tctl else ""]
        f.write(",".join(row) + "\n")
    time.sleep(interval)
