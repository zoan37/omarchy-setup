#!/bin/bash
# Removes the wpa-eapol-guard timer/service/script. Run once the patched mt76 (updates/mt76-usb-txleak-fix)
# or a kernel >= 7.3.4 is running and eapol-wmem.sh stays near 0 for a day.
# Keeps eapol-wmem.sh / wpa-wedged.sh and the watchdog/stats: they are harmless with the fix
# (the watchdog's un-wedge check just never fires). Restores nothing else; nothing is restarted.
set -euo pipefail
sudo systemctl disable --now wpa-eapol-guard.timer
sudo rm -f /etc/systemd/system/wpa-eapol-guard.timer /etc/systemd/system/wpa-eapol-guard.service /usr/local/bin/wpa-eapol-guard.sh
sudo systemctl daemon-reload
sudo systemctl reset-failed wpa-eapol-guard.service 2>/dev/null || true
systemctl list-timers --all --no-pager | grep -c wpa-eapol-guard || echo "guard removed"
