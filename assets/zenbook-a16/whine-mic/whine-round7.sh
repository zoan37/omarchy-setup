#!/bin/bash
T="6820 8923"
U="sudo -u napdivad XDG_RUNTIME_DIR=/run/user/1000"
rec(){ $U timeout 6 pw-record --target 70 --rate 48000 --channels 1 /home/napdivad/m.wav >/dev/null 2>&1; python3 /home/napdivad/whine-tones.py /home/napdivad/m.wav $T; }
avg(){ python3 -c '
import sys
rows=[l.split() for l in sys.stdin if l.strip()]; keys=[t.split("=")[0] for t in rows[0]]
vals=[[float(t.split("=")[1]) for t in r] for r in rows]
print("%-40s" % sys.argv[1] + "  ".join("%s %6.1f" % (k, sum(v[i] for v in vals)/len(vals)) for i,k in enumerate(keys)))' "$1"; }
meas(){ sleep 6; local i; for i in 1 2 3; do rec; done | avg "$1"; }
W=/sys/bus/pci/devices/0004:01:00.0/link
echo "wifi power_save: $(iw dev wlan0 get power_save)  link l1_aspm=$(cat $W/l1_aspm)"
meas "1 baseline (wifi ps on, L1 on)"
iw dev wlan0 set power_save off; meas "2 wifi power_save off"
echo 0 > $W/l1_aspm; meas "3 + wifi link L1 off"
ping -i 0.1 -q 192.168.0.1 >/dev/null 2>&1 & PP=$!; meas "4 + 10 pings/s traffic"; kill $PP 2>/dev/null
echo 1 > $W/l1_aspm; meas "5 wifi ps off, L1 on"
iw dev wlan0 set power_save on
echo 0 > $W/l1_aspm; meas "6 wifi ps on, L1 off"; echo 1 > $W/l1_aspm
meas "7 baseline again"
