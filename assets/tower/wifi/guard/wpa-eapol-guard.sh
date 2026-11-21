#!/bin/bash
# Proactive workaround for the mt76 USB TX skb leak (upstream 82856da2d3b6, not in 7.2.15).
# mt76u drops zero-length WNM keep-alives without freeing them, so wpa_supplicant's l2 socket
# send buffer fills after ~222 keep-alives (~30 h), then wpa blocks forever and the AP
# deauths us (reason 16). Restarting wpa_supplicant gives it a fresh socket. That costs a
# short Wi-Fi blip (~10 s), so do it at 70% (~156 keep-alives, ~21 h) instead of waiting
# for the hang. Run from a timer every 5 min. Never touches USB or modules.
CON=""; . /etc/default/tower-wifi   # sets CON=<NM connection name>
read -r t tb pct < <(/usr/local/bin/eapol-wmem.sh) || exit 0
[ -n "$pct" ] || exit 0
if [ "$pct" -ge 70 ]; then
  logger -t wpa-eapol-guard "EAPOL socket wmem $t/$tb ($pct%) - restarting wpa_supplicant before it wedges"
  timeout 30 systemctl restart wpa_supplicant || { pkill -KILL -x wpa_supplicant; sleep 2; systemctl start wpa_supplicant; }
  sleep 5; timeout 45 nmcli con up "$CON" ifname wlp244s0f4u2i3 >/dev/null 2>&1
  logger -t wpa-eapol-guard "done; new wmem: $(/usr/local/bin/eapol-wmem.sh)"
fi
