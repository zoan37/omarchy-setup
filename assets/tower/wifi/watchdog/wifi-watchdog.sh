#!/bin/bash
# Reconnects tower Wi-Fi (MT7921U USB) if it drops off its NetworkManager connection.
# 2026-11-21: root cause of the "hung chip" is wpa_supplicant wedged in sendto() on a full
# l2 packet socket (mt76 USB TX skb leak, upstream fix 82856da2d3b6). That blocked sendto holds a netdev reference, so ANY
# USB unbind/deauthorize while it is stuck deadlocks in unregister_netdevice until reboot.
# Rule: un-wedge/restart wpa_supplicant FIRST. Never touch USB from here.
IF=wlp244s0f4u2i3; CON=""; . /etc/default/tower-wifi   # sets CON=<NM connection name>
up() { gw=$(ip -4 route show dev $IF default 2>/dev/null | awk '{print $3; exit}'); [ -n "$gw" ] && timeout 10 ping -c2 -W3 -I $IF "$gw" >/dev/null 2>&1; }
restart_wpa() {
  logger -t wifi-watchdog "restarting wpa_supplicant ($1)"
  # SIGKILL interrupts the blocked sendto (TASK_INTERRUPTIBLE) so the netdev ref is released.
  pkill -KILL -x wpa_supplicant; sleep 2
  timeout 30 systemctl restart wpa_supplicant; sleep 5
}
if /usr/local/bin/wpa-wedged.sh; then restart_wpa "wedged in sendto, EAPOL wmem $(/usr/local/bin/eapol-wmem.sh)"; fi
up && exit 0
sleep 20; up && exit 0
if [ ! -e /sys/class/net/$IF ]; then logger -t wifi-watchdog "adapter missing; needs replug or reboot (wired 10.77.0.6 still works)"; exit 0; fi
logger -t wifi-watchdog "Wi-Fi down, trying nmcli con up"
timeout 60 /usr/local/bin/wifi-snapshot.sh
timeout 45 nmcli con up "$CON" ifname $IF >/dev/null 2>&1; sleep 5
up && { logger -t wifi-watchdog "recovered via nmcli"; exit 0; }
restart_wpa "nmcli con up did not recover"
timeout 15 nmcli dev wifi rescan ifname $IF >/dev/null 2>&1; sleep 5
timeout 45 nmcli con up "$CON" ifname $IF >/dev/null 2>&1; sleep 5
up && logger -t wifi-watchdog "recovered after wpa_supplicant restart" || logger -t wifi-watchdog "recovery failed; will retry next minute"
