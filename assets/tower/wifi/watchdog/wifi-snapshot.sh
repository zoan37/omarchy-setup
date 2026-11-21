#!/bin/bash
# Saves everything useful about the adapter at the moment a drop is detected.
IF=wlp244s0f4u2i3; f=/var/log/wifi-drops/$(date +%Y%m%d-%H%M%S).txt
{
  echo "== $(date)"; uname -r
  echo "== iw link"; timeout 5 iw dev $IF link
  echo "== iw station dump"; timeout 5 iw dev $IF station dump
  echo "== ip"; ip -br a; ip route
  for d in /sys/kernel/debug/ieee80211/phy*/mt76; do
    for x in "$d"/*; do [ -f "$x" ] && [ -r "$x" ] && { echo "== $x"; timeout 3 cat "$x" 2>&1 | head -80; }; done
  done
  echo "== kernel last 10 min"; journalctl -k --since "-10min" --no-pager
  echo "== wpa_supplicant + NM last 10 min"; journalctl -u wpa_supplicant -u NetworkManager --since "-10min" --no-pager | tail -1500
  echo "== wifi-stats last 10 min"; journalctl -t wifi-stats --since "-10min" --no-pager
} > "$f" 2>&1
logger -t wifi-watchdog "saved drop snapshot $f"
ls -1t /var/log/wifi-drops/*.txt | tail -n +31 | xargs -r rm -f
