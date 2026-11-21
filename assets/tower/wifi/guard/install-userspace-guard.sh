#!/bin/bash
# Installs the wpa_supplicant wedge guard + the watchdog/stats that use it (see tower-wifi-mt7921u-wedge.md).
# Safe while Wi-Fi is up: restarts nothing, loads no modules. Existing scripts are kept as .bak-<timestamp>.
# Needs /etc/default/tower-wifi with CON="<NM Wi-Fi connection name>" (template: ../watchdog/tower-wifi.default).
set -euo pipefail
H=$(dirname "$(readlink -f "$0")")
[ -r /etc/default/tower-wifi ] || { echo "create /etc/default/tower-wifi first (CON=...)"; exit 1; }
ts=$(date +%Y%m%d%H%M)
for f in $H/eapol-wmem.sh $H/wpa-wedged.sh $H/wpa-eapol-guard.sh $H/../watchdog/wifi-watchdog.sh $H/../watchdog/wifi-stats.sh; do
  b=$(basename $f)
  [ -e /usr/local/bin/$b ] && sudo cp -a /usr/local/bin/$b /usr/local/bin/$b.bak-$ts
  # install to a new inode and rename: never rewrite a script bash may be reading in place
  sudo install -m755 $f /usr/local/bin/$b.new && sudo mv /usr/local/bin/$b.new /usr/local/bin/$b
done
sudo install -m644 $H/wpa-eapol-guard.service $H/wpa-eapol-guard.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wpa-eapol-guard.timer
systemctl list-timers wpa-eapol-guard.timer wifi-watchdog.timer wifi-stats.timer --no-pager
sudo /usr/local/bin/eapol-wmem.sh   # "<wmem> 212992 <pct>"
