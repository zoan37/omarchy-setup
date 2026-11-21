#!/bin/bash
# Reconnects tower Wi-Fi (MT7921U USB) if it drops off its NetworkManager connection.
# 2026-11-21: no more USB deauthorize. When the mt76 USB TX leak wedges wpa_supplicant, its blocked
# sendto() holds a netdev reference, so a software USB unbind hangs forever in unregister_netdevice.
# Restarting wpa_supplicant (below) is the recovery; see tower-wifi-mt7921u-wedge.md.
IF=wlp244s0f4u2i3; CON=""; . /etc/default/tower-wifi   # sets CON=<NM connection name>
up() { gw=$(ip -4 route show dev $IF default 2>/dev/null | awk "{print \$3; exit}"); [ -n "$gw" ] && timeout 10 ping -c2 -W3 -I $IF "$gw" >/dev/null 2>&1; }
up && exit 0
sleep 20; up && exit 0
if [ ! -e /sys/class/net/$IF ]; then logger -t wifi-watchdog "adapter missing; needs replug or reboot (wired 10.77.0.6 still works)"; exit 0; fi
logger -t wifi-watchdog "Wi-Fi down, trying nmcli con up"
timeout 60 /usr/local/bin/wifi-snapshot.sh
timeout 45 nmcli con up "$CON" ifname $IF >/dev/null 2>&1; sleep 5
up && { logger -t wifi-watchdog "recovered via nmcli"; exit 0; }
logger -t wifi-watchdog "still down, restarting wpa_supplicant + rescan"
timeout 30 systemctl restart wpa_supplicant; sleep 5
timeout 15 nmcli dev wifi rescan ifname $IF >/dev/null 2>&1; sleep 5
timeout 45 nmcli con up "$CON" ifname $IF >/dev/null 2>&1; sleep 5
up && logger -t wifi-watchdog "recovered after wpa_supplicant restart" || logger -t wifi-watchdog "recovery failed; will retry next minute"
