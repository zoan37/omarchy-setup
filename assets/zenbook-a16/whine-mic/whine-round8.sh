#!/bin/bash
# Round 8: knobs not yet measured. Run as root. Webcam mic at keyboard centre.
T="6820 8923"
U="sudo -u napdivad XDG_RUNTIME_DIR=/run/user/1000"
TGT=$($U pactl list short sources | awk '/alsa_input.usb/ {print $1; exit}')
[ -n "$TGT" ] || { echo "no USB mic source found"; exit 1; }
echo "mic source id $TGT"
rec(){ $U timeout 6 pw-record --target $TGT --rate 48000 --channels 1 /home/napdivad/m.wav >/dev/null 2>&1; python3 /home/napdivad/whine-tones.py /home/napdivad/m.wav $T; }
avg(){ python3 -c '
import sys
rows=[l.split() for l in sys.stdin if l.strip()]; keys=[t.split("=")[0] for t in rows[0]]
vals=[[float(t.split("=")[1]) for t in r] for r in rows]
print("%-40s" % sys.argv[1] + "  ".join("%s %6.1f" % (k, sum(v[i] for v in vals)/len(vals)) for i,k in enumerate(keys)))' "$1"; }
meas(){ sleep 8; local i; for i in 1 2 3; do rec; done | avg "$1"; }
peaks(){ $U timeout 10 pw-record --target $TGT --rate 48000 --channels 1 /home/napdivad/p.wav >/dev/null 2>&1; python3 /home/napdivad/whine-fft.py /home/napdivad/p.wav | head -14; }
RP=/sys/bus/pci/devices/0005:00:00.0; EP=/sys/bus/pci/devices/0005:01:00.0
WRP=/sys/bus/pci/devices/0004:00:00.0; WEP=/sys/bus/pci/devices/0004:01:00.0
setspeed(){ # $1 root port bdf, $2 endpoint sysfs dir, $3 target gen 1..5
  local v c; v=$(setpci -s $1 CAP_EXP+0x30.w); setpci -s $1 CAP_EXP+0x30.w=$(printf %04x $(( (0x$v & ~0xF) | $3 )))
  c=$(setpci -s $1 CAP_EXP+0x10.w); setpci -s $1 CAP_EXP+0x10.w=$(printf %04x $(( 0x$c | 0x20 ))); sleep 1
  echo "   link now: $(cat $2/current_link_speed) x$(cat $2/current_link_width)"; }
sync
echo "== full-spectrum peaks, current state"; peaks
meas "1 baseline (all current fixes)"
echo "-- NVMe link speed"
setspeed 0005:00:00.0 $EP 3; meas "2 NVMe Gen3"
setspeed 0005:00:00.0 $EP 2; meas "3 NVMe Gen2"
setspeed 0005:00:00.0 $EP 1; meas "4 NVMe Gen1"
setspeed 0005:00:00.0 $EP 4; meas "5 NVMe Gen4 (restored)"
echo "-- Wi-Fi link speed"
setspeed 0004:00:00.0 $WEP 1; meas "6 WiFi Gen1"
setspeed 0004:00:00.0 $WEP 3; meas "7 WiFi Gen3 (restored)"
echo "-- CPU cores"
for c in $(seq 6 17); do echo 0 > /sys/devices/system/cpu/cpu$c/online; done; meas "8 cores 6-17 offline (cluster0 only)"
for c in $(seq 1 5); do echo 0 > /sys/devices/system/cpu/cpu$c/online; done; meas "9 only cpu0 online"
for c in $(seq 1 17); do echo 1 > /sys/devices/system/cpu/cpu$c/online; done; meas "10 all cores back"
echo "-- CPU min freq"
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo 1516800 > $p/scaling_min_freq; done; meas "11 min freq 1.5 GHz all clusters"
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo 355200 > $p/scaling_min_freq; done
echo "-- GPU devfreq floor"
echo performance > /sys/class/devfreq/3d00000.gpu/governor; meas "12 GPU devfreq max"
echo simple_ondemand > /sys/class/devfreq/3d00000.gpu/governor
meas "13 baseline again"
echo "== full-spectrum peaks, end"; peaks
echo "usb resets: $(dmesg | grep -c 'usb 1-1: reset')"
