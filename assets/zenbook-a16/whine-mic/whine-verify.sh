#!/bin/bash
T="6820 8923"
rec(){ sudo -u napdivad XDG_RUNTIME_DIR=/run/user/1000 timeout 6 pw-record --target 70 --rate 48000 --channels 1 /home/napdivad/m.wav >/dev/null 2>&1; python3 /home/napdivad/whine-tones.py /home/napdivad/m.wav $T; }
avg(){ python3 -c '
import sys
rows=[l.split() for l in sys.stdin if l.strip()]; keys=[t.split("=")[0] for t in rows[0]]
vals=[[float(t.split("=")[1]) for t in r] for r in rows]
print("%-34s" % sys.argv[1] + "  ".join("%s %6.1f" % (k, sum(v[i] for v in vals)/len(vals)) for i,k in enumerate(keys)) + "  (n=%d)" % len(vals))' "$1"; }
meas(){ sleep 8; local i; for i in 1 2 3 4; do rec; done | avg "$1"; }
N=/sys/bus/pci/devices/0005:01:00.0/link
setlink(){ echo 1 > $N/clkpm; echo 1 > $N/l1_1_aspm; echo 1 > $N/l1_1_pcipm; echo 1 > $N/l1_2_aspm; echo 1 > $N/l1_2_pcipm; echo $1 > $N/l1_aspm; echo "   link: l1_aspm=$(cat $N/l1_aspm) l1_1=$(cat $N/l1_1_aspm)/$(cat $N/l1_1_pcipm) l1_2=$(cat $N/l1_2_aspm)/$(cat $N/l1_2_pcipm) clkpm=$(cat $N/clkpm)"; }
r0=$(dmesg | grep -c "usb 1-1: reset")
setlink 0; meas "A  NVMe L1 OFF"
setlink 1; meas "B  NVMe L1 ON (stock)"
setlink 0; meas "C  NVMe L1 OFF again"
setlink 1; meas "D  NVMe L1 ON again"
setlink 0
echo "usb webcam resets during test: $(( $(dmesg | grep -c "usb 1-1: reset") - r0 ))"
