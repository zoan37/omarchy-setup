#!/bin/bash
T="6820 8923"
U="sudo -u napdivad XDG_RUNTIME_DIR=/run/user/1000"
rec(){ $U timeout 6 pw-record --target 70 --rate 48000 --channels 1 /home/napdivad/m.wav >/dev/null 2>&1; python3 /home/napdivad/whine-tones.py /home/napdivad/m.wav $T; }
avg(){ python3 -c '
import sys
rows=[l.split() for l in sys.stdin if l.strip()]; keys=[t.split("=")[0] for t in rows[0]]
vals=[[float(t.split("=")[1]) for t in r] for r in rows]
print("%-36s" % sys.argv[1] + "  ".join("%s %6.1f" % (k, sum(v[i] for v in vals)/len(vals)) for i,k in enumerate(keys)))' "$1"; }
meas(){ sleep 6; local i; for i in 1 2 3; do rec; done | avg "$1"; }
H="$U HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1) hyprctl"
BL=/sys/class/backlight/*/brightness; b0=$(cat $BL)
meas "1 baseline"
$H keyword monitor "eDP-1,2880x1800@60,auto,1.6" >/dev/null; meas "2 display 60 Hz"; $H keyword monitor "eDP-1,2880x1800@120,auto,1.6" >/dev/null
$H dispatch dpms off >/dev/null; meas "3 screen off"; $H dispatch dpms on >/dev/null
echo 2047 > $BL; meas "4 brightness max"; echo 100 > $BL; meas "5 brightness min"; echo $b0 > $BL
nmcli radio wifi off; meas "6 Wi-Fi radio off"; nmcli radio wifi on
$U systemctl --user stop wireplumber pipewire pipewire-pulse; sleep 1; $U systemctl --user start pipewire pipewire-pulse wireplumber; sleep 3
$U systemctl --user stop wireplumber pipewire pipewire-pulse 2>/dev/null; $U timeout 6 arecord -D hw:1,0 -f S16_LE -r 48000 -c 1 -q /home/napdivad/m.wav >/dev/null 2>&1; python3 /home/napdivad/whine-tones.py /home/napdivad/m.wav $T | avg "7 audio stack stopped (raw ALSA)"; $U systemctl --user start pipewire pipewire-pulse wireplumber; sleep 4
meas "8 baseline again"
